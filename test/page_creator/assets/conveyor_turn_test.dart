import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

void main() {
  group('ConveyorTurnEntry serialization', () {
    test('round-trips through JSON', () {
      final config = ConveyorConfig(
        key: 'conveyor1',
        turns: [
          ConveyorTurnEntry(position: 0.3, angle: 45, radius: 2.0),
          ConveyorTurnEntry(position: 0.7, angle: -90, radius: 1.0),
        ],
      );
      config.variant = 'conveyor';

      final restored = ConveyorConfig.fromJson(config.toJson());
      expect(restored.turns, hasLength(2));
      expect(restored.turns[0].position, 0.3);
      expect(restored.turns[0].angle, 45);
      expect(restored.turns[0].radius, 2.0);
      expect(restored.turns[1].angle, -90);
    });

    test('old configs without turns deserialize to straight conveyor', () {
      final config = ConveyorConfig(key: 'conveyor1');
      config.variant = 'conveyor';
      final json = config.toJson()..remove('turns');
      final restored = ConveyorConfig.fromJson(json);
      expect(restored.turns, isEmpty);
    });
  });

  group('ConveyorPathGeometry', () {
    const size = Size(300, 40);

    test('returns null for straight conveyors', () {
      expect(ConveyorPathGeometry.build([], size), isNull);
    });

    test('thicknessFactor thins the belt', () {
      final fat = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)],
        const Size(300, 300),
      )!;
      final thin = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)],
        const Size(300, 300),
        thicknessFactor: 0.15,
      )!;
      expect(thin.beltWidth, lessThan(fat.beltWidth));
      // The thin belt wastes less of the box on its own width, so its
      // centerline path is longer.
      expect(thin.length, greaterThan(fat.length));
    });

    test('fitted belt stays inside the bounding box', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.3, angle: 90, radius: 1.5)],
        size,
      )!;
      // Centerline bounds inflated by half the belt width must fit the box.
      final beltBounds =
          geometry.path.getBounds().inflate(geometry.beltWidth / 2);
      expect(beltBounds.left, greaterThanOrEqualTo(-0.5));
      expect(beltBounds.top, greaterThanOrEqualTo(-0.5));
      expect(beltBounds.right, lessThanOrEqualTo(size.width + 0.5));
      expect(beltBounds.bottom, lessThanOrEqualTo(size.height + 0.5));
    });

    test('tangent follows the turn direction', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.0)],
        size,
      )!;
      // Before the turn the belt travels horizontally (+x).
      final before = geometry.tangentAt(0.1).vector;
      expect(before.dx, closeTo(1.0, 1e-6));
      expect(before.dy, closeTo(0.0, 1e-6));
      // After a +90° turn it travels downwards (+y in screen coords).
      final after = geometry.tangentAt(0.95).vector;
      expect(after.dx, closeTo(0.0, 1e-3));
      expect(after.dy, closeTo(1.0, 1e-3));
    });

    test('negative angle turns the other way', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: -90, radius: 1.0)],
        size,
      )!;
      final after = geometry.tangentAt(0.95).vector;
      expect(after.dy, closeTo(-1.0, 1e-3));
    });

    test('fractional positions map monotonically along the path', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.3, angle: 45, radius: 1.5)],
        size,
      )!;
      var previous = -1.0;
      for (var f = 0.0; f <= 1.0; f += 0.1) {
        final p = geometry.tangentAt(f).position;
        // Distance from the start point must grow with the fraction.
        final start = geometry.tangentAt(0).position;
        final d = sqrt(pow(p.dx - start.dx, 2) + pow(p.dy - start.dy, 2));
        expect(d, greaterThanOrEqualTo(previous));
        previous = d;
      }
    });

    test('extractFraction yields a segment of the expected length', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 60, radius: 2.0)],
        size,
      )!;
      final segment = geometry.extractFraction(0.2, 0.4);
      final segmentLength = segment
          .computeMetrics()
          .fold<double>(0, (sum, m) => sum + m.length);
      // PathMetric walks the curve in flattened steps, so allow a hair of
      // discretisation error.
      expect(segmentLength, closeTo(geometry.length * 0.2, 1e-2));
    });

    test('bandOutline spans the requested stretch of belt', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 60, radius: 2.0)],
        const Size(400, 200),
        thicknessFactor: 0.2,
      )!;
      final width = geometry.beltWidth * 0.8;
      final outline =
          geometry.bandOutline(0.3, 0.6, width: width, radius: width * 0.2)!;
      final bounds = outline.getBounds();
      // Every point of the stretch, fattened by half the band, must be inside
      // the outline's bounds — and nothing far outside it.
      for (var f = 0.3; f <= 0.6; f += 0.01) {
        final p = geometry.tangentAt(f).position;
        expect(bounds.inflate(0.5).contains(p), isTrue, reason: 'at $f');
      }
      expect(bounds.width, lessThanOrEqualTo(geometry.length + width));
      expect(bounds.height, lessThanOrEqualTo(geometry.length + width));
    });

    test('bandOutline stays within half a band of the centerline', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)],
        const Size(400, 200),
        thicknessFactor: 0.2,
      )!;
      const width = 20.0;
      final outline = geometry.bandOutline(0.2, 0.8, width: width, radius: 4)!;
      final centerline = geometry.extractFraction(0.2, 0.8).getBounds();
      // The band is the centerline fattened by half its width, no more.
      expect(outline.getBounds().left,
          greaterThanOrEqualTo(centerline.left - width / 2 - 0.5));
      expect(outline.getBounds().right,
          lessThanOrEqualTo(centerline.right + width / 2 + 0.5));
      expect(outline.getBounds().top,
          greaterThanOrEqualTo(centerline.top - width / 2 - 0.5));
      expect(outline.getBounds().bottom,
          lessThanOrEqualTo(centerline.bottom + width / 2 + 0.5));
    });

    test('bandOutline degenerates safely on an empty or inverted stretch', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 60, radius: 2.0)],
        size,
      )!;
      expect(geometry.bandOutline(0.5, 0.5, width: 10, radius: 2)!.getBounds(),
          Rect.zero);
      expect(geometry.bandOutline(0.7, 0.2, width: 10, radius: 2)!.getBounds(),
          Rect.zero);
      expect(geometry.bandOutline(0, 1, width: 0, radius: 2)!.getBounds(),
          Rect.zero);
    });

    test('a band narrower than its corner radius still closes', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 60, radius: 2.0)],
        const Size(400, 200),
        thicknessFactor: 0.2,
      )!;
      // Radius clamped to half the width and half the span, like an RRect.
      final outline = geometry.bandOutline(0.4, 0.42, width: 8, radius: 40)!;
      expect(outline.getBounds().isEmpty, isFalse);
    });

    test('a band wider than its own bend has no outline', () {
      // The inner edge would reach past the centre of curvature and fold the
      // outline into a bow tie; the painter strokes the centerline instead.
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 120, radius: 0.5)],
        size,
        thicknessFactor: 1.0,
      )!;
      expect(
          geometry.bandOutline(0, 1, width: geometry.beltWidth * 4, radius: 2),
          isNull);
    });

    test('the fold verdict is the belt\'s, not its box\'s', () {
      // It used to be read off samples of the path taken every few absolute
      // pixels, so the same belt could be judged foldable at one size and not
      // at another — and a page re-fit swapped a band for a stroked
      // centerline under the operator.
      List<ConveyorTurnEntry> turns() =>
          [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 0.6)];
      double foldRatio(double scale) {
        final g = ConveyorPathGeometry.build(
            turns(), Size(189 * scale, 270 * scale),
            thicknessFactor: 0.45)!;
        return g.beltWidth / 2 / g.minTurnRadius;
      }

      final atFullSize = foldRatio(1.0);
      for (final scale in [0.9, 0.8, 0.7, 0.6, 0.5]) {
        // Not exact, and cannot be. An unfillable box now has its belt
        // sized by measuring the ink, and the ink includes the outline —
        // two pixels wide on every screen, by design, so that a small belt
        // is outlined as legibly as a big one. A fixed width is a bigger
        // share of a small belt than of a big one, so it moves this ratio
        // by just under a percent across the sizes below. Every other length
        // in the fit is proportional.
        //
        // The defect this guards against was of a different order: the bend
        // radius was read back off samples taken every few *absolute*
        // pixels, so the verdict moved by whole percent with the box and
        // swapped a drawn band for a stroked centerline under the operator
        // on a resize. `bandOutline` keeps 2% of headroom before it calls a
        // belt folded, so what is left here can only matter to a belt
        // already sitting within a percent of that edge.
        expect(foldRatio(scale), closeTo(atFullSize, 1e-2),
            reason: 'the belt is the same fraction of its own bend at every '
                'size, so it folds at every size or at none');
      }
    });
  });

  group('where a newly added turn lands', () {
    test('the first turn goes to the middle of the belt', () {
      expect(ConveyorTurnEntry.freePosition([]), closeTo(0.5, 1e-9));
    });

    test('a second turn does not stack on the first', () {
      // Two turns on the same point share a corner, where each fillet is
      // clamped to the zero-length straight between them and both bends
      // paint as one — so the added turn appeared to do nothing.
      final first = [ConveyorTurnEntry(position: 0.5)];
      final second = ConveyorTurnEntry.freePosition(first);
      expect(second, isNot(closeTo(0.5, 1e-6)));
      expect(second, inInclusiveRange(0.0, 1.0));
    });

    test('each turn lands in the widest gap left', () {
      final turns = <ConveyorTurnEntry>[];
      for (var i = 0; i < 5; i++) {
        turns.add(ConveyorTurnEntry(
            position: ConveyorTurnEntry.freePosition(turns)));
      }
      final positions = turns.map((t) => t.position).toList()..sort();
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i] - positions[i - 1], greaterThan(1e-3),
            reason: 'turns must not stack: $positions');
      }
    });

    test('positions outside the belt do not throw the search off', () {
      final odd = [
        ConveyorTurnEntry(position: -3),
        ConveyorTurnEntry(position: 4),
      ];
      final pick = ConveyorTurnEntry.freePosition(odd);
      expect(pick, inInclusiveRange(0.0, 1.0));
    });
  });
}
