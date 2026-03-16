import 'package:marionette_flutter/marionette_flutter.dart';

/// Initializes MarionetteBinding for AI-driven UI verification.
///
/// Only called when `--dart-define=MARIONETTE=true` is passed.
/// The const bool guard in main.dart ensures this code (and the
/// marionette_flutter import) is tree-shaken from release builds.
void initMarionette() {
  MarionetteBinding.ensureInitialized();
}
