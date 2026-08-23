/// Subprocess probe for `log_config_test.dart`.
///
/// [logLevelFromEnv] and [initLogConfig] read `Platform.environment`, which
/// cannot be mutated in-process, so the only honest way to prove the env vars
/// are actually consulted -- and consulted under *those* names -- is to run
/// this in a child process with them set.
///
/// Prints `LEVEL=<name>`, then runs [initLogConfig] so the parent can inspect
/// whatever landed in `CENTROID_LOG_FILE`.
library;

import 'package:tfc_dart/core/log_config.dart';

void main() {
  // ignore: avoid_print
  print('LEVEL=${logLevelFromEnv().name}');
  initLogConfig();
}
