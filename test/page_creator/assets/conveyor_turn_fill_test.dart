// A turned belt must fill its box and sit centred in it, at every box shape.
//
// Measured in painted pixels, not in geometry. The belt is rasterised and the
// bounds of what it actually put on the canvas are compared to the box — the
// same thing an operator does by eye, and the only measurement that cannot be
// argued with. `ConveyorPathGeometry.path` is no substitute: `Path.getBounds`
// is a control-point estimate that overshoots a stretched cubic by tens of
// pixels, and the band the painter fills is not the centerline's bounds
// inflated either.
//
// The reference shape is taken from a belt on the plant's freezer page: a
// U-turn built from four fillets (-30, +120, +120, -30, summing to 180) in a
// nearly square box with an explicit belt width. It is the most demanding
// shape configured anywhere, because the entry and exit runs are antiparallel:
// stretching both moves the ends in opposite directions, so the bounding box
// barely responds and the fill solve cannot converge on it at any size.
//
// Rasterised before this change, across the fifteen canvases below, that belt
// covered 30%-83% of its box's width and 67%-92% of its height — and which of
// those it landed on depended on the window:
//
//     1920x1080  fill 0.417/0.712      1600x900   fill 0.588/0.924
//     2560x1080  fill 0.305/0.760      3840x2160  fill 0.406/0.697
//
// The last pair is the telling one. Every canvas in it is 16:9, so all four
// configure the same box proportions and the same belt-to-box ratio; the belt
// should be the same belt at a different magnification. Instead 1600x900 came
// out half again as wide as 3840x2160. That is the resize the operator sees:
// not a belt that scales, a belt that reshapes.
//
// Two things were wrong, and they compound.
//
// The solve rejects this shape at every size, so every canvas took the
// *fallback* — which shrank the whole skeleton by `min(sx, sy)`. That kept the
// bends circular in name only: a uniform shrink scales the radii down with
// everything else, and the belt came out at 0.66 of its configured radius
// regardless. So the true-radius guarantee the fallback was protecting was
// already gone, and what it bought was a belt floating in its box. The
// fallback now fits each axis on its own.
//
// The fit then aimed the *centerline* at the box inset by half a belt on all
// four sides. But the band extends half a belt sideways from the centerline,
// so on the axis a run travels along it adds nothing — and a U-turn's two ends
// both run vertically. That reserved a strip of box on each side that nothing
// was ever drawn into. The fit now measures the ink and lands it on the box.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

import 'painted_bounds.dart';

/// The reference belt, as a page stores it: fractions of the canvas.
const _relW = 0.1, _relH = 0.095, _relBelt = 0.025;

List<ConveyorTurnEntry> _uTurn() => [
      ConveyorTurnEntry(position: 0.15, angle: -30.0, radius: 1.2),
      ConveyorTurnEntry(position: 0.3, angle: 120.0, radius: 1.2),
      ConveyorTurnEntry(position: 0.7, angle: 120.0, radius: 1.2),
      ConveyorTurnEntry(position: 0.75, angle: -30.0, radius: 1.0),
    ];

/// Every canvas shape worth caring about: standard desktop, ultrawide, 4:3,
/// square, portrait — and one aspect at five sizes, the case that used to
/// disagree with itself.
const _canvases = <Size>[
  Size(1920, 1080),
  Size(2560, 1080),
  Size(3440, 1440),
  Size(1280, 1024),
  Size(1024, 768),
  Size(1600, 900),
  Size(1366, 768),
  Size(1024, 1400),
  Size(800, 1280),
  Size(960, 540),
  Size(3840, 2160),
  Size(1920, 1200),
  Size(2048, 1080),
  Size(1280, 800),
  Size(1440, 1440),
];

Future<({Rect painted, Size box})> _render(
    WidgetTester tester, Size canvas) async {
  final box = Size(_relW * canvas.width, _relH * canvas.height);
  final geometry = ConveyorPathGeometry.build(_uTurn(), box,
      beltWidthOverride: _relBelt * canvas.height);
  expect(geometry, isNotNull, reason: 'no geometry for $canvas');
  final bounds = await tester.runAsync(() => paintedBounds(box, geometry));
  expect(bounds, isNotNull, reason: 'nothing painted for $canvas');
  return (painted: bounds!, box: box);
}

/// Rasteriser rounding, and nothing else.
///
/// The belt is allowed no room over the edge: the fit measures the outline
/// into the ink it places, so the border lands inside the box rather than
/// straddling it.
const _slop = 0.5;

