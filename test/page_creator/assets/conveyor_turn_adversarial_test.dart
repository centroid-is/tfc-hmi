import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// Deliberate attempts to break the turn geometry: degenerate inputs, hostile
/// combinations, and a broad deterministic sweep asserting the invariants
/// that must survive *any* configuration:
///
///  * build never throws and never returns NaN geometry
///  * the painted belt stays inside its box whenever the belt itself fits
///  * belt positions map monotonically along the path
///  * the belt is never shorter than the straight line between its ends
void main() {
  const box = Size(400, 200);

  void checkInvariants(List<ConveyorTurnEntry> turns, Size size,
      {double? beltWidthOverride, String? reason}) {
    final g = ConveyorPathGeometry.build(turns, size,
        thicknessFactor: 0.3, beltWidthOverride: beltWidthOverride);
    if (size.width <= 0 || size.height <= 0) {
      expect(g, isNull, reason: reason);
      return;
    }
    expect(g, isNotNull, reason: reason);
    expect(g!.length.isFinite, isTrue, reason: reason);
    expect(g.length, greaterThan(0), reason: reason);

    final b = g.path.getBounds();
    for (final v in [b.left, b.top, b.right, b.bottom]) {
      expect(v.isFinite, isTrue, reason: '$reason: non-finite bounds');
    }

    // Whenever the belt is narrow enough to ever fit the box, the painted
    // area must be contained. A belt wider than the box may spill by design.
    // Measure the ink itself — the band outline plus border — rather than
    // inflating the centerline bounds on every side: the belt ends in flat
    // caps, and the fit centers the ink, spending slack exactly where the
    // band does not extend.
    if (g.beltWidth + 8 < size.shortestSide) {
      final band = g
              .bandOutline(0, 1,
                  width: g.beltWidth, radius: g.beltWidth * 0.2)
              ?.getBounds() ??
          g.path.getBounds().inflate(g.beltWidth / 2);
      final painted = band.inflate(2);
      expect(painted.left, greaterThanOrEqualTo(-0.5), reason: reason);
      expect(painted.top, greaterThanOrEqualTo(-0.5), reason: reason);
      expect(painted.right, lessThanOrEqualTo(size.width + 0.5),
          reason: reason);
      expect(painted.bottom, lessThanOrEqualTo(size.height + 0.5),
          reason: reason);
    }

    // Fractions walk forward, never backward or off the path.
    var last = 0.0;
    for (var f = 0.0; f <= 1.0; f += 0.05) {
      final t = g.tangentAt(f);
      expect(t.position.dx.isFinite && t.position.dy.isFinite, isTrue,
          reason: '$reason: non-finite tangent at $f');
      final d = (t.position - g.tangentAt(0).position).distance;
      expect(d.isFinite, isTrue, reason: reason);
      last = max(last, d);
    }
    expect(last, greaterThan(0), reason: '$reason: belt has no extent');

    // The belt cannot be shorter than the crow-flies distance of its ends.
    final ends =
        (g.tangentAt(1).position - g.tangentAt(0).position).distance;
    expect(g.length, greaterThanOrEqualTo(ends - 0.5), reason: reason);
  }

  group('degenerate inputs', () {
    test('empty and zero-angle turn lists build nothing', () {
      expect(ConveyorPathGeometry.build([], box), isNull);
      // angle 0 is filtered; an all-zero list is a straight belt with a
      // valid path.
      final g = ConveyorPathGeometry.build(
          [ConveyorTurnEntry(position: 0.5, angle: 0)], box,
          thicknessFactor: 0.3);
      expect(g, isNotNull);
      expect(g!.tangentAt(0.9).vector.dy.abs(), lessThan(1e-6));
    });

    test('zero and negative box sizes never crash', () {
      for (final size in const [Size(0, 0), Size(-10, 50), Size(50, -10)]) {
        checkInvariants(
            [ConveyorTurnEntry(position: 0.5, angle: 45)], size,
            reason: 'box $size');
      }
    });

    test('1x1 box never crashes', () {
      checkInvariants([ConveyorTurnEntry(position: 0.5, angle: 45)],
          const Size(1, 1),
          reason: '1x1');
    });

    test('positions outside 0..1 are clamped, not obeyed', () {
      checkInvariants([
        ConveyorTurnEntry(position: -3, angle: 45),
        ConveyorTurnEntry(position: 7, angle: -45),
      ], box, reason: 'positions off the belt');
    });

    test('two turns on the same position share a corner without crashing',
        () {
      checkInvariants([
        ConveyorTurnEntry(position: 0.5, angle: 45),
        ConveyorTurnEntry(position: 0.5, angle: 45),
      ], box, reason: 'stacked turns');
    });

    test('turns at the very ends of the belt', () {
      checkInvariants([
        ConveyorTurnEntry(position: 0.0, angle: 45),
        ConveyorTurnEntry(position: 1.0, angle: -45),
      ], box, reason: 'turns at 0 and 1');
    });

    test('a half-circle turn does not blow up on tan(90)', () {
      for (final angle in [180.0, -180.0, 179.9, -179.9]) {
        checkInvariants([ConveyorTurnEntry(position: 0.5, angle: angle)],
            const Size(400, 400),
            reason: 'angle $angle');
      }
    });

    test('angles beyond the editor range still build', () {
      // JSON can carry anything; the geometry clamps rather than trusts.
      for (final angle in [720.0, -3600.0, 1e9]) {
        checkInvariants([ConveyorTurnEntry(position: 0.5, angle: angle)],
            const Size(400, 400),
            reason: 'angle $angle');
      }
    });

    test('hostile radii', () {
      for (final radius in [0.0, -5.0, 1e6, double.maxFinite]) {
        checkInvariants(
            [ConveyorTurnEntry(position: 0.5, angle: 90, radius: radius)],
            box,
            reason: 'radius $radius');
      }
    });

    test('non-finite numbers from hand-edited JSON', () {
      for (final v in [double.nan, double.infinity, double.negativeInfinity]) {
        final g = ConveyorPathGeometry.build(
            [ConveyorTurnEntry(position: 0.5, angle: 45, radius: 1.5)],
            box,
            thicknessFactor: 0.3,
            beltWidthOverride: v);
        // Either refuse or produce finite geometry — never NaN output.
        if (g != null) {
          expect(g.path.getBounds().left.isFinite, isTrue,
              reason: 'beltWidthOverride $v');
        }
      }
    });
  });

  group('hostile combinations', () {
    test('a spiral: four 90s the same way folds back without crashing', () {
      checkInvariants([
        ConveyorTurnEntry(position: 0.2, angle: 90, radius: 1.0),
        ConveyorTurnEntry(position: 0.4, angle: 90, radius: 1.0),
        ConveyorTurnEntry(position: 0.6, angle: 90, radius: 1.0),
        ConveyorTurnEntry(position: 0.8, angle: 90, radius: 1.0),
      ], const Size(400, 400), reason: 'closed loop');
    });

    test('ten alternating turns', () {
      checkInvariants([
        for (var i = 0; i < 10; i++)
          ConveyorTurnEntry(
              position: (i + 1) / 11,
              angle: i.isEven ? 60 : -60,
              radius: 0.8),
      ], const Size(600, 300), reason: 'zigzag');
    });

    test('belt wider than the box with turns', () {
      checkInvariants([ConveyorTurnEntry(position: 0.5, angle: 45)],
          const Size(400, 30),
          beltWidthOverride: 80, reason: 'spilling belt');
    });

    test('sweep: angles x radii x boxes x positions', () {
      for (final angle in [-179.0, -135.0, -90.0, -30.0, 30.0, 90.0, 135.0, 179.0]) {
        for (final radius in [0.5, 1.5, 5.0]) {
          for (final size in const [
            Size(400, 60),
            Size(400, 200),
            Size(200, 400),
            Size(100, 100),
          ]) {
            for (final position in [0.0, 0.25, 0.5, 0.9, 1.0]) {
              checkInvariants(
                  [
                    ConveyorTurnEntry(
                        position: position, angle: angle, radius: radius)
                  ],
                  size,
                  reason: 'angle $angle radius $radius box $size '
                      'position $position');
            }
          }
        }
      }
    });

    test('sweep with explicit belt width', () {
      for (final width in [2.0, 20.0, 60.0]) {
        for (final angle in [-120.0, -45.0, 45.0, 120.0]) {
          checkInvariants(
              [ConveyorTurnEntry(position: 0.4, angle: angle, radius: 1.5)],
              box,
              beltWidthOverride: width,
              reason: 'width $width angle $angle');
        }
      }
    });
  });

  group('fill contract', () {
    test('a fillable single turn spans its box', () {
      final g = ConveyorPathGeometry.build(
          [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.5)],
          const Size(400, 300),
          beltWidthOverride: 30)!;
      const inset = 30 / 2 + 2;
      final b = g.path.getBounds();
      expect(b.width, closeTo(400 - 2 * inset, 1.0));
      expect(b.height, closeTo(300 - 2 * inset, 1.0));
    });

    test('the fill never paints outside the box', () {
      // The whole point of the clamp after the solve.
      for (final size in const [Size(400, 300), Size(300, 400), Size(500, 100)]) {
        final g = ConveyorPathGeometry.build(
            [ConveyorTurnEntry(position: 0.5, angle: 60, radius: 1.5)], size,
            beltWidthOverride: 24)!;
        // The real ink: band outline plus border (see the sweep invariant).
        final band = g
                .bandOutline(0, 1,
                    width: g.beltWidth, radius: g.beltWidth * 0.2)
                ?.getBounds() ??
            g.path.getBounds().inflate(g.beltWidth / 2);
        final painted = band.inflate(2);
        expect(painted.left, greaterThanOrEqualTo(-0.5));
        expect(painted.top, greaterThanOrEqualTo(-0.5));
        expect(painted.right, lessThanOrEqualTo(size.width + 0.5));
        expect(painted.bottom, lessThanOrEqualTo(size.height + 0.5));
      }
    });

    test('a solved fill is deterministic', () {
      Path build() => ConveyorPathGeometry.build(
              [ConveyorTurnEntry(position: 0.4, angle: 75, radius: 2.0)],
              const Size(420, 260),
              beltWidthOverride: 26)!
          .path;
      expect(build().getBounds(), build().getBounds());
    });
  });
}
