import 'dart:io' show Platform;

import 'package:postgres/postgres.dart' as pg;

/// Database connection configuration for the MCP server.
///
/// This class decouples the MCP server from direct `Platform.environment`
/// reads, making the DB config injectable from any source:
///
/// - **Standalone binary** (Claude Desktop): uses [fromEnvironment] which
///   reads `CENTROID_PG*` env vars with CLI arg fallbacks.
/// - **In-process mode** (Flutter app): the Flutter side constructs a
///   [ServerDatabaseConfig] from secure storage and injects it directly.
/// - **Tests**: construct directly with explicit [endpoint] values.
class ServerDatabaseConfig {
  /// The PostgreSQL endpoint to connect to.
  final pg.Endpoint endpoint;

  /// SSL mode for the connection.
  final pg.SslMode sslMode;

  /// Creates a config with an explicit endpoint.
  const ServerDatabaseConfig({
    required this.endpoint,
    this.sslMode = pg.SslMode.disable,
  });

  /// Creates a config from environment variables and optional CLI arg fallbacks.
  ///
  /// Resolution order for each field:
  /// 1. Environment variable (e.g. `CENTROID_PGHOST`)
  /// 2. CLI argument from [cliArgs] (e.g. `db-host`)
  /// 3. Hard-coded default
  ///
  /// [envProvider] defaults to `Platform.environment[key]` but can be injected
  /// for testing or for non-standard env sources.
  ///
  /// [cliArgs] maps CLI option names to their string values (e.g., from
  /// `ArgResults`). Keys use the `db-host`, `db-port`, etc. naming convention.
  factory ServerDatabaseConfig.fromEnvironment({
    String? Function(String key)? envProvider,
    Map<String, String> cliArgs = const {},
  }) {
    final env = envProvider ?? (key) => Platform.environment[key];

    final host =
        env('CENTROID_PGHOST') ?? cliArgs['db-host'] ?? 'localhost';
    final portStr =
        env('CENTROID_PGPORT') ?? cliArgs['db-port'] ?? '5432';
    final port = int.tryParse(portStr) ?? 5432;
    final database =
        env('CENTROID_PGDATABASE') ?? cliArgs['db-name'] ?? 'hmi';
    final username =
        env('CENTROID_PGUSER') ?? cliArgs['db-user'] ?? 'postgres';
    final password =
        env('CENTROID_PGPASSWORD') ?? cliArgs['db-password'] ?? '';

    final sslModeStr = env('CENTROID_PGSSLMODE');
    final sslMode = sslModeStr != null
        ? pg.SslMode.values.firstWhere(
            (mode) => mode.name == sslModeStr,
            orElse: () => pg.SslMode.disable,
          )
        : pg.SslMode.disable;

    return ServerDatabaseConfig(
      endpoint: pg.Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      ),
      sslMode: sslMode,
    );
  }

  @override
  String toString() {
    return 'ServerDatabaseConfig('
        'host: ${endpoint.host}, '
        'port: ${endpoint.port}, '
        'database: ${endpoint.database}, '
        'username: ${endpoint.username}, '
        'sslMode: ${sslMode.name}'
        ')';
  }
}
