import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tfc_dart/core/modbus_device_client.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'preferences.dart';
import 'collector.dart';

part 'state_man.g.dart';

Future<KeyMappings> fetchKeyMappings(PreferencesApi prefs) async {
  var keyMappingsJson = await prefs.getString('key_mappings');
  if (keyMappingsJson == null) {
    final defaultKeyMappings = KeyMappings(nodes: {
      "exampleKey": KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 42, identifier: "identifier"))
    });
    keyMappingsJson = jsonEncode(defaultKeyMappings.toJson());
    await prefs.setString('key_mappings', keyMappingsJson);
  }
  return KeyMappings.fromJson(jsonDecode(keyMappingsJson));
}

@Riverpod(keepAlive: true)
Future<StateMan> stateMan(Ref ref) async {
  // Use ref.read instead of ref.watch to break the reactive dependency chain.
  // StateMan reads config once at init; DB reconnects should NOT cascade here
  // and destroy all OPC-UA connections/isolates.
  final prefs = await ref.read(preferencesProvider.future);
  final config = await StateManConfig.fromPrefs(prefs);

  final keyMappings = await fetchKeyMappings(prefs);

  // Watch for changes in specific preferences
  final listener = prefs.onPreferencesChanged.listen(
    (key) {
      if (key == 'key_mappings') {
        ref.read(stateManProvider.future).then((stateMan) async {
          ref.read(preferencesProvider.future).then((newPrefs) async {
            stateMan.updateKeyMappings(await fetchKeyMappings(newPrefs));
          });
        });
      }
    },
    onError: (error) {
      stderr.writeln('Error in preferences listener: $error');
    },
  );

  try {
    final m2400Clients = createM2400DeviceClients(config.jbtm);
    final modbusClients = buildModbusDeviceClients(config.modbus, keyMappings);
    final deviceClients = [...m2400Clients, ...modbusClients];
    final stateMan = await StateMan.create(
        config: config,
        keyMappings: keyMappings,
        deviceClients: deviceClients);

    // Initialize collector
    ref.read(collectorProvider.future);

    ref.onDispose(() async {
      listener.cancel();
      await stateMan.close();
    });
    return stateMan;
  } catch (e) {
    listener.cancel();
    stderr.writeln('Error parsing key mappings: $e');
    rethrow;
  }
}

final substitutionsChangedProvider =
    StreamProvider<Map<String, String>>((ref) async* {
  final sm = await ref.watch(stateManProvider.future);
  yield* sm.substitutionsChanged;
});
