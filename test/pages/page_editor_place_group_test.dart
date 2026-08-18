import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/pages/page_editor.dart';

/// `placeGroupAt` backs the context menu's "Paste here": it drops a pasted
/// group with the centre of its combined bounding box on the click point.
///
/// What matters most: the group moves rigidly (spacing survives), the drop
/// point means the same thing on a non-square canvas, and a paste near an
/// edge lands flush against it instead of half off-screen — leading edge
/// first, the same rule `rotateGroup` uses.
void main() {
  List<AssetPlacement> place(
    List<AssetPlacement> placements,
    double x,
    double y, {
    double aspectRatio = 1.0,
  }) =>
      placeGroupAt(
        placements: placements,
        targetX: x,
        targetY: y,
        aspectRatio: aspectRatio,
      );

  AssetPlacement at(double x, double y, {double? angle, double size = 0.1}) =>
      AssetPlacement(x: x, y: y, width: size, height: size, angle: angle);

  group('placeGroupAt — landing on the target', () {
    test('a single asset is centred on the click point', () {
      final result = place([at(0.1, 0.1)], 0.6, 0.7);

      expect(result.single.x, closeTo(0.6, 1e-12));
      expect(result.single.y, closeTo(0.7, 1e-12));
    });

    test('a group lands with its bounding-box centre on the click point', () {
      final result = place([at(0.1, 0.2), at(0.3, 0.2)], 0.5, 0.5);

      expect((result[0].x + result[1].x) / 2, closeTo(0.5, 1e-12));
      for (final p in result) {
        expect(p.y, closeTo(0.5, 1e-12));
      }
    });

    test('the group moves rigidly: spacing survives the translation', () {
      final result = place([at(0.1, 0.2), at(0.3, 0.5)], 0.6, 0.6);

      expect(result[1].x - result[0].x, closeTo(0.2, 1e-12));
      expect(result[1].y - result[0].y, closeTo(0.3, 1e-12));
    });

    test('a wide canvas does not skew the drop point', () {
      // x and y are normalized independently; the target is normalized the
      // same way, so the centre must land exactly on it regardless of aspect.
      final result = place([at(0.1, 0.1)], 0.6, 0.7, aspectRatio: 16 / 9);

      expect(result.single.x, closeTo(0.6, 1e-12));
      expect(result.single.y, closeTo(0.7, 1e-12));
    });
  });

  group('placeGroupAt — staying on the canvas', () {
    test('a paste at the edge lands flush against it', () {
      // A 0.1-wide asset dropped at x = 1.0 can only reach 0.95.
      final result = place([at(0.5, 0.5)], 1.0, 0.5);

      expect(result.single.x, closeTo(0.95, 1e-12));
      expect(result.single.y, closeTo(0.5, 1e-12));
    });

    test('an edge paste keeps the group rigid', () {
      // Clamping per asset would pile both onto the corner.
      final result = place([at(0.2, 0.2), at(0.4, 0.2)], 1.0, 0.0);

      expect(result[1].x - result[0].x, closeTo(0.2, 1e-12));
      expect(result[1].x, closeTo(0.95, 1e-12));
      for (final p in result) {
        expect(p.y, closeTo(0.05, 1e-12));
      }
    });

    test('a rotated asset is nudged by its rotated extents', () {
      // 0.4 wide, 0.05 tall, turned upright: near the top edge it is its
      // width that must fit vertically.
      final result = place([
        AssetPlacement(x: 0.5, y: 0.5, width: 0.4, height: 0.05, angle: 90),
      ], 0.5, 0.0);

      expect(result.single.y, closeTo(0.2, 1e-12));
    });

    test('a group too large to fit overhangs the bottom/right', () {
      // The same rule as rotateGroup: align the top/left edge, where an
      // asset out of reach cannot be grabbed.
      final result = place([
        AssetPlacement(x: 0.3, y: 0.5, width: 0.5, height: 0.1),
        AssetPlacement(x: 0.9, y: 0.5, width: 0.5, height: 0.1),
      ], 0.5, 0.5);

      expect(result[0].x, closeTo(0.25, 1e-12));
      // Centres are clamped as a last resort, never off-canvas.
      for (final p in result) {
        expect(p.x, inInclusiveRange(0.0, 1.0));
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('the edge nudge respects the aspect ratio', () {
      // On a 16:9 canvas a 0.1-of-width asset is 0.1 * 16/9 canvas heights
      // wide, but only 0.1 of the *width* axis — so flush right is still
      // 1 - 0.05 in normalized x.
      final result = place([at(0.5, 0.5)], 1.0, 0.5, aspectRatio: 16 / 9);
      expect(result.single.x, closeTo(0.95, 1e-12));
    });

    test('an off-canvas target is treated as the nearest edge', () {
      final result = place([at(0.5, 0.5)], 2.0, -1.0);

      expect(result.single.x, closeTo(0.95, 1e-12));
      expect(result.single.y, closeTo(0.05, 1e-12));
    });
  });

  group('placeGroupAt — edge cases', () {
    test('an empty group returns empty', () {
      expect(place([], 0.5, 0.5), isEmpty);
    });

    test('does not mutate the input', () {
      final before = [at(0.3, 0.4, angle: 15)];
      place(before, 0.8, 0.8);

      expect(before.single.x, 0.3);
      expect(before.single.y, 0.4);
    });

    test('sizes and angles pass through untouched, null included', () {
      final result = place(
        [at(0.3, 0.4, angle: 30), at(0.5, 0.5)],
        0.6,
        0.6,
      );

      expect(result[0].angle, 30);
      expect(result[1].angle, isNull);
      expect(result[0].width, 0.1);
      expect(result[0].height, 0.1);
    });

    test('coordinates stay finite for a degenerate canvas', () {
      for (final aspect in [0.0, double.infinity, double.nan]) {
        final result = place([at(0.3, 0.5)], 0.7, 0.7, aspectRatio: aspect);
        expect(result.single.x.isFinite, isTrue, reason: 'aspect $aspect');
        expect(result.single.y.isFinite, isTrue, reason: 'aspect $aspect');
      }
    });
  });
}
