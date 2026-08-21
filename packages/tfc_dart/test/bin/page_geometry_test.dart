// The classification these tests pin down is the whole point of the tool.
//
// A first attempt at keying `/boxes/freezers` ran a shortest path over
// conveyor endpoint distance and produced a chain that was wrong. Two faults
// caused it, and there is a test here for each:
//
//   1. No hard cutoff on the gap. The search stepped between belts 0.116 apart
//      -- more than three times the join tolerance -- because a weighted
//      shortest path will always find *some* route.
//   2. No notion of alignment. A plant lays parallel lines centimetres apart,
//      so the nearest endpoint to the end of line 1's belt is often the side
//      of line 2's belt.

@TestOn('vm')
library;

import 'package:test/test.dart';

import '../../bin/page_geometry.dart';

void main() {
  const tol = Tol();

  // Horizontal belt, 0.10 wide, centred at (0.50, 0.80): spans x 0.45..0.55.
  Belt horiz(double cx, double cy, {double w = 0.10, double angle = 0}) =>
      Belt(0, 'ConveyorConfig', '', cx, cy, angle, w);

  group('classify', () {
    test('belts meeting end to end on one line continue the run', () {
      final a = horiz(0.50, 0.80);
      final b = horiz(0.60, 0.80);
      expect(classify(a, b, tol), Link.inline);
    });

    test('a belt drawn at 180 still continues the run', () {
      // Direction of travel is not recoverable from the drawing, so only the
      // axis matters: 0 and 180 are the same axis.
      final a = horiz(0.50, 0.80);
      final b = horiz(0.60, 0.80, angle: 180);
      expect(classify(a, b, tol), Link.inline);
    });

    test('belts meeting at a right angle are a transfer, not a run', () {
      final a = horiz(0.50, 0.80);
      final b = Belt(1, 'ConveyorConfig', '', 0.55, 0.85, 90, 0.10);
      expect(classify(a, b, tol), Link.transfer);
    });

    test('a neighbouring lane is never a continuation', () {
      // This is the mistake that produced the bad line 1 chain: two rows a
      // few centimetres apart, ends close enough to look connected.
      final a = horiz(0.50, 0.80);
      final b = horiz(0.60, 0.83);
      expect(classify(a, b, tol), Link.parallel);
    });

    test('belts that overlap side by side are lanes, not one run', () {
      // Same line to within tolerance, but they lie on top of each other
      // rather than abutting. Treating these as one run is what let a group
      // drift across the page in small steps.
      final a = horiz(0.50, 0.80);
      final b = horiz(0.52, 0.81);
      expect(classify(a, b, tol), Link.parallel);
    });

    test('a gap wider than the join tolerance is never a chain step', () {
      // The specific failure: idx 34 and idx 6 on /boxes/freezers are 0.116
      // apart and were walked as if connected. They are lane-neighbours at
      // most -- what matters is that neither kind of walkable link is
      // returned, so a chain cannot cross the gap.
      final a = horiz(0.50, 0.80);
      final b = horiz(0.50, 0.916);
      final link = classify(a, b, tol);
      expect(link, isNot(Link.inline));
      expect(link, isNot(Link.transfer));
    });

    test('belts far apart on the same axis are unrelated, not lanes', () {
      // Without an upper bound on the sideways offset, every horizontal belt
      // on the page counts as a neighbour of every other one.
      final a = horiz(0.50, 0.20);
      final b = horiz(0.50, 0.80);
      expect(classify(a, b, tol), Link.none);
    });

    test('aligned belts that do not overlap are unrelated', () {
      // Close enough sideways, but one is far off along the axis.
      final a = horiz(0.20, 0.80);
      final b = horiz(0.80, 0.83);
      expect(classify(a, b, tol), Link.none);
    });
  });

  group('Belt geometry', () {
    test('endpoints straddle the centre along the angle', () {
      final b = horiz(0.50, 0.80);
      expect(b.a.x, closeTo(0.45, 1e-9));
      expect(b.b.x, closeTo(0.55, 1e-9));
      expect(b.a.y, closeTo(0.80, 1e-9));
    });

    test('axis folds to a half turn', () {
      expect(horiz(0, 0, angle: 270).axis, closeTo(90, 1e-9));
      expect(horiz(0, 0, angle: 180).axis, closeTo(0, 1e-9));
    });

    test('axis delta takes the short way round', () {
      final a = horiz(0, 0, angle: 179);
      final b = horiz(0, 0, angle: 1);
      expect(a.axisDeltaTo(b), closeTo(2, 1e-9));
    });

    test('perpendicular offset ignores distance along the belt', () {
      final a = horiz(0.50, 0.80);
      final b = horiz(0.90, 0.83);
      expect(a.perpOffsetTo(b), closeTo(0.03, 1e-9));
    });
  });
}
