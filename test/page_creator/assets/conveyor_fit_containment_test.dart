import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// The page editor treats every asset as a bounding box: hit-testing,
/// selection and z-order all use it. A belt that paints outside its box would
/// break that invariant, so containment is asserted rather than eyeballed in
/// a golden.
void main() {
  // A belt that runs out, flares, U-turns and returns — the sweeps total 180
  // so it leaves heading back the way it came.
  final uTurn = [
    ConveyorTurnEntry(position: 0.15, angle: -30, radius: 1.0),
    ConveyorTurnEntry(position: 0.35, angle: 120, radius: 1.2),
    ConveyorTurnEntry(position: 0.62, angle: 120, radius: 1.2),
    ConveyorTurnEntry(position: 0.85, angle: -30, radius: 1.0),
  ];
  final turnSets = <String, List<ConveyorTurnEntry>>{
    'single 30': [ConveyorTurnEntry(position: 0.3, angle: 30, radius: 1.5)],
    'single 90': [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)],
    'negative 45': [ConveyorTurnEntry(position: 0.4, angle: -45, radius: 1.5)],
    's-curve': [
      ConveyorTurnEntry(position: 0.25, angle: 60, radius: 1.5),
      ConveyorTurnEntry(position: 0.6, angle: -60, radius: 1.5),
    ],
    'flared u-turn': uTurn,
  };
  const boxes = [
    Size(400, 60),
    Size(400, 100),
    Size(400, 300),
    Size(300, 300),
    Size(120, 300),
  ];

  group('turned belt stays inside its bounding box', () {
    for (final box in boxes) {
      for (final entry in turnSets.entries) {
        for (final thickness in [0.15, 0.3, 0.6]) {
          test('${box.width.toInt()}x${box.height.toInt()} '
              '${entry.key} thk $thickness', () {
            final g = ConveyorPathGeometry.build(entry.value, box,
                thicknessFactor: thickness);
            expect(g, isNotNull);
            // The painter strokes the centerline at beltWidth, plus a 2px
            // border on each side.
            final painted =
                g!.path.getBounds().inflate(g.beltWidth / 2 + 2);
            expect(painted.left, greaterThanOrEqualTo(-0.5));
            expect(painted.top, greaterThanOrEqualTo(-0.5));
            expect(painted.right, lessThanOrEqualTo(box.width + 0.5));
            expect(painted.bottom, lessThanOrEqualTo(box.height + 0.5));
          });
        }
      }
    }
  });

  group('belt thickness is independent of turn geometry', () {
    // The whole point of the fit change: two conveyors sharing a box and a
    // thickness must render the same belt height whatever their turns do,
    // otherwise they cannot be lined up on a page by eye.
    for (final box in boxes) {
      test('${box.width.toInt()}x${box.height.toInt()} matches across turns',
          () {
        final widths = turnSets.values
            .map((t) =>
                ConveyorPathGeometry.build(t, box, thicknessFactor: 0.3)!
                    .beltWidth)
            .toSet();
        expect(widths, hasLength(1));
        expect(widths.single, closeTo(box.height * 0.3, 1e-9));
      });
    }
  });

  test('straight conveyors still opt out of path geometry', () {
    expect(ConveyorPathGeometry.build([], const Size(400, 60)), isNull);
  });

  test('a turned belt defaults to a thickness that leaves room to bend', () {
    final straight = ConveyorConfig();
    final turned = ConveyorConfig(
        turns: [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)]);
    expect(straight.effectiveBeltThickness, 1.0);
    expect(turned.effectiveBeltThickness, lessThan(1.0));
    // An explicit setting always wins.
    turned.beltThickness = 0.9;
    expect(turned.effectiveBeltThickness, 0.9);
  });
}
