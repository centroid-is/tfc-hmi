import 'dart:io';
import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:json_annotation/json_annotation.dart';
export 'package:postgres/postgres.dart' show Sql;
import 'package:logger/logger.dart';

import '../converter/duration_converter.dart';

part 'database.g.dart';

// todo skoða
// https://github.com/osaxma/postgresql-dart-replication-example/blob/main/example/listen_v3.dart

extension IntervalToDuration on Interval {
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
    implements JsonConverter<Endpoint, Map<String, dynamic>> {
  const EndpointConverter();

  @override
  Endpoint fromJson(Map<String, dynamic> json) {
    return Endpoint(
      host: json['host'] as String,
      port: json['port'] as int,
      database: json['database'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
      isUnixSocket: json['isUnixSocket'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson(Endpoint endpoint) => {
        'host': endpoint.host,
        'port': endpoint.port,
        'database': endpoint.database,
        'username': endpoint.username,
        'password': endpoint.password,
        'isUnixSocket': endpoint.isUnixSocket,
      };
}

class SslModeConverter implements JsonConverter<SslMode, String> {
  const SslModeConverter();

  @override
  SslMode fromJson(String json) {
    return SslMode.values.firstWhere(
      (mode) => mode.name == json,
      orElse: () => SslMode.disable,
    );
  }

  @override
  String toJson(SslMode mode) => mode.name;
}

@JsonSerializable()
class DatabaseConfig {
  @EndpointConverter()
  Endpoint? postgres;
  @SslModeConverter()
  SslMode? sslMode;

  DatabaseConfig({this.postgres, this.sslMode});

  factory DatabaseConfig.fromJson(Map<String, dynamic> json) =>
      _$DatabaseConfigFromJson(json);

  Map<String, dynamic> toJson() => _$DatabaseConfigToJson(this);
}

class DatabaseException implements Exception {
  DatabaseException(this.message);

  final String message;
}

// https://docs.tigerdata.com/api/latest/data-retention/add_retention_policy/
@JsonSerializable()
class RetentionPolicy {
  @DurationMinutesConverter()
  @JsonKey(name: 'drop_after_min')
  final Duration
      dropAfter; // Chunks fully older than this interval when the policy is run are dropped
  @DurationMinutesConverter()
  @JsonKey(name: 'schedule_interval_min')
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

class Database implements Session {
  Database(this.config);

  Connection? conn;
  final DatabaseConfig config;
  static const configLocation = 'database_config';
  Map<String, RetentionPolicy> retentionPolicies = {};

  // Add a cache for prepared statements
  final Map<String, Statement> _preparedStatements = {};
  static final Logger logger = Logger();

  Future<void> connect() async {
    if (conn != null && conn!.isOpen) {
      return;
    }
    conn = await Connection.open(
      config.postgres!,
      settings: PoolSettings(
        sslMode: config.sslMode,
        maxConnectionCount: 20,
        maxConnectionAge: const Duration(minutes: 10),
        maxSessionUse: const Duration(minutes: 10),
      ),
    ).onError((error, stackTrace) {
      throw DatabaseException(
        'conn to Postgres failed: $error\n $stackTrace',
      );
    });
  }

  @override
  bool get isOpen => conn != null && conn!.isOpen;

  @override
  Future<void> get closed => conn?.closed ?? Future.value();

  Future<void> close() async {
    await conn?.close();
  }

  @override
  Future<Statement> prepare(Object /* String | Sql */ query) async {
    await connect();
    return conn!.prepare(query);
  }

  @override
  Future<Result> execute(
    Object /* String | Sql */ query, {
    Object? /* List<Object?|TypedValue> | Map<String, Object?|TypedValue> */
        parameters,
    bool ignoreRows = false,
    QueryMode? queryMode,
    Duration? timeout,
  }) async {
    await connect();
    return conn!.execute(query,
        parameters: parameters,
        ignoreRows: ignoreRows,
        queryMode: queryMode,
        timeout: timeout);
  }

  /// Check if a table exists
  Future<bool> tableExists(String tableName) async {
    final result = await execute(Sql.named('''
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = @tableName
      );
    '''), parameters: {'tableName': tableName});

    return (result.first[0] as bool);
  }

  Future<void> registerRetentionPolicy(
      String tableName, RetentionPolicy retention) async {
    retentionPolicies[tableName] = retention;
    // We will actually create the table when the first data point is inserted,
    // because we need to know the type of the value column beforehand
    if (await tableExists(tableName)) {
      final currentRetention = await getRetentionPolicy(tableName);
      if (currentRetention != retention) {
        await _updateRetentionPolicy(tableName, retention);
      }
    }
  }

  /// Insert a time-series data point
  Future<void> insertTimeseriesData(
      String tableName, DateTime time, dynamic value) async {
    Future<void> insert() async {
      if (value is Map<String, dynamic>) {
        // Handle complex object - create columns for each key
        await _insertComplexValue(tableName, time, value);
      } else {
        // Handle simple value using prepared statement
        await _insertSimpleValue(tableName, time, value);
      }
    }

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
  }

  /// Insert simple value using prepared statement
  Future<void> _insertSimpleValue(
      String tableName, DateTime time, dynamic value) async {
    final statementKey = 'insert_simple_$tableName';

    // Get or create prepared statement
    Statement statement =
        _preparedStatements[statementKey] ?? await prepare(Sql.named('''
          INSERT INTO "$tableName" (time, value)
          VALUES (@time, @value)
        '''));

    // Cache the statement for reuse
    if (!_preparedStatements.containsKey(statementKey)) {
      _preparedStatements[statementKey] = statement;
    }

    final now = DateTime.now();
    await statement.run({
      'time': time,
      'value': value,
    });
    logger
        .i('inserted $tableName $value took ${DateTime.now().difference(now)}');
  }

  /// Insert complex value with separate columns for each key
  Future<void> _insertComplexValue(
      String tableName, DateTime time, Map<String, dynamic> value) async {
    // Create a unique key based on the column structure
    final columnNames = value.keys.toList()..sort(); // Sort for consistent key
    final statementKey = 'insert_complex_${tableName}_${columnNames.join('_')}';

    // Get or create prepared statement
    Statement statement = _preparedStatements[statementKey] ??
        await _createComplexInsertStatement(tableName, columnNames);

    // Cache the statement for reuse
    if (!_preparedStatements.containsKey(statementKey)) {
      _preparedStatements[statementKey] = statement;
    }

    // Build parameters map
    final parameters = <String, dynamic>{'time': time};
    for (final entry in value.entries) {
      parameters[entry.key] = entry.value;
    }

    await statement.run(parameters);
  }

  /// Create a prepared statement for complex insert with specific columns
  Future<Statement> _createComplexInsertStatement(
      String tableName, List<String> columnNames) async {
    final columns = ['time', ...columnNames.map((name) => '"$name"')];
    final placeholders = ['@time', ...columnNames.map((name) => '@$name')];

    final sql = '''
      INSERT INTO "$tableName" (${columns.join(', ')})
      VALUES (${placeholders.join(', ')})
    ''';

    return await prepare(Sql.named(sql));
  }

  /// Query time-series data
  Future<List<TimeseriesData<dynamic>>> queryTimeseriesData(
      String tableName, DateTime since,
      {String? orderBy = 'time ASC'}) async {
    // Create unique key for prepared statement based on table
    final statementKey = 'stream/query_timeseries_$tableName';

    // Get or create prepared statement
    Statement statement;
    if (_preparedStatements.containsKey(statementKey)) {
      statement = _preparedStatements[statementKey]!;
    } else {
      statement = await prepare(Sql.named('''
            SELECT * FROM "$tableName"
            WHERE time >= @since
            ORDER BY time ASC
            '''));
      _preparedStatements[statementKey] = statement;
    }

    // Execute the prepared statement
    final result = await statement.run({'since': since});

    // Map each row to a Map<String, dynamic>
    final columnNames = result.schema.columns
        .map((c) => c.columnName ?? 'unknown_column_${c.typeOid}')
        .toList();
    if (columnNames.contains('time')) {
      DateTime? time;
      return result.map((row) {
        final map = <String, dynamic>{};
        for (var i = 0; i < columnNames.length; i++) {
          if (columnNames[i] == 'time') {
            time = row[i] as DateTime;
          } else {
            map[columnNames[i]] = row[i];
          }
        }
        if (map.length == 1 && map.containsKey('value')) {
          return TimeseriesData(map['value'], time!);
        }
        return TimeseriesData(map, time!);
      }).toList();
    }
    throw DatabaseException('Time column not found in table $tableName');
  }

  Stream<List<TimeseriesData<dynamic>>> streamTimeseriesData(
      String tableName, DateTime since,
      {String? orderBy = 'time ASC'}) {
    // Create unique key for prepared statement based on table
    final statementKey = 'stream/query_timeseries_$tableName';

    // Bind the statement with parameters to get a stream
    late ResultStream stream;

    final controller = StreamController<List<TimeseriesData<dynamic>>>();
    controller.onListen = () async {
      try {
        // Get or create prepared statement
        Statement statement;
        if (_preparedStatements.containsKey(statementKey)) {
          statement = _preparedStatements[statementKey]!;
        } else {
          statement = await prepare(Sql.named('''
            SELECT * FROM "$tableName"
            WHERE time >= @since
            ORDER BY time ASC
            '''));
          _preparedStatements[statementKey] = statement;
        }
        stream = statement.bind({'since': since});
      } catch (e, stackTrace) {
        logger.e('Error streaming timeseries data for $tableName',
            error: e, stackTrace: stackTrace);
        controller.addError(e);
        controller.close();
        return;
      }
      List<String>? columnNames;
      List<TimeseriesData<dynamic>> result = [];

      final subscription = stream.listen((row) {
        try {
          if (controller.isClosed) return;
          columnNames ??= row.schema.columns
              .map((c) => c.columnName ?? 'unknown_column_${c.typeOid}')
              .toList();
          final map = <String, dynamic>{};
          DateTime? time;
          for (var i = 0; i < columnNames!.length; i++) {
            if (columnNames![i] == 'time') {
              time = row[i] as DateTime;
            } else {
              map[columnNames![i]] = row[i];
            }
          }
          if (map.length == 1 && map.containsKey('value')) {
            result.add(TimeseriesData(map['value'], time!));
          } else {
            result.add(TimeseriesData(map, time!));
          }
          controller.add(result);
        } catch (e, stackTrace) {
          logger.e('Error streaming timeseries data for $tableName',
              error: e, stackTrace: stackTrace);
          controller.addError(e);
          controller.close();
        }
      });
      subscription.onError((error, stackTrace) {
        logger.e('Error streaming timeseries data for $tableName',
            error: error, stackTrace: stackTrace);
        controller.addError(error);
      });
      subscription.onDone(() {
        controller.close();
      });
    };

    return controller.stream;
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
    final sinceTimes = <DateTime>[];

    // Generate time buckets from oldest to newest
    for (int i = howMany - 1; i >= 0; i--) {
      final bucketStart = endTime.subtract(interval * (i + 1));
      sinceTimes.add(bucketStart);
    }

    // Create unique key for prepared statement based on table and number of intervals
    final statementKey = 'count_timeseries_${tableName}_$howMany';

    // Get or create prepared statement
    Statement statement;
    if (_preparedStatements.containsKey(statementKey)) {
      statement = _preparedStatements[statementKey]!;
    } else {
      // Build a UNION query for the specific number of intervals
      final unionQueries = <String>[];
      for (int i = 0; i < howMany; i++) {
        final paramName = 'since$i';
        final nextParamName = 'since${i + 1}';
        unionQueries.add('''
          SELECT COUNT(*) as count_$i FROM "$tableName"
          WHERE time >= @$paramName AND time < @$nextParamName
        ''');
      }
      final sql = unionQueries.join(' UNION ALL ');
      statement = await prepare(Sql.named(sql));
      _preparedStatements[statementKey] = statement;
    }

    // Build parameters map
    final parameters = <String, dynamic>{};
    for (int i = 0; i < sinceTimes.length; i++) {
      final paramName = 'since$i';
      final nextParamName = 'since${i + 1}';
      final bucketEnd = i < sinceTimes.length - 1 ? sinceTimes[i + 1] : endTime;

      parameters[paramName] = sinceTimes[i];
      parameters[nextParamName] = bucketEnd;
    }

    // Execute the prepared statement
    final result = await statement.run(parameters);

    // Extract counts from result rows
    final counts = <DateTime, int>{};
    for (int i = 0; i < result.length; i++) {
      counts[sinceTimes[i]] = result[i][0] as int;
    }
    return counts;
  }

  /// Get the retention duration for a hypertable
  Future<RetentionPolicy?> getRetentionPolicy(String tableName) async {
    final result = await execute(Sql.named('''
      SELECT config ->> 'drop_after' AS drop_after, schedule_interval FROM timescaledb_information.jobs
      WHERE proc_name = 'policy_retention' AND hypertable_name = @tableName
    '''), parameters: {'tableName': tableName});
    if (result.isEmpty) {
      return null;
    }
    final dropAfter = result.first[0] as String;
    final scheduleInterval = result.first[1] as Interval?;

    return RetentionPolicy(
      dropAfter: parsePostgresInterval(dropAfter)!,
      scheduleInterval: scheduleInterval?.toDuration(),
    );
  }

  static String? durationToPostgresInterval(Duration? duration) {
    if (duration == null) return null;

    // Use the postgres package's Interval class for consistent formatting
    final interval = Interval.duration(duration);
    return interval.toString();
  }

  static Duration? parsePostgresInterval(String? interval) {
    if (interval == null) return null;

    // TimescaleDB might return intervals in different formats
    // Let's handle the most common cases:

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

    final secondsMatch = RegExp(r'(\d+)\s*second').firstMatch(interval);
    if (secondsMatch != null) {
      final seconds = int.parse(secondsMatch.group(1)!);
      return Duration(seconds: seconds);
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

  Future<void> _createTimeseriesTable(
      String tableName, RetentionPolicy retention, dynamic value) async {
    if (value is Map<String, dynamic>) {
      // Create table with columns for each key in the complex object
      await _createComplexTimeseriesTable(tableName, retention, value);
    } else {
      // Create simple table with time and value columns
      String valueType;
      switch (value) {
        case int():
          valueType = 'INTEGER';
          break;
        case double():
          valueType = 'DOUBLE PRECISION';
          break;
        case bool():
          valueType = 'BOOLEAN';
          break;
        case String():
          valueType = 'TEXT';
          break;
        default:
          valueType = 'JSONB';
          break;
      }
      await execute('''
        CREATE TABLE IF NOT EXISTS "$tableName" (
          time TIMESTAMPTZ NOT NULL,
          value $valueType NOT NULL
        );
      ''');
      await _updateRetentionPolicy(tableName, retention);
    }
  }

  /// Create table for complex objects with separate columns for each key
  Future<void> _createComplexTimeseriesTable(String tableName,
      RetentionPolicy retention, Map<String, dynamic> value) async {
    final columns = ['time TIMESTAMPTZ NOT NULL'];

    for (final entry in value.entries) {
      final columnName = entry.key;
      final columnValue = entry.value;
      final columnType = _getPostgresType(columnValue);
      columns.add('"$columnName" $columnType');
    }

    final createTableSql = '''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        ${columns.join(',\n        ')}
      );
    ''';

    await execute(createTableSql);
    await _updateRetentionPolicy(tableName, retention);
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
      default:
        return 'JSONB'; // For complex nested objects
    }
  }

  Future<void> _updateRetentionPolicy(
      String tableName, RetentionPolicy retention) async {
    // Convert to hypertable
    await execute('''
      SELECT create_hypertable('"$tableName"', 'time', if_not_exists => TRUE, migrate_data => TRUE);
    ''');

    // Remove any existing retention policy first, then add new one
    final dropAfter = durationToPostgresInterval(retention.dropAfter);
    final scheduleInterval =
        durationToPostgresInterval(retention.scheduleInterval);
    await execute('''
      SELECT remove_retention_policy('"$tableName"', if_exists => TRUE);
    ''');
    try {
      if (scheduleInterval != null) {
        await execute('''
        SELECT add_retention_policy('"$tableName"', drop_after => INTERVAL '$dropAfter', schedule_interval => INTERVAL '$scheduleInterval');
      ''');
      } else {
        await execute('''
          SELECT add_retention_policy('"$tableName"', drop_after => INTERVAL '$dropAfter');
        ''');
      }
    } catch (e) {
      stderr.writeln('Error updating retention policy for $tableName: $e');
    }
  }

  /// Returns true if the table was created successfully, false if it already exists or policy is missing
  Future<bool> _tryToCreateTimeseriesTable(
      String tableName, dynamic value) async {
    // Check if table exists
    if (await tableExists(tableName)) {
      return false;
    }
    if (!retentionPolicies.containsKey(tableName)) {
      stderr.writeln(
          'Table $tableName does not exist, and no retention policy is set');
      return false;
    }

    await _createTimeseriesTable(
        tableName, retentionPolicies[tableName]!, value);
    return true;
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
