import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/pages/page_editor.dart';

/// `rotateGroup` backs the editor's "Rotate 90°" context-menu entries. It
/// rotates a multi-selection rigidly about the centre of its bounding box:
/// each asset spins on its own centre *and* orbits the group's.
///
/// Two properties matter most and are easy to break:
///   - coordinates are normalized independently against a non-square canvas,
///     so the maths has to un-scale x before rotating or the group shears;
///   - turning a selection and turning it back must land where it started,
///     which rules out the systematic error of `math.cos(pi / 2)`.
void main() {
  /// Square canvas keeps the aspect correction out of the way.
  List<AssetPlacement> rotate(
    List<AssetPlacement> placements,
    double degrees, {
    double aspectRatio = 1.0,
  }) =>
      rotateGroup(
        placements: placements,
        degrees: degrees,
        aspectRatio: aspectRatio,
      );

  AssetPlacement at(double x, double y, {double? angle, double size = 0.1}) =>
      AssetPlacement(x: x, y: y, width: size, height: size, angle: angle);

  group('rotateGroup — single asset', () {
    test('spins in place: its own centre is the group centre', () {
      final result = rotate([at(0.25, 0.75)], 90);

      expect(result.single.x, closeTo(0.25, 1e-12));
      expect(result.single.y, closeTo(0.75, 1e-12));
      expect(result.single.angle, 90);
    });

    test('accumulates onto an existing angle', () {
      expect(rotate([at(0.5, 0.5, angle: 30)], 90).single.angle, 120);
    });

    test('wraps past a full turn', () {
      expect(rotate([at(0.5, 0.5, angle: 300)], 90).single.angle, 30);
      expect(rotate([at(0.5, 0.5, angle: 10)], -90).single.angle, 280);
    });
  });

  group('rotateGroup — group geometry', () {
    test('a horizontal row becomes a vertical column', () {
      // Three assets in a row at y = 0.5, centred on x = 0.5.
      final result = rotate([at(0.3, 0.5), at(0.5, 0.5), at(0.7, 0.5)], 90);

      // Same centre, and the spread has moved from x to y.
      for (final p in result) {
        expect(p.x, closeTo(0.5, 1e-12));
      }
      expect(result.map((p) => p.y), [
        closeTo(0.3, 1e-12),
        closeTo(0.5, 1e-12),
        closeTo(0.7, 1e-12),
      ]);
    });

    test('clockwise sends the leftmost asset to the top', () {
      // Screen y grows downward, so a +90° (clockwise) turn maps left→top.
      final result = rotate([at(0.3, 0.5), at(0.7, 0.5)], 90);
      expect(result[0].y, lessThan(result[1].y));
    });

    test('counter-clockwise sends the leftmost asset to the bottom', () {
      final result = rotate([at(0.3, 0.5), at(0.7, 0.5)], -90);
      expect(result[0].y, greaterThan(result[1].y));
    });

    test('every asset also spins, not just orbits', () {
      final result = rotate([at(0.3, 0.5), at(0.7, 0.5)], 90);
      expect(result.map((p) => p.angle), [90, 90]);
    });

    test('180° is a point reflection through the group centre', () {
      final result = rotate([at(0.3, 0.4), at(0.7, 0.6)], 180);

      expect(result[0].x, closeTo(0.7, 1e-12));
      expect(result[0].y, closeTo(0.6, 1e-12));
      expect(result[1].x, closeTo(0.3, 1e-12));
      expect(result[1].y, closeTo(0.4, 1e-12));
    });

    test('preserves the distance between assets on a square canvas', () {
      final before = [at(0.2, 0.3), at(0.6, 0.3)];
      final after = rotate(before, 90);

      final gap = (after[1].y - after[0].y).abs();
      expect(gap, closeTo(0.4, 1e-12));
    });
  });

  group('rotateGroup — aspect ratio', () {
    test('a wide canvas does not shear the group', () {
      // A 16:9 canvas: 0.1 of width is 16/9 as many pixels as 0.1 of height.
      // A row spanning 0.4 of the width must come out spanning
      // 0.4 * 16/9 of the height, or the layout has been squashed.
      const aspect = 16 / 9;
      final result =
          rotate([at(0.3, 0.5), at(0.7, 0.5)], 90, aspectRatio: aspect);

      final gapInHeights = (result[1].y - result[0].y).abs();
      expect(gapInHeights, closeTo(0.4 * aspect, 1e-12));
    });

    test('naive normalized rotation would have squashed it', () {
      // Guards the test above from silently passing if the aspect handling is
      // dropped: without it the gap would come out as a plain 0.4.
      const aspect = 16 / 9;
      final result =
          rotate([at(0.3, 0.5), at(0.7, 0.5)], 90, aspectRatio: aspect);

      expect((result[1].y - result[0].y).abs(), isNot(closeTo(0.4, 1e-6)));
    });

    test('falls back to square for a degenerate canvas', () {
      // A zero-height canvas gives aspectRatio = infinity; coordinates must
      // stay finite rather than turning into NaN.
      for (final aspect in [0.0, double.infinity, double.nan]) {
        final result =
            rotate([at(0.3, 0.5), at(0.7, 0.5)], 90, aspectRatio: aspect);
        for (final p in result) {
          expect(p.x.isFinite, isTrue, reason: 'aspect $aspect');
          expect(p.y.isFinite, isTrue, reason: 'aspect $aspect');
        }
      }
    });
  });

  group('rotateGroup — round trips', () {
    test('clockwise then counter-clockwise restores the coordinates', () {
      // Tolerance is a couple of ulps for the rounding in
      // `centre + (p - centre)`; what must not survive is a *systematic*
      // error, which is what the quarter-turn lookup table removes.
      //
      // The group is compact enough to fit the canvas in both orientations —
      // one that does not gets nudged back on, which is a real (and tested
      // below) departure from a clean round trip.
      final before = [at(0.4, 0.35), at(0.55, 0.45), at(0.45, 0.6, angle: 30)];
      final after = rotate(rotate(before, 90, aspectRatio: 16 / 9), -90,
          aspectRatio: 16 / 9);

      for (var i = 0; i < before.length; i++) {
        expect(after[i].x, closeTo(before[i].x, 1e-15), reason: 'x of $i');
        expect(after[i].y, closeTo(before[i].y, 1e-15), reason: 'y of $i');
        expect(after[i].angle, before[i].angle, reason: 'angle of asset $i');
      }
    });

    test('twenty quarter turns do not accumulate drift', () {
      // Five full revolutions: a per-turn bias would show up as ~20x the
      // single-turn error, so the same tolerance that fits one turn is a
      // real check that nothing is creeping.
      final before = [at(0.25, 0.25), at(0.4, 0.6)];
      var after = before;
      for (var i = 0; i < 20; i++) {
        after = rotate(after, 90);
      }

      for (var i = 0; i < before.length; i++) {
        expect(after[i].x, closeTo(before[i].x, 1e-15));
        expect(after[i].y, closeTo(before[i].y, 1e-15));
        expect(after[i].angle, before[i].angle);
      }
    });

    test('assets of differing sizes round trip too', () {
      // The bounding box is built from rotated extents; if it were not, a
      // mixed-size group's centre would drift on each turn.
      final before = [
        AssetPlacement(x: 0.3, y: 0.4, width: 0.4, height: 0.05),
        AssetPlacement(x: 0.6, y: 0.5, width: 0.05, height: 0.3),
      ];
      final after = rotate(rotate(before, 90), -90);

      for (var i = 0; i < before.length; i++) {
        expect(after[i].x, closeTo(before[i].x, 1e-12));
        expect(after[i].y, closeTo(before[i].y, 1e-12));
      }
    });
  });

  group('rotateGroup — angle nullability', () {
    test('leaves a never-rotated asset null when it returns to 0', () {
      // AssetStack only applies the page mirror transform to assets with a
      // non-null angle, so null must survive a round trip.
      final after = rotate(rotate([at(0.5, 0.5)], 90), -90);
      expect(after.single.angle, isNull);
    });

    test('collapses an explicit 0 to null', () {
      // The documented trade-off of the rule above: null is the canonical
      // representation of "no rotation", so an explicit 0 does not survive.
      final after = rotate([at(0.5, 0.5, angle: 0)], 0);
      expect(after.single.angle, isNull);
    });

    test('a null angle becomes explicit once actually rotated', () {
      expect(rotate([at(0.5, 0.5)], 90).single.angle, 90);
    });
  });

  group('rotateGroup — staying on the canvas', () {
    test('translates a group that would rotate off the top edge', () {
      // A wide, short row near the top: rotating it makes it tall, and a
      // naive rotation would push half of it above y = 0.
      final result = rotate([
        AssetPlacement(x: 0.5, y: 0.1, width: 0.1, height: 0.05),
        AssetPlacement(x: 0.5, y: 0.1, width: 0.6, height: 0.05),
      ], 90);

      for (final p in result) {
        expect(p.y, greaterThanOrEqualTo(0.0));
        expect(p.y, lessThanOrEqualTo(1.0));
      }
    });

    test('shifts the group as a unit, preserving relative spacing', () {
      // Clamping each asset independently would pile them onto the edge; the
      // gap between them has to survive.
      final result = rotate([at(0.1, 0.1), at(0.5, 0.1)], 90);

      final gap = (result[1].y - result[0].y).abs();
      expect(gap, closeTo(0.4, 1e-12));
      for (final p in result) {
        expect(p.x, inInclusiveRange(0.0, 1.0));
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('keeps centres on the canvas when the group is too big to fit', () {
      final result = rotate([
        AssetPlacement(x: 0.5, y: 0.5, width: 0.95, height: 0.05),
        AssetPlacement(x: 0.1, y: 0.5, width: 0.05, height: 0.05),
      ], 90);

      for (final p in result) {
        expect(p.x, inInclusiveRange(0.0, 1.0));
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('a group too tall for the canvas once rotated is nudged back on', () {
      // A full-width row on a 16:9 canvas turns into a column 1.24 canvas
      // heights tall — it cannot fit, so the trailing asset lands on the
      // bottom edge rather than off-canvas, and the turn is no longer a clean
      // round trip. Documented rather than fixed: the alternative leaves
      // assets somewhere the operator cannot grab them.
      const aspect = 16 / 9;
      final before = [at(0.15, 0.5), at(0.85, 0.5)];
      final rotated = rotate(before, 90, aspectRatio: aspect);

      for (final p in rotated) {
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
      // Still ordered, still spread out — just compressed to fit.
      expect(rotated[0].y, lessThan(rotated[1].y));

      final back = rotate(rotated, -90, aspectRatio: aspect);
      expect(back[0].x, isNot(closeTo(before[0].x, 1e-6)));
    });

    test('a group already well inside the canvas is not moved', () {
      final result = rotate([at(0.4, 0.45), at(0.6, 0.55)], 90);

      // Centre of the pair is (0.5, 0.5) and stays there.
      expect((result[0].x + result[1].x) / 2, closeTo(0.5, 1e-12));
      expect((result[0].y + result[1].y) / 2, closeTo(0.5, 1e-12));
    });
  });

  group('rotateGroup — edge cases', () {
    test('an empty selection returns empty', () {
      expect(rotate([], 90), isEmpty);
    });

    test('does not mutate the input', () {
      final before = [at(0.3, 0.4, angle: 15)];
      rotate(before, 90);

      expect(before.single.x, 0.3);
      expect(before.single.y, 0.4);
      expect(before.single.angle, 15);
    });

    test('sizes pass through untouched', () {
      final result =
          rotate([AssetPlacement(x: 0.5, y: 0.5, width: 0.4, height: 0.1)], 90);

      // Rotation is expressed through the angle; the stored extents stay in
      // the asset's own frame, as AssetStack expects.
      expect(result.single.width, 0.4);
      expect(result.single.height, 0.1);
    });

    test('0° is a no-op', () {
      final before = [at(0.3, 0.4), at(0.7, 0.6)];
      final after = rotate(before, 0);

      for (var i = 0; i < before.length; i++) {
        expect(after[i].x, closeTo(before[i].x, 1e-12));
        expect(after[i].y, closeTo(before[i].y, 1e-12));
        expect(after[i].angle, isNull);
      }
    });

    test('handles a non-quarter turn', () {
      // The menu only offers quarter turns, but the helper is general.
      final result = rotate([at(0.5, 0.3), at(0.5, 0.7)], 45);
      expect(result[0].angle, 45);
      // Clockwise swings the upper asset out to the right and down; the
      // pair ends up on the anti-diagonal.
      expect(result[0].x, greaterThan(result[1].x));
      expect(result[0].y, lessThan(result[1].y));
    });
  });
}
