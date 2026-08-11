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
      expect(segmentLength, closeTo(geometry.length * 0.2, 1e-3));
    });

    test('trimmedEnds cuts the requested length off both ends', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 60, radius: 2.0)],
        size,
      )!;
      final trim = geometry.length * 0.1;
      final trimmed = geometry.trimmedEnds(trim);
      final length = trimmed
          .computeMetrics()
          .fold<double>(0, (sum, m) => sum + m.length);
      expect(length, closeTo(geometry.length - 2 * trim, 1e-3));
    });

    test('trimmedEnds never inverts on a belt shorter than the trim', () {
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 60, radius: 2.0)],
        size,
      )!;
      final trimmed = geometry.trimmedEnds(geometry.length * 5);
      final length = trimmed
          .computeMetrics()
          .fold<double>(0, (sum, m) => sum + m.length);
      expect(length, greaterThanOrEqualTo(0));
      expect(length, lessThan(geometry.length));
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
