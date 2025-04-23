import 'dart:io';
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../page_creator/client.dart';

part 'state_man.g.dart';

@Riverpod(keepAlive: true)
StateMan stateMan(Ref ref) {
  // Todo: do differently, config should be in the state man
  Map<String, String> envVars = Platform.environment;
  var configDirectory = envVars['CONFIGURATION_DIRECTORY'];
  configDirectory ??= '${Directory.current.path}/config';
  if (!Directory(configDirectory).existsSync()) {
    Directory(configDirectory).createSync(recursive: true);
  }
  final configFile = File('$configDirectory/state_man.json');
  final config =
      StateManConfig.fromJson(jsonDecode(configFile.readAsStringSync()));
  final keyMappingsFile = File('$configDirectory/key_mappings.json');
  final keyMappings =
      KeyMappings.fromJson(jsonDecode(keyMappingsFile.readAsStringSync()));

  final client = StateMan(config: config, keyMappings: keyMappings);
  return client;
}
