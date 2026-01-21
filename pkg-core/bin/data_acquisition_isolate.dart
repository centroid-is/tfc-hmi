import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:logger/logger.dart';
import 'package:tfc_core/core/collector.dart';
import 'package:tfc_core/core/database.dart';
import 'package:tfc_core/core/database_drift.dart';
import 'package:tfc_core/core/state_man.dart';

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
Future<void> dataAcquisitionIsolateEntry(DataAcquisitionIsolateConfig config) async {
  Logger.defaultFilter = () => _TraceFilter();
  final logger = Logger();

  final server = OpcUAConfig.fromJson(config.serverJson);
  final dbConfig = DatabaseConfig.fromJson(config.dbConfigJson);
  final keyMappings = KeyMappings.fromJson(config.keyMappingsJson);

  logger.i('Starting DataAcquisition isolate for server: ${server.serverAlias ?? server.endpoint}');

  final db = Database(await AppDatabase.create(dbConfig));
  final smConfig = StateManConfig(opcua: [server]);

  final stateMan = await StateMan.create(
    config: smConfig,
    keyMappings: keyMappings,
    useIsolate: false, // Already in isolate, no need for nested isolates
  );

  final collector = Collector(
    config: CollectorConfig(collect: true),
    stateMan: stateMan,
    database: db,
  );

  logger.i('DataAcquisition isolate running for ${server.serverAlias ?? server.endpoint}');

  // Keep isolate alive indefinitely
  await Completer<void>().future;
}

/// Spawn a DataAcquisition isolate for a single server.
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

  final errorPort = ReceivePort();
  errorPort.listen((message) {
    final error = message[0];
    final stackTrace = message[1];
    stderr.writeln('Isolate error for ${server.serverAlias ?? server.endpoint}:');
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    exit(1);
  });

  final exitPort = ReceivePort();
  exitPort.listen((_) {
    Logger().e('Isolate exited unexpectedly for ${server.serverAlias ?? server.endpoint}');
    exit(1);
  });

  await Isolate.spawn(
    dataAcquisitionIsolateEntry,
    config,
    onError: errorPort.sendPort,
    onExit: exitPort.sendPort,
  );
}
