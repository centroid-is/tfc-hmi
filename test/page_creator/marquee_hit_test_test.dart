// Regression tests for the page-editor marquee gate.
//
// The gate decides "did the pointer-down hit an asset or empty canvas?"
// before starting a drag-selection rubber band. Pre-fix, the gate used an
// unrotated AABB test, which fails in both directions for any rotated
// asset: clicks on the rotated visual outside the AABB wrongly started a
// marquee; clicks on empty space inside the AABB wrongly refused to.
//
// The fix applies the inverse rotation around the asset centre and tests
// the unrotated half-extents.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/pages/page_editor.dart'
    show marqueeHitTestRotatedAsset, projectDragDeltaToCanvas;

void main() {
  // Asset centred at (100, 100), 40 wide x 10 tall (half-extents 20 x 5).
  const cx = 100.0;
  const cy = 100.0;
  const halfW = 20.0;
  const halfH = 5.0;

  group('marqueeHitTestRotatedAsset — unrotated baseline', () {
    test('centre of asset is a hit', () {
      expect(
        marqueeHitTestRotatedAsset(
          pointer: const Offset(100, 100),
          cx: cx,
          cy: cy,
          halfW: halfW,
          halfH: halfH,
          angleDegrees: 0,
        ),
        isTrue,
      );
    });

    test('far outside is a miss', () {
      expect(
        marqueeHitTestRotatedAsset(
          pointer: const Offset(50, 50),
          cx: cx,
          cy: cy,
          halfW: halfW,
          halfH: halfH,
          angleDegrees: 0,
        ),
        isFalse,
      );
    });
  });

  group('marqueeHitTestRotatedAsset — rotated 90 degrees', () {
    // After 90° rotation around the centre, the visual occupies
    // x in [95, 105], y in [80, 120].

    test('point inside rotated visual but outside unrotated AABB is a hit', () {
      // (100, 85) is INSIDE the rotated visual (x=100 is within [95,105],
      // y=85 is within [80,120]) but OUTSIDE the unrotated AABB
      // (which occupies x in [80,120], y in [95,105]).
      expect(
        marqueeHitTestRotatedAsset(
          pointer: const Offset(100, 85),
          cx: cx,
          cy: cy,
          halfW: halfW,
          halfH: halfH,
          angleDegrees: 90,
        ),
        isTrue,
        reason:
            'Clicks on the rotated visual must register as a hit so the asset drag flow starts (and the marquee does not).',
      );
    });

    test('point outside rotated visual but inside unrotated AABB is a miss', () {
      // (85, 100) is INSIDE the unrotated AABB (x=85 within [80,120],
      // y=100 within [95,105]) but OUTSIDE the rotated visual
      // (which requires x within [95,105]).
      expect(
        marqueeHitTestRotatedAsset(
          pointer: const Offset(85, 100),
          cx: cx,
          cy: cy,
          halfW: halfW,
          halfH: halfH,
          angleDegrees: 90,
        ),
        isFalse,
        reason:
            'Clicks on empty canvas inside the pre-rotation rect must NOT register as an asset hit; the marquee must be allowed to start.',
      );
    });

    test('centre is still a hit at 90 degrees', () {
      expect(
        marqueeHitTestRotatedAsset(
          pointer: const Offset(100, 100),
          cx: cx,
          cy: cy,
          halfW: halfW,
          halfH: halfH,
          angleDegrees: 90,
        ),
        isTrue,
      );
    });
  });

  group('marqueeHitTestRotatedAsset — rotated 45 degrees', () {
    test('point on the rotated diagonal edge is a hit', () {
      // 45° rotation maps the (halfW, 0) corner to roughly
      // (halfW/√2, halfW/√2) ≈ (14.14, 14.14).
      expect(
        marqueeHitTestRotatedAsset(
          pointer: const Offset(110, 110),
          cx: cx,
          cy: cy,
          halfW: halfW,
          halfH: halfH,
          angleDegrees: 45,
        ),
        isTrue,
        reason: 'A point along the rotated long axis should be a hit',
      );
    });

    test('point on what was the unrotated corner is now a miss', () {
      // The unrotated (cx+halfW, cy+halfH) = (120, 105) corner.
      // After undoing 45°, this lands at (~13.43, ~-10.6) which exceeds
      // the half-extents.
      expect(
        marqueeHitTestRotatedAsset(
          pointer: const Offset(120, 105),
          cx: cx,
          cy: cy,
          halfW: halfW,
          halfH: halfH,
          angleDegrees: 45,
        ),
        isFalse,
      );
    });
  });

  group('projectDragDeltaToCanvas — drag direction matches screen at all angles',
      () {
    // Bug: dragging a rotated sensor LEFT/RIGHT made it move UP/DOWN because
    // `DragUpdateDetails.delta` arrived in the rotated GestureDetector's
    // local frame. Fix: project the delta back into the canvas frame by
    // applying +angle.

    test('angle 0: identity', () {
      final out = projectDragDeltaToCanvas(
        delta: const Offset(5, 3),
        angleDegrees: 0,
      );
      expect(out.dx, closeTo(5, 1e-9));
      expect(out.dy, closeTo(3, 1e-9));
    });

    test('angle 90: a local-right drag is a canvas-down drag', () {
      // At angle 90 the asset has rotated CW from the operator\'s POV. The
      // local right axis points down on screen. So when the operator drags
      // RIGHT on screen, in the rotated GestureDetector\'s local frame
      // that arrives as `delta = (0, +X)` (local-DOWN, because Flutter\'s
      // +y is screen-down and the rotation maps screen-right → local-down...
      // actually it depends on rotation direction. We test the inverse:
      // a local +x delta (which a 90°-rotated GestureDetector receives
      // when the screen pointer moves DOWN) projects to canvas +y here.
      final out = projectDragDeltaToCanvas(
        delta: const Offset(10, 0),
        angleDegrees: 90,
      );
      // cos90=0, sin90=1: (10*0 - 0*1, 10*1 + 0*0) = (0, 10)
      expect(out.dx, closeTo(0, 1e-9));
      expect(out.dy, closeTo(10, 1e-9));
    });

    test('angle 90: a local-down drag is a canvas-left drag', () {
      final out = projectDragDeltaToCanvas(
        delta: const Offset(0, 10),
        angleDegrees: 90,
      );
      // cos90=0, sin90=1: (0*0 - 10*1, 0*1 + 10*0) = (-10, 0)
      expect(out.dx, closeTo(-10, 1e-9));
      expect(out.dy, closeTo(0, 1e-9));
    });

    test('angle 180: inverts both axes', () {
      final out = projectDragDeltaToCanvas(
        delta: const Offset(5, 3),
        angleDegrees: 180,
      );
      expect(out.dx, closeTo(-5, 1e-9));
      expect(out.dy, closeTo(-3, 1e-9));
    });

    test('angle 90 round trip: project then inverse-project recovers delta',
        () {
      const original = Offset(7, -4);
      final canvas =
          projectDragDeltaToCanvas(delta: original, angleDegrees: 90);
      final back =
          projectDragDeltaToCanvas(delta: canvas, angleDegrees: -90);
      expect(back.dx, closeTo(original.dx, 1e-9));
      expect(back.dy, closeTo(original.dy, 1e-9));
    });
  });
}
