import 'dart:async';
import 'dart:io';

import 'package:tfc_core/core/database.dart';
import 'package:tfc_core/core/database_drift.dart';
import 'package:tfc_core/core/preferences.dart';
import 'package:tfc_core/core/secure_storage/secure_storage.dart';

import 'data_acquisition_isolate.dart';
import 'package:tfc_core/core/state_man.dart';

import 'package:logger/logger.dart';

class TraceFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true; // Allow all log levels including trace
  }
}

void main() async {
  Logger.defaultFilter = () => TraceFilter();
  final logger = Logger();

  final dbConfig = await DatabaseConfig.fromEnv();
  final db = Database(await AppDatabase.spawn(dbConfig));
  final prefs = await Preferences.create(db: db);

  final statemanConfigFilePath =
      Platform.environment['CENTROID_STATEMAN_FILE_PATH'];
  if (statemanConfigFilePath == null) {
    throw Exception("Stateman Config file path needs to be set");
  }
  final smConfig = await StateManConfig.fromFile(statemanConfigFilePath);

  final keyMappings = await KeyMappings.fromPrefs(prefs, createDefault: false);

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
