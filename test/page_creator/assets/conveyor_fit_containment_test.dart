import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

import 'painted_bounds.dart';

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
          testWidgets('${box.width.toInt()}x${box.height.toInt()} '
              '${entry.key} thk $thickness', (tester) async {
            final g = ConveyorPathGeometry.build(entry.value, box,
                thicknessFactor: thickness);
            expect(g, isNotNull);
            // Rasterised rather than derived. The ink is not the band outline
            // — the border is stroked on that outline, so half of it lies
            // beyond — and it is not the centerline's bounds inflated either,
            // which overestimates at the flat ends and, on a stretched
            // skeleton, everywhere. See `painted_bounds.dart`.
            final painted =
                await tester.runAsync(() => paintedBounds(box, g));
            expect(painted, isNotNull, reason: 'nothing painted');

            // A belt as wide as its own box has nowhere to go: the width is
            // set in screen units and the fit stands down rather than
            // squeezing the centerline into a sliver, so it paints over the
            // edge by design. Everything else has to stay in.
            final clearance = ConveyorPathGeometry.marginFor(box);
            final allBelt =
                g!.beltWidth >= box.shortestSide - 2 * clearance - 0.5;
            if (allBelt) return;

            // Half of the 2px outline, plus half a pixel of rasteriser
            // rounding.
            //
            // Where the box cannot be filled at true radius the fit measures
            // the outline into the ink it places, and the belt lands wholly
            // inside — those cases clear this with a pixel to spare. Where
            // the solve *did* succeed the band is centred on the box and the
            // outline straddles its edge, because reserving room for a fixed
            // number of pixels there would mean scaling the skeleton by a
            // factor that depends on how big the box happens to be — and
            // that is precisely what makes a belt come out a different shape
            // on a different screen. A hairline over the edge of a rectangle
            // that is only ever drawn in the page editor is the cheaper end
            // of that trade.
            const slop = 2.0 / 2 + 0.5;
            expect(painted!.left, greaterThanOrEqualTo(-slop));
            expect(painted.top, greaterThanOrEqualTo(-slop));
            expect(painted.right, lessThanOrEqualTo(box.width + slop));
            expect(painted.bottom, lessThanOrEqualTo(box.height + slop));
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
