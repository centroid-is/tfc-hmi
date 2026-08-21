/// Golden comparison that tolerates a hair of pixel drift.
///
/// Goldens in this repo are generated on a developer's Mac and verified on a
/// CI Mac (`skip: !Platform.isMacOS`), and the two do not always run the same
/// Flutter — CI installs the version in `.flutter-version` while a developer
/// runs whatever is on their PATH. Different Flutter versions rasterise the same
/// drawing very slightly differently, so an exact byte comparison eventually
/// fails on an image nobody touched: `third_party_speedBatcher_populated.png`
/// went red at 10 differing pixels out of 356,700 — 0.0028% — with no change
/// to the painter behind it.
///
/// The tolerance below is chosen against that number: loose enough to absorb
/// antialiasing drift along a few edges, tight enough that a real regression
/// still fails. These goldens are line drawings of machines; moving, resizing
/// or dropping any part of one shifts thousands of pixels, orders of magnitude
/// past the threshold.
///
/// This does not paper over a mismatch that matters. If a golden fails here,
/// it changed by more than a rendering rounding error.
///
/// The tolerance is a safety net for drift nobody caused, not a licence to
/// author goldens on the wrong Flutter — one generated off-version can land
/// just inside the threshold, pass, and leave the next person an image already
/// most of the way to failing. Run `scripts/check-flutter-version.sh` before
/// `--update-goldens`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fraction of pixels allowed to differ before a golden is called a failure.
///
/// 0.01% — roughly 36 pixels on the smallest golden in the suite, about 3.5×
/// the largest cross-version drift observed.
const double kGoldenTolerance = 0.0001;

/// Wraps the ambient [goldenFileComparator] so comparisons allow
/// [kGoldenTolerance] drift.
///
/// Call from a `flutter_test_config.dart`, which runs after the test bootstrap
/// has installed the per-suite [LocalFileComparator] — that comparator knows
/// where the suite's `goldens/` directory is, and this preserves it.
void useTolerantGoldenComparator({double tolerance = kGoldenTolerance}) {
  final current = goldenFileComparator;
  if (current is! LocalFileComparator) return;
  goldenFileComparator = TolerantGoldenComparator(
    // LocalFileComparator takes the test file and keeps its directory; handing
    // back any file in the existing basedir reproduces the same basedir.
    current.basedir.resolve('flutter_test_config.dart'),
    tolerance: tolerance,
  );
}

/// A [LocalFileComparator] that passes when at most [tolerance] of the pixels
/// differ. Public so `golden_tolerance_test.dart` can exercise the threshold
/// directly; production code should go through [useTolerantGoldenComparator].
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {required this.tolerance})
      : assert(tolerance >= 0 && tolerance <= 1);

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed || result.diffPercent <= tolerance) {
      if (!result.passed) {
        // Say so rather than passing in silence — a golden that keeps creeping
        // towards the threshold is worth someone regenerating.
        debugPrint('Golden "$golden" differs by '
            '${(result.diffPercent * 100).toStringAsFixed(4)}%, within the '
            '${(tolerance * 100).toStringAsFixed(4)}% tolerance — passing.');
      }
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
