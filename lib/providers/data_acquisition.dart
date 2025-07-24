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

class DataAcquisition {
  final List<Isolate> collectors;

  DataAcquisition({required this.collectors});

  // Method to close all collectors
  Future<void> closeAll() async {
    for (final isolate in collectors) {
      try {
        isolate.kill(priority: Isolate.immediate);
      } catch (e) {
        // Ignore errors when exiting
      }
    }
  }
}

// Message structure for isolate communication
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

// Entry point for the isolate
@pragma('vm:entry-point')
void entryPoint(IsolateMessage isolateMessage) async {
  late Collector collector;

  try {
    // Create database connection in isolate
    final db = await AppDatabase.create(isolateMessage.databaseConfig);
    await db.open();
    final database = Database(db);

    // Create Collector in isolate
    collector = Collector(
      config: CollectorConfig(collect: true),
      stateMan: await StateMan.create(
        config: isolateMessage.stateManConfig,
        keyMappings: isolateMessage.keyMappings,
      ),
      database: database,
    );

    // Wait indefinitely for close message
  } catch (e, stackTrace) {
    stderr.writeln('Error in isolate: ${isolateMessage.serverName}');
    stderr.writeln(e);
    stderr.writeln(stackTrace);
  }

  // TODO make this properly, this doesnt work
  while (true) {
    await Future.delayed(const Duration(seconds: 1));
  }
  collector.close();
}

// Create data acquisition for each client
// Will be run in a isolate with one database connection
@Riverpod(keepAlive: true)
Future<DataAcquisition> dataAcquisition(Ref ref) async {
  final stateMan = await ref.watch(stateManProvider.future);
  final stateManConfig = stateMan.config;

  final Map<String?, KeyMappings> collectEntries =
      {}; // key: server name, value: list of collect entries
  for (final keyMapping in stateMan.keyMappings.nodes.entries) {
    if (keyMapping.value.collect != null) {
      collectEntries[keyMapping.value.server] ??= KeyMappings(nodes: {});
      collectEntries[keyMapping.value.server]!.nodes[keyMapping.key] =
          KeyMappingEntry(
              opcuaNode: keyMapping.value.opcuaNode,
              collect: keyMapping.value.collect);
    }
  }

  // Create a map of server name to its config
  final Map<String?, StateManConfig> stateManConfigs = {};
  for (final server in stateManConfig.opcua) {
    stateManConfigs[server.serverAlias] = StateManConfig(opcua: [server]);
  }

  final List<Isolate> collectors = [];
  final logger = Logger();

  for (final server in stateManConfigs.keys) {
    if (collectEntries.containsKey(server)) {
      try {
        // Create isolate message
        final message = IsolateMessage(
          serverName: server ?? 'unknown',
          keyMappings: collectEntries[server]!,
          stateManConfig: stateManConfigs[server]!,
          databaseConfig: await DatabaseConfig.fromPreferences(),
        );

        // Spawn isolate
        final isolate = await Isolate.spawn(entryPoint, message,
            debugName: 'collector-${server ?? 'unknown'}');

        collectors.add(isolate);
        logger.i('Started collector isolate for server: $server');
      } catch (e, stackTrace) {
        logger.e('Failed to spawn isolate for server $server: $e',
            error: e, stackTrace: stackTrace);
      }
    }
  }

  return DataAcquisition(collectors: collectors);
}
