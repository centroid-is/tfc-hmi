import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

/// A turned belt must be a function of its box's *shape*, not of its size.
///
/// The plant view is an aspect-locked canvas: opening a docked side pane over
/// the device an operator tapped re-fits the whole page beside the pane, which
/// hands every asset a box of the same shape at a smaller scale (0.68x on a
/// 1280x800 window). Every other asset simply gets smaller. A conveyor with
/// turns used to get *reshaped*: the fit's accept tests are relative — belt
/// widths, proportions, self-overlap — but two of the lengths they were
/// measured against were not (a 2px box margin, a 0.5px fill tolerance), so
/// `inner` came out a slightly different shape at a different scale. A belt
/// sitting near any accept boundary flipped verdict on the rescale and
/// dropped from the box-filling solve to the uniform-fit fallback, i.e. from
/// spanning its box to a fraction of it — the "conveyor squeezes when the
/// side pane opens" the operator sees.
void main() {
  /// What the belt looks like in [box], in units of the box itself: every
  /// number here is dimensionless, so a belt that merely got smaller with its
  /// box scores identically at every scale.
  ({double beltWidth, double length, double inkWidth, double inkHeight})
      shapeIn(List<ConveyorTurnEntry> turns, Size box,
          {double thickness = 0.35, double? beltWidthRelative}) {
    final geometry = ConveyorPathGeometry.build(
      turns,
      box,
      thicknessFactor: thickness,
      beltWidthOverride:
          beltWidthRelative == null ? null : beltWidthRelative * box.height,
    );
    expect(geometry, isNotNull, reason: 'no geometry built for $box');
    final ink = geometry!
            .bandOutline(0, 1, width: geometry.beltWidth, radius: 0)
            ?.getBounds() ??
        geometry.path.getBounds();
    return (
      beltWidth: geometry.beltWidth / box.height,
      length: geometry.length / box.width,
      inkWidth: ink.width / box.width,
      inkHeight: ink.height / box.height,
    );
  }

  /// Every scale the page re-fit can land a conveyor on: the 0.68x of a
  /// pane opening on a 1280x800 window, and the range around it that other
  /// window shapes and pane widths produce.
  const scales = [1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.684, 0.6, 0.5];

  void expectScaleInvariant(
    String what,
    List<ConveyorTurnEntry> Function() turns,
    Size box, {
    double thickness = 0.35,
    double? beltWidthRelative,
  }) {
    final reference = shapeIn(turns(), box,
        thickness: thickness, beltWidthRelative: beltWidthRelative);
    for (final scale in scales) {
      final scaled = shapeIn(
          turns(), Size(box.width * scale, box.height * scale),
          thickness: thickness, beltWidthRelative: beltWidthRelative);
      // The belt is outlined with a border of a fixed pixel width, and that
      // outline is reserved on both sides of the box before the belt is
      // fitted into what is left. Those four pixels are a bigger share of a
      // small box than of a big one, so the belt inside comes out a little
      // smaller as the box shrinks — and, being taken out of the inner box
      // rather than the box, a little more than four pixels' worth. Eight
      // pixels against the short side bounds it — and ten once the belt is
      // fat enough that what is left of the box to fit it into is small.
      // That is 11% on the smallest box here and 4% on the biggest, against
      // a reshape, which is what this test is for and which moves these
      // numbers by tens of percent.
      final allowance = 10.0 / (box.shortestSide * scale);
      void same(String metric, double a, double b) {
        expect((a - b).abs(), lessThan(a.abs() * allowance + 1e-6),
            reason: '$what: $metric changed at ${scale}x scale — '
                'the belt was reshaped by the page re-fit, not just resized '
                '($a -> $b)');
      }

      same('belt width', reference.beltWidth, scaled.beltWidth);
      same('belt length', reference.length, scaled.length);
      same('ink width', reference.inkWidth, scaled.inkWidth);
      same('ink height', reference.inkHeight, scaled.inkHeight);
    }
  }

  test('a serpentine keeps its shape when the page re-fits', () {
    // Two U-turns in one belt. The runs of this one pass close enough to
    // each other to sit right at the self-overlap boundary — the case that
    // flipped verdict on the re-fit and collapsed the belt to a sixth of its
    // box width.
    expectScaleInvariant(
      'serpentine, two U-turns',
      () => [
        for (var i = 0; i < 4; i++)
          ConveyorTurnEntry(
            position: (i + 1) / 5,
            angle: (i ~/ 2) % 2 == 0 ? 90 : -90,
            radius: 0.3,
          )
      ],
      const Size(544, 270),
    );
  });

  test('a single U-turn keeps its shape when the page re-fits', () {
    expectScaleInvariant(
      'single U-turn',
      () => [
        ConveyorTurnEntry(position: 0.3, angle: 90, radius: 0.9),
        ConveyorTurnEntry(position: 0.5, angle: 90, radius: 0.9),
      ],
      const Size(544, 270),
    );
  });

  test('an L keeps its shape when the page re-fits', () {
    expectScaleInvariant(
      'single 90 degree bend',
      () => [ConveyorTurnEntry(position: 0.5, angle: 90, radius: 1.8)],
      const Size(544, 270),
    );
  });

  test('an explicit belt width keeps its shape when the page re-fits', () {
    // The canvas-relative belt width travels with the canvas, so this must
    // hold for it too.
    expectScaleInvariant(
      'S-curve with an explicit belt width',
      () => [
        ConveyorTurnEntry(position: 0.25, angle: 60, radius: 1.5),
        ConveyorTurnEntry(position: 0.6, angle: -60, radius: 1.5),
      ],
      const Size(400, 300),
      beltWidthRelative: 0.12,
    );
  });

  test('every turn count and box shape survives the re-fit', () {
    // The sweep that found the case above: whatever an operator has drawn,
    // opening a pane over it must not redraw it.
    for (final turnCount in [1, 2, 4, 6]) {
      for (var t = 1; t <= 9; t++) {
        for (var r = 1; r <= 8; r++) {
          for (final aspect in [1.0, 1.6, 0.7]) {
            final radius = r * 0.3;
            expectScaleInvariant(
              'turns=$turnCount thickness=${t * 0.05 + 0.05} radius=$radius '
              'aspect=$aspect',
              () => [
                for (var i = 0; i < turnCount; i++)
                  ConveyorTurnEntry(
                    position: (i + 1) / (turnCount + 1),
                    angle: (i ~/ 2) % 2 == 0 ? 90 : -90,
                    radius: radius,
                  )
              ],
              Size(270 * aspect, 270),
              thickness: t * 0.05 + 0.05,
            );
          }
        }
      }
    }
  });
}
