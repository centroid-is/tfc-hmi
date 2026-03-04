import 'dart:async';
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

/// Simulates a database outage by switching the TCP proxy to reject mode.
/// The proxy keeps listening but immediately destroys incoming connections,
/// giving an instant connection-reset on all platforms (including Windows,
/// where closing the socket causes a slow connect-timeout instead of
/// ECONNREFUSED).
Future<void> stopTimescaleDb() async {
  await _dbProxy.stop();
}

/// Simulates database recovery by restarting the TCP proxy.
Future<void> startTimescaleDb() async {
  await _dbProxy.start();
  await waitForDatabaseReady();
}

// ---------------------------------------------------------------------------
// TCP proxy – sits between tests and PostgreSQL.
// To simulate DB outage: stop the proxy.
// To simulate recovery: restart the proxy.
// PostgreSQL stays running the entire time – no platform-specific stop/start.
// ---------------------------------------------------------------------------

const _proxyPort = 15432;
const _realPgPort = 5432;
final _dbProxy = DbProxy(listenPort: _proxyPort, targetPort: _realPgPort);

class DbProxy {
  final int listenPort;
  final int targetPort;
  ServerSocket? _server;
  final List<_DbProxyPair> _connections = [];

  /// When true, the proxy accepts TCP connections but immediately destroys
  /// them.  This gives an instant connection-reset on every platform
  /// (unlike closing the ServerSocket, which causes a slow connect-timeout
  /// on Windows instead of ECONNREFUSED).
  bool _rejecting = false;

  bool get isRunning => _server != null && !_rejecting;

  DbProxy({required this.listenPort, required this.targetPort});

  Future<void> start() async {
    _rejecting = false;
    if (_server != null) {
      print('[db-proxy] forwarding on $listenPort → $targetPort');
      return; // server socket already bound, just clear reject flag
    }
    _server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, listenPort);
    _server!.listen(_handleConnection);
    print('[db-proxy] listening on $listenPort → $targetPort');
  }

  void _handleConnection(Socket clientSocket) async {
    // Reject mode: accept the TCP handshake, then immediately destroy.
    // The client sees an instant RST on all platforms.
    if (_rejecting) {
      try {
        clientSocket.destroy();
      } catch (_) {}
      return;
    }
    try {
      final serverSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        targetPort,
        timeout: const Duration(seconds: 5),
      );
      // Re-check after await: stop() may have been called during connect.
      if (_rejecting) {
        try {
          clientSocket.destroy();
        } catch (_) {}
        try {
          serverSocket.destroy();
        } catch (_) {}
        return;
      }
      final pair = _DbProxyPair(clientSocket, serverSocket);
      _connections.add(pair);
      pair.start(() => _connections.remove(pair));
    } catch (e) {
      try {
        clientSocket.destroy();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _rejecting = true;
    // Close all existing forwarding connections immediately.
    for (final conn in List.of(_connections)) {
      conn.close();
    }
    _connections.clear();
    // Yield to let any in-flight _handleConnection callbacks see
    // _rejecting == true and destroy their connections.
    await Future.delayed(const Duration(milliseconds: 100));
    // Clean up any pairs that slipped through the race window.
    for (final conn in List.of(_connections)) {
      conn.close();
    }
    _connections.clear();
    print('[db-proxy] rejecting connections');
  }

  /// Fully shuts down the proxy (used in tearDownAll).
  Future<void> shutdown() async {
    _rejecting = true;
    final server = _server;
    _server = null;
    await server?.close();
    for (final conn in List.of(_connections)) {
      conn.close();
    }
    _connections.clear();
    print('[db-proxy] shut down');
  }
}

class _DbProxyPair {
  final Socket client;
  final Socket server;
  StreamSubscription? _clientSub;
  StreamSubscription? _serverSub;
  bool _closed = false;

  _DbProxyPair(this.client, this.server);

  void start(void Function() onClose) {
    client.done.catchError((_) {});
    server.done.catchError((_) {});
    _clientSub = client.listen(
      (data) {
        try {
          server.add(data);
        } catch (_) {}
      },
      onDone: () => _doClose(onClose),
      onError: (_) => _doClose(onClose),
    );
    _serverSub = server.listen(
      (data) {
        try {
          client.add(data);
        } catch (_) {}
      },
      onDone: () => _doClose(onClose),
      onError: (_) => _doClose(onClose),
    );
  }

  void _doClose(void Function() onClose) {
    close();
    onClose();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _clientSub?.cancel();
    _serverSub?.cancel();
    try {
      client.destroy();
    } catch (_) {}
    try {
      server.destroy();
    } catch (_) {}
  }
}

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
