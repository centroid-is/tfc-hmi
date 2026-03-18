import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/preferences.dart' show Preferences;
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    show
        AlarmReader,
        DriftDrawingIndex,
        DriftTechDocIndex,
        EnvOperatorIdentity,
        McpConfig,
        McpDatabase,
        StateReader,
        readMcpConfigFromPreferences;

import '../mcp/alarm_man_alarm_reader.dart';
import '../mcp/mcp_lifecycle_state.dart';
import '../mcp/mcp_bridge_notifier.dart';
import '../mcp/state_man_state_reader.dart';
import 'alarm.dart';
import 'database.dart' show databaseProvider;
import 'plc.dart' show plcCodeIndexProvider;
import 'preferences.dart' show preferencesProvider;
import 'state_man.dart';

export '../mcp/mcp_bridge_notifier.dart'
    show
        McpBridgeNotifier,
        McpBridgeState,
        McpConnectionState,
        kMcpConfigKey;

/// Provides a singleton [McpBridgeNotifier] for managing the SSE MCP server.
///
/// Uses [ChangeNotifierProvider] so that [ref.watch] consumers rebuild
/// when the bridge state changes (e.g., server starts/stops).
final mcpBridgeProvider = ChangeNotifierProvider<McpBridgeNotifier>((ref) {
  final notifier = McpBridgeNotifier();
  ref.onDispose(() {
    notifier.dispose();
  });
  return notifier;
});

/// Assembles the environment variable map for the MCP server subprocess.
Map<String, String> getMcpServerEnv() {
  final env = io.Platform.environment;
  return {
    if (env['CENTROID_PGHOST'] != null)
      'CENTROID_PGHOST': env['CENTROID_PGHOST']!,
    if (env['CENTROID_PGPORT'] != null)
      'CENTROID_PGPORT': env['CENTROID_PGPORT']!,
    if (env['CENTROID_PGDATABASE'] != null)
      'CENTROID_PGDATABASE': env['CENTROID_PGDATABASE']!,
    if (env['CENTROID_PGUSER'] != null)
      'CENTROID_PGUSER': env['CENTROID_PGUSER']!,
    if (env['CENTROID_PGPASSWORD'] != null)
      'CENTROID_PGPASSWORD': env['CENTROID_PGPASSWORD']!,
  };
}

/// Returns the operator identity from TFC_USER environment variable.
String getMcpOperatorId() {
  return io.Platform.environment['TFC_USER'] ?? 'operator';
}

/// Whether the MCP chat feature is available.
bool isMcpChatAvailable() {
  return io.Platform.environment.containsKey('TFC_USER');
}


/// Mutable state for the MCP server lifecycle provider.
final _serverLifecycle = McpLifecycleState();

/// Provider for the consolidated MCP config (single JSON blob).
final mcpConfigProvider = FutureProvider<McpConfig>((ref) async {
  final prefs = await ref.watch(preferencesProvider.future);
  return await readMcpConfigFromPreferences(prefs);
});

/// Provider for the MCP server enabled preference.
final mcpEnabledProvider = FutureProvider<bool>((ref) async {
  final config = await ref.watch(mcpConfigProvider.future);
  return config.serverEnabled;
});

/// Provider for the in-app chat bubble preference.
final mcpChatEnabledProvider = FutureProvider<bool>((ref) async {
  final config = await ref.watch(mcpConfigProvider.future);
  return config.chatEnabled;
});

/// Provider for the MCP server port preference.
final mcpPortProvider = FutureProvider<int>((ref) async {
  final config = await ref.watch(mcpConfigProvider.future);
  return config.port;
});

/// No-op reader for when StateMan is unavailable (no OPC-UA connection).
class _EmptyStateReader implements StateReader {
  @override
  Map<String, dynamic> get currentValues => {};
  @override
  dynamic getValue(String key) => null;
  @override
  List<String> get keys => [];
}

/// No-op reader for when AlarmMan is unavailable.
class _EmptyAlarmReader implements AlarmReader {
  @override
  List<Map<String, dynamic>> get alarmConfigs => [];
}

