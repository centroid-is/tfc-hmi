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

  /// Factory: creates an [AppDatabase], spawning a DriftIsolate.
  static Future<AppDatabase> spawn(DatabaseConfig config) async {
    if (config.postgres != null) {
      // Spawn a DriftIsolate handling the Postgres connection off the main isolate.
      final isolate = await DriftIsolate.spawn(
        () => PgDatabase(
          endpoint: config.postgres!,
          settings: pg.ConnectionSettings(
            sslMode: config.sslMode,
          ),
          logStatements: config.debug,
        ),
      );
      final executor = await isolate.connect();
      return AppDatabase._(config, executor);
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
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

  /// Query data from a dynamic table
  Future<List<QueryRow>> tableQuery(
    String tableName, {
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
  }) async {
    final cols = columns?.join(', ') ?? '*';
    final whereClause = where != null ? ' WHERE $where' : '';
    final orderByClause = orderBy != null ? ' ORDER BY $orderBy' : '';

    final result = await customSelect(
      'SELECT $cols FROM "$tableName"$whereClause$orderByClause',
      variables:
          whereArgs != null ? [for (var arg in whereArgs) Variable(arg)] : [],
    ).get();

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
}
