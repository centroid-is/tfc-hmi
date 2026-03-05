import 'dart:async';
import 'dart:isolate';

import 'package:logger/logger.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/state_man.dart';

class _TraceFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => true;
}

/// Configuration for spawning a DataAcquisition isolate.
class DataAcquisitionIsolateConfig {
  final Map<String, dynamic>? serverJson;
  final Map<String, dynamic> dbConfigJson;
  final Map<String, dynamic> keyMappingsJson;
  final List<Map<String, dynamic>> jbtmJson;
  final bool enableStatsLogging;

  DataAcquisitionIsolateConfig({
    this.serverJson,
    required this.dbConfigJson,
    required this.keyMappingsJson,
    this.jbtmJson = const [],
    this.enableStatsLogging = false,
  });
}

/// Isolate entry point for running DataAcquisition.
///
/// Supports OPC UA (single server via [serverJson]) and/or M2400 devices
/// (multiple servers via [jbtmJson]).
@pragma('vm:entry-point')
Future<void> dataAcquisitionIsolateEntry(
    DataAcquisitionIsolateConfig config) async {
  Logger.defaultFilter = () => _TraceFilter();
  final logger = Logger();

  final dbConfig = DatabaseConfig.fromJson(config.dbConfigJson);
  final keyMappings = KeyMappings.fromJson(config.keyMappingsJson);

  // Build OPC UA config
  final opcuaServers = <OpcUAConfig>[];
  String isolateName;
  if (config.serverJson != null) {
    final server = OpcUAConfig.fromJson(config.serverJson!);
    opcuaServers.add(server);
    isolateName = server.serverAlias ?? server.endpoint;
  } else {
    isolateName = 'jbtm';
  }

  // Build M2400 configs
  final jbtmConfigs =
      config.jbtmJson.map((j) => M2400Config.fromJson(j)).toList();

  logger.i('Starting DataAcquisition isolate "$isolateName" '
      '(opcua: ${opcuaServers.length}, m2400: ${jbtmConfigs.length})');

  final db = await Database.connectWithRetry(dbConfig, useIsolate: false);
  final smConfig = StateManConfig(opcua: opcuaServers, jbtm: jbtmConfigs);

  // Create M2400 device clients
  final deviceClients = createM2400DeviceClients(jbtmConfigs);

  final stateMan = await StateMan.create(
    config: smConfig,
    keyMappings: keyMappings,
    useIsolate: false, // Already in isolate, no need for nested isolates
    alias: 'data_acq',
    deviceClients: deviceClients,
  );

  // ignore: unused_local_variable
  final collector = Collector(
    config: CollectorConfig(collect: true),
    stateMan: stateMan,
    database: db,
  );

  logger.i('DataAcquisition isolate running for $isolateName');

  // Keep isolate alive indefinitely
  await Completer<void>().future;
}

/// Spawn a DataAcquisition isolate for a single OPC UA server.
/// Automatically respawns the isolate on failure with exponential backoff.
Future<void> spawnDataAcquisitionIsolate({
  required OpcUAConfig server,
  required DatabaseConfig dbConfig,
  required KeyMappings keyMappings,
  bool enableStatsLogging = false,
}) async {
  final config = DataAcquisitionIsolateConfig(
    serverJson: server.toJson(),
    dbConfigJson: dbConfig.toJson(),
    keyMappingsJson: keyMappings.toJson(),
    enableStatsLogging: enableStatsLogging,
  );

  final serverName = server.serverAlias ?? server.endpoint;
  await _spawnWithRespawn(config, serverName);
}

/// Spawn a single DataAcquisition isolate for all M2400 servers.
/// Automatically respawns on failure with exponential backoff.
Future<void> spawnM2400DataAcquisitionIsolate({
  required List<M2400Config> servers,
  required DatabaseConfig dbConfig,
  required KeyMappings keyMappings,
  bool enableStatsLogging = false,
}) async {
  final config = DataAcquisitionIsolateConfig(
    dbConfigJson: dbConfig.toJson(),
    keyMappingsJson: keyMappings.toJson(),
    jbtmJson: servers.map((s) => s.toJson()).toList(),
    enableStatsLogging: enableStatsLogging,
  );

  final aliases = servers.map((s) => s.serverAlias ?? s.host).join(', ');
  await _spawnWithRespawn(config, 'jbtm[$aliases]');
}

Future<void> _spawnWithRespawn(
    DataAcquisitionIsolateConfig config, String name) async {
  final logger = Logger();
  var restartDelay = const Duration(seconds: 2);
  const maxDelay = Duration(seconds: 30);

  Future<void> spawn() async {
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    void scheduleRespawn(String reason) {
      errorPort.close();
      exitPort.close();
      logger.w(
          'Respawning isolate for $name in ${restartDelay.inSeconds}s ($reason)');
      Future.delayed(restartDelay, () {
        restartDelay = restartDelay * 2;
        if (restartDelay > maxDelay) restartDelay = maxDelay;
        spawn();
      });
    }

    errorPort.listen((message) {
      final error = message[0];
      final stackTrace = message[1];
      logger.e('Isolate error for $name:\n$error\n$stackTrace');
      scheduleRespawn('uncaught error');
    });

    exitPort.listen((_) {
      logger.e('Isolate exited unexpectedly for $name');
      scheduleRespawn('unexpected exit');
    });

    try {
      await Isolate.spawn(
        dataAcquisitionIsolateEntry,
        config,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      // Reset backoff on successful spawn
      restartDelay = const Duration(seconds: 2);
    } catch (e) {
      logger.e('Failed to spawn isolate for $name: $e');
      scheduleRespawn('spawn failure');
    }
  }

  await spawn();
}
