// Turning a published shape into the ring that gets drawn around it.
//
// This is the half of the open-pane mark that has no widgets in it: walk a
// path into points, then push those points off the shape. Tested against a
// disc and a band rather than against a live asset, because the properties
// that matter — the ring keeps the shape, stands the same distance off it all
// the way round, and moves the edge of a hole into the hole — are properties
// of the geometry, not of any one conveyor.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/hit_boundary.dart';

/// Distance from [centre] to the furthest and nearest point of an outline.
({double min, double max}) _radii(List<Offset> ring, Offset centre) {
  var min = double.infinity;
  var max = 0.0;
  for (final point in ring) {
    final r = (point - centre).distance;
    min = math.min(min, r);
    max = math.max(max, r);
  }
  return (min: min, max: max);
}

Rect _bounds(List<Offset> ring) {
  var rect = Rect.fromLTRB(
    double.infinity,
    double.infinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final p in ring) {
    rect = Rect.fromLTRB(
      math.min(rect.left, p.dx),
      math.min(rect.top, p.dy),
      math.max(rect.right, p.dx),
      math.max(rect.bottom, p.dy),
    );
  }
  return rect;
}

void main() {
  const centre = Offset(60, 60);

  Path disc({double radius = 30}) =>
      Path()..addOval(Rect.fromCircle(center: centre, radius: radius));

  group('flatten', () {
    test('walks a path into points along it', () {
      final ring = flattenPath(disc()).single;

      // Every point on the rim, and enough of them that the straight line
      // between neighbours is not a shortcut anyone can see.
      final radii = _radii(ring, centre);
      expect(radii.min, closeTo(30, 0.2));
      expect(radii.max, closeTo(30, 0.2));
      expect(ring.length, closeTo(2 * math.pi * 30 / 2, 3));
    });

    test('a coarser step gives fewer points on the same shape', () {
      final fine = flattenPath(disc()).single;
      final coarse = flattenPath(disc(), step: 8).single;
      expect(coarse.length, lessThan(fine.length));
      final radii = _radii(coarse, centre);
      expect(radii.min, closeTo(30, 0.3));
      expect(radii.max, closeTo(30, 0.3));
    });

    test('one ring per closed subpath, and none for an empty path', () {
      final two = Path()
        ..addOval(Rect.fromCircle(center: centre, radius: 30))
        ..addOval(Rect.fromCircle(center: centre, radius: 12));
      expect(flattenPath(two), hasLength(2));
      expect(flattenPath(Path()), isEmpty);
    });
  });

  group('standoff', () {
    test('stands the ring off the shape by the distance asked for', () {
      final shape = disc();
      final ring = offsetContour(
        flattenPath(shape).single,
        4,
        inside: shape.contains,
      );

      // Evenly, all the way round: the complaint that started this was a ring
      // 2px clear of a belt above and 3px clear below.
      final radii = _radii(ring, centre);
      expect(radii.min, closeTo(34, 0.3));
      expect(radii.max, closeTo(34, 0.3));
    });

    test('a band keeps its shape, standing off both long edges', () {
      // The straight-conveyor case: a belt down the middle of a taller box.
      const belt = Rect.fromLTWH(10, 50, 100, 20);
      final shape = Path()..addRect(belt);
      final ring = offsetContour(
        flattenPath(shape).single,
        4,
        inside: shape.contains,
      );

      final bounds = _bounds(ring);
      expect(bounds.top, closeTo(belt.top - 4, 0.5));
      expect(bounds.bottom, closeTo(belt.bottom + 4, 0.5));
      expect(bounds.left, closeTo(belt.left - 4, 0.5));
      expect(bounds.right, closeTo(belt.right + 4, 0.5));
    });

    test('moves the edge of a hole into the hole', () {
      // Both edges stand off the material, so the inner one shrinks.
      final shape = Path()
        ..addOval(Rect.fromCircle(center: centre, radius: 40))
        ..addOval(Rect.fromCircle(center: centre, radius: 20))
        ..fillType = PathFillType.evenOdd;

      final rings = [
        for (final ring in flattenPath(shape))
          offsetContour(ring, 3, inside: shape.contains),
      ];
      expect(rings, hasLength(2));

      final radii = [for (final ring in rings) _radii(ring, centre)]
        ..sort((a, b) => a.max.compareTo(b.max));
      expect(radii.first.max, closeTo(17, 0.5), reason: 'inside the hole');
      expect(radii.last.max, closeTo(43, 0.5), reason: 'outside the disc');
    });

    test('leaves a ring alone at zero, and one too short to have a normal',
        () {
      final ring = flattenPath(disc()).single;
      expect(offsetContour(ring, 0, inside: disc().contains), same(ring));
      final stub = [Offset.zero, const Offset(1, 1)];
      expect(offsetContour(stub, 3, inside: disc().contains), same(stub));
    });
  });

  group('painter', () {
    test('repaints when the outline or the ink changes', () {
      final contours = <List<Offset>>[
        [Offset.zero, const Offset(1, 1), const Offset(0, 1)]
      ];
      const ink = Color(0xFF102030);
      final painter = HitBoundaryPainter(contours: contours, color: ink);

      expect(
        painter.shouldRepaint(
            HitBoundaryPainter(contours: contours, color: ink)),
        isFalse,
      );
      expect(
        painter.shouldRepaint(HitBoundaryPainter(
            contours: contours, color: const Color(0xFF405060))),
        isTrue,
      );
      expect(
        painter.shouldRepaint(HitBoundaryPainter(
            contours: [
              [Offset.zero, const Offset(2, 2), const Offset(0, 2)]
            ],
            color: ink)),
        isTrue,
      );
    });
  });
}
