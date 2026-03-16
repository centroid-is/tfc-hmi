import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart';

void main() {
  group('ServerDatabaseConfig', () {
    group('direct construction', () {
      test('creates config with explicit endpoint', () {
        final endpoint = pg.Endpoint(
          host: 'db.example.com',
          port: 5433,
          database: 'mydb',
          username: 'admin',
          password: 'secret',
        );

        final config = ServerDatabaseConfig(
          endpoint: endpoint,
          sslMode: pg.SslMode.require,
        );

        expect(config.endpoint.host, 'db.example.com');
        expect(config.endpoint.port, 5433);
        expect(config.endpoint.database, 'mydb');
        expect(config.endpoint.username, 'admin');
        expect(config.endpoint.password, 'secret');
        expect(config.sslMode, pg.SslMode.require);
      });

      test('defaults sslMode to disable', () {
        final config = ServerDatabaseConfig(
          endpoint: pg.Endpoint(
            host: 'localhost',
            port: 5432,
            database: 'hmi',
          ),
        );

        expect(config.sslMode, pg.SslMode.disable);
      });
    });

    group('fromEnvironment', () {
      test('reads all CENTROID_PG* vars from env provider', () {
        final config = ServerDatabaseConfig.fromEnvironment(
          envProvider: (key) => {
            'CENTROID_PGHOST': 'pg.example.com',
            'CENTROID_PGPORT': '5433',
            'CENTROID_PGDATABASE': 'production',
            'CENTROID_PGUSER': 'app_user',
            'CENTROID_PGPASSWORD': 'app_pass',
            'CENTROID_PGSSLMODE': 'require',
          }[key],
        );

        expect(config.endpoint.host, 'pg.example.com');
        expect(config.endpoint.port, 5433);
        expect(config.endpoint.database, 'production');
        expect(config.endpoint.username, 'app_user');
        expect(config.endpoint.password, 'app_pass');
        expect(config.sslMode, pg.SslMode.require);
      });

      test('uses defaults when env vars are missing', () {
        final config = ServerDatabaseConfig.fromEnvironment(
          envProvider: (_) => null,
        );

        expect(config.endpoint.host, 'localhost');
        expect(config.endpoint.port, 5432);
        expect(config.endpoint.database, 'hmi');
        expect(config.endpoint.username, 'postgres');
        expect(config.endpoint.password, '');
        expect(config.sslMode, pg.SslMode.disable);
      });

      test('uses CLI arg fallbacks for missing env vars', () {
        final config = ServerDatabaseConfig.fromEnvironment(
          envProvider: (key) => {
            'CENTROID_PGHOST': 'env-host',
          }[key],
          cliArgs: {
            'db-host': 'cli-host',
            'db-port': '5434',
            'db-name': 'cli-db',
            'db-user': 'cli-user',
            'db-password': 'cli-pass',
          },
        );

        // CENTROID_PGHOST is set, so env wins over CLI
        expect(config.endpoint.host, 'env-host');
        // These fall through to CLI args
        expect(config.endpoint.port, 5434);
        expect(config.endpoint.database, 'cli-db');
        expect(config.endpoint.username, 'cli-user');
        expect(config.endpoint.password, 'cli-pass');
      });

      test('env vars take precedence over CLI args', () {
        final config = ServerDatabaseConfig.fromEnvironment(
          envProvider: (key) => {
            'CENTROID_PGHOST': 'env-host',
            'CENTROID_PGPORT': '5433',
            'CENTROID_PGDATABASE': 'env-db',
            'CENTROID_PGUSER': 'env-user',
            'CENTROID_PGPASSWORD': 'env-pass',
          }[key],
          cliArgs: {
            'db-host': 'cli-host',
            'db-port': '9999',
            'db-name': 'cli-db',
            'db-user': 'cli-user',
            'db-password': 'cli-pass',
          },
        );

        expect(config.endpoint.host, 'env-host');
        expect(config.endpoint.port, 5433);
        expect(config.endpoint.database, 'env-db');
        expect(config.endpoint.username, 'env-user');
        expect(config.endpoint.password, 'env-pass');
      });

      test('handles invalid port gracefully', () {
        final config = ServerDatabaseConfig.fromEnvironment(
          envProvider: (key) =>
              key == 'CENTROID_PGPORT' ? 'not-a-number' : null,
        );

        // Falls back to default port
        expect(config.endpoint.port, 5432);
      });

      test('handles unknown SSL mode gracefully', () {
        final config = ServerDatabaseConfig.fromEnvironment(
          envProvider: (key) =>
              key == 'CENTROID_PGSSLMODE' ? 'unknown_mode' : null,
        );

        expect(config.sslMode, pg.SslMode.disable);
      });

      test('reads from Platform.environment by default', () {
        // When no envProvider is given, it should use Platform.environment.
        // We can't control Platform.environment in tests, but we verify
        // the factory doesn't throw.
        final config = ServerDatabaseConfig.fromEnvironment();
        expect(config, isNotNull);
        expect(config.endpoint, isNotNull);
      });
    });

    group('ServerDatabase.fromConfig', () {
      test('creates a database from config', () {
        final config = ServerDatabaseConfig(
          endpoint: pg.Endpoint(
            host: 'localhost',
            port: 5432,
            database: 'test',
            username: 'test',
            password: 'test',
          ),
        );

        final db = ServerDatabase.fromConfig(config);
        expect(db, isA<ServerDatabase>());
      });

      test('passes sslMode through to pool', () {
        final config = ServerDatabaseConfig(
          endpoint: pg.Endpoint(
            host: 'localhost',
            port: 5432,
            database: 'test',
          ),
          sslMode: pg.SslMode.require,
        );

        // Should not throw
        final db = ServerDatabase.fromConfig(config);
        expect(db, isA<ServerDatabase>());
      });
    });

    group('toString', () {
      test('produces readable output without password', () {
        final config = ServerDatabaseConfig(
          endpoint: pg.Endpoint(
            host: 'db.example.com',
            port: 5433,
            database: 'prod',
            username: 'admin',
            password: 'super_secret',
          ),
        );

        final str = config.toString();
        expect(str, contains('db.example.com'));
        expect(str, contains('5433'));
        expect(str, contains('prod'));
        expect(str, isNot(contains('super_secret')));
      });
    });
  });
}
