// A rotated asset has to look rotated from the outside too.
//
// `LayoutRotatedBox` rotates its child in `paint` and inverts the same
// rotation in `hitTest`, so taps landed correctly and the picture was right.
// But neither of those is what `getTransformTo`, `localToGlobal` or
// `WidgetTester.getRect` consult — those walk `applyPaintTransform`, which was
// never overridden, so every measurement taken from outside a rotated asset
// came back as though the asset were not rotated at all.
//
// Three things measure assets that way: `showSidePane`'s `avoidRect` (the rect
// the plant view keeps clear of the device an operator just tapped), the page
// editor's `_assetScreenRect`, and the shape an asset publishes for the mark
// on the plant view — the last of which is what noticed
// (`hit_boundary_drift_test`).
//
// The contract here is the one that matters and the one that was broken:
// where the framework says the child is drawn is where taps on it land.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';

void main() {
  const childKey = Key('rotated-child');

  /// A 80×20 child turned by [angle] inside a box laid out to its rotated
  /// bounding rectangle.
  Future<void> pumpRotated(WidgetTester tester, double angle,
      {VoidCallback? onTap}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: LayoutRotatedBox(
            angle: angle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: const SizedBox(
                key: childKey,
                width: 80,
                height: 20,
              ),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('a quarter turn is reported to whoever measures the child',
      (tester) async {
    await pumpRotated(tester, math.pi / 2);

    final box = tester.getRect(find.byType(LayoutRotatedBox));
    final child = tester.getRect(find.byKey(childKey));

    // The box lays out to the rotated bounds — 80×20 turned upright — and the
    // child, measured through the paint transform, fills it.
    expect(box.width, closeTo(20, 0.01));
    expect(box.height, closeTo(80, 0.01));
    expect(child.width, closeTo(20, 0.01),
        reason: 'measured unrotated, this came back 80 wide');
    expect(child.height, closeTo(80, 0.01));
    expect(child.center.dx, closeTo(box.center.dx, 0.01));
    expect(child.center.dy, closeTo(box.center.dy, 0.01));
  });

  testWidgets('where the child is measured is where taps on it land',
      (tester) async {
    var taps = 0;
    await pumpRotated(tester, math.pi / 2, onTap: () => taps++);

    final child = tester.getRect(find.byKey(childKey));
    // Well inside the long axis of the turned child: 30px above its centre is
    // on it, and 15px beyond the end is not.
    await tester.tapAt(child.center + const Offset(0, 30));
    await tester.pump();
    expect(taps, 1, reason: 'the measured rect is where the child really is');

    await tester.tapAt(child.center + const Offset(0, 55));
    await tester.pump();
    expect(taps, 1, reason: 'past the end of the child, nothing to hit');

    // And across the short axis, which is where an unreported rotation showed
    // up as a tap that missed.
    await tester.tapAt(child.center + const Offset(8, 0));
    await tester.pump();
    expect(taps, 2);
    await tester.tapAt(child.center + const Offset(18, 0));
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('an unrotated box measures as it always did', (tester) async {
    await pumpRotated(tester, 0);

    final child = tester.getRect(find.byKey(childKey));
    expect(child.width, closeTo(80, 0.01));
    expect(child.height, closeTo(20, 0.01));
    expect(child, tester.getRect(find.byType(LayoutRotatedBox)));
  });

  testWidgets('an odd angle round-trips through the reported transform',
      (tester) async {
    await pumpRotated(tester, 35 * math.pi / 180);

    final box = tester.renderObject<RenderBox>(find.byType(LayoutRotatedBox));
    final child = tester.renderObject<RenderBox>(find.byKey(childKey));

    // A point in the child's own coordinates, carried out to the box's and
    // back, has to come home — and the box's own hit test has to agree that
    // the carried point is on the child.
    const inChild = Offset(70, 15);
    final inBox = MatrixUtils.transformPoint(
        child.getTransformTo(box), inChild);
    final home = MatrixUtils.transformPoint(
        Matrix4.tryInvert(child.getTransformTo(box))!, inBox);
    expect((home - inChild).distance, lessThan(0.01));

    final result = BoxHitTestResult();
    expect(box.hitTest(result, position: inBox), isTrue,
        reason: 'the transform and the hit test describe the same rotation');
  });
}
