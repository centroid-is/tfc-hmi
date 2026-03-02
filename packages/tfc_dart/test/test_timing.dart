import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

/// Allocate [count] ports from a file-specific range.
///
/// Each test file passes a unique [fileIndex] (0–9) to get a non-overlapping
/// block of 1000 ports: file 0 → 20000–20999, file 1 → 21000–21999, etc.
/// A small random offset within the block avoids collisions across runs.
List<int> allocatePorts(int fileIndex, int count) {
  final base = 20000 + fileIndex * 1000 + Random().nextInt(900);
  return List.generate(count, (i) => base + i);
}

/// Call at top of main() to print elapsed time for every test.
/// For group-level setUpAll/tearDownAll, wrap the body with [timed].
void enableTestTiming() {
  final sw = Stopwatch();

  setUp(() {
    sw.reset();
    sw.start();
  });

  tearDown(() {
    final ms = sw.elapsedMilliseconds;
    stderr.writeln('  ⏱ ${ms}ms');
  });
}

/// Wrap a setUpAll/tearDownAll/test body to print timing.
/// Usage: setUpAll(timed('setUpAll', () async { ... }));
dynamic Function() timed(String label, dynamic Function() body) {
  return () async {
    final sw = Stopwatch()..start();
    try {
      await body();
    } finally {
      stderr.writeln('  ⏱ [$label] ${sw.elapsedMilliseconds}ms');
    }
  };
}
