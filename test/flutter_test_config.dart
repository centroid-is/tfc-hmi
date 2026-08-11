import 'dart:async';

import 'helpers/golden_tolerance.dart';

/// Applies to every test under `test/` except `test/widgets/`, which has its
/// own config (Flutter uses the nearest one, not all of them — so that file
/// calls [useTolerantGoldenComparator] as well).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  useTolerantGoldenComparator();
  await testMain();
}
