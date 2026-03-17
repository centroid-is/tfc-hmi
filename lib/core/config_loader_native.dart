import 'dart:io' if (dart.library.js_interop) 'io_stub.dart';

import 'package:tfc_dart/core/config_source.dart';
import 'package:tfc_dart/core/config_source_native.dart';

/// Loads a [StaticConfig] from the directory specified by the
/// `CENTROID_CONFIG_DIR` environment variable.
///
/// Returns `null` when the env var is not set (normal interactive mode).
Future<StaticConfig?> loadStaticConfig() async {
  final configDir = Platform.environment['CENTROID_CONFIG_DIR'];
  if (configDir == null) return null;
  return staticConfigFromDirectory(configDir);
}
