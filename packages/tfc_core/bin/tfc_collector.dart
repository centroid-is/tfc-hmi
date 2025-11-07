import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:tfc_core/tfc_core.dart';

/// TFC Data Collector - Headless OPC UA to PostgreSQL data collector
///
/// This executable spawns one isolate per OPC UA server for efficient
/// parallel data collection without Flutter/UI overhead.
///
/// Usage:
///   dart run tfc_core:tfc_collector
///   OR
///   dart compile exe bin/tfc_collector.dart -o tfc_collector
///   ./tfc_collector
///
/// Configuration: Use `tfc_config` TUI tool to set up database and OPC UA servers.

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);

/// Message sent to worker isolates at startup
class IsolateMessage {
  final String serverName;
  final KeyMappings keyMappings;
  final StateManConfig stateManConfig;
  final DatabaseConfig databaseConfig;

  IsolateMessage({
    required this.serverName,
    required this.keyMappings,
    required this.stateManConfig,
    required this.databaseConfig,
  });
}

/// Worker isolate entry point - one per OPC UA server
@pragma('vm:entry-point')
void workerEntryPoint(IsolateMessage msg) async {
  void log(Object o) => stderr.writeln('[${msg.serverName}] $o');

  try {
    log('Starting worker...');

    // Create and open database connection
    final appDb = await AppDatabase.spawn(msg.databaseConfig);
    await appDb.open();

    // Wait for database readiness with retry logic
    await _withDbRetry(() async {
      await appDb.customSelect('SELECT 1').get();
    }, onRetry: (attempt, error, next) {
      log('DB not ready, retry #$attempt in ${next.inMilliseconds}ms: $error');
    });

    final database = Database(appDb);
    log('Database connected');

    // Build StateMan for this server (no isolate since we're already in one)
    final stateMan = await StateMan.create(
      config: msg.stateManConfig,
      keyMappings: msg.keyMappings,
      useIsolate: false,
    );
    log('OPC UA client connected');

    // Start collector
    final _ = Collector(
      config: CollectorConfig(collect: true),
      stateMan: stateMan,
      database: database,
    );
    log('Collector started - collecting ${msg.keyMappings.nodes.length} signal(s)');

    // Keep alive indefinitely
    final keepAlive = Completer<void>();
    await keepAlive.future;
  } catch (e, st) {
    log('FATAL: $e');
    log('$st');
    rethrow;
  }
}

/// Handle for tracking worker isolates
class _WorkerHandle {
  final String serverName;
  final Isolate isolate;
  final ReceivePort exitPort;
  final ReceivePort errorPort;
  final StreamSubscription exitSub;
  final StreamSubscription errorSub;
  int restartAttempt;

  _WorkerHandle({
    required this.serverName,
    required this.isolate,
    required this.exitPort,
    required this.errorPort,
    required this.exitSub,
    required this.errorSub,
    required this.restartAttempt,
  });

  void dispose() {
    exitSub.cancel();
    errorSub.cancel();
    exitPort.close();
    errorPort.close();
  }
}

/// Backoff calculation: 200ms, 400ms, 800ms ... capped at 5s
int _backoffMs(int attempt) {
  final ms = 200 * (1 << (attempt - 1));
  return ms.clamp(200, 5000);
}

/// Spawn a single worker isolate with supervision
Future<_WorkerHandle> _spawnWorker({
  required String serverName,
  required IsolateMessage message,
  required void Function(String server, bool crashed) onExitOrError,
  int restartAttempt = 1,
}) async {
  final exitPort = ReceivePort();
  final errorPort = ReceivePort();

  final isolate = await Isolate.spawn(
    workerEntryPoint,
    message,
    debugName: 'collector-$serverName',
    errorsAreFatal: true,
    onExit: exitPort.sendPort,
  );

  // Handle errors
  final errorSub = errorPort.listen((dynamic payload) {
    try {
      final list = payload as List<dynamic>;
      final error = list.isNotEmpty ? list[0] : 'unknown';
      final stack = list.length > 1 ? list[1] : '';
      logger.e('Worker error ($serverName): $error', error: error, stackTrace: stack);
    } catch (_) {
      logger.e('Worker error ($serverName): $payload');
    }
    onExitOrError(serverName, true);
  });

  isolate.addErrorListener(errorPort.sendPort);

  // Handle exits
  final exitSub = exitPort.listen((_) {
    logger.w('Worker exited ($serverName)');
    onExitOrError(serverName, false);
  });

  logger.i('Spawned worker for server: $serverName (attempt $restartAttempt)');

  return _WorkerHandle(
    serverName: serverName,
    isolate: isolate,
    exitPort: exitPort,
    errorPort: errorPort,
    exitSub: exitSub,
    errorSub: errorSub,
    restartAttempt: restartAttempt,
  );
}

