import 'package:postgres/postgres.dart';
import 'package:json_annotation/json_annotation.dart';

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
}

class DatabaseException implements Exception {
  DatabaseException(this.message);

  final String message;
}

class Database {
  Database(this.config);

  Connection? connection;
  final DatabaseConfig config;

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

  Future<void> execute(String sql) async {
    await connect();
    await connection!.execute(sql);
  }

  bool get connected => connection != null && connection!.isOpen;
}
