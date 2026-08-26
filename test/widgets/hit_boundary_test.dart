// The boundary tracer, against shapes whose outline is known in advance.
//
// This is the half of the open-pane mark that has no widgets in it: given a
// predicate saying where a tap lands, sample it and trace the line between
// yes and no. Tested here with a disc, a band and a ring rather than with a
// live asset, because the property that matters — the traced line follows the
// shape, and follows it *outside* the shape once dilated — is a property of
// the geometry, not of any one conveyor.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/hit_boundary.dart';

/// Distance from [centre] to the furthest and nearest point of an outline.
({double min, double max}) _radii(
  List<(Offset, Offset)> segments,
  Offset centre,
) {
  var min = double.infinity;
  var max = 0.0;
  for (final (from, to) in segments) {
    for (final point in [from, to]) {
      final r = (point - centre).distance;
      min = math.min(min, r);
      max = math.max(max, r);
    }
  }
  return (min: min, max: max);
}

Rect _bounds(List<(Offset, Offset)> segments) {
  var rect = Rect.fromLTRB(
    double.infinity,
    double.infinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final (from, to) in segments) {
    for (final p in [from, to]) {
      rect = Rect.fromLTRB(
        math.min(rect.left, p.dx),
        math.min(rect.top, p.dy),
        math.max(rect.right, p.dx),
        math.max(rect.bottom, p.dy),
      );
    }
  }
  return rect;
}

