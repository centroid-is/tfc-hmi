import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/collector.dart';
import '../core/state_man.dart';
import '../core/database.dart';
import '../core/database_drift.dart';

import 'state_man.dart';

part 'data_acquisition.g.dart';

/// Holds running worker isolates so callers can shut them down.
class DataAcquisition {
  final List<_CollectorHandle> _handles;
  DataAcquisition({required List<_CollectorHandle> handles})
      : _handles = handles;

  List<Isolate> get collectors => _handles.map((h) => h.isolate).toList();

  Future<void> closeAll() async {
    for (final h in _handles) {
      h.dispose();
      try {
        h.isolate.kill(priority: Isolate.immediate);
      } catch (_) {
        // ignore
      }
    }
  }
}

/// Message sent to worker isolates at startup.
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

/// Simple backoff: 200ms, 400ms, 800ms … capped at 5s.
int _backoffMs(int attempt) {
  final ms = 200 * (1 << (attempt - 1));
  if (ms < 200) return 200;
  if (ms > 5000) return 5000;
  return ms;
}

/// Main entry point for worker isolate.
/// Keep it simple: open DB, wait for readiness, build StateMan + Collector, then idle.
/// If anything throws *outside* awaited code (timers/streams inside Collector),
/// the isolate will crash; the supervisor in the main isolate will respawn it.
@pragma('vm:entry-point')
void entryPoint(IsolateMessage isolateMessage) async {
  // Optional: light logging to stderr (visible in docker logs, etc.)
  void log(Object o) => stderr.writeln('[${isolateMessage.serverName}] $o');

  try {
    // Create AppDatabase and open socket
    final appDb = await AppDatabase.create(isolateMessage.databaseConfig);
    await appDb.open();

    // Gate on actual readiness: handles DNS not ready, "connection refused", "starting up"
    await withDbRetry(() async {
      await appDb.customSelect('SELECT 1').get();
    }, onRetry: (attempt, error, next) {
      log('DB not ready, retry #$attempt in ${next.inMilliseconds}ms: $error');
    });

    final database = Database(appDb);

    // Build StateMan for this worker
    final stateMan = await StateMan.create(
      config: isolateMessage.stateManConfig,
      keyMappings: isolateMessage.keyMappings,
      useIsolate: false,
    );

    // Start the collector (it may immediately issue DB writes)
    final _ = Collector(
      config: CollectorConfig(collect: true),
      stateMan: stateMan,
      database: database,
    );

    log('collector started');

    // Keep alive indefinitely; supervisor listens for crashes and will respawn on exit.
    final keepAlive = Completer<void>();
    await keepAlive.future;
  } catch (e, st) {
    log('fatal during worker startup: $e');
    log(st);
    // Let the isolate exit; the supervisor will restart it.
  }
}

/// Internal handle the supervisor keeps for each worker.
class _CollectorHandle {
  final String serverName;
  final Isolate isolate;
  final ReceivePort _exitPort;
  final ReceivePort _errorPort;
  final StreamSubscription _exitSub;
  final StreamSubscription _errorSub;
  int restartAttempt;

  _CollectorHandle({
    required this.serverName,
    required this.isolate,
    required ReceivePort exitPort,
    required ReceivePort errorPort,
    required StreamSubscription exitSub,
    required StreamSubscription errorSub,
    required this.restartAttempt,
  })  : _exitPort = exitPort,
        _errorPort = errorPort,
        _exitSub = exitSub,
        _errorSub = errorSub;

  void dispose() {
    _exitSub.cancel();
    _errorSub.cancel();
    _exitPort.close();
    _errorPort.close();
  }
}

final _logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
  ),
);

/// Spawns a single worker isolate and wires up exit+error listeners that call [onExitOrError].
Future<_CollectorHandle> _spawnWorker({
  required String serverName,
  required IsolateMessage message,
  required void Function(String server, bool crashed) onExitOrError,
  int restartAttempt = 1,
}) async {
  final exitPort = ReceivePort();
  final errorPort = ReceivePort();

  final isolate = await Isolate.spawn(
    entryPoint,
    message,
    debugName: 'collector-$serverName',
    errorsAreFatal: true,
    onExit: exitPort
        .sendPort, // also available via addOnExitListener; this is convenient
  );

  // Route errors (as [error, stack] lists) -> callback
  final errorSub = errorPort.listen((dynamic payload) {
    try {
      final list = payload as List<dynamic>;
      final error = list.isNotEmpty ? list[0] : 'unknown';
      final stack = list.length > 1 ? list[1] : '';
      _logger.e('Worker error ($serverName): $error',
          error: error, stackTrace: stack);
    } catch (_) {
      _logger.e('Worker error ($serverName): $payload');
    }
    onExitOrError(serverName, true);
  });

  // Attach the error port
  isolate.addErrorListener(errorPort.sendPort);

  // When the isolate exits (normal or crash), this fires
  final exitSub = exitPort.listen((_) {
    _logger.w('Worker exited ($serverName)');
    onExitOrError(serverName, false);
  });

  _logger.i('Spawned worker for server: $serverName (attempt $restartAttempt)');

  return _CollectorHandle(
    serverName: serverName,
    isolate: isolate,
    exitPort: exitPort,
    errorPort: errorPort,
    exitSub: exitSub,
    errorSub: errorSub,
    restartAttempt: restartAttempt,
  );
}

