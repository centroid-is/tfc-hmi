import 'dart:async';
import 'dart:io';

import 'package:tfc_dart/core/aggregator_server.dart';
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

  // SharedStateMan for AlarmMan + AggregatorServer
  final sharedStateMan = await StateMan.create(
    config: smConfig,
    keyMappings: keyMappings,
    useIsolate: true,
    alias: 'shared',
  );

  // Setup alarm monitoring with database persistence
  final alarmHandler = await AlarmMan.create(
    prefs,
    sharedStateMan,
    historyToDb: true,
  );

  // Track isolate handles for hot-reload
  final isolateHandles = <String, IsolateHandle>{};

  // Reload callback: diff old vs new configs, stop/spawn as needed
  Future<String> reloadClients(List<OpcUAConfig> newServers) async {
    final newByAlias = <String, OpcUAConfig>{};
    for (final s in newServers) {
      newByAlias[s.serverAlias ?? s.endpoint] = s;
    }

    final oldAliases = isolateHandles.keys.toSet();
    final newAliases = newByAlias.keys.toSet();

    // Removed: stop isolate
    for (final alias in oldAliases.difference(newAliases)) {
      logger.i('Stopping isolate for removed server "$alias"');
      isolateHandles[alias]?.stop();
      isolateHandles.remove(alias);
    }

    // Added or changed: stop old (if exists) and spawn new
    for (final alias in newAliases) {
      final newConfig = newByAlias[alias]!;
      final oldHandle = isolateHandles[alias];

      if (oldHandle != null && oldAliases.contains(alias)) {
        // Check if config actually changed (need to compare with current)
        final oldConfig = smConfig.opcua.firstWhere(
          (c) => (c.serverAlias ?? c.endpoint) == alias,
          orElse: () => OpcUAConfig(), // fallback means it's new
        );
        if (oldConfig == newConfig) continue; // unchanged

        logger.i('Restarting isolate for changed server "$alias"');
        oldHandle.stop();
      } else {
        logger.i('Spawning isolate for new server "$alias"');
      }

      final filtered = keyMappings.filterByServer(newConfig.serverAlias);
      final handle = await spawnDataAcquisitionIsolate(
        server: newConfig,
        dbConfig: dbConfig,
        keyMappings: filtered,
      );
      isolateHandles[alias] = handle;
    }

    return 'ok: ${newServers.length} server(s) configured';
  }

  // Start AggregatorServer if enabled
  if (smConfig.aggregator?.enabled == true) {
    final aggregator = AggregatorServer(
      config: smConfig.aggregator!,
      sharedStateMan: sharedStateMan,
      alarmMan: alarmHandler,
      configFilePath: statemanConfigFilePath,
      onReloadClients: reloadClients,
      prefs: prefs,
    );
    await aggregator.initialize();
    unawaited(aggregator.runLoop());
    logger.i(
        'Aggregator server started on port ${smConfig.aggregator!.port}');
  }

  logger.i('Spawning ${smConfig.opcua.length} DataAcquisition isolate(s)');

  // Spawn one isolate per OPC UA server
  for (final server in smConfig.opcua) {
    final alias = server.serverAlias ?? server.endpoint;
    final filtered = keyMappings.filterByServer(server.serverAlias);
    final collectedKeys = filtered.nodes.entries
        .where((e) => e.value.collect != null)
        .map((e) => e.key);
    logger.i(
        'Spawning isolate for server ${server.serverAlias} ${server.endpoint} with ${filtered.nodes.length} keys (${collectedKeys.length} collected):\n${collectedKeys.map((k) => '  - $k').join('\n')}');

    final handle = await spawnDataAcquisitionIsolate(
      server: server,
      dbConfig: dbConfig,
      keyMappings: filtered,
    );
    isolateHandles[alias] = handle;
  }

  logger.i('All isolates spawned, main thread waiting...');

  // Keep main alive indefinitely
  await Completer<void>().future;
}
