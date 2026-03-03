import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

final dockerComposePath = '${Directory.current.path}/test/integration';
const databaseName = 'testdb';

/// True when a native (non-Docker) TimescaleDB is provided externally.
/// Set TIMESCALEDB_EXTERNAL=1 in the environment to enable this mode.
bool get _useExternalDb =>
    Platform.environment['TIMESCALEDB_EXTERNAL'] == '1';

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

DatabaseConfig getTestConfig() {
  return DatabaseConfig(
    postgres: Endpoint(
      host: 'localhost',
      port: 5432,
      database: 'testdb',
      username: 'testuser',
      password: 'testpass',
    ),
    sslMode: SslMode.disable,
    debug: true,
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

/// Waits for the database to be ready by attempting connections
Future<void> waitForDatabaseReady() async {
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

/// Stops just the timescaledb container (simulates DB outage).
/// When TIMESCALEDB_EXTERNAL=1, stops the native Homebrew PostgreSQL service.
Future<void> stopTimescaleDb() async {
  if (_useExternalDb) {
    final serviceName =
        Platform.environment['PG_SERVICE_NAME'] ?? 'postgresql@17';
    final result = await Process.run('brew', ['services', 'stop', serviceName]);
    if (result.exitCode != 0) {
      throw Exception('Failed to stop native PostgreSQL: ${result.stderr}');
    }
    print('Native PostgreSQL stopped');
    return;
  }
  final result = await Process.run(
    'docker',
    ['stop', 'test-db'],
  );
  if (result.exitCode != 0) {
    throw Exception('Failed to stop timescaledb: ${result.stderr}');
  }
  print('TimescaleDB stopped');
}

/// Starts just the timescaledb container (simulates DB recovery).
/// When TIMESCALEDB_EXTERNAL=1, starts the native Homebrew PostgreSQL service.
Future<void> startTimescaleDb() async {
  if (_useExternalDb) {
    final serviceName =
        Platform.environment['PG_SERVICE_NAME'] ?? 'postgresql@17';
    final result =
        await Process.run('brew', ['services', 'start', serviceName]);
    if (result.exitCode != 0) {
      throw Exception('Failed to start native PostgreSQL: ${result.stderr}');
    }
    // Wait for PostgreSQL to become ready after restart
    await waitForDatabaseReady();
    print('Native PostgreSQL started');
    return;
  }
  final result = await Process.run(
    'docker',
    ['start', 'test-db'],
  );
  if (result.exitCode != 0) {
    throw Exception('Failed to start timescaledb: ${result.stderr}');
  }
  print('TimescaleDB started');
}
