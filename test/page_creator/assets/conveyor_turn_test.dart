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
  });
}
