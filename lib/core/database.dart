import 'package:postgres/postgres.dart';
import 'package:json_annotation/json_annotation.dart';

export 'package:postgres/postgres.dart' show Sql;

part 'database.g.dart';

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

class Database implements Session {
  Database(this.config);

  Connection? connection;
  final DatabaseConfig config;
  static const configLocation = 'database_config';

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

  /// Create a TimescaleDB hypertable for time-series data
  Future<void> createTimeseriesTable(
      String tableName, Duration retention) async {
    // Create the table with simple schema
    await execute('''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        time TIMESTAMPTZ NOT NULL,
        value JSONB NOT NULL
      );
    ''');

    // Convert to hypertable
    await execute('''
      SELECT create_hypertable('$tableName', 'time', if_not_exists => TRUE);
    ''');

    // Remove any existing retention policy first, then add new one
    final retentionMinutes = retention.inMinutes;
    await execute('''
      SELECT remove_retention_policy('$tableName', if_exists => TRUE);
    ''');
    await execute('''
      SELECT add_retention_policy('$tableName', drop_after => INTERVAL '$retentionMinutes minutes');
    ''');
  }

  /// Insert a time-series data point
  Future<void> insertTimeseriesData(
      String tableName, DateTime time, dynamic value) async {
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
  Future<Duration> getRetentionDuration(String tableName) async {
    final result = await execute(Sql.named('''
      SELECT config ->> 'drop_after' AS drop_after FROM timescaledb_information.jobs
      WHERE proc_name = 'policy_retention' AND hypertable_name = @tableName
    '''), parameters: {'tableName': tableName});
    return parsePostgresInterval(result.first[0] as String);
  }

  static Duration parsePostgresInterval(String interval) {
    // PostgreSQL interval format: "00:10:00" (HH:MM:SS)
    final parts = interval.split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final seconds = int.parse(parts[2]);
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    throw FormatException('Invalid PostgreSQL interval format: $interval');
  }
}