/// Supervisor: spawns N workers (one per server with collect-entries), and restarts whichever dies.
@Riverpod(keepAlive: true)
Future<DataAcquisition> dataAcquisition(Ref ref) async {
  final stateMan = await ref.watch(stateManProvider.future);
  final stateManConfig = stateMan.config;

  // Build server -> keyMappings of items that should be collected
  final Map<String?, KeyMappings> collectEntries = {};
  for (final entry in stateMan.keyMappings.nodes.entries) {
    if (entry.value.collect != null) {
      collectEntries[entry.value.server] ??= KeyMappings(nodes: {});
      collectEntries[entry.value.server]!.nodes[entry.key] = KeyMappingEntry(
        opcuaNode: entry.value.opcuaNode,
        collect: entry.value.collect,
      );
    }
  }

  // server -> StateManConfig (one server per worker isolate)
  final Map<String?, StateManConfig> serverConfigs = {};
  for (final server in stateManConfig.opcua) {
    serverConfigs[server.serverAlias] = StateManConfig(opcua: [server]);
  }

  final handles = <_CollectorHandle>[];
  final byServer = <String, _CollectorHandle>{};

  // Callback used by each worker’s error/exit listeners to schedule restarts
  Future<void> scheduleRestart(String server, bool crashed) async {
    final h = byServer[server];
    if (h == null) return;

    // Dispose old listeners & remove from map
    h.dispose();
    byServer.remove(server);

    final nextAttempt = (h.restartAttempt + 1).clamp(1, 32);
    final delay = Duration(milliseconds: _backoffMs(nextAttempt));
    _logger.w(
        'Scheduling restart for $server in ${delay.inMilliseconds}ms (attempt $nextAttempt)');

    await Future.delayed(delay);

    // Rebuild message fresh (DB prefs may have changed)
    final msg = IsolateMessage(
      serverName: server,
      keyMappings: collectEntries[server]!,
      stateManConfig: serverConfigs[server]!,
      databaseConfig: await DatabaseConfig.fromPrefs(),
    );

    // Spawn replacement and track it
    final newHandle = await _spawnWorker(
      serverName: server,
      message: msg,
      onExitOrError: (s, crashed) => scheduleRestart(s, crashed),
      restartAttempt: nextAttempt,
    );
    handles.add(newHandle);
    byServer[server] = newHandle;

    // Reset attempt after a successful spawn; if it dies again, it will increment anew.
    newHandle.restartAttempt = 1;
  }

  // Initial spawn for each server with collect-entries
  for (final server in serverConfigs.keys) {
    final name = server ?? 'unknown';
    if (!collectEntries.containsKey(server)) continue;

    final message = IsolateMessage(
      serverName: name,
      keyMappings: collectEntries[server]!,
      stateManConfig: serverConfigs[server]!,
      databaseConfig: await DatabaseConfig.fromPrefs(),
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

  // Clean up everything when the provider is disposed (app shutdown)
  ref.onDispose(() async {
    for (final h in handles) {
      h.dispose();
      try {
        h.isolate.kill(priority: Isolate.immediate);
      } catch (_) {}
    }
  });

  return DataAcquisition(handles: handles);
}

// lib/core/db_retry.dart
//
// Lightweight retry + backoff wrapper for transient DB connectivity issues.
// Designed to work without importing driver-specific types. It recognizes:
//  - SocketException (DNS lookup failures, connection refused, resets, etc.)
//  - Postgres "starting up" (SQLSTATE 57P03) or similar messages
//  - Generic transient phrases in exception messages
//
// Usage:
//   final rows = await withDbRetry(() => db.customSelect('SELECT 1').get());
//
// You can override what counts as "transient" via the `isTransient` parameter,
// and observe retries via `onRetry`.

typedef AsyncOp<T> = Future<T> Function();

Future<T> withDbRetry<T>(
  AsyncOp<T> op, {
  int maxAttempts = 10,
  Duration initialDelay = const Duration(milliseconds: 200),
  Duration maxDelay = const Duration(seconds: 5),
  void Function(int attempt, Object error, Duration nextDelay)? onRetry,
  bool Function(Object error)? isTransient,
}) async {
  Object? lastErr;
  final transient = isTransient ?? _defaultIsTransient;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await op();
    } catch (e) {
      lastErr = e;

      // Stop immediately on non-transient errors or when out of attempts.
      if (!transient(e) || attempt == maxAttempts) {
        break;
      }

      final delay = _expBackoff(attempt, initialDelay, maxDelay);
      if (onRetry != null) onRetry(attempt, e, delay);
      await Future.delayed(delay);
    }
  }

  // ignore: only_throw_errors
  throw lastErr ?? Exception('DB operation failed (unknown error)');
}

bool _defaultIsTransient(Object e) {
  // Network/IO problems are transient by default.
  if (e is SocketException) return true;
  if (e is TimeoutException) return true;

  // Postgres "database is starting up"
  final code = _sqlState(e);
  if (code == '57P03') return true;

  // Fallback: look for common transient phrases.
  final msg = e.toString().toLowerCase();
  const hints = <String>[
    'starting up',
    'connection refused',
    'connection reset',
    'broken pipe',
    'failed host lookup',
    'temporary failure in name resolution',
    'could not connect',
    'connection closed',
    'server closed the connection',
    'terminating connection',
    'the database system is starting up',
  ];
  for (final h in hints) {
    if (msg.contains(h)) return true;
  }
  return false;
}

/// Best-effort extractor for SQLSTATE without importing driver types.
/// Works with postgres.dart's PostgresException which exposes `code`.
String? _sqlState(Object e) {
  try {
    final dynamic d = e;
    final code = d.code;
    if (code is String && code.length == 5) return code;
  } catch (_) {
    // ignore
  }
  return null;
}

Duration _expBackoff(int attempt, Duration initial, Duration max) {
  // 200ms, 400ms, 800ms, ... capped at `max`.
  final factor = 1 << (attempt - 1);
  final ms = initial.inMilliseconds * factor;
  final capped = ms > max.inMilliseconds ? max.inMilliseconds : ms;
  return Duration(milliseconds: capped);
}
