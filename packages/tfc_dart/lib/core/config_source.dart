import 'state_man.dart';

/// Holds pre-loaded config data from static files.
/// When non-null, providers use these instead of Preferences/SecureStorage.
class StaticConfig {
  final StateManConfig stateManConfig;
  final KeyMappings keyMappings;
  final String? pageEditorJson;

  const StaticConfig({
    required this.stateManConfig,
    required this.keyMappings,
    this.pageEditorJson,
  });

  /// Load from raw JSON strings (works on all platforms including web).
  static StaticConfig fromStrings({
    required String configJson,
    required String keyMappingsJson,
    String? pageEditorJson,
  }) {
    return StaticConfig(
      stateManConfig: StateManConfig.fromString(configJson),
      keyMappings: KeyMappings.fromString(keyMappingsJson),
      pageEditorJson: pageEditorJson,
    );
  }
}
