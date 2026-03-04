import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

import '../proxy.dart';

final dockerComposePath = '${Directory.current.path}/test/integration';
const databaseName = 'testdb';

/// True when a native (non-Docker) TimescaleDB is provided externally.
/// Set TIMESCALEDB_EXTERNAL=1 in the environment to enable this mode.
bool get _useExternalDb =>
    Platform.environment['TIMESCALEDB_EXTERNAL'] == '1';

/// Simulates a database outage by switching the TCP proxy to reject mode.
/// The proxy keeps listening but immediately destroys incoming connections,
/// giving an instant connection-reset on all platforms (including Windows,
/// where closing the socket causes a slow connect-timeout instead of
/// ECONNREFUSED).
Future<void> stopTimescaleDb() async {
  await _dbProxy.reject();
  print('[db-proxy] rejecting connections');
}

/// Simulates database recovery by restarting the TCP proxy.
Future<void> startTimescaleDb() async {
  await _dbProxy.start();
  print('[db-proxy] forwarding on ${_dbProxy.port} → $_realPgPort');
  await waitForDatabaseReady();
}

// ---------------------------------------------------------------------------
// TCP proxy – sits between tests and PostgreSQL.
// To simulate DB outage: reject via the proxy.
// To simulate recovery: restart the proxy.
// PostgreSQL stays running the entire time – no platform-specific stop/start.
// ---------------------------------------------------------------------------

const _proxyPort = 15432;
const _realPgPort = 5432;
final _dbProxy =
    TcpProxy(listenPort: _proxyPort, targetPort: _realPgPort);

// ---------------------------------------------------------------------------
// Docker Compose / external DB lifecycle (used once in setUpAll / tearDownAll)
// ---------------------------------------------------------------------------

/// Starts Docker Compose services (no-op when TIMESCALEDB_EXTERNAL=1).
Future<void> startDockerCompose() async {
  if (_useExternalDb) {
    print('TIMESCALEDB_EXTERNAL=1: skipping Docker Compose startup');
    return;
  }
  try {
    final result = await Process.run(
      'docker',
      ['compose', 'up', '-d'],
      workingDirectory: dockerComposePath,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to start Docker Compose: ${result.stderr}');
    }

    print('Docker Compose services started successfully');
  } catch (e) {
    final res = await Process.run(
      'pwd',
      [],
      workingDirectory: dockerComposePath,
    );

    throw Exception(
        'Failed to start Docker Compose from folder ${res.stdout}: $e');
  }
}

/// Stops Docker Compose services (no-op when TIMESCALEDB_EXTERNAL=1).
Future<void> stopDockerCompose() async {
  // Fully shut down the proxy so the next test run starts clean.
  await _dbProxy.shutdown();
  print('[db-proxy] shut down');

  if (_useExternalDb) {
    print('TIMESCALEDB_EXTERNAL=1: skipping Docker Compose teardown');
    return;
  }
  try {
    final result = await Process.run(
      'docker',
      ['compose', 'down'],
      workingDirectory: dockerComposePath,
    );

    if (result.exitCode != 0) {
      print('Warning: Failed to stop Docker Compose: ${result.stderr}');
    } else {
      print('Docker Compose services stopped successfully');
    }
  } catch (e) {
    final res = await Process.run(
      'pwd',
      [],
      workingDirectory: dockerComposePath,
    );

    throw Exception(
        'Failed to stop Docker Compose from folder ${res.stdout}: $e');
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

DatabaseConfig getTestConfig() {
  return DatabaseConfig(
    postgres: Endpoint(
      host: 'localhost',
      port: _proxyPort,
      database: 'testdb',
      username: 'testuser',
      password: 'testpass',
    ),
    sslMode: SslMode.disable,
    debug: true,
    // Short pool timeouts so queries fail fast when proxy is down.
    // Prevents pool queries from bridging simulated outages.
    connectTimeout: const Duration(seconds: 2),
    queryTimeout: const Duration(seconds: 5),
  );
}

Future<Connection> getTestConnection() async {
  final testConfig = getTestConfig();

  final testDb = await Connection.open(
    testConfig.postgres!,
    settings: ConnectionSettings(
      sslMode: testConfig.sslMode,
    ),
  );

  return testDb;
}

/// Waits for the database to be ready by attempting connections through the
/// proxy.  Ensures the proxy is started first.
Future<void> waitForDatabaseReady() async {
  await _dbProxy.start();

  const maxAttempts = 30;
  const delay = Duration(seconds: 1);

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final testDb = await getTestConnection();
      await testDb.close();

      print('Database is ready after $attempt attempts');
      return;
    } catch (e) {
      if (attempt == maxAttempts) {
        throw Exception(
            'Database failed to become ready after $maxAttempts attempts: $e');
      }
      print(
          'Database not ready yet (attempt $attempt/$maxAttempts), waiting..., $e');
      await Future.delayed(delay);
    }
  }
}

Future<Database> connectToDatabase() async {
  final db = Database(await AppDatabase.spawn(getTestConfig()));
  await db.db.open();
  return db;
}

// ---------------------------------------------------------------------------
// Simulated DB outage / recovery (used by resilience tests)
// ---------------------------------------------------------------------------
