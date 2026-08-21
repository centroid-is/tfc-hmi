/// The y-axis scaling behind every pane trend.
///
/// The bug these guard: a trend whose axis is re-derived from the exact
/// extremes on every arriving sample redraws the same signal small, then
/// bigger, then small again — the line "breathes" while the reading itself is
/// steady. `stableTrendRange` snaps the padded range onto round steps so the
/// axis holds still until the signal genuinely leaves it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/graph.dart';

void main() {
  group('stableTrendRange', () {
    test('contains the data with headroom on both sides', () {
      final r = stableTrendRange(41.0, 48.3);
      expect(r.min, lessThan(41.0));
      expect(r.max, greaterThan(48.3));
    });

    test('holds still while the signal wanders inside one notch', () {
      // The reading drifts around 4.2 the way a live analog value does. Each
      // of these is one rebuild of the pane; the axis must not move, or the
      // trace is redrawn at a different scale every second.
      final ranges = [
        stableTrendRange(4.09, 4.51),
        stableTrendRange(4.11, 4.49),
        stableTrendRange(4.10, 4.50),
        stableTrendRange(4.12, 4.48),
      ];
      for (final r in ranges.skip(1)) {
        expect(r.min, ranges.first.min);
        expect(r.max, ranges.first.max);
      }
    });

    test('moves once the signal leaves the notch it was in', () {
      final calm = stableTrendRange(4.09, 4.51);
      final excursion = stableTrendRange(4.09, 9.80);
      expect(excursion.max, greaterThan(calm.max));
    });

    test('snaps to round numbers so the ticks read cleanly', () {
      final r = stableTrendRange(41.0, 48.3);
      // Step lands on 2 here, so both ends are multiples of it.
      expect(r.min % 2, 0);
      expect(r.max % 2, 0);
    });

    test('opens a window around a dead-flat signal', () {
      final r = stableTrendRange(4.21, 4.21);
      expect(r.min, lessThan(4.21));
      expect(r.max, greaterThan(4.21));
      // Centred, not pinned to the frame: the line should draw mid-plot.
      final middle = (r.min + r.max) / 2;
      expect((4.21 - middle).abs(), lessThan((r.max - r.min) / 4));
    });

    test('scales a flat window to the reading own magnitude', () {
      final small = stableTrendRange(4.2, 4.2);
      final large = stableTrendRange(4200, 4200);
      expect(large.max - large.min, greaterThan(small.max - small.min));
    });

    test('floor clamps the bottom for a quantity framed from zero', () {
      // Current: the 10% headroom would otherwise put the axis below zero,
      // wasting a strip of a plot that is already only 100px tall.
      final r = stableTrendRange(0, 3.2, floor: 0);
      expect(r.min, 0);
      expect(r.max, greaterThanOrEqualTo(3.2));
    });

    test('survives a series with no finite extremes', () {
      final r = stableTrendRange(double.infinity, double.negativeInfinity);
      expect(r.min, lessThan(r.max));
    });

    test('never returns an empty range', () {
      for (final (lo, hi) in [
        (0.0, 0.0),
        (-5.0, -5.0),
        (1e-9, 1e-9),
        (-273.0, 1000.0),
      ]) {
        final r = stableTrendRange(lo, hi);
        expect(r.max, greaterThan(r.min), reason: 'for $lo..$hi');
      }
    });
  });
}
