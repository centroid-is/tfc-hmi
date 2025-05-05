import 'dart:convert';
import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../page_creator/client.dart';
import 'preferences.dart';

part 'state_man.g.dart';

@Riverpod(keepAlive: true)
Future<StateMan> stateMan(Ref ref) async {
  final prefs = await ref.read(preferencesProvider.future);

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
      "exampleKey": NodeIdConfig(namespace: 42, identifier: "identifier")
    });
    keyMappingsJson = jsonEncode(defaultKeyMappings.toJson());
    await prefs.setString('key_mappings', keyMappingsJson);
  }
  try {
    return StateMan(
        config: config,
        keyMappings: KeyMappings.fromJson(jsonDecode(keyMappingsJson)));
  } catch (e) {
    stderr.writeln('Error parsing key mappings: $e');
    rethrow;
  }
}
