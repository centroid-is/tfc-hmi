import 'dart:convert';
import 'dart:io'
    if (dart.library.js_interop) 'package:tfc/core/io_stub.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tfc_dart/core/config_source.dart';
import 'package:tfc_dart/core/modbus_device_client.dart';
import 'package:tfc_dart/core/mqtt_device_client.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'preferences.dart';
import 'static_config.dart';
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
  // Check for static config first — bypasses preferences entirely
  final staticCfg = await ref.read(staticConfigProvider.future);
  if (staticCfg != null) {
    return _createFromStaticConfig(ref, staticCfg);
  }

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
      if (!kIsWeb) stderr.writeln('Error in preferences listener: $error');
    },
  );

  try {
    final m2400Clients = kIsWeb
        ? <DeviceClient>[]
        : createM2400DeviceClients(config.jbtm);
    final modbusClients = kIsWeb
        ? <DeviceClient>[]
        : buildModbusDeviceClients(config.modbus, keyMappings);
    // MQTT clients always created (work on all platforms)
    final mqttClients = config.mqtt
        .map((mqttConfig) => MqttDeviceClientAdapter(mqttConfig, keyMappings))
        .toList();
    final deviceClients = [...m2400Clients, ...modbusClients, ...mqttClients];
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
    if (!kIsWeb) stderr.writeln('Error parsing key mappings: $e');
    rethrow;
  }
}

/// Creates StateMan from static config, bypassing preferences entirely.
/// Only MQTT device clients are created (no OPC UA, M2400, Modbus).
Future<StateMan> _createFromStaticConfig(
    Ref ref, StaticConfig staticCfg) async {
  final config = staticCfg.stateManConfig;
  final keyMappings = staticCfg.keyMappings;

  final mqttClients = config.mqtt
      .map((mqttConfig) => MqttDeviceClientAdapter(mqttConfig, keyMappings))
      .toList();

  final stateMan = await StateMan.create(
    config: config,
    keyMappings: keyMappings,
    deviceClients: mqttClients,
  );

  // Initialize collector (matches normal path behavior at line 84)
  ref.read(collectorProvider.future);

  ref.onDispose(() async {
    await stateMan.close();
  });
  return stateMan;
}

final substitutionsChangedProvider =
    StreamProvider<Map<String, String>>((ref) async* {
  final sm = await ref.watch(stateManProvider.future);
  yield* sm.substitutionsChanged;
});
