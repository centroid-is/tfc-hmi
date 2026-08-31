// Turning a published shape into the ring that gets drawn around it.
//
// This is the half of the open-pane mark that has no widgets in it: walk a
// path into points, then push those points off the shape. Tested against a
// disc and a band rather than against a live asset, because the properties
// that matter — the ring keeps the shape, stands the same distance off it all
// the way round, and moves the edge of a hole into the hole — are properties
// of the geometry, not of any one conveyor.
//
// And then cutting that ring into the dashes that crawl round it. Those are
// geometry too: a dash pattern that fits the ring exactly, painted runs that
// lie on the ring and nowhere else, and a phase that returns the picture it
// started from — which is the whole of what makes the crawl look continuous
// rather than like a ring being redrawn.
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
    test('repaints when the outline or either tone changes', () {
      final contours = <List<Offset>>[
        [Offset.zero, const Offset(1, 1), const Offset(0, 1)]
      ];
      final painter = HitBoundaryPainter(contours: contours);

      expect(
        painter.shouldRepaint(HitBoundaryPainter(contours: contours)),
        isFalse,
      );
      expect(
        painter.shouldRepaint(HitBoundaryPainter(
            contours: contours, ink: const Color(0xFF405060))),
        isTrue,
      );
      expect(
        painter.shouldRepaint(HitBoundaryPainter(
            contours: contours, halo: const Color(0xFF405060))),
        isTrue,
      );
      expect(
        painter.shouldRepaint(HitBoundaryPainter(contours: [
          [Offset.zero, const Offset(2, 2), const Offset(0, 2)]
        ])),
        isTrue,
      );
    });

    test('repaints as the dashes move, and when the style changes', () {
      final contours = <List<Offset>>[
        [Offset.zero, const Offset(1, 1), const Offset(0, 1)]
      ];
      final painter = HitBoundaryPainter(contours: contours);

      expect(
        painter.shouldRepaint(
            HitBoundaryPainter(contours: contours, phase: 0.25)),
        isTrue,
        reason: 'the crawl is nothing but a changing phase',
      );
      expect(
        painter.shouldRepaint(HitBoundaryPainter(
            contours: contours, style: HitBoundaryStyle.brisk)),
        isTrue,
      );
      expect(
        painter.shouldRepaint(HitBoundaryPainter(
            contours: contours, style: HitBoundaryStyle.pulsing)),
        isTrue,
        reason: 'a ring that breathes instead of crawling is a different ring',
      );
    });

    test('a ring that only breathes keeps its dashes where they are', () {
      // The pulsing style animates opacity, not position. Phase still drives
      // it — that is what makes the breath — so the guard is that the dashes
      // it cuts do not move with it.
      final ring = [
        for (var i = 0; i < 4; i++)
          Offset(i == 1 || i == 2 ? 100 : 0, i >= 2 ? 100 : 0),
      ];
      final still = HitBoundaryStyle.pulsing;
      expect(still.crawl, isFalse);
      expect(still.pulse, greaterThan(0));

      // The painter slides the pattern by `phase * period` only when the
      // style crawls, so a still ring is the phase-0 cut at every phase.
      final at0 = dashRing(ring, dash: 6, gap: 4, phase: 0);
      final at7 = dashRing(ring, dash: 6, gap: 4, phase: 7);
      expect(at7, isNot(at0), reason: 'the cut itself does move with phase');
      expect(dashRing(ring, dash: 6, gap: 4, phase: 0), at0);
    });

    test('the two tones are far enough apart to carry any background', () {
      // W3C technique C40: two colours at least 9:1 apart guarantee that one
      // of them clears 3:1 against whatever solid colour they land on. The
      // ring lands on state fills as often as on the page. The halo no longer
      // surrounds the ink — under `twoTone` it alternates with it along the
      // same line — but it is the same guarantee and the same pair.
      double luminance(Color c) => c.withValues(alpha: 1).computeLuminance();
      final ink = luminance(HitBoundaryPainter.defaultInk);
      final halo = luminance(HitBoundaryPainter.defaultHalo);
      final contrast =
          (math.max(ink, halo) + 0.05) / (math.min(ink, halo) + 0.05);
      expect(contrast, greaterThan(9));
    });
  });

  group('fitDashes', () {
    test('scales the pattern so a whole number of it fits the ring', () {
      // 100 wants ten 6+4s and gets them.
      expect(fitDashes(100, dash: 6, gap: 4), (dash: 6.0, gap: 4.0));

      // 93 does not. Nine periods is the nearest fit, so every dash and every
      // gap gives by the same fraction rather than one runt taking all of it.
      final fitted = fitDashes(93, dash: 6, gap: 4);
      expect(93 / (fitted.dash + fitted.gap), closeTo(9, 1e-9));
      expect(fitted.dash / fitted.gap, closeTo(6 / 4, 1e-9),
          reason: 'the pattern keeps its proportions');
    });

    test('a ring too short for one period still gets one', () {
      final fitted = fitDashes(3, dash: 6, gap: 4);
      expect(fitted.dash + fitted.gap, closeTo(3, 1e-9));
    });

    test('leaves a degenerate ring alone', () {
      expect(fitDashes(0, dash: 6, gap: 4), (dash: 6.0, gap: 4.0));
    });
  });

  group('dashRing', () {
    /// A square, walked corner to corner — perimeter 400.
    List<Offset> square([double side = 100]) => [
          Offset.zero,
          Offset(side, 0),
          Offset(side, side),
          Offset(0, side),
        ];

    double runLength(List<Offset> run) {
      var length = 0.0;
      for (var i = 1; i < run.length; i++) {
        length += (run[i] - run[i - 1]).distance;
      }
      return length;
    }

    test('cuts the ring into runs of the length asked for', () {
      final runs = dashRing(square(), dash: 6, gap: 4);
      expect(runs, hasLength(40), reason: '400 / (6 + 4)');
      for (final run in runs) {
        expect(runLength(run), closeTo(6, 1e-6));
      }
    });

    test('every run lies on the ring it was cut from', () {
      // The dashes are the outline, not an approximation drawn near it: a run
      // that left the ring would be a second opinion about the asset's shape,
      // which is the thing this whole file exists to prevent.
      final ring = square();
      for (final run in dashRing(ring, dash: 6, gap: 4, phase: 3.7)) {
        for (final point in run) {
          final onEdge = (point.dy.abs() < 1e-6 || (point.dy - 100).abs() < 1e-6)
                  && point.dx >= -1e-6 && point.dx <= 100 + 1e-6 ||
              (point.dx.abs() < 1e-6 || (point.dx - 100).abs() < 1e-6) &&
                  point.dy >= -1e-6 && point.dy <= 100 + 1e-6;
          expect(onEdge, isTrue, reason: '$point is off the square');
        }
      }
    });

    test('a run turns the corner rather than cutting it', () {
      // A dash straddling a corner keeps the corner point, so it bends with
      // the ring. Cutting straight across would round every corner of every
      // marked asset by however long a dash is.
      final ring = square();
      // Phase 0 puts a dash boundary on the corner at 100; 97 lands a dash
      // across it.
      final runs = dashRing(ring, dash: 6, gap: 4, phase: -97);
      final turning = runs.where((r) => r.length > 2).toList();
      expect(turning, isNotEmpty);
      expect(
        turning.any((r) => r.any((p) => (p - const Offset(100, 0)).distance < 1e-6)),
        isTrue,
      );
    });

    test('one whole period of phase is the same picture again', () {
      // What makes the crawl read as a ring of dashes moving rather than as a
      // ring being redrawn — and what lets the animation loop.
      String shape(List<List<Offset>> runs) => runs
          .map((r) => r
              .map((p) => '${p.dx.toStringAsFixed(4)},${p.dy.toStringAsFixed(4)}')
              .join(';'))
          .join('|');

      final ring = square();
      expect(
        shape(dashRing(ring, dash: 6, gap: 4, phase: 10)),
        shape(dashRing(ring, dash: 6, gap: 4, phase: 0)),
      );
      // Half a period along, every dash sits where its own gap was.
      expect(
        shape(dashRing(ring, dash: 6, gap: 4, phase: 5)),
        isNot(shape(dashRing(ring, dash: 6, gap: 4, phase: 0))),
      );
    });

    test('the dashes and their gaps tile the ring without overlapping', () {
      // The two-tone arrangement: the light runs are the same pattern slid on
      // by one dash, so together the two cover the ring exactly once.
      final ring = square();
      final dashes = dashRing(ring, dash: 6, gap: 4, phase: 2);
      final gaps = dashRing(ring, dash: 4, gap: 6, phase: 2 - 6);
      final covered = dashes.fold(0.0, (sum, r) => sum + runLength(r)) +
          gaps.fold(0.0, (sum, r) => sum + runLength(r));
      expect(covered, closeTo(400, 1e-4));
    });

    test('a pattern with no gap is the whole closed ring', () {
      final runs = dashRing(square(), dash: 6, gap: 0);
      expect(runs, hasLength(1));
      expect(runLength(runs.single), closeTo(400, 1e-6));
    });

    test('nothing to cut gives nothing', () {
      expect(dashRing(const [Offset.zero], dash: 6, gap: 4), isEmpty);
      expect(dashRing(square(), dash: 0, gap: 4), isEmpty);
      expect(
        dashRing(const [Offset.zero, Offset.zero, Offset.zero],
            dash: 6, gap: 4),
        isEmpty,
        reason: 'a ring of no length',
      );
    });
  });
}
