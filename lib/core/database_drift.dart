import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift/isolate.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart' as pg;

import 'alarm.dart';
import 'database.dart';

part 'database_drift.g.dart';

@UseRowClass(AlarmConfig, constructor: 'fromDb')
class Alarm extends Table {
  @override
  Set<Column> get primaryKey => {uid};

  TextColumn get uid => text()();
  TextColumn get key => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get rules =>
      text()(); // JSON string representation of List<AlarmRule>
}

class AlarmHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get alarmUid => text().references(Alarm, #uid)();
  TextColumn get alarmTitle => text()();
  TextColumn get alarmDescription => text()();
  TextColumn get alarmLevel => text()();
  TextColumn get expression => text().nullable()();
  BoolColumn get active => boolean()();
  BoolColumn get pendingAck => boolean()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deactivatedAt => dateTime().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
}

class FlutterPreferences extends Table {
  @override
  Set<Column> get primaryKey => {key};

  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  TextColumn get type => text()();
}

@DriftDatabase(tables: [Alarm, AlarmHistory, FlutterPreferences])
class AppDatabase extends _$AppDatabase {
  final DatabaseConfig config;
  AppDatabase._(this.config, QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  bool get native => executor is NativeDatabase;
  bool get postgres => executor is PgDatabase;

  /// Check if the connection is open.
  Future<bool> get isOpen async {
    if (executor is DelegatedDatabase) {
      return await (executor as DelegatedDatabase).delegate.isOpen;
    }
    // TODO: This is a hack to check if the connection is open, maybe not correct
    return await executor.ensureOpen(this);
  }

  Future<void> open() async {
    await executor.ensureOpen(this);
  }

  /// Factory: creates an [AppDatabase], in the current isolate.
  /// sqlite: will be created in the background, if postgres is not provided
  static Future<AppDatabase> create(DatabaseConfig config) async {
    if (config.postgres != null) {
      final pool = pg.Pool.withEndpoints([config.postgres!],
          settings: pg.PoolSettings(
            maxConnectionCount: 20,
            sslMode: config.sslMode,
          ));
      return AppDatabase._(
          config, PgDatabase.opened(pool, logStatements: config.debug));
    }
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    // Use a local NativeDatabase (or FlutterQueryExecutor).
    final executor = NativeDatabase.createInBackground(
      file,
      logStatements: config.debug,
    );
    return AppDatabase._(config, executor);
  }

  /// Factory: creates an [AppDatabase], spawning a DriftIsolate.
  static Future<AppDatabase> spawn(DatabaseConfig config) async {
    if (config.postgres != null) {
      // Spawn a DriftIsolate handling the Postgres connection off the main isolate.
      final isolate = await DriftIsolate.spawn(() {
        final pool = pg.Pool.withEndpoints([config.postgres!],
            settings: pg.PoolSettings(
              maxConnectionCount: 20,
              sslMode: config.sslMode,
            ));
        return PgDatabase.opened(pool, logStatements: config.debug);
      });
      final executor = await isolate.connect();
      return AppDatabase._(config, executor);
    } else {
      final dbFolder = await getApplicationSupportDirectory();
      final file = File(p.join(dbFolder.path, 'db.sqlite'));
      // Use a local NativeDatabase (or FlutterQueryExecutor).
      final executor = NativeDatabase.createInBackground(
        file,
        logStatements: config.debug,
      );
      return AppDatabase._(config, executor);
    }
  }

  /// Create a runtime-defined table
  /// The columns are a map of column name to column type
  Future<void> createTable(
      String tableName, Map<String, String> columns) async {
    final columnDefs =
        columns.entries.map((e) => '${e.key} ${e.value}').join(', ');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        $columnDefs
      )
    ''');
  }

  /// Check if a table exists
  Future<bool> tableExists(String tableName) async {
    final result = await customSelect(
      r'''
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_name = $1
    ) AS "exists"
    ''',
      variables: [Variable.withString(tableName)],
    ).getSingle();

    return result.read<bool>('exists');
  }

  /// Insert data into a dynamic table
  Future<int> tableInsert(String tableName, Map<String, dynamic> data) async {
    final keys = data.keys.map((key) => '"$key"').join(', ');
    final placeholders = data.keys.map((key) {
      if (key == 'time') {
        return '\$${data.keys.toList().indexOf(key) + 1}::timestamptz';
      }
      return '\$${data.keys.toList().indexOf(key) + 1}';
    }).join(', ');

    // Create variables with custom types for arrays
    final variables = data.values.map((value) {
      return Variable(value);
    }).toList();

    return await customInsert(
      'INSERT INTO "$tableName" ($keys) VALUES ($placeholders)',
      variables: variables,
    );
  }

  /// Query data from a dynamic table with detailed analysis
  Future<List<QueryRow>> tableQuery(
    String tableName, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    // await testRawPostgresConnection();
    // final startnet = DateTime.now();
    // await testConnectionLatency();
    // final durationnet = DateTime.now().difference(startnet);
    // print('⏱️  tableQuery: Network latency: ${durationnet.inMilliseconds}ms');

    final start = DateTime.now();
    // print('🔍 tableQuery: Building query for table $tableName');

    final cols = columns?.join(', ') ?? '*';
    final whereClause = where != null ? ' WHERE $where' : '';
    final orderByClause = orderBy != null ? ' ORDER BY $orderBy' : '';

    final sql = 'SELECT $cols FROM "$tableName"$whereClause$orderByClause';
    // print(' tableQuery: SQL: $sql');

    // // Add EXPLAIN ANALYZE to see what PostgreSQL is doing
    // final explainSql = 'EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) $sql';
    // print('🔬 tableQuery: Running EXPLAIN ANALYZE...');

    // try {
    //   final explainResult = await customSelect(
    //     explainSql,
    //     variables:
    //         whereArgs != null ? [for (var arg in whereArgs) Variable(arg)] : [],
    //   ).get();

    //   print('📊 tableQuery: Query Plan:');
    //   for (final row in explainResult) {
    //     print('   ${row.data.values.first}');
    //   }
    // } catch (e) {
    //   print('⚠️  tableQuery: Could not get query plan: $e');
    // }

    final result = await customSelect(
      sql,
      variables:
          whereArgs != null ? [for (var arg in whereArgs) Variable(arg)] : [],
    ).get();

    final duration = DateTime.now().difference(start);
    print('⏱️  tableQuery: Query execution took ${duration.inMilliseconds}ms');

    return result;
  }

  /// TODO: SQLITE
  Future<void> updateRetentionPolicy(
      String tableName, RetentionPolicy retention) async {
    // Convert to hypertable
    await customStatement('''
      SELECT create_hypertable('"$tableName"', 'time', if_not_exists => TRUE, migrate_data => TRUE);
    ''');

    // Remove any existing retention policy first, then add new one
    final dropAfter = pg.Interval.duration(retention.dropAfter);

    await customStatement('''
      SELECT remove_retention_policy('"$tableName"', if_exists => TRUE);
    ''');
    try {
      if (retention.scheduleInterval != null) {
        final scheduleInterval =
            pg.Interval.duration(retention.scheduleInterval!);
        await customStatement('''
          SELECT add_retention_policy('"$tableName"', drop_after => INTERVAL '$dropAfter', schedule_interval => INTERVAL '$scheduleInterval');
        ''');
      } else {
        await customStatement('''
          SELECT add_retention_policy('"$tableName"', drop_after => INTERVAL '$dropAfter');
        ''');
      }
    } catch (e) {
      stderr.writeln('Error updating retention policy for $tableName: $e');
    }
  }

  /// Get the retention duration for a hypertable
  Future<RetentionPolicy?> getRetentionPolicy(String tableName) async {
    final select = customSelect(r'''
      SELECT config ->> 'drop_after' AS drop_after, schedule_interval FROM timescaledb_information.jobs
      WHERE proc_name = 'policy_retention' AND hypertable_name = $1
    ''', variables: [Variable.withString(tableName)]);
    final result = await select.getSingle();
    final dropAfter = result.read<String>('drop_after');
    final scheduleInterval = result.read<String>('schedule_interval');

    return RetentionPolicy(
      dropAfter: parsePostgresInterval(dropAfter)!,
      scheduleInterval: parsePostgresInterval(scheduleInterval),
    );
  }

  static Duration? parsePostgresInterval(String? interval) {
    if (interval == null) return null;

    // TimescaleDB might return intervals in different formats
    // Let's handle the most common cases:

    // Format: "10 microseconds"
    final microsecondsMatch =
        RegExp(r'(\d+)\s*microseconds').firstMatch(interval);
    if (microsecondsMatch != null) {
      final microseconds = int.parse(microsecondsMatch.group(1)!);
      return Duration(microseconds: microseconds);
    }

    // Format: "10 milliseconds"
    final millisecondsMatch =
        RegExp(r'(\d+)\s*milliseconds').firstMatch(interval);
    if (millisecondsMatch != null) {
      final milliseconds = int.parse(millisecondsMatch.group(1)!);
      return Duration(milliseconds: milliseconds);
    }

    final secondsMatch = RegExp(r'(\d+)\s*second').firstMatch(interval);
    if (secondsMatch != null) {
      final seconds = int.parse(secondsMatch.group(1)!);
      return Duration(seconds: seconds);
    }

    // Format: "10 minutes", "1 hour", etc.
    final minutesMatch = RegExp(r'(\d+)\s*minute').firstMatch(interval);
    if (minutesMatch != null) {
      final minutes = int.parse(minutesMatch.group(1)!);
      return Duration(minutes: minutes);
    }

    final hoursMatch = RegExp(r'(\d+)\s*hour').firstMatch(interval);
    if (hoursMatch != null) {
      final hours = int.parse(hoursMatch.group(1)!);
      return Duration(hours: hours);
    }

    final daysMatch = RegExp(r'(\d+)\s*day').firstMatch(interval);
    if (daysMatch != null) {
      final days = int.parse(daysMatch.group(1)!);
      return Duration(days: days);
    }

    final monthsMatch = RegExp(r'(\d+)\s*month').firstMatch(interval);
    if (monthsMatch != null) {
      final months = int.parse(monthsMatch.group(1)!);
      return Duration(days: months * 30); // TODO: This is not correct
    }

    final yearsMatch = RegExp(r'(\d+)\s*year').firstMatch(interval);
    if (yearsMatch != null) {
      final years = int.parse(yearsMatch.group(1)!);
      return Duration(days: years * 365); // TODO: This is not correct
    }

    // Format: "00:10:00" (HH:MM:SS)
    final timeMatch = RegExp(r'(\d+):(\d+):(\d+)').firstMatch(interval);
    if (timeMatch != null) {
      final hours = int.parse(timeMatch.group(1)!);
      final minutes = int.parse(timeMatch.group(2)!);
      final seconds = int.parse(timeMatch.group(3)!);
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }

    throw FormatException('Unable to parse PostgreSQL interval: $interval');
  }

  /// Get table statistics for performance analysis
  Future<void> analyzeTablePerformance(String tableName) async {
    print('📊 Analyzing table performance for $tableName');

    try {
      // Get table size
      final sizeResult = await customSelect('''
        SELECT 
          pg_size_pretty(pg_total_relation_size('"$tableName"')) as table_size,
          pg_size_pretty(pg_relation_size('"$tableName"')) as data_size,
          pg_size_pretty(pg_total_relation_size('"$tableName"') - pg_relation_size('"$tableName"')) as index_size
      ''').getSingle();

      print(
          ' Table size: ${sizeResult.data['table_size']} (data: ${sizeResult.data['data_size']}, indexes: ${sizeResult.data['index_size']})');

      // Get row count
      final countResult =
          await customSelect('SELECT COUNT(*) as row_count FROM "$tableName"')
              .getSingle();
      print(' Row count: ${countResult.data['row_count']}');

      // Get time range
      final timeRangeResult = await customSelect('''
        SELECT 
          MIN(time) as min_time,
          MAX(time) as max_time,
          MAX(time) - MIN(time) as time_span
        FROM "$tableName"
      ''').getSingle();

      print(
          '⏰ Time range: ${timeRangeResult.data['min_time']} to ${timeRangeResult.data['max_time']}');
      print('⏱️  Time span: ${timeRangeResult.data['time_span']}');

      // Check for indexes
      final indexResult = await customSelect('''
        SELECT indexname, indexdef 
        FROM pg_indexes 
        WHERE tablename = '$tableName'
      ''').get();

      print('🔍 Indexes:');
      for (final index in indexResult) {
        print('   ${index.data['indexname']}: ${index.data['indexdef']}');
      }
    } catch (e) {
      print('⚠️  Could not analyze table: $e');
    }
  }

  /// Check if time column has proper indexing
  Future<void> checkTimeIndex(String tableName) async {
    print('🔍 Checking time index for $tableName');

    try {
      final indexResult = await customSelect('''
        SELECT indexname 
        FROM pg_indexes 
        WHERE tablename = '$tableName' 
        AND indexdef LIKE '%time%'
      ''').get();

      if (indexResult.isEmpty) {
        print(
            '⚠️  WARNING: No time-based index found! This could be causing slow queries.');
        print(
            '💡 Consider creating an index: CREATE INDEX ON "$tableName" (time);');
      } else {
        print(
            '✅ Time index found: ${indexResult.map((r) => r.data['indexname']).join(', ')}');
      }
    } catch (e) {
      print('⚠️  Could not check indexes: $e');
    }
  }

  /// Test connection latency with detailed breakdown
  Future<void> testConnectionLatency() async {
    print(' Testing connection latency with detailed breakdown...');

    // Test 1: Simple connection test with timing
    final start1 = DateTime.now();
    print('🔍 Step 1: About to call customSelect("SELECT 1")');

    // Add timing around the actual database call
    final dbStart = DateTime.now();
    print('🔍 Step 1a: About to call .getSingle()');
    await customSelect('SELECT 1').getSingle();
    final dbDuration = DateTime.now().difference(dbStart);

    final totalDuration = DateTime.now().difference(start1);
    print('⏱️  Step 1: Database call took ${dbDuration.inMilliseconds}ms');
    print(
        '⏱️  Step 1: Total time including overhead: ${totalDuration.inMilliseconds}ms');
    print(
        '⏱️  Step 1: Drift isolate overhead: ${(totalDuration - dbDuration).inMilliseconds}ms');

    // Test 2: Test with a more complex query
    final start2 = DateTime.now();
    print('🔍 Step 2: About to call customSelect("SELECT NOW()")');

    final dbStart2 = DateTime.now();
    await customSelect('SELECT NOW()').getSingle();
    final dbDuration2 = DateTime.now().difference(dbStart2);

    final totalDuration2 = DateTime.now().difference(start2);
    print('⏱️  Step 2: Database call took ${dbDuration2.inMilliseconds}ms');
    print(
        '⏱️  Step 2: Total time including overhead: ${totalDuration2.inMilliseconds}ms');
    print(
        '⏱️  Step 2: Drift isolate overhead: ${(totalDuration2 - dbDuration2).inMilliseconds}ms');

    print(' Connection latency summary:');
    print('   Database call 1: ${dbDuration.inMilliseconds}ms');
    print('   Database call 2: ${dbDuration2.inMilliseconds}ms');
    print(
        '   Drift overhead 1: ${(totalDuration - dbDuration).inMilliseconds}ms');
    print(
        '   Drift overhead 2: ${(totalDuration2 - dbDuration2).inMilliseconds}ms');

    if ((totalDuration - dbDuration).inMilliseconds > 100) {
      print('⚠️  High Drift isolate overhead detected! The issue is likely:');
      print('   1. Drift isolate communication is slow');
      print('   2. Serialization/deserialization overhead');
      print('   3. Isolate message passing bottleneck');
      print('   4. Memory pressure causing isolate slowdown');
    }
  }

  /// Test Drift isolate performance
  Future<void> testDriftIsolatePerformance() async {
    print('🔍 Testing Drift isolate performance...');

    // Test 1: Simple operation
    final start1 = DateTime.now();
    print('🔍 Test 1: Simple customSelect');
    await customSelect('SELECT 1').getSingle();
    final duration1 = DateTime.now().difference(start1);
    print('⏱️  Test 1 took: ${duration1.inMilliseconds}ms');

    // Test 2: Multiple operations
    final start2 = DateTime.now();
    print('🔍 Test 2: Multiple operations');
    for (int i = 0; i < 3; i++) {
      await customSelect('SELECT $i').getSingle();
    }
    final duration2 = DateTime.now().difference(start2);
    print(
        '⏱️  Test 2 took: ${duration2.inMilliseconds}ms (avg: ${duration2.inMilliseconds / 3}ms per operation)');

    // Test 3: Check if it's a one-time overhead
    final start3 = DateTime.now();
    print('🔍 Test 3: Repeated operation');
    await customSelect('SELECT 1').getSingle();
    final duration3 = DateTime.now().difference(start3);
    print('⏱️  Test 3 took: ${duration3.inMilliseconds}ms');
  }

  Future<void> testRawPostgresConnection() async {
    print('🔍 Testing raw PostgreSQL connection...');

    if (config.postgres == null) {
      print('❌ No PostgreSQL config available');
      return;
    }

    final start = DateTime.now();
    print('🔍 Creating raw PostgreSQL connection...');

    try {
      // Create a direct connection without the pool
      final connection = await pg.Connection.open(config.postgres!);
      final connectDuration = DateTime.now().difference(start);
      print(
          '⏱️  Raw connection creation took ${connectDuration.inMilliseconds}ms');

      // Test a simple query
      final queryStart = DateTime.now();
      final result = await connection.execute('SELECT 1');
      final queryDuration = DateTime.now().difference(queryStart);
      print('⏱️  Raw query execution took ${queryDuration.inMilliseconds}ms');

      await connection.close();
      print('✅ Raw connection test completed');
    } catch (e) {
      print('❌ Raw connection test failed: $e');
    }
  }
}
