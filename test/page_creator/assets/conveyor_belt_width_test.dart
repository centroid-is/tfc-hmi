import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// Belt width can be given in the same screen-relative units as [RelativeSize],
/// so a straight belt and a turned belt set to the same percentage paint the
/// same width and line up on a page.
void main() {
  const screen = Size(1920, 1080);

  ConveyorConfig config({
    double? beltWidthRelative,
    List<ConveyorTurnEntry> turns = const [],
    RelativeSize size = const RelativeSize(width: 0.2, height: 0.1),
  }) {
    final c = ConveyorConfig(turns: turns);
    c.size = size;
    c.beltWidthRelative = beltWidthRelative;
    return c;
  }

  final turn = [ConveyorTurnEntry(position: 0.4, angle: 45, radius: 1.5)];

  group('screen-relative belt width', () {
    test('4% resolves to the same pixels with and without turns', () {
      final straight = config(beltWidthRelative: 0.04);
      final turned = config(beltWidthRelative: 0.04, turns: turn);
      expect(straight.requestedBeltWidth(screen), closeTo(0.04 * 1080, 1e-9));
      expect(turned.requestedBeltWidth(screen),
          equals(straight.requestedBeltWidth(screen)));
    });

    test('a turned belt actually paints at the requested width', () {
      final turned = config(beltWidthRelative: 0.04, turns: turn);
      final box = turned.size.toSize(screen);
      final g = ConveyorPathGeometry.build(turned.turns, box,
          beltWidthOverride: turned.requestedBeltWidth(screen));
      expect(g!.beltWidth, closeTo(0.04 * 1080, 1e-9));
    });

    test('belt width is independent of the box it sits in', () {
      // Two turned conveyors with different boxes but the same belt width
      // setting must paint the same belt.
      final wide = config(
          beltWidthRelative: 0.04,
          turns: turn,
          size: const RelativeSize(width: 0.3, height: 0.2));
      final narrow = config(
          beltWidthRelative: 0.04,
          turns: turn,
          size: const RelativeSize(width: 0.15, height: 0.12));
      double painted(ConveyorConfig c) => ConveyorPathGeometry.build(
              c.turns, c.size.toSize(screen),
              beltWidthOverride: c.requestedBeltWidth(screen))!
          .beltWidth;
      expect(painted(wide), closeTo(painted(narrow), 1e-9));
    });

    test('unset falls back to the box-relative thickness', () {
      final c = config(turns: turn);
      expect(c.requestedBeltWidth(screen), isNull);
      expect(c.beltWidthOverflows(screen), isFalse);
    });
  });

  group('overflow is honoured and flagged', () {
    test('a belt wider than the box is flagged but still painted as set', () {
      // Box is 10% of screen height = 108px; ask for 20% = 216px.
      final c = config(beltWidthRelative: 0.2);
      expect(c.beltWidthOverflows(screen), isTrue);
      expect(c.requestedBeltWidth(screen), closeTo(0.2 * 1080, 1e-9));
      expect(c.maxBeltWidth(screen), lessThan(0.2 * 1080));
    });

    test('a turned belt is bounded by the short side, not the height', () {
      // A tall box: height 30% = 324px, width 5% of 1920 = 96px. A bend curves
      // in both axes, so the width is what limits it.
      final c = config(
          beltWidthRelative: 0.2,
          turns: turn,
          size: const RelativeSize(width: 0.05, height: 0.3));
      expect(c.beltWidthOverflows(screen), isTrue);
      expect(c.maxBeltWidth(screen), lessThan(96.0 + 1));
    });

    test('a belt that fits is not flagged', () {
      final c = config(beltWidthRelative: 0.05);
      expect(c.beltWidthOverflows(screen), isFalse);
      expect(c.requestedBeltWidth(screen), closeTo(0.05 * 1080, 1e-9));
    });

    test('an oversized turned belt keeps its width and its centerline fit',
        () {
      // The belt spills over the box, but the skeleton it is stroked along
      // must still be laid out as if the belt were containable — otherwise
      // the fit collapses and the whole conveyor shrinks to nothing.
      final c = config(beltWidthRelative: 0.5, turns: turn);
      final box = c.size.toSize(screen);
      final g = ConveyorPathGeometry.build(c.turns, box,
          beltWidthOverride: c.requestedBeltWidth(screen))!;
      expect(g.beltWidth, closeTo(0.5 * 1080, 1e-9));
      final centerline = g.path.getBounds();
      expect(centerline.left, greaterThanOrEqualTo(-0.5));
      expect(centerline.top, greaterThanOrEqualTo(-0.5));
      expect(centerline.right, lessThanOrEqualTo(box.width + 0.5));
      expect(centerline.bottom, lessThanOrEqualTo(box.height + 0.5));
    });

    test('shrinking the box does not change an explicit belt width', () {
      // The reported bug: 2.5% stayed 2.5% only while the box was tall
      // enough, and quietly thinned once it was not.
      double painted(RelativeSize size) {
        final c = config(beltWidthRelative: 0.025, turns: turn, size: size);
        return ConveyorPathGeometry.build(c.turns, c.size.toSize(screen),
                beltWidthOverride: c.requestedBeltWidth(screen))!
            .beltWidth;
      }

      const roomy = RelativeSize(width: 0.2, height: 0.1);
      const cramped = RelativeSize(width: 0.2, height: 0.02);
      expect(painted(cramped), closeTo(0.025 * 1080, 1e-9));
      expect(painted(cramped), closeTo(painted(roomy), 1e-9));
    });
  });

  test('belt width survives a JSON round-trip', () {
    final c = config(beltWidthRelative: 0.04, turns: turn);
    final restored = ConveyorConfig.fromJson(c.toJson());
    expect(restored.beltWidthRelative, closeTo(0.04, 1e-9));
  });

  test('configs written before the setting existed still load', () {
    // Drop the key entirely, the way a config saved before this feature looks.
    final json = config(turns: turn).toJson()..remove('beltWidthRelative');
    expect(json.containsKey('beltWidthRelative'), isFalse);
    final restored = ConveyorConfig.fromJson(json);
    expect(restored.beltWidthRelative, isNull);
    // And it still renders, falling back to the box-relative thickness.
    expect(restored.requestedBeltWidth(screen), isNull);
    expect(restored.effectiveBeltThickness, closeTo(0.4, 1e-9));
  });
}