void main() {
  group('a turned belt fills its box, centred, at any window shape', () {
    for (final canvas in _canvases) {
      testWidgets('${canvas.width.toInt()}x${canvas.height.toInt()}',
          (tester) async {
        final r = await _render(tester, canvas);

        // Fills it. Before this change the width ran as low as 0.30.
        //
        // The ceiling is a shade under 1: the fit keeps `_marginFraction` of
        // the box's short side clear on each side and reserves the outline's
        // width inside that, so the measured span runs 0.98 to 1.00 rather
        // than exactly 1. What matters is that it no longer depends on the
        // window.
        expect(r.painted.width / r.box.width, greaterThan(0.98),
            reason: 'belt does not span the box width');
        expect(r.painted.height / r.box.height, greaterThan(0.98),
            reason: 'belt does not span the box height');

        // And does not spill past it — outline included.
        expect(r.painted.left, greaterThan(-_slop));
        expect(r.painted.top, greaterThan(-_slop));
        expect(r.painted.right, lessThan(r.box.width + _slop));
        expect(r.painted.bottom, lessThan(r.box.height + _slop));

        // And sits in the middle of it.
        final offX = (r.painted.center.dx - r.box.width / 2) / r.box.width;
        final offY = (r.painted.center.dy - r.box.height / 2) / r.box.height;
        expect(offX.abs(), lessThan(0.01), reason: 'off-centre horizontally');
        expect(offY.abs(), lessThan(0.01), reason: 'off-centre vertically');
      });
    }
  });

  group('the drawn belt is a function of the box, not the window', () {
    testWidgets('the same box proportions give the same belt at any size',
        (tester) async {
      // All five are 16:9, so they configure the same box proportions and the
      // same belt-to-box ratio. Before this change the painted width ran
      // 0.406 at 3840x2160 and 0.588 at 1600x900 — the same page, resized,
      // redrawn as a different shape.
      const sameShape = [
        Size(960, 540),
        Size(1366, 768),
        Size(1600, 900),
        Size(1920, 1080),
        Size(3840, 2160),
      ];
      final fills = <double>[];
      for (final canvas in sameShape) {
        final r = await _render(tester, canvas);
        fills.add(r.painted.width / r.box.width);
      }
      for (final f in fills) {
        // Not exact: the outline is a fixed two pixels wide whatever the box,
        // so it is a larger share of a small belt than of a big one.
        // Everything the fit itself does is proportional.
        expect((f - fills.first).abs(), lessThan(0.05),
            reason: 'same box shape produced different belts: $fills');
      }
    });

    testWidgets('every aspect from ultrawide to portrait fills its box',
        (tester) async {
      // Squashing or stretching the window reshapes the box, and the belt
      // reshapes with it — but it must never be left floating.
      for (final aspect in [3.0, 2.4, 1.78, 1.33, 1.0, 0.75, 0.5]) {
        final r = await _render(tester, Size(1080 * aspect, 1080));
        expect(r.painted.width / r.box.width, greaterThan(0.98),
            reason: 'width at aspect $aspect');
        expect(r.painted.height / r.box.height, greaterThan(0.98),
            reason: 'height at aspect $aspect');
      }
    });
  });

  group('a plain straight belt is unaffected', () {
    test('no turns yields no geometry, as before', () {
      expect(ConveyorPathGeometry.build(const [], const Size(200, 100)), isNull);
    });

    testWidgets('a single gentle bend fills its box too', (tester) async {
      const box = Size(200.0, 100.0);
      final geometry = ConveyorPathGeometry.build(
        [ConveyorTurnEntry(position: 0.5, angle: 30.0, radius: 1.0)],
        box,
        beltWidthOverride: 12,
      );
      expect(geometry, isNotNull);
      final b = await tester.runAsync(() => paintedBounds(box, geometry));
      expect(b, isNotNull);
      expect(b!.width / box.width, greaterThan(0.98));
      expect((b.center.dx - box.width / 2).abs(), lessThan(1.0));
      expect((b.center.dy - box.height / 2).abs(), lessThan(1.0));
    });
  });

  group('degenerate boxes do not produce nonsense', () {
    test('a belt wider than its box is left alone to spill', () {
      // Nothing can make this fit — the band alone is wider than the box —
      // and dragging the centerline around to centre the spill only folds the
      // bend into a blob.
      final g = ConveyorPathGeometry.build(_uTurn(), const Size(40, 12),
          beltWidthOverride: 30);
      expect(g, isNotNull);
      final b = g!.path.getBounds();
      expect(b.width.isFinite && b.height.isFinite, isTrue);
      expect(b.width, greaterThan(0));
    });

    test('an extreme aspect stays finite and centred', () {
      final g = ConveyorPathGeometry.build(_uTurn(), const Size(2000, 30),
          beltWidthOverride: 8);
      expect(g, isNotNull);
      final b = g!.path.getBounds();
      expect(b.width.isFinite && b.height.isFinite, isTrue);
      expect((b.center.dy - 15).abs() / 30, lessThan(0.05));
      expect(max(b.width, b.height).isFinite, isTrue);
    });

    test('a box of a few pixels yields finite geometry', () {
      final g = ConveyorPathGeometry.build(_uTurn(), const Size(3, 2),
          beltWidthOverride: 0.5);
      expect(g, isNotNull);
      final b = g!.path.getBounds();
      expect(b.width.isFinite && b.height.isFinite, isTrue);
    });
  });
}
