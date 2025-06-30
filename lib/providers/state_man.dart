import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/state_man.dart';
import 'preferences.dart';
import 'collector.dart';

part 'state_man.g.dart';

@Riverpod(keepAlive: true)
Future<StateMan> stateMan(Ref ref) async {
  final SharedPreferencesAsync sharedPreferences = SharedPreferencesAsync();

  var stateManJson = await sharedPreferences.getString('state_man_config');
  if (stateManJson == null) {
    final defaultConfig = StateManConfig(opcua: [OpcUAConfig()]);
    stateManJson = jsonEncode(defaultConfig.toJson());
    await sharedPreferences.setString('state_man_config', stateManJson);
  }
  final config = StateManConfig.fromJson(jsonDecode(stateManJson));

  final prefs = await ref.watch(preferencesProvider.future);

  var keyMappingsJson = await prefs.getString('key_mappings');
  if (keyMappingsJson == null) {
    final defaultKeyMappings = KeyMappings(nodes: {
      "exampleKey": KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 42, identifier: "identifier"))
    });
    keyMappingsJson = jsonEncode(defaultKeyMappings.toJson());
    await prefs.setString('key_mappings', keyMappingsJson);
  }
  final keyMappings = KeyMappings.fromJson(jsonDecode(keyMappingsJson));

  // Watch for changes in specific preferences
  final listener = prefs.onPreferencesChanged.listen(
    (key) {
      if (key == 'key_mappings') {
        ref.invalidateSelf();
      }
    },
    onError: (error) {
      stderr.writeln('Error in preferences listener: $error');
    },
  );

  try {
    final stateMan =
        await StateMan.create(config: config, keyMappings: keyMappings);

    // Initialize collector
    ref.read(collectorProvider.future);

    ref.onDispose(() async {
      listener.cancel();
      stateMan.close();
    });
    return stateMan;
  } catch (e) {
    listener.cancel();
    stderr.writeln('Error parsing key mappings: $e');
    rethrow;
  }
}
