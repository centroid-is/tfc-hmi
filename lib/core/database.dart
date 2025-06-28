import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:json_annotation/json_annotation.dart';
export 'package:postgres/postgres.dart' show Sql;

import 'duration_converter.dart';

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

  Connection? connection;
  final DatabaseConfig config;
  static const configLocation = 'database_config';
  Map<String, RetentionPolicy> retentionPolicies = {};

  Future<void> connect() async {
    if (connection != null && connection!.isOpen) {
      return;
    }
    connection = await Connection.open(
      config.postgres!,
      settings: ConnectionSettings(sslMode: config.sslMode),
    ).onError((error, stackTrace) {
      throw DatabaseException(
        'Connection to Postgres failed: $error\n $stackTrace',
      );
    });
  }

  @override
  bool get isOpen => connection != null && connection!.isOpen;

  @override
  Future<void> get closed => connection?.closed ?? Future.value();

  Future<void> close() async {
    await connection?.close();
  }

  @override
  Future<Statement> prepare(Object /* String | Sql */ query) async {
    await connect();
    return connection!.prepare(query);
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
    return connection!.execute(query,
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
      await execute(
        Sql.named('''
      INSERT INTO "$tableName" (time, value)
      VALUES (@time, @value)
      '''),
        parameters: {
          'time': time,
          'value': value,
        },
      );
    }

    try {
      await insert();
    } catch (e) {
      if (await _tryToCreateTimeseriesTable(tableName, value)) {
        await insert();
      } else {
        rethrow;
      }
    }
  }

  /// Query time-series data
  Future<List<List<dynamic>>> queryTimeseriesData(
      String tableName, DateTime? since,
      {String? orderBy = 'time ASC'}) async {
    final result = await execute(
      since != null ? Sql.named('''
            SELECT time, value FROM "$tableName"
            WHERE time >= @since
            ORDER BY $orderBy
            ''') : Sql.named('''
            SELECT time, value FROM "$tableName"
            ORDER BY $orderBy
            '''),
      parameters: since != null ? {'since': since} : null,
    );
    return result.toList();
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
      String tableName, RetentionPolicy retention, String valueType) async {
    // Create the table with simple schema
    await execute('''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        time TIMESTAMPTZ NOT NULL,
        value $valueType NOT NULL
      );
    ''');
    await _updateRetentionPolicy(tableName, retention);
  }

  Future<void> _updateRetentionPolicy(
      String tableName, RetentionPolicy retention) async {
    // Convert to hypertable
    await execute('''
      SELECT create_hypertable('$tableName', 'time', if_not_exists => TRUE);
    ''');

    // Remove any existing retention policy first, then add new one
    final dropAfter = durationToPostgresInterval(retention.dropAfter);
    final scheduleInterval =
        durationToPostgresInterval(retention.scheduleInterval);
    await execute('''
      SELECT remove_retention_policy('$tableName', if_exists => TRUE);
    ''');
    if (scheduleInterval != null) {
      await execute('''
        SELECT add_retention_policy('$tableName', drop_after => INTERVAL '$dropAfter', schedule_interval => INTERVAL '$scheduleInterval');
      ''');
    } else {
      await execute('''
        SELECT add_retention_policy('$tableName', drop_after => INTERVAL '$dropAfter');
      ''');
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
    String dataType;

    switch (value) {
      case int():
        dataType = 'INTEGER';
        break;
      case double():
        dataType = 'DOUBLE PRECISION';
        break;
      case bool():
        dataType = 'BOOLEAN';
        break;
      case String():
        dataType = 'TEXT';
        break;
      default:
        dataType = 'JSONB';
        break;
    }
    await _createTimeseriesTable(
        tableName, retentionPolicies[tableName]!, dataType);
    return true;
  }
}
