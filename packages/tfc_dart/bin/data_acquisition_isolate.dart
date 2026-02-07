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
  final Map<String, dynamic> serverJson;
  final Map<String, dynamic> dbConfigJson;
  final Map<String, dynamic> keyMappingsJson;
  final bool enableStatsLogging;

  DataAcquisitionIsolateConfig({
    required this.serverJson,
    required this.dbConfigJson,
    required this.keyMappingsJson,
    this.enableStatsLogging = false,
  });
}

/// Isolate entry point for running DataAcquisition for a single server.
@pragma('vm:entry-point')
Future<void> dataAcquisitionIsolateEntry(
    DataAcquisitionIsolateConfig config) async {
  Logger.defaultFilter = () => _TraceFilter();
  final logger = Logger();

  final server = OpcUAConfig.fromJson(config.serverJson);
  final dbConfig = DatabaseConfig.fromJson(config.dbConfigJson);
  final keyMappings = KeyMappings.fromJson(config.keyMappingsJson);
  final serverName = server.serverAlias ?? server.endpoint;

  logger.i('Starting DataAcquisition isolate for server: $serverName');

  final db = await Database.connectWithRetry(dbConfig, useIsolate: false);
  final smConfig = StateManConfig(opcua: [server]);

  final stateMan = await StateMan.create(
    config: smConfig,
    keyMappings: keyMappings,
    useIsolate: false, // Already in isolate, no need for nested isolates
    alias: 'data_acq',
  );

  // ignore: unused_local_variable
  final collector = Collector(
    config: CollectorConfig(collect: true),
    stateMan: stateMan,
    database: db,
  );

  logger.i('DataAcquisition isolate running for $serverName');

  // Keep isolate alive indefinitely
  await Completer<void>().future;
}

/// Spawn a DataAcquisition isolate for a single server.
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
          'Respawning isolate for $serverName in ${restartDelay.inSeconds}s ($reason)');
      Future.delayed(restartDelay, () {
        restartDelay = restartDelay * 2;
        if (restartDelay > maxDelay) restartDelay = maxDelay;
        spawn();
      });
    }

    errorPort.listen((message) {
      final error = message[0];
      final stackTrace = message[1];
      logger.e('Isolate error for $serverName:\n$error\n$stackTrace');
      scheduleRespawn('uncaught error');
    });

    exitPort.listen((_) {
      logger.e('Isolate exited unexpectedly for $serverName');
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
      logger.e('Failed to spawn isolate for $serverName: $e');
      scheduleRespawn('spawn failure');
    }
  }

  await spawn();
}