void main() {
  const area = Rect.fromLTWH(0, 0, 120, 120);
  const centre = Offset(60, 60);

  bool disc(Offset p) => (p - centre).distance <= 30;

  group('probe', () {
    test('samples the area a cell at a time, and beyond its edges', () {
      final mask = HitMask.probe(area: area, cell: 4, hit: disc);

      // Padded by two cells on each side so a shape reaching the edge still
      // has misses to be traced against.
      expect(mask.area.left, area.left - 8);
      expect(mask.area.width, area.width + 16);
      expect(mask.cols, (mask.area.width / 4).ceil());
      expect(mask.rows, (mask.area.height / 4).ceil());
    });

    test('answers the predicate, and nothing beyond the grid', () {
      final mask = HitMask.probe(area: area, cell: 4, hit: disc);

      // The sample nearest the centre is inside the disc; the corners are not.
      final centreCol = ((centre.dx - mask.area.left) / 4).floor();
      final centreRow = ((centre.dy - mask.area.top) / 4).floor();
      expect(mask.at(centreCol, centreRow), isTrue);
      expect(mask.at(0, 0), isFalse);
      expect(mask.at(-1, 0), isFalse, reason: 'off-grid reads as a miss');
      expect(mask.at(mask.cols, mask.rows), isFalse);
      expect(mask.isEmpty, isFalse);
    });

    test('a predicate nothing satisfies leaves an empty mask', () {
      final mask = HitMask.probe(area: area, cell: 4, hit: (_) => false);
      expect(mask.isEmpty, isTrue);
      expect(hitBoundarySegments(mask), isEmpty);
    });

    test('cell size follows the asset area, within bounds', () {
      // A sensor dot gets the floor, a page-wide belt the ceiling, and
      // everything between gets roughly the sample budget.
      expect(HitMask.cellFor(const Size(20, 20)), 2.0);
      expect(HitMask.cellFor(const Size(4000, 2000)), 12.0);

      const middling = Size(300, 200);
      final cell = HitMask.cellFor(middling, budget: 6000);
      final samples = (middling.width / cell) * (middling.height / cell);
      expect(samples, closeTo(6000, 600));
    });
  });

  group('boundary', () {
    test('traces a disc at its own radius, within a sample of it', () {
      final mask = HitMask.probe(area: area, cell: 2, hit: disc);
      final segments = hitBoundarySegments(mask);

      expect(segments, isNotEmpty);
      final radii = _radii(segments, centre);
      // Every traced point sits on the edge of the disc, give or take the
      // sample spacing — no stray segment cutting across the middle.
      expect(radii.min, greaterThan(30 - 2));
      expect(radii.max, lessThan(30 + 2));
    });

    test('a band is traced as a band, not as its bounding box', () {
      // The straight-conveyor case: a belt down the middle of a much taller
      // box. The whole point of tracing the hit test is that the outline
      // hugs the belt.
      const belt = Rect.fromLTWH(10, 50, 100, 20);
      final mask = HitMask.probe(
        area: area,
        cell: 2,
        hit: (p) => belt.contains(p),
      );

      final bounds = _bounds(hitBoundarySegments(mask));
      expect(bounds.top, closeTo(belt.top, 3));
      expect(bounds.bottom, closeTo(belt.bottom, 3));
      expect(bounds.height, lessThan(belt.height + 6));
      expect(bounds.height, lessThan(area.height / 3),
          reason: 'the box is 120 tall and the belt is 20; '
              'an outline of the box would be a lie about where taps land');
    });

    test('a shape with a hole is traced inside and out', () {
      // Both edges are edges of what takes a tap, so both are drawn.
      final mask = HitMask.probe(
        area: area,
        cell: 2,
        hit: (p) {
          final r = (p - centre).distance;
          return r <= 40 && r >= 20;
        },
      );
      final segments = hitBoundarySegments(mask);
      final radii = _radii(segments, centre);

      expect(radii.min, closeTo(20, 2), reason: 'the inner edge is traced');
      expect(radii.max, closeTo(40, 2), reason: 'the outer edge is traced');
    });
  });

  group('contours', () {
    test('a disc traces as one ring, a shape with a hole as two', () {
      final disc1 = traceContours(
          hitBoundarySegments(HitMask.probe(area: area, cell: 2, hit: disc)));
      expect(disc1, hasLength(1));

      final ring = traceContours(hitBoundarySegments(HitMask.probe(
        area: area,
        cell: 2,
        hit: (p) {
          final r = (p - centre).distance;
          return r <= 40 && r >= 20;
        },
      )));
      expect(ring, hasLength(2),
          reason: 'the outer edge and the edge of the hole');
    });

    test('a ring closes: it comes back to where it started', () {
      final contour = traceContours(
              hitBoundarySegments(HitMask.probe(area: area, cell: 2, hit: disc)))
          .single;
      // Not repeated at the end — the painter closes the path — so "closed"
      // means the last point is a step away from the first.
      expect((contour.last - contour.first).distance, lessThanOrEqualTo(2));
      expect(contour.length, greaterThan(20));
    });

    test('two separate shapes trace as two rings', () {
      final contours = traceContours(hitBoundarySegments(HitMask.probe(
        area: area,
        cell: 2,
        hit: (p) =>
            (p - const Offset(35, 60)).distance <= 15 ||
            (p - const Offset(85, 60)).distance <= 15,
      )));
      expect(contours, hasLength(2));
    });

    test('nothing to trace gives nothing', () {
      expect(traceContours(const []), isEmpty);
    });
  });

  group('smoothing', () {
    test('cuts the corners without moving the shape', () {
      final mask = HitMask.probe(area: area, cell: 4, hit: disc);
      final rough = traceContours(hitBoundarySegments(mask)).single;
      final smooth = smoothContour(rough);

      // Chaikin's twice: four times the points, and every one of them still
      // on the disc's edge within a fraction of a cell.
      expect(smooth.length, rough.length * 4);
      final radii = _radii([for (final p in smooth) (p, p)], centre);
      expect(radii.min, greaterThan(30 - 4));
      expect(radii.max, lessThan(30 + 4));
    });

    test('a smoothed ring turns less sharply than the ring it came from', () {
      // The property that matters: the staircase is gone. Measured as the
      // worst turn between neighbouring points — the traced ring corners at
      // the full 45° a chamfered staircase steps by, a smoothed one nowhere
      // near it.
      double sharpestTurn(List<Offset> ring) {
        var worst = 0.0;
        for (var i = 0; i < ring.length; i++) {
          final a = ring[i];
          final b = ring[(i + 1) % ring.length];
          final c = ring[(i + 2) % ring.length];
          final first = math.atan2(b.dy - a.dy, b.dx - a.dx);
          final second = math.atan2(c.dy - b.dy, c.dx - b.dx);
          var turn = (second - first).abs();
          if (turn > math.pi) turn = 2 * math.pi - turn;
          worst = math.max(worst, turn);
        }
        return worst;
      }

      final mask = HitMask.probe(area: area, cell: 4, hit: disc);
      final rough = traceContours(hitBoundarySegments(mask)).single;
      expect(sharpestTurn(rough), closeTo(math.pi / 4, 1e-9));
      expect(sharpestTurn(smoothContour(rough)), lessThan(math.pi / 6));
    });

    test('leaves a ring too short to smooth alone', () {
      final stub = [Offset.zero, const Offset(1, 0), const Offset(0, 1)];
      expect(smoothContour(stub), same(stub));
      expect(smoothContour(stub, iterations: 0), same(stub));
    });
  });

  group('refinement', () {
    test('bisects each crossing onto the real edge', () {
      // The grid answers to within half a sample and the error is uneven —
      // it depends where the shape falls against the grid, which is how a
      // belt centred in its box came out 2px clear above and 3px below.
      const coarse = 8.0;
      final mask = HitMask.probe(area: area, cell: coarse, hit: disc);

      final rough = _radii(hitBoundarySegments(mask), centre);
      final refined = _radii(hitBoundarySegments(mask, refine: disc), centre);

      expect(refined.max - refined.min, lessThan(0.5),
          reason: 'every crossing lands on the rim of the disc');
      expect(refined.max - refined.min, lessThan(rough.max - rough.min),
          reason: 'and it is tighter than the grid alone manages');
      expect(refined.min, closeTo(30, 0.2));
      expect(refined.max, closeTo(30, 0.2));
    });

    test('agrees with itself across a shared cell edge', () {
      // Neighbouring squares bisect the same edge independently, and
      // [traceContours] chains on the points being identical, not close.
      final mask = HitMask.probe(area: area, cell: 4, hit: disc);
      final contours = traceContours(
          hitBoundarySegments(mask, refine: disc));
      expect(contours, hasLength(1),
          reason: 'one ring, so every crossing met its neighbour exactly');
    });
  });

  group('standoff', () {
    test('stands the ring off the shape by the distance asked for', () {
      final mask = HitMask.probe(area: area, cell: 3, hit: disc);
      final ring = hitBoundaryContours(
        mask,
        refine: disc,
        standoff: 4,
      ).single;
      final radii = _radii([for (final p in ring) (p, p)], centre);

      // Evenly, all the way round — the complaint that started this was a
      // ring 2px clear of a belt above and 3px clear below.
      expect(radii.min, closeTo(34, 0.6));
      expect(radii.max, closeTo(34, 0.6));
    });

    test('moves the edge of a hole into the hole', () {
      // Both edges stand off the material, so the inner one shrinks.
      final rings = hitBoundaryContours(
        HitMask.probe(
          area: area,
          cell: 2,
          hit: (p) {
            final r = (p - centre).distance;
            return r <= 40 && r >= 20;
          },
        ),
        refine: (p) {
          final r = (p - centre).distance;
          return r <= 40 && r >= 20;
        },
        standoff: 3,
      );
      expect(rings, hasLength(2));

      final radii = [
        for (final ring in rings)
          _radii([for (final p in ring) (p, p)], centre),
      ]..sort((a, b) => a.max.compareTo(b.max));
      expect(radii.first.max, closeTo(17, 1), reason: 'inside the hole');
      expect(radii.last.max, closeTo(43, 1), reason: 'outside the disc');
    });

    test('without a predicate there is nothing to stand off from', () {
      final mask = HitMask.probe(area: area, cell: 3, hit: disc);
      final plain = hitBoundaryContours(mask, standoff: 4).single;
      final radii = _radii([for (final p in plain) (p, p)], centre);
      expect(radii.max, lessThan(33),
          reason: 'the standoff is ignored, not guessed at');
    });

    test('leaves a ring alone at zero, and one too short to have a normal',
        () {
      final ring = [
        for (var i = 0; i < 12; i++)
          Offset(60 + 20 * math.cos(i * math.pi / 6),
              60 + 20 * math.sin(i * math.pi / 6)),
      ];
      expect(offsetContour(ring, 0, inside: disc), same(ring));
      final stub = [Offset.zero, const Offset(1, 1)];
      expect(offsetContour(stub, 3, inside: disc), same(stub));
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