Future<void> main(List<String> arguments) async {
  logger.i('═══════════════════════════════════════════════════════');
  logger.i('TFC Data Collector - Pure Dart Edition');
  logger.i('Isolate-based architecture for optimal performance');
  logger.i('═══════════════════════════════════════════════════════');
  logger.i('');

  try {
    // Load configuration from secure storage
    logger.i('Loading configuration...');
    final secureStorage = SecureStorage.getInstance();
    final dbConfigJson = await secureStorage.read(key: 'database_config');
    final stateManConfigJson = await secureStorage.read(key: 'state_man_config');

    if (dbConfigJson == null || stateManConfigJson == null) {
      logger.w('Configuration not found in secure storage.');
      logger.i('');
      logger.i('Please run the configuration tool first:');
      logger.i('  dart run tfc_core:tfc_config');
      logger.i('');
      logger.i('Or use the Flutter UI application (centroid-hmi)');
      exit(0);
    }

    final dbConfig = DatabaseConfig.fromJson(jsonDecode(dbConfigJson));
    final stateManConfig = StateManConfig.fromJson(jsonDecode(stateManConfigJson));

    logger.i('✓ Configuration loaded');
    logger.i('  Database: ${dbConfig.postgres?.host ?? "SQLite (local)"}');
    logger.i('  OPC UA servers: ${stateManConfig.opcua.length}');
    logger.i('');

    // Load preferences to get KeyMappings
    logger.i('Loading preferences and key mappings...');
    final appDb = await AppDatabase.spawn(dbConfig);
    final database = Database(appDb);
    await database.open();
    final prefs = await Preferences.create(db: database);

    // Build the full StateMan to extract key mappings
    final fullStateMan = await StateMan.create(
      config: stateManConfig,
      keyMappings: KeyMappings(nodes: {}), // Will load from prefs
      useIsolate: false,
    );

    // Build server -> keyMappings for items that should be collected
    final Map<String?, KeyMappings> collectEntries = {};
    for (final entry in fullStateMan.keyMappings.nodes.entries) {
      if (entry.value.collect != null) {
        collectEntries[entry.value.server] ??= KeyMappings(nodes: {});
        collectEntries[entry.value.server]!.nodes[entry.key] = KeyMappingEntry(
          opcuaNode: entry.value.opcuaNode,
          collect: entry.value.collect,
        );
      }
    }

    // Build server -> StateManConfig (one server per worker isolate)
    final Map<String?, StateManConfig> serverConfigs = {};
    for (final server in stateManConfig.opcua) {
      serverConfigs[server.serverAlias] = StateManConfig(opcua: [server]);
    }

    logger.i('✓ Found ${collectEntries.length} server(s) with data to collect');
    logger.i('');

    final handles = <_WorkerHandle>[];
    final byServer = <String, _WorkerHandle>{};

    // Callback for restarting crashed workers
    Future<void> scheduleRestart(String server, bool crashed) async {
      final h = byServer[server];
      if (h == null) return;

      h.dispose();
      byServer.remove(server);

      final nextAttempt = (h.restartAttempt + 1).clamp(1, 32);
      final delay = Duration(milliseconds: _backoffMs(nextAttempt));
      logger.w('Restarting $server in ${delay.inMilliseconds}ms (attempt $nextAttempt)');

      await Future.delayed(delay);

      // Respawn
      final msg = IsolateMessage(
        serverName: server,
        keyMappings: collectEntries[server]!,
        stateManConfig: serverConfigs[server]!,
        databaseConfig: dbConfig,
      );

      final newHandle = await _spawnWorker(
        serverName: server,
        message: msg,
        onExitOrError: (s, crashed) => scheduleRestart(s, crashed),
        restartAttempt: nextAttempt,
      );

      handles.add(newHandle);
      byServer[server] = newHandle;
      newHandle.restartAttempt = 1;
    }

    // Spawn workers for each server with collect-entries
    for (final server in serverConfigs.keys) {
      final name = server ?? 'unknown';
      if (!collectEntries.containsKey(server)) {
        logger.w('Skipping $name: no signals configured for collection');
        continue;
      }

      final message = IsolateMessage(
        serverName: name,
        keyMappings: collectEntries[server]!,
        stateManConfig: serverConfigs[server]!,
        databaseConfig: dbConfig,
      );

      final handle = await _spawnWorker(
        serverName: name,
        message: message,
        onExitOrError: (s, crashed) => scheduleRestart(s, crashed),
        restartAttempt: 1,
      );

      handles.add(handle);
      byServer[name] = handle;
    }

    logger.i('');
    logger.i('═══════════════════════════════════════════════════════');
    logger.i('TFC Data Collector is running');
    logger.i('${handles.length} worker(s) active, collecting data...');
    logger.i('Press Ctrl+C to stop');
    logger.i('═══════════════════════════════════════════════════════');

    // Setup signal handlers for graceful shutdown
    ProcessSignal.sigint.watch().listen((signal) async {
      logger.i('');
      logger.i('Shutting down gracefully...');
      for (final h in handles) {
        h.dispose();
        h.isolate.kill(priority: Isolate.immediate);
      }
      await database.close();
      logger.i('Goodbye!');
      exit(0);
    });

    ProcessSignal.sigterm.watch().listen((signal) async {
      logger.i('');
      logger.i('Received SIGTERM, shutting down...');
      for (final h in handles) {
        h.dispose();
        h.isolate.kill(priority: Isolate.immediate);
      }
      await database.close();
      exit(0);
    });

    // Keep alive
    await Future<void>.delayed(const Duration(days: 365 * 100));

  } catch (e, stackTrace) {
    logger.e('Fatal error', error: e, stackTrace: stackTrace);
    logger.i('');
    logger.i('Please check your configuration and try again.');
    logger.i('Run: dart run tfc_core:tfc_config');
    exit(1);
  }
}

// Simple DB retry logic
Future<T> _withDbRetry<T>(
  Future<T> Function() op, {
  int maxAttempts = 10,
  void Function(int attempt, Object error, Duration nextDelay)? onRetry,
}) async {
  Object? lastErr;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await op();
    } catch (e) {
      lastErr = e;

      if (attempt == maxAttempts) break;

      final delay = Duration(milliseconds: 200 * (1 << (attempt - 1)));
      final capped = delay.inMilliseconds > 5000
          ? const Duration(seconds: 5)
          : delay;

      if (onRetry != null) onRetry(attempt, e, capped);
      await Future.delayed(capped);
    }
  }

  throw lastErr ?? Exception('DB operation failed');
}