/// Starts the SSE server, using live data readers if available.
///
/// If StateMan or AlarmMan aren't ready (e.g., no OPC-UA connection),
/// the server starts anyway with empty readers. Config, drawings, PLC
/// code, and trend tools still work without live data.
Future<void> _startServer(McpBridgeNotifier bridge, int port,
    {required Ref ref}) async {
  StateReader stateReader;
  AlarmReader alarmReader;

  // Await live readers; fall back to empty no-ops only on actual error.
  try {
    final stateMan = await ref.read(stateManProvider.future);
    final reader = StateManStateReader(stateMan);
    await reader.init();
    _serverLifecycle.activeStateReader = reader;
    stateReader = reader;
  } catch (e) {
    io.stderr.writeln('_startServer: StateMan unavailable, using empty reader: $e');
    stateReader = _EmptyStateReader();
  }

  try {
    final alarmMan = await ref.read(alarmManProvider.future);
    alarmReader = AlarmManAlarmReader(alarmMan);
  } catch (e) {
    io.stderr.writeln('_startServer: AlarmMan unavailable, using empty reader: $e');
    alarmReader = _EmptyAlarmReader();
  }

  final dbWrapper = await ref.read(databaseProvider.future);
  if (dbWrapper == null) {
    throw StateError('Database not connected');
  }
  final McpDatabase database = dbWrapper.db;
  final identity = EnvOperatorIdentity();

  final config = await ref.read(mcpConfigProvider.future);

  await bridge.startSseServer(
    port,
    stateReader: stateReader,
    alarmReader: alarmReader,
    database: database,
    identity: identity,
    toggles: config.toggles,
    drawingIndex: DriftDrawingIndex(database),
    plcCodeIndex: ref.read(plcCodeIndexProvider),
    techDocIndex: DriftTechDocIndex(database),
  );
}

/// Manages the MCP SSE server lifecycle based on the enabled preference.
///
/// When [mcpEnabledProvider] is true, starts the SSE server on the configured
/// port with live StateMan/AlarmMan readers.
///
/// When it goes false, stops the server.
///
/// Also watches config preference changes for debounced server restart.
final mcpServerLifecycleProvider = Provider<void>((ref) {
  // Watch enabled state changes.
  // Ignore AsyncLoading transitions to avoid stop/restart cycles when
  // preferencesProvider is temporarily invalidated (e.g. database reconnect).
  ref.listen<AsyncValue<bool>>(mcpEnabledProvider, (prev, next) async {
    // Skip loading states — preserve whatever is currently running.
    if (next is AsyncLoading) return;

    final enabled = next.valueOrNull ?? false;
    final bridge = ref.read(mcpBridgeProvider);

    if (enabled && !bridge.isRunning) {
      try {
        final port = await ref.read(mcpPortProvider.future);
        await _startServer(bridge, port, ref: ref);
      } catch (e) {
        io.stderr.writeln('mcpServerLifecycleProvider: failed to start: $e');
        _serverLifecycle.disposeReader();
      }
    } else if (!enabled && bridge.isRunning) {
      _serverLifecycle.disposeReader();
      await bridge.stopSseServer();
    }
  });

  // Watch config preference changes for debounced server restart.
  // Listens for changes to the consolidated McpConfig key.
  ref.listen<AsyncValue<Preferences>>(preferencesProvider, (prev, next) {
    final prefs = next.valueOrNull;
    if (prefs == null) return;
    if (_serverLifecycle.toggleListenerSetUp) return;
    _serverLifecycle.toggleListenerSetUp = true;

    final sub = prefs.onPreferencesChanged.listen((key) {
      if (key != McpConfig.kPrefKey) return;

      final bridge = ref.read(mcpBridgeProvider);
      if (!bridge.isRunning) return;

      _serverLifecycle.cancelTimer();
      _serverLifecycle.reconnectTimer = Timer(const Duration(milliseconds: 800), () async {
        try {
          await bridge.stopSseServer();
          _serverLifecycle.disposeReader();

          // Re-read config to get latest toggles/port.
          ref.invalidate(mcpConfigProvider);
          final port = await ref.read(mcpPortProvider.future);
          await _startServer(bridge, port, ref: ref);
        } catch (e) {
          io.stderr.writeln('Toggle reconnect failed: $e');
        }
      });
    });

    ref.onDispose(() {
      sub.cancel();
      _serverLifecycle.dispose();
    });
  });
});
