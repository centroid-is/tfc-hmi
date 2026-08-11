import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// Turn positions mark where a corner sits on the belt. A symmetric set of
/// positions must therefore produce a symmetric belt — the run into the first
/// turn and the run out of the last one have to match.
void main() {
  const box = Size(300, 400);
  const beltWidth = 30.0;

  ConveyorPathGeometry geom(List<ConveyorTurnEntry> turns) =>
      ConveyorPathGeometry.build(turns, box, beltWidthOverride: beltWidth)!;

  group('symmetric turns give a symmetric belt', () {
    for (final radius in [0.8, 1.2, 2.5]) {
      test('flared u-turn, loop radius $radius', () {
        final g = geom([
          ConveyorTurnEntry(position: 0.15, angle: -30, radius: 1.0),
          ConveyorTurnEntry(position: 0.35, angle: 120, radius: radius),
          ConveyorTurnEntry(position: 0.65, angle: 120, radius: radius),
          ConveyorTurnEntry(position: 0.85, angle: -30, radius: 1.0),
        ]);
        final start = g.tangentAt(0.0).position;
        final end = g.tangentAt(1.0).position;
        // Enters heading right, leaves heading left: the two ends should line
        // up vertically, i.e. share an x.
        expect((end.dx - start.dx).abs(), lessThan(1.0),
            reason: 'entry and exit runs must end at the same x');
      });
    }

    test('single turn: the belt fills the box on both axes', () {
      final g = geom([ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)]);
      // The bend is fixed geometry; the runs stretch so the belt spans its
      // box. The centerline is inset by half the belt width plus the border.
      const inset = beltWidth / 2 + 2;
      final b = g.path.getBounds();
      expect(b.width, closeTo(box.width - 2 * inset, 1.0));
      expect(b.height, closeTo(box.height - 2 * inset, 1.0));
    });

    test('single turn: the arc keeps its true radius', () {
      final g = geom([ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)]);
      // With true geometry the belt's length is exactly determined: the two
      // runs reach the box, the fillet replaces the corner with a quarter
      // circle, and each tangent leg it eats equals its radius at 90.
      const inset = beltWidth / 2 + 2;
      const r = 1.5 * beltWidth;
      final w = box.width - 2 * inset;
      final h = box.height - 2 * inset;
      expect(g.length, closeTo(w + h - 2 * r + pi * r / 2, 2.0));
      expect(g.scale, closeTo(1.0, 0.01));
    });

    test('s-curve returns to its entry heading and offsets evenly', () {
      final g = geom([
        ConveyorTurnEntry(position: 0.3, angle: 60, radius: 1.2),
        ConveyorTurnEntry(position: 0.7, angle: -60, radius: 1.2),
      ]);
      final startV = g.tangentAt(0.0).vector;
      final endV = g.tangentAt(1.0).vector;
      // Sweeps cancel, so it must leave parallel to how it entered.
      expect(endV.dy / endV.distance, closeTo(startV.dy / startV.distance, 0.02));
    });
  });

  group('turn positions are honoured, not consumed by arc length', () {
    test('a big radius does not delete the runs after it', () {
      // The old walk spent positional budget on arc length, so a large radius
      // left negative straights that were silently skipped.
      final g = geom([
        ConveyorTurnEntry(position: 0.15, angle: -30, radius: 1.0),
        ConveyorTurnEntry(position: 0.35, angle: 120, radius: 2.5),
        ConveyorTurnEntry(position: 0.65, angle: 120, radius: 2.5),
        ConveyorTurnEntry(position: 0.85, angle: -30, radius: 1.0),
      ]);
      final start = g.tangentAt(0.0).position;
      final end = g.tangentAt(1.0).position;
      expect((end.dx - start.dx).abs(), lessThan(1.0));
    });

    test('the belt spans its box for any loop radius that fits', () {
      // The runs absorb whatever length the box demands, so changing the
      // loop radius changes the shape but never leaves the box unfilled.
      const inset = beltWidth / 2 + 2;
      for (final radius in [0.8, 1.2, 2.5]) {
        final g = geom([
          ConveyorTurnEntry(position: 0.15, angle: -30, radius: 1.0),
          ConveyorTurnEntry(position: 0.35, angle: 120, radius: radius),
          ConveyorTurnEntry(position: 0.65, angle: 120, radius: radius),
          ConveyorTurnEntry(position: 0.85, angle: -30, radius: 1.0),
        ]);
        final b = g.path.getBounds();
        expect(b.width, closeTo(box.width - 2 * inset, 1.0),
            reason: 'radius $radius left the box unfilled across');
        expect(b.height, closeTo(box.height - 2 * inset, 1.0),
            reason: 'radius $radius left the box unfilled down');
      }
    });

    test('moving one turn does not shift the others', () {
      // Corner positions are absolute, so nudging the second turn must leave
      // the first turn's corner where it was.
      Offset firstCornerish(double secondPosition) => geom([
            ConveyorTurnEntry(position: 0.25, angle: 45, radius: 1.0),
            ConveyorTurnEntry(position: secondPosition, angle: -45, radius: 1.0),
          ]).tangentAt(0.0).position;
      expect(firstCornerish(0.6).dx, closeTo(firstCornerish(0.8).dx, 2.0));
    });
  });
}
