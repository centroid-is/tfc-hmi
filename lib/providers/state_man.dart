import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/state_man.dart';
import 'preferences.dart';

part 'state_man.g.dart';

@Riverpod(keepAlive: true)
Future<StateMan> stateMan(Ref ref) async {
  final prefs = await ref.watch(preferencesProvider.future);

  var stateManJson = await prefs.getString('state_man_config');
  if (stateManJson == null) {
    final defaultConfig = StateManConfig(opcua: OpcUAConfig());
    stateManJson = jsonEncode(defaultConfig.toJson());
    await prefs.setString('state_man_config', stateManJson);
  }
  final config = StateManConfig.fromJson(jsonDecode(stateManJson));

  var keyMappingsJson = await prefs.getString('key_mappings');
  if (keyMappingsJson == null) {
    final defaultKeyMappings = KeyMappings(nodes: {
      "exampleKey": KeyMappingEntry(
          nodeId: NodeIdConfig(namespace: 42, identifier: "identifier"))
    });
    keyMappingsJson = jsonEncode(defaultKeyMappings.toJson());
    await prefs.setString('key_mappings', keyMappingsJson);
  }
  final keyMappings = KeyMappings.fromJson(jsonDecode(keyMappingsJson));

  // Watch for changes in specific preferences
  final listener = prefs.onPreferencesChanged.listen(
    (key) {
      if (key == 'state_man_config' || key == 'key_mappings') {
        ref.invalidateSelf();
      }
    },
    onError: (error) {
      stderr.writeln('Error in preferences listener: $error');
    },
  );

  ref.onDispose(() {
    listener.cancel();
  });

  try {
    final stateMan = StateMan(config: config, keyMappings: keyMappings);
    for (var entry in keyMappings.nodes.entries) {
      if (entry.value.collectSize != null) {
        await stateMan.collect(entry.key, entry.value.collectSize!);
      }
    }
    return stateMan;
  } catch (e) {
    stderr.writeln('Error parsing key mappings: $e');
    rethrow;
  }
}
