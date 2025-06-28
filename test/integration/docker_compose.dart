import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:tfc/core/database.dart';

final dockerComposePath = '${Directory.current.path}/test/integration';
const databaseName = 'testdb';

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

/// Waits for the database to be ready by attempting connections
Future<void> waitForDatabaseReady() async {
  const maxAttempts = 30;
  const delay = Duration(seconds: 1);

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final testConfig = DatabaseConfig(
        postgres: Endpoint(
          host: 'localhost',
          port: 5432,
          database: 'testdb',
          username: 'testuser',
          password: 'testpass',
        ),
        sslMode: SslMode.disable,
      );

      final testDb = Database(testConfig);
      await testDb.connect();
      await testDb.close();

      print('Database is ready after $attempt attempts');
      return;
    } catch (e) {
      if (attempt == maxAttempts) {
        throw Exception(
            'Database failed to become ready after $maxAttempts attempts: $e');
      }
      print(
          'Database not ready yet (attempt $attempt/$maxAttempts), waiting...');
      await Future.delayed(delay);
    }
  }
}

Future<Database> connectToDatabase() async {
  final testConfig = DatabaseConfig(
    postgres: Endpoint(
      host: 'localhost',
      port: 5432,
      database: databaseName,
      username: 'testuser',
      password: 'testpass',
    ),
    sslMode: SslMode.disable,
  );
  final db = Database(testConfig);
  await db.connect();
  return db;
}
