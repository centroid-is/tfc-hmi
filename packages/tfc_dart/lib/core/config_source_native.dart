import 'dart:io';

import 'config_source.dart';
import 'state_man.dart';

/// Load a [StaticConfig] from a directory containing config.json,
/// keymappings.json, and optionally page-editor.json.
/// Uses dart:io — only works on native platforms.
Future<StaticConfig> staticConfigFromDirectory(String dirPath) async {
  final configFile = File('$dirPath/config.json');
  final keyMappingsFile = File('$dirPath/keymappings.json');
  final pageEditorFile = File('$dirPath/page-editor.json');

  final config = await StateManConfig.fromFile(configFile.path);
  final keyMappings = await KeyMappings.fromFile(keyMappingsFile.path);
  final pageEditorJson = await pageEditorFile.exists()
      ? await pageEditorFile.readAsString()
      : null;

  return StaticConfig(
    stateManConfig: config,
    keyMappings: keyMappings,
    pageEditorJson: pageEditorJson,
  );
}
