import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/elevator_layout.dart';

void main() {
  group('platformOffsetTop', () {
    // ---------------------------------------------------------------------
    // Original cases (Plan 02-03 lock). To preserve their semantics under
    // the new signature, we pass `maxChildHeight = bboxHeight - platformH`
    // — i.e., the travel range equals full headroom, which is exactly what
    // the old 3-arg formula produced. The expected values therefore remain
    // unchanged.
    // ---------------------------------------------------------------------
    test('progress=0.0, h=100, ph=20 -> 80 (platform at bottom)', () {
      expect(platformOffsetTop(0.0, 100.0, 20.0, 80.0), 80.0);
    });
    test('progress=1.0, h=100, ph=20 -> 0 (platform at top)', () {
      expect(platformOffsetTop(1.0, 100.0, 20.0, 80.0), 0.0);
    });
    test('progress=0.5, h=100, ph=20 -> 40 (geometric centre)', () {
      expect(platformOffsetTop(0.5, 100.0, 20.0, 80.0), 40.0);
    });
    test('progress=0.0, h=200, ph=10 -> 190 (verifies (h - ph) factor)', () {
      expect(platformOffsetTop(0.0, 200.0, 10.0, 190.0), 190.0);
    });
    test('progress=1.0, h=200, ph=10 -> 0 (top is platform-height-independent)', () {
      expect(platformOffsetTop(1.0, 200.0, 10.0, 190.0), 0.0);
    });
    test('progress=0.5, h=200, ph=40 -> 80 (proves platform thickness subtraction)', () {
      expect(platformOffsetTop(0.5, 200.0, 40.0, 160.0), 80.0);
    });
    test('platform-fills-bbox at progress=0 -> 0 (degenerate)', () {
      // headroom=0 — maxChildHeight is irrelevant; pass 0.0.
      expect(platformOffsetTop(0.0, 100.0, 100.0, 0.0), 0.0);
    });
    test('platform-fills-bbox at progress=1 -> 0 (degenerate)', () {
      expect(platformOffsetTop(1.0, 100.0, 100.0, 0.0), 0.0);
    });

    // ---------------------------------------------------------------------
    // Plan 260511-dxa — travel range equals tallest child height (ELEV-10).
    //
    // Locked semantics:
    //   effectiveTravel = clamp(maxChildHeight, 0, bboxH - platformH)
    //   platformY        = (bboxH - platformH) - progress * effectiveTravel
    //
    // The platform still rests at (bboxH - platformH) at progress=0 for ALL
    // maxChildHeight values; the travel range varies with maxChildHeight.
    // ---------------------------------------------------------------------
    test(
        'no children (maxChildHeight=0) -> platform pinned at bottom for progress=0',
        () {
      expect(platformOffsetTop(0.0, 200.0, 10.0, 0.0), 190.0);
    });
    test(
        'no children (maxChildHeight=0) -> platform pinned at bottom for progress=0.5',
        () {
      expect(platformOffsetTop(0.5, 200.0, 10.0, 0.0), 190.0);
    });
    test(
        'no children (maxChildHeight=0) -> platform pinned at bottom for progress=1.0',
        () {
      expect(platformOffsetTop(1.0, 200.0, 10.0, 0.0), 190.0);
    });
    test('tallest child smaller than headroom -> travel equals childHeight', () {
      // bbox=200, ph=10 → headroom=190. childH=40 → travel=40.
      // progress=1 → platformY = 190 - 40 = 150.
      expect(platformOffsetTop(1.0, 200.0, 10.0, 40.0), 150.0);
    });
    test('tallest child smaller than headroom at progress=0.5 -> half-travel',
        () {
      // headroom=190, travel=40, progress=0.5 → platformY = 190 - 20 = 170.
      expect(platformOffsetTop(0.5, 200.0, 10.0, 40.0), 170.0);
    });
    test('tallest child equals headroom -> full original behaviour at progress=1',
        () {
      // headroom=190 == maxChildHeight → restores the old full-range
      // behaviour (platform climbs to the top at progress=1).
      expect(platformOffsetTop(1.0, 200.0, 10.0, 190.0), 0.0);
    });
    test('tallest child exceeds headroom -> clamps to headroom at progress=1',
        () {
      // maxChildHeight=500 > headroom=190 → effectiveTravel clamps to 190.
      expect(platformOffsetTop(1.0, 200.0, 10.0, 500.0), 0.0);
    });
    test('tallest child exceeds headroom -> clamps to headroom at progress=0.5',
        () {
      // effectiveTravel=190, progress=0.5 → platformY = 190 - 95 = 95.
      expect(platformOffsetTop(0.5, 200.0, 10.0, 500.0), 95.0);
    });
    test('negative maxChildHeight -> clamps to 0 (defensive)', () {
      // -5 clamps to 0 → travel=0 → platform pinned at bottom regardless of
      // progress.
      expect(platformOffsetTop(1.0, 200.0, 10.0, -5.0), 190.0);
    });
  });

  group('platformProgress', () {
    test('rawValue=0.0 -> 0.0', () => expect(platformProgress(0.0), 0.0));
    test('rawValue=50.0 -> 0.5', () => expect(platformProgress(50.0), 0.5));
    test('rawValue=100.0 -> 1.0', () => expect(platformProgress(100.0), 1.0));
    test('rawValue=-5.0 (low OOR) -> 0.0 (clamped)', () =>
        expect(platformProgress(-5.0), 0.0));
    test('rawValue=125.0 (high OOR) -> 1.0 (clamped)', () =>
        expect(platformProgress(125.0), 1.0));
    test('rawValue=NaN -> 0.0 (defensive)', () =>
        expect(platformProgress(double.nan), 0.0));
    test('rawValue=+Infinity -> 1.0 (clamped)', () =>
        expect(platformProgress(double.infinity), 1.0));
    test('rawValue=-Infinity -> 0.0 (clamped)', () =>
        expect(platformProgress(double.negativeInfinity), 0.0));
  });
}
