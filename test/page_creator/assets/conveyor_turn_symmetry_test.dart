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

    test('single turn: runs either side are mirror lengths', () {
      final g = geom([ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)]);
      final start = g.tangentAt(0.0).position;
      final end = g.tangentAt(1.0).position;
      // A 90 turn at the midpoint: the horizontal run before and the vertical
      // run after are equally long, so the end is as far down as it is right.
      final acrossX = (end.dx - start.dx).abs();
      final acrossY = (end.dy - start.dy).abs();
      expect(acrossX, closeTo(acrossY, 1.0));
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

    test('belt length stays near the nominal length', () {
      // A fillet cuts the corner, so the belt is at most the nominal length
      // and never wildly over it the way the additive walk was.
      for (final radius in [0.8, 1.2, 2.5]) {
        final g = geom([
          ConveyorTurnEntry(position: 0.15, angle: -30, radius: 1.0),
          ConveyorTurnEntry(position: 0.35, angle: 120, radius: radius),
          ConveyorTurnEntry(position: 0.65, angle: 120, radius: radius),
          ConveyorTurnEntry(position: 0.85, angle: -30, radius: 1.0),
        ]);
        final natural = g.length / g.scale;
        expect(natural, lessThanOrEqualTo(box.width + 1.0),
            reason: 'radius $radius overran the nominal belt length');
        expect(natural, greaterThan(box.width * 0.5),
            reason: 'radius $radius collapsed the belt');
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
