import 'dart:async';
import 'dart:io';

import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/alarm.dart';

import 'package:logger/logger.dart';
import 'data_acquisition_isolate.dart';

class TraceFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true; // Allow all log levels including trace
  }
}

void main() async {
  // Exit cleanly on SIGTERM (Docker stop) even if stuck in a retry loop
  ProcessSignal.sigterm.watch().listen((_) => exit(0));

  Logger.defaultFilter = () => TraceFilter();
  final logger = Logger();

  final dbConfig = await DatabaseConfig.fromEnv();
  final db = await Database.connectWithRetry(dbConfig);
  final prefs = await Preferences.create(db: db);

  final statemanConfigFilePath =
      Platform.environment['CENTROID_STATEMAN_FILE_PATH'];
  if (statemanConfigFilePath == null) {
    throw Exception("Stateman Config file path needs to be set");
  }
  final smConfig = await StateManConfig.fromFile(statemanConfigFilePath);

  final keyMappings = await KeyMappings.fromPrefs(prefs, createDefault: false);

  // Disable SSL for alarm StateMan to test if the issue is specific to
  // encrypted secure channel renewal
  final alarmSmConfig = smConfig.copy();
  // for (final opcuaConfig in alarmSmConfig.opcua) {
  //   opcuaConfig.sslCert = null;
  //   opcuaConfig.sslKey = null;
  //   opcuaConfig.password = null;
  //   opcuaConfig.username = null;
  // }

  // Create StateMan for alarm monitoring (with separate certificate)
  final stateMan = await StateMan.create(
    config: alarmSmConfig,
    keyMappings: keyMappings,
    useIsolate: false,
    staticLinking: false,
    alias: 'alarmman',
  );

  // Setup alarm monitoring with database persistence
  // ignore: unused_local_variable
  final alarmHandler = await AlarmMan.create(
    prefs,
    stateMan,
    historyToDb: true,
  );

  logger.i('Spawning ${smConfig.opcua.length} DataAcquisition isolate(s)');

  // Spawn one isolate per OPC UA server
  for (final server in smConfig.opcua) {
    final filtered = keyMappings.filterByServer(server.serverAlias);
    final collectedKeys = filtered.nodes.entries
        .where((e) => e.value.collect != null)
        .map((e) => e.key);
    logger.i(
        'Spawning isolate for server ${server.serverAlias} ${server.endpoint} with ${filtered.nodes.length} keys (${collectedKeys.length} collected):\n${collectedKeys.map((k) => '  - $k').join('\n')}');

    await spawnDataAcquisitionIsolate(
      server: server,
      dbConfig: dbConfig,
      keyMappings: filtered,
    );
  }

  logger.i('All isolates spawned, main thread waiting...');

  // Keep main alive indefinitely
  await Completer<void>().future;
}
