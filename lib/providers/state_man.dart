import 'dart:io';
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../page_creator/client.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'state_man.g.dart';

@Riverpod(keepAlive: true)
Future<StateMan> stateMan(Ref ref) async {
  final prefs = SharedPreferencesAsync();

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
  final keyMappings = KeyMappings.fromJson(jsonDecode(keyMappingsJson));

  return StateMan(config: config, keyMappings: keyMappings);
}
