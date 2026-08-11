import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/pages/page_editor.dart';

/// `mirrorGroup` backs the editor's "Mirror horizontally / vertically"
/// context-menu entries. It reflects a selection about the centre of its
/// bounding box: the layout comes back in the opposite order, and each asset's
/// own orientation is reflected with it.
///
/// The properties that matter and are easy to break:
///   - reflecting twice about the same axis has to be the identity, which is
///     what makes the entry safe to press by mistake;
///   - the group's bounding box must map onto itself, so mirroring never
///     drifts a selection across the canvas;
///   - x is normalized against a non-square canvas, so a rotated asset's
///     bounding box needs the aspect correction or the centre comes out wrong;
///   - an angle back at zero has to come back as null, the "never rotated"
///     value `AssetStack` treats specially.
void main() {
  List<AssetPlacement> mirror(
    List<AssetPlacement> placements,
    MirrorAxis axis, {
    double aspectRatio = 1.0,
  }) =>
      mirrorGroup(
        placements: placements,
        axis: axis,
        aspectRatio: aspectRatio,
      );

  AssetPlacement at(double x, double y, {double? angle, double size = 0.1}) =>
      AssetPlacement(x: x, y: y, width: size, height: size, angle: angle);

  group('mirrorGroup — single asset', () {
    test('stays put: its own centre is the group centre', () {
      final h = mirror([at(0.25, 0.75)], MirrorAxis.horizontal).single;
      expect(h.x, closeTo(0.25, 1e-12));
      expect(h.y, closeTo(0.75, 1e-12));

      final v = mirror([at(0.25, 0.75)], MirrorAxis.vertical).single;
      expect(v.x, closeTo(0.25, 1e-12));
      expect(v.y, closeTo(0.75, 1e-12));
    });

    test('a horizontal flip turns an unrotated asset upside down', () {
      // The documented cost of reflecting the angle rather than the artwork:
      // 0 reflects to 180 across a vertical axis. Symmetric equipment looks
      // the same either way, but the value really does change.
      expect(mirror([at(0.5, 0.5)], MirrorAxis.horizontal).single.angle, 180);
    });

    test('a vertical flip leaves an unrotated asset alone', () {
      expect(mirror([at(0.5, 0.5)], MirrorAxis.vertical).single.angle, isNull);
    });

    test('reflects a lean the other way', () {
      // Clockwise degrees, y down: 30° points right-and-down. Across a
      // vertical axis that becomes left-and-down, which is 150°.
      expect(
          mirror([at(0.5, 0.5, angle: 30)], MirrorAxis.horizontal).single.angle,
          150);
      // Across a horizontal axis it becomes right-and-up, which is 330°.
      expect(
          mirror([at(0.5, 0.5, angle: 30)], MirrorAxis.vertical).single.angle,
          330);
    });

    test('leaves an asset already square to the flip axis square to it', () {
      // A quarter-turned asset is parallel to the vertical mirror line, so a
      // horizontal flip cannot change which way it lies.
      expect(
          mirror([at(0.5, 0.5, angle: 90)], MirrorAxis.horizontal).single.angle,
          90);
    });
  });

  group('mirrorGroup — the layout', () {
    test('reverses a row about the group centre', () {
      final result = mirror(
        [at(0.2, 0.5), at(0.4, 0.5), at(0.9, 0.5)],
        MirrorAxis.horizontal,
      );

      // Centre of the box spanning 0.2..0.9 is 0.55, so each x reflects to
      // 1.1 - x. The order along the row is reversed.
      expect(result[0].x, closeTo(0.9, 1e-12));
      expect(result[1].x, closeTo(0.7, 1e-12));
      expect(result[2].x, closeTo(0.2, 1e-12));

      // The axis not being mirrored is untouched.
      for (final p in result) {
        expect(p.y, closeTo(0.5, 1e-12));
      }
    });

    test('reverses a column about the group centre', () {
      final result = mirror(
        [at(0.5, 0.2), at(0.5, 0.4), at(0.5, 0.9)],
        MirrorAxis.vertical,
      );

      expect(result[0].y, closeTo(0.9, 1e-12));
      expect(result[1].y, closeTo(0.7, 1e-12));
      expect(result[2].y, closeTo(0.2, 1e-12));
      for (final p in result) {
        expect(p.x, closeTo(0.5, 1e-12));
      }
    });

    test('leaves the group where it was', () {
      // The bounding box maps onto itself, so a selection nowhere near the
      // middle of the canvas does not slide towards it.
      final result = mirror(
        [at(0.05, 0.05), at(0.25, 0.15)],
        MirrorAxis.horizontal,
      );

      final xs = [for (final p in result) p.x]..sort();
      expect(xs.first, closeTo(0.05, 1e-12));
      expect(xs.last, closeTo(0.25, 1e-12));
    });

    test('is unaffected by the aspect ratio for unrotated assets', () {
      // x reflects about a centre derived from the same x values, so the
      // aspect scaling cancels. It only matters once an asset is rotated and
      // its bounding box has to be measured.
      for (final aspect in [1.0, 16 / 9, 0.5]) {
        final result = mirror(
          [at(0.2, 0.5), at(0.6, 0.5)],
          MirrorAxis.horizontal,
          aspectRatio: aspect,
        );
        expect(result[0].x, closeTo(0.6, 1e-12), reason: 'aspect $aspect');
        expect(result[1].x, closeTo(0.2, 1e-12), reason: 'aspect $aspect');
      }
    });
  });

  group('mirrorGroup — round trips', () {
    test('mirroring twice about the same axis is the identity', () {
      final start = [
        at(0.2, 0.3, angle: 30),
        at(0.7, 0.8),
        at(0.45, 0.55, angle: 90),
      ];

      for (final axis in MirrorAxis.values) {
        final back = mirror(mirror(start, axis, aspectRatio: 16 / 9), axis,
            aspectRatio: 16 / 9);
        for (var i = 0; i < start.length; i++) {
          expect(back[i].x, closeTo(start[i].x, 1e-12), reason: '$axis x[$i]');
          expect(back[i].y, closeTo(start[i].y, 1e-12), reason: '$axis y[$i]');
          expect(back[i].angle, start[i].angle, reason: '$axis angle[$i]');
        }
      }
    });

    test('both axes together is a half turn of the layout', () {
      final both = mirror(
        mirror([at(0.2, 0.3), at(0.6, 0.7)], MirrorAxis.horizontal),
        MirrorAxis.vertical,
      );

      // Point reflection through the group centre (0.4, 0.5).
      expect(both[0].x, closeTo(0.6, 1e-12));
      expect(both[0].y, closeTo(0.7, 1e-12));
      expect(both[1].x, closeTo(0.2, 1e-12));
      expect(both[1].y, closeTo(0.3, 1e-12));

      // ...and of each asset: 0 -> 180 -> 180.
      expect(both[0].angle, 180);
    });
  });

  group('mirrorGroup — degenerate input', () {
    test('an empty selection comes back empty', () {
      expect(mirror([], MirrorAxis.horizontal), isEmpty);
    });

    test('a non-finite aspect ratio falls back to square rather than NaN', () {
      for (final aspect in [double.nan, 0.0, double.infinity, -2.0]) {
        final result = mirror(
            [at(0.2, 0.5), at(0.6, 0.5)], MirrorAxis.horizontal,
            aspectRatio: aspect);
        for (final p in result) {
          expect(p.x.isFinite, isTrue, reason: 'aspect $aspect');
          expect(p.y.isFinite, isTrue, reason: 'aspect $aspect');
        }
      }
    });

    test('nothing is mutated', () {
      final start = [at(0.2, 0.3, angle: 30)];
      mirror(start, MirrorAxis.horizontal);
      expect(start.single.x, 0.2);
      expect(start.single.angle, 30);
    });
  });
}
