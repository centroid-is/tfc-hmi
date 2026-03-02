import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

final dockerComposePath = '${Directory.current.path}/test/integration';

/// Per-test-file database container manager.
///
/// Each test file creates its own [TestDb] with a dedicated compose file,
/// container name, and port so integration tests can run in parallel.
class TestDb {
  final String composeFile;
  final String containerName;
  final int port;

  TestDb({
    required this.composeFile,
    required this.containerName,
    required this.port,
  });

  /// Start (or restart) the container via docker compose.
  Future<void> start() async {
    // Tear down any previous run first
    await _compose(['down', '--remove-orphans']);
    final result = await _compose(['up', '-d']);
    if (result.exitCode != 0) {
      throw Exception(
          'Failed to start $composeFile: ${result.stderr}');
    }
    print('[$containerName] started on port $port');
  }

  /// Tear down the container via docker compose.
  Future<void> stop() async {
    final result = await _compose(['down']);
    if (result.exitCode != 0) {
      print('Warning: Failed to stop $composeFile: ${result.stderr}');
    } else {
      print('[$containerName] stopped');
    }
  }

  /// Stop the container without removing it (simulates DB outage).
  Future<void> stopContainer() async {
    final result = await Process.run('docker', ['stop', containerName]);
    if (result.exitCode != 0) {
      throw Exception('Failed to stop $containerName: ${result.stderr}');
    }
    print('[$containerName] container stopped');
  }

  /// Restart a stopped container (simulates DB recovery).
  Future<void> startContainer() async {
    final result = await Process.run('docker', ['start', containerName]);
    if (result.exitCode != 0) {
      throw Exception('Failed to start $containerName: ${result.stderr}');
    }
    print('[$containerName] container started');
  }

  /// Database config pointing to this container's port.
  DatabaseConfig config() {
    return DatabaseConfig(
      postgres: Endpoint(
        host: 'localhost',
        port: port,
        database: 'testdb',
        username: 'testuser',
        password: 'testpass',
      ),
      sslMode: SslMode.disable,
      debug: true,
    );
  }

  /// Open a raw postgres connection.
  Future<Connection> connection() async {
    final cfg = config();
    return Connection.open(
      cfg.postgres!,
      settings: ConnectionSettings(sslMode: cfg.sslMode),
    );
  }

  /// Poll until the database accepts connections.
  Future<void> waitForReady() async {
    const maxAttempts = 30;
    const delay = Duration(seconds: 1);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final conn = await connection();
        await conn.close();
        print('[$containerName] ready after $attempt attempts');
        return;
      } catch (e) {
        if (attempt == maxAttempts) {
          throw Exception(
              '[$containerName] not ready after $maxAttempts attempts: $e');
        }
        print('[$containerName] not ready (attempt $attempt/$maxAttempts)');
        await Future.delayed(delay);
      }
    }
  }

  /// Create a full Database connection.
  Future<Database> connect() async {
    final db = Database(await AppDatabase.spawn(config()));
    await db.db.open();
    return db;
  }

  Future<ProcessResult> _compose(List<String> args) {
    return Process.run(
      'docker',
      ['compose', '-p', containerName, '-f', composeFile, ...args],
      workingDirectory: dockerComposePath,
    );
  }
}

// ---------------------------------------------------------------------------
// Legacy helpers (kept for backwards compatibility)
// ---------------------------------------------------------------------------

/// Starts Docker Compose services
Future<void> startDockerCompose() async {
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

/// Stops Docker Compose services
Future<void> stopDockerCompose() async {
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

/// Stops just the timescaledb container (simulates DB outage)
Future<void> stopTimescaleDb() async {
  final result = await Process.run(
    'docker',
    ['stop', 'test-db'],
  );
  if (result.exitCode != 0) {
    throw Exception('Failed to stop timescaledb: ${result.stderr}');
  }
  print('TimescaleDB stopped');
}

/// Starts just the timescaledb container (simulates DB recovery)
Future<void> startTimescaleDb() async {
  final result = await Process.run(
    'docker',
    ['start', 'test-db'],
  );
  if (result.exitCode != 0) {
    throw Exception('Failed to start timescaledb: ${result.stderr}');
  }
  print('TimescaleDB started');
}
