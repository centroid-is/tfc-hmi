import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' show QueryRow;
import 'package:postgres/postgres.dart' as pg;
import 'package:postgres/postgres.dart' show Endpoint, SslMode;
import 'package:json_annotation/json_annotation.dart' as json;
export 'package:postgres/postgres.dart' show Sql;
import 'package:logger/logger.dart';

import 'condition_variable.dart';
import 'secure_storage/secure_storage.dart';
import 'database_drift.dart';
import '../converter/duration_converter.dart';

part 'database.g.dart';

// todo skoða
// https://github.com/osaxma/postgresql-dart-replication-example/blob/main/example/listen_v3.dart

extension IntervalToDuration on pg.Interval {
  Duration toDuration() {
    // TODO: THIS IS BAD
    // Convert months to approximate days (30 days per month)
    final monthDays = months * 30;
    final totalDays = days + monthDays;

    return Duration(
      days: totalDays,
      microseconds: microseconds,
    );
  }
}

class EndpointConverter
    implements json.JsonConverter<pg.Endpoint, Map<String, dynamic>> {
  const EndpointConverter();

  @override
  pg.Endpoint fromJson(Map<String, dynamic> json) {
    return pg.Endpoint(
      host: json['host'] as String,
      port: json['port'] as int,
      database: json['database'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
      isUnixSocket: json['isUnixSocket'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson(pg.Endpoint endpoint) => {
        'host': endpoint.host,
        'port': endpoint.port,
        'database': endpoint.database,
        'username': endpoint.username,
        'password': endpoint.password,
        'isUnixSocket': endpoint.isUnixSocket,
      };
}

class SslModeConverter implements json.JsonConverter<pg.SslMode, String> {
  const SslModeConverter();

  @override
  pg.SslMode fromJson(String json) {
    return pg.SslMode.values.firstWhere(
      (mode) => mode.name == json,
      orElse: () => pg.SslMode.disable,
    );
  }

  @override
  String toJson(pg.SslMode mode) => mode.name;
}

@json.JsonSerializable()
class DatabaseConfig {
  @EndpointConverter()
  pg.Endpoint? postgres;
  @SslModeConverter()
  pg.SslMode? sslMode;
  bool debug = false;

  DatabaseConfig({this.postgres, this.sslMode, this.debug = false});

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) =>
      _$DatabaseConfigFromJson(json);

  Map<String, dynamic> toJson() => _$DatabaseConfigToJson(this);

  static const _configLocation = 'database_config';

  static Future<DatabaseConfig> fromPrefs() async {
    final prefs = SecureStorage.getInstance();
    var configJson = await prefs.read(key: _configLocation);
    DatabaseConfig config;
    if (configJson == null) {
      // If not found, create default config
      config = DatabaseConfig(
          postgres: null); // Or provide a default Endpoint if needed
      configJson = jsonEncode(config.toJson());
      await prefs.write(key: _configLocation, value: configJson);
    } else {
      config = DatabaseConfig.fromJson(jsonDecode(configJson));
    }
    return config;
  }

  Future<void> toPrefs() async {
    final prefs = SecureStorage.getInstance();
    final configJson = jsonEncode(toJson());
    await prefs.write(key: _configLocation, value: configJson);
  }
}

class DatabaseException implements Exception {
  DatabaseException(this.message);

  final String message;
}

// https://docs.tigerdata.com/api/latest/data-retention/add_retention_policy/
@json.JsonSerializable()
class RetentionPolicy {
  @DurationMinutesConverter()
  @json.JsonKey(name: 'drop_after_min')
  final Duration
      dropAfter; // Chunks fully older than this interval when the policy is run are dropped
  @DurationMinutesConverter()
  @json.JsonKey(name: 'schedule_interval_min')
  final Duration?
      scheduleInterval; // The interval between the finish time of the last execution and the next start. Defaults to NULL.

  const RetentionPolicy({required this.dropAfter, this.scheduleInterval});

  factory RetentionPolicy.fromJson(Map<String, dynamic> json) =>
      _$RetentionPolicyFromJson(json);

  Map<String, dynamic> toJson() => _$RetentionPolicyToJson(this);

  @override
  bool operator ==(Object other) {
    if (other is RetentionPolicy) {
      return dropAfter == other.dropAfter &&
          scheduleInterval == other.scheduleInterval;
    }
    return false;
  }

  @override
  int get hashCode => dropAfter.hashCode ^ scheduleInterval.hashCode;

  @override
  String toString() =>
      'RetentionPolicy(dropAfter: $dropAfter, scheduleInterval: $scheduleInterval)';
}

class Database {
  Database(this.db);

  AppDatabase db;
  Map<String, RetentionPolicy> retentionPolicies = {};
  static final Logger logger = Logger();
  final Map<String, Completer<void>> _tableCreationLocks = {};

  Future<void> open() async {
    try {
      await db.open();
    } catch (e) {
      throw DatabaseException('Failed to open database: $e');
    }
  }

  Future<void> registerRetentionPolicy(
      String tableName, RetentionPolicy retention) async {
    retentionPolicies[tableName] = retention;
    // We will actually create the table when the first data point is inserted,
    // because we need to know the type of the value column beforehand
    if (await db.tableExists(tableName)) {
      final currentRetention = await db.getRetentionPolicy(tableName);
      if (currentRetention != retention) {
        await db.updateRetentionPolicy(tableName, retention);
      }
    }
  }

  /// Insert a time-series data point
  Future<void> insertTimeseriesData(
      String tableName, DateTime time, dynamic value) async {
    // Wait if another task is already creating this table
    // while (_tableCreationLocks.containsKey(tableName)) {
    //   await _tableCreationLocks[tableName]!.future;
    // }

    Future<void> insert() async {
      if (value is Map<String, dynamic>) {
        await db
            .tableInsert(tableName, {"time": time.toIso8601String(), ...value});
      } else {
        await db.tableInsert(
            tableName, {'time': time.toIso8601String(), 'value': value});
      }
    }

    if (busy) {
      await cv.wait();
    }

    busy = true;

    try {
      await insert();
    } catch (e) {
      logger.e('error inserting $tableName $value: $e');
      if (await _tryToCreateTimeseriesTable(tableName, value)) {
        await insert();
      } else {
        rethrow;
      }
    }

    busy = false;
    cv.releaseOne();
  }

  CV cv = CV();
  bool busy = false;
  Future<Map<String, List<TimeseriesData<dynamic>>>>
      queryTimeseriesDataMultiple(List<String> tableNames, DateTime to,
          {String? orderBy = 'time ASC', DateTime? from}) async {
    Map<String, List<String>> tapleMap = {};
    for (final tableName in tableNames) {
      tapleMap[tableName] = ['value', 'time'];
    }
    final where = from != null
        ? r'time >= $1::timestamptz AND time <= $2::timestamptz'
        : r'time >= $1::timestamptz';
    final whereArgs = from != null ? [from, to] : [to];
    final rows = await db.tableQueryMultiple(tapleMap,
        where: where, whereArgs: whereArgs, orderBy: orderBy);
    final map = Map<String, List<TimeseriesData<dynamic>>>();
    for (final row in rows) {
      final time = row.data['time'];
      if (time == null) continue;
      final d = row.data;
      final nonNullTuples =
          d.entries.where((e) => e.value != null && e.key != 'time').toList();
      for (final tuple in nonNullTuples) {
        if (!map.containsKey(tuple.key)) {
          map[tuple.key] = [];
        }
        map[tuple.key]!.add(TimeseriesData(tuple.value, time));
      }
    }
    return map;
  }

  /// Query time-series data with performance analysis
  Future<List<TimeseriesData<dynamic>>> queryTimeseriesData(
      String tableName, DateTime to,
      {String? orderBy = 'time ASC', DateTime? from}) async {
    // final totalStart = DateTime.now();
    // print('🔍 queryTimeseriesData: Starting query for table $tableName');
    // print('📅 queryTimeseriesData: Querying since $since');

    // // Analyze table performance first
    // await db.analyzeTablePerformance(tableName);

    late final List<QueryRow> result;

    // final queryStart = DateTime.now();
    if (from != null) {
      final startTime = from.isBefore(to) ? from : to;
      final endTime = from.isBefore(to) ? to : from;
      // If from is provided, we need to query from that time
      // We need to query from the time of the first data point in the table
      result = await db.tableQuery(tableName,
          where: r'time >= $1::timestamptz AND time <= $2::timestamptz',
          whereArgs: [startTime, endTime],
          orderBy: orderBy);
    } else {
      result = await db.tableQuery(tableName,
          where: r'time >= $1::timestamptz', whereArgs: [to], orderBy: orderBy);
    }

    // final queryDuration = DateTime.now().difference(queryStart);
    // print(
    //     '⏱️  queryTimeseriesData: Database query took ${queryDuration.inMilliseconds}ms, returned ${result.length} rows');

    // final processStart = DateTime.now();
    if (result.isEmpty) {
      print('📊 queryTimeseriesData: No results found');
      return [];
    }

    if (result.first.data.containsKey('time')) {
      final processed = result.map((row) {
        final time = row.read<DateTime>('time');
        if (row.data.length == 2 && row.data.containsKey('value')) {
          return TimeseriesData(row.data['value'], time);
        }
        row.data.remove('time');
        return TimeseriesData(row.data, time);
      }).toList();

      // final processDuration = DateTime.now().difference(processStart);
      // final totalDuration = DateTime.now().difference(totalStart);
      // print(
      //     '⏱️  queryTimeseriesData: Data processing took ${processDuration.inMilliseconds}ms');
      // print(
      //     '⏱️  queryTimeseriesData: Total operation took ${totalDuration.inMilliseconds}ms');
      return processed;
    }

    throw DatabaseException('Time column not found in table $tableName');
  }

  /// columns: {tableName: columnName}
  Future<void> createView(String viewName, Map<String, String> columns) async {
    if (columns.isEmpty) {
      throw DatabaseException('createView("$viewName"): columns map is empty');
    }

    // Quote identifiers safely
    String q(String ident) => '"${ident.replaceAll('"', '""')}"';

    final qView = q(viewName);
    final tables = columns.keys.toList();

    // Build alias map t0, t1, ...
    final aliasFor = <String, String>{};
    for (var i = 0; i < tables.length; i++) {
      aliasFor[tables[i]] = 't$i';
    }

    // CTE: all distinct timestamps across all tables
    final allTimes =
        tables.map((t) => 'SELECT time FROM ${q(t)}').join('\nUNION\n');

    // SELECT list: time + requested columns, aliased as table_col
    final selectCols = <String>['at.time AS "time"'];
    for (final t in tables) {
      final alias = aliasFor[t]!;
      final col = columns[t]!;
      final outAlias = '${t}_${col}';
      selectCols.add('$alias.${q(col)} AS ${q(outAlias)}');
    }

    // LEFT JOIN each table to the all_times spine
    final joins = tables.map((t) {
      final alias = aliasFor[t]!;
      return 'LEFT JOIN ${q(t)} $alias ON $alias.time = at.time';
    }).join('\n');

    final isPg = db.postgres; // PgDatabase vs. Native (sqlite)
    final createKeyword = isPg ? 'MATERIALIZED VIEW' : 'VIEW';
    final dropStmt = isPg
        ? 'DROP MATERIALIZED VIEW IF EXISTS $qView CASCADE;'
        : 'DROP VIEW IF EXISTS $qView CASCADE;';

    final createSql = '''
CREATE $createKeyword $qView AS
WITH all_times AS (
  $allTimes
)
SELECT
  ${selectCols.join(',\n  ')}
FROM all_times at
$joins
ORDER BY at.time;
''';

    // Execute (separate statements for compatibility)
    await db.customStatement(dropStmt);
    await db.customStatement(createSql);

    // Postgres-only: add a UNIQUE index on time to allow REFRESH CONCURRENTLY
    if (isPg) {
      final idxName = ('${viewName}_time_uidx'
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9_]+'), '_'))
          .replaceAll(RegExp(r'_+'), '_');
      await db.customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS $idxName ON $qView ("time");');
    }
  }

  /// Count time-series data points in regular time intervals
  /// Returns a map of counts for each interval, from oldest to newest {bucketStart: count, ...}
  /// [interval] is the duration of each bucket
  /// [howMany] is the number of buckets to count
  /// [since] is the end time for the buckets (defaults to now)
  Future<Map<DateTime, int>> countTimeseriesDataMultiple(
      String tableName, Duration interval, int howMany,
      {DateTime? since}) async {
    if (howMany <= 0) {
      return {};
    }

    final endTime = since ?? DateTime.now();
    final bucketStarts = <DateTime>[];
    final bucketEnds = <DateTime>[];

    // Generate time buckets from oldest to newest
    for (int i = howMany - 1; i >= 0; i--) {
      final bucketStart = endTime.subtract(interval * (i + 1));
      final bucketEnd = endTime.subtract(interval * i);
      bucketStarts.add(bucketStart);
      bucketEnds.add(bucketEnd);
    }

    // Build a UNION query for the specific number of intervals
    final unionQueries = <String>[];
    for (int i = 0; i < howMany; i++) {
      final startTime = bucketStarts[i].toIso8601String();
      final endTime = bucketEnds[i].toIso8601String();
      unionQueries.add('''
          SELECT COUNT(*) as count FROM "$tableName"
          WHERE time >= '$startTime' AND time < '$endTime'
        ''');
    }
    final sql = unionQueries.join(' UNION ALL ');

    final result = await db.customSelect(sql).get();

    // Extract counts from result rows
    final counts = <DateTime, int>{};
    for (int i = 0; i < result.length; i++) {
      counts[bucketStarts[i]] = result[i].read<int>('count');
    }
    return counts;
  }

  Future<void> _createTimeseriesTable(
      String tableName, RetentionPolicy retention, dynamic value) async {
    if (value is Map<String, dynamic>) {
      // Create table with columns for each key in the complex object
      await _createComplexTimeseriesTable(tableName, retention, value);
    } else {
      String valueType = _getPostgresType(value);
      await db
          .createTable(tableName, {'value': valueType, 'time': 'TIMESTAMPTZ'});
      await db.updateRetentionPolicy(tableName, retention);
    }
  }

  /// Create table for complex objects with separate columns for each key
  Future<void> _createComplexTimeseriesTable(String tableName,
      RetentionPolicy retention, Map<String, dynamic> value) async {
    Map<String, String> columns = {};

    for (final entry in value.entries) {
      final columnName = entry.key;
      final columnValue = entry.value;
      final columnType = _getPostgresType(columnValue);
      columns[columnName] = columnType;
    }

    await db.createTable(tableName, {'time': 'TIMESTAMPTZ', ...columns});
    await db.updateRetentionPolicy(tableName, retention);
  }

  /// Get PostgreSQL type for a value
  String _getPostgresType(dynamic value) {
    if (value is List) {
      // Infer array type from first element, default to TEXT[]
      if (value.isEmpty) {
        // todo this is error prone, I think we should just skip it, and create it by altering the table afterwards when there is a value
        return 'TEXT[]';
      }
      final first = value.first;
      switch (first) {
        case int():
          return 'INTEGER[]';
        case double():
          return 'DOUBLE PRECISION[]';
        case bool():
          return 'BOOLEAN[]';
        case String():
          return 'TEXT[]';
        case Duration():
          return 'INTERVAL[]';
        case DateTime():
          return 'TIMESTAMPTZ[]';
        default:
          return 'JSONB[]'; // fallback for complex/nested objects
      }
    }
    switch (value) {
      case int():
        return 'INTEGER';
      case double():
        return 'DOUBLE PRECISION';
      case bool():
        return 'BOOLEAN';
      case String():
        return 'TEXT';
      case null:
        return 'TEXT'; // Allow NULL values, TODO: I DONT LIKE THIS
      case Duration():
        return 'INTERVAL';
      case DateTime():
        return 'TIMESTAMPTZ';
      default:
        return 'JSONB'; // For complex nested objects
    }
  }

  /// Returns true if the table was created successfully, false if it already exists or policy is missing
  Future<bool> _tryToCreateTimeseriesTable(
      String tableName, dynamic value) async {
    // Check again after waiting - table might have been created
    // if (await db.tableExists(tableName)) {
    //   return true;
    // }

    if (!retentionPolicies.containsKey(tableName)) {
      stderr.writeln(
          'Table $tableName does not exist, and no retention policy is set');
      return false;
    }

    // Acquire lock for this table
    final completer = Completer<void>();
    logger.t("Lock Creating table $tableName");

    _tableCreationLocks[tableName] = completer;

    try {
      logger.t("Creating table $tableName");
      await _createTimeseriesTable(
          tableName, retentionPolicies[tableName]!, value);
    } finally {
      // Release lock
      _tableCreationLocks.remove(tableName);
      completer.complete();
    }
    return true;
  }

  Future<void> close() async {
    await db.close();
  }
}

class TimeseriesData<T> {
  final T value;
  final DateTime time;

  @override
  String toString() {
    return 'TimeseriesData(value: $value, time: $time)';
  }

  TimeseriesData(this.value, this.time);
}
