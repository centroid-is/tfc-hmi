/// Subprocess probe for `log_config_test.dart`.
///
/// [logLevelFromEnv] reads `Platform.environment`, which cannot be mutated
/// in-process, so the only honest way to prove the env var is actually
/// consulted -- and that it is consulted under *that* name -- is to run this
/// in a child process with the variable set.
///
/// Prints one line: the resolved level name.
import 'package:tfc_dart/core/log_config.dart';

void main() {
  // ignore: avoid_print
  print('LEVEL=${logLevelFromEnv().name}');
}
