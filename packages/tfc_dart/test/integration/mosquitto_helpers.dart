import 'dart:async';
import 'dart:io';

final _dockerComposePath = '${Directory.current.path}/test/integration';

/// True when an external Mosquitto broker is provided.
/// Set MOSQUITTO_EXTERNAL=1 in the environment to skip Docker lifecycle.
bool get _useExternalBroker =>
    Platform.environment['MOSQUITTO_EXTERNAL'] == '1';

/// Starts Mosquitto via docker compose (no-op if MOSQUITTO_EXTERNAL=1).
Future<void> startMosquitto() async {
  if (_useExternalBroker) {
    print('MOSQUITTO_EXTERNAL=1: skipping Docker Compose startup');
    return;
  }
  try {
    final result = await Process.run(
      'docker',
      ['compose', 'up', '-d', 'mosquitto'],
      workingDirectory: _dockerComposePath,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to start Mosquitto: ${result.stderr}');
    }

    print('Mosquitto service started successfully');
  } catch (e) {
    throw Exception('Failed to start Mosquitto: $e');
  }
}

/// Stops Mosquitto via docker compose (no-op if MOSQUITTO_EXTERNAL=1).
Future<void> stopMosquitto() async {
  if (_useExternalBroker) {
    print('MOSQUITTO_EXTERNAL=1: skipping Docker Compose teardown');
    return;
  }
  try {
    final result = await Process.run(
      'docker',
      ['compose', 'down'],
      workingDirectory: _dockerComposePath,
    );

    if (result.exitCode != 0) {
      print('Warning: Failed to stop Mosquitto: ${result.stderr}');
    } else {
      print('Mosquitto service stopped successfully');
    }
  } catch (e) {
    throw Exception('Failed to stop Mosquitto: $e');
  }
}

/// Polls localhost:1883 until MQTT connection succeeds (max 30 attempts, 1s delay).
Future<void> waitForMosquittoReady() async {
  const maxAttempts = 30;
  const delay = Duration(seconds: 1);

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final socket = await Socket.connect('localhost', 1883,
          timeout: const Duration(seconds: 2));
      await socket.close();
      print('Mosquitto is ready after $attempt attempts');
      return;
    } catch (e) {
      if (attempt == maxAttempts) {
        throw Exception(
            'Mosquitto failed to become ready after $maxAttempts attempts: $e');
      }
      print(
          'Mosquitto not ready yet (attempt $attempt/$maxAttempts), waiting...');
      await Future.delayed(delay);
    }
  }
}
