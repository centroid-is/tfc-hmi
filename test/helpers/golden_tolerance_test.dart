/// Tests for the tolerant golden comparator.
///
/// A comparator that can wave a mismatch through needs its own guard rail: if
/// the threshold logic were inverted or the tolerance read as a percentage
/// instead of a fraction, every golden in the repo would quietly stop
/// catching anything and nothing else would notice.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_tolerance.dart';

/// A [width]×[height] opaque white PNG with the first [differing] pixels
/// turned black.
Future<Uint8List> _png({
  required int width,
  required int height,
  int differing = 0,
}) async {
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    final value = i < differing ? 0 : 255;
    pixels[o] = value; // R
    pixels[o + 1] = value; // G
    pixels[o + 2] = value; // B
    pixels[o + 3] = 255; // A
  }

  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  final encoded = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return encoded!.buffer.asUint8List();
}

/// A comparator whose "golden on disk" is [golden], so the tests supply the
/// reference image rather than committing fixture PNGs.
///
/// [basedir] still has to be a real writable directory: on a mismatch the
/// comparator asks Flutter to write the diff images out, and that path is
/// worth exercising too.
class _InMemoryComparator extends TolerantGoldenComparator {
  _InMemoryComparator(this.golden,
      {required super.tolerance, required Directory basedir})
      : super(basedir.uri.resolve('test.dart'));

  final Uint8List golden;

  @override
  Future<List<int>> getGoldenBytes(Uri golden) async => this.golden;
}

void main() {
  // 100×100 = 10,000 pixels, so one pixel is exactly 0.01%.
  const width = 100;
  const height = 100;

  late Uint8List reference;
  late Directory workdir;

  setUp(() async {
    reference = await _png(width: width, height: height);
    workdir = Directory.systemTemp.createTempSync('golden_tolerance_test');
    addTearDown(() => workdir.deleteSync(recursive: true));
  });

  test('an identical image passes', () async {
    final comparator =
        _InMemoryComparator(reference, tolerance: 0.0, basedir: workdir);
    expect(
        await comparator.compare(reference, Uri.parse('golden.png')), isTrue);
  });

  test('a difference under the tolerance passes', () async {
    // 5 pixels of 10,000 = 0.05%, inside a 0.1% tolerance.
    final drifted = await _png(width: width, height: height, differing: 5);
    final comparator =
        _InMemoryComparator(reference, tolerance: 0.001, basedir: workdir);
    expect(await comparator.compare(drifted, Uri.parse('golden.png')), isTrue);
  });

  test('a difference exactly at the tolerance passes', () async {
    // 10 pixels of 10,000 = 0.1%.
    final drifted = await _png(width: width, height: height, differing: 10);
    final comparator =
        _InMemoryComparator(reference, tolerance: 0.001, basedir: workdir);
    expect(await comparator.compare(drifted, Uri.parse('golden.png')), isTrue);
  });

  test('a difference over the tolerance still fails', () async {
    // 20 pixels of 10,000 = 0.2%, outside a 0.1% tolerance. This is the case
    // that matters: the comparator must not become a rubber stamp.
    final drifted = await _png(width: width, height: height, differing: 20);
    final comparator =
        _InMemoryComparator(reference, tolerance: 0.001, basedir: workdir);
    await expectLater(
      () => comparator.compare(drifted, Uri.parse('golden.png')),
      throwsA(isA<FlutterError>()),
    );
  });

  test('a wholly different image fails at the shipped tolerance', () async {
    final black =
        await _png(width: width, height: height, differing: width * height);
    final comparator = _InMemoryComparator(reference,
        tolerance: kGoldenTolerance, basedir: workdir);
    await expectLater(
      () => comparator.compare(black, Uri.parse('golden.png')),
      throwsA(isA<FlutterError>()),
    );
  });

  test('the shipped tolerance is small enough to be meaningful', () {
    // Guards against someone "fixing" a failing golden by widening this until
    // it passes. 0.01% is ~36 pixels on the smallest golden in the suite.
    expect(kGoldenTolerance, lessThanOrEqualTo(0.0005));
    expect(kGoldenTolerance, greaterThan(0));
  });

  test('flutter_test_config.dart installs it for the whole suite', () {
    // The wiring is the part most likely to rot silently — a renamed config
    // file or a nested one shadowing the root would leave goldens back on
    // exact comparison with nothing to say so.
    expect(goldenFileComparator, isA<TolerantGoldenComparator>());
    expect((goldenFileComparator as TolerantGoldenComparator).tolerance,
        kGoldenTolerance);
  });

  test('useTolerantGoldenComparator keeps the suite golden directory',
      () async {
    final original = goldenFileComparator;
    addTearDown(() => goldenFileComparator = original);

    final before = (original as LocalFileComparator).basedir;
    useTolerantGoldenComparator();

    expect(goldenFileComparator, isA<TolerantGoldenComparator>());
    expect((goldenFileComparator as LocalFileComparator).basedir, before,
        reason:
            'a different basedir would look for goldens in the wrong place');
  });
}
