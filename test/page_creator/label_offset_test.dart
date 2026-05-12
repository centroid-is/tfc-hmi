// Regression tests for the page_view `labelOffset` helper.
//
// Bug: `TextPos.inside` fell through the switch's default case and landed
// on the right-side positioning logic, so buttons (and any other asset)
// configured with `textPos: TextPos.inside` rendered their label OUTSIDE
// the asset on the right instead of CENTRED INSIDE it.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/pages/page_view.dart' show labelOffset;
import 'package:tfc/page_creator/assets/common.dart' show TextPos;

void main() {
  // Asset centred at (100, 100), 40 wide x 20 tall (half-extents 20 x 10).
  const center = Offset(100, 100);
  const assetSize = Size(40, 20);
  // Label is 12 wide x 8 tall.
  const textSize = Size(12, 8);

  group('labelOffset — TextPos.inside centres the label on the asset', () {
    test('inside-positioned label is centred on the asset', () {
      final off = labelOffset(center, assetSize, textSize, TextPos.inside);
      // Centre minus half the text size → label top-left = (94, 96).
      expect(off, const Offset(94, 96),
          reason:
              'TextPos.inside must centre the label on the asset; previously it fell through to the right-side default and rendered outside the asset.');
    });

    test('inside-positioned label sits inside the asset rect', () {
      final off = labelOffset(center, assetSize, textSize, TextPos.inside);
      final labelRect = off & textSize;
      final assetRect = Rect.fromCenter(
        center: center,
        width: assetSize.width,
        height: assetSize.height,
      );
      expect(assetRect.contains(labelRect.topLeft), isTrue);
      expect(assetRect.contains(labelRect.bottomRight), isTrue);
    });
  });

  group('labelOffset — sanity checks for the other positions', () {
    test('right-positioned label sits to the right of the asset', () {
      final off = labelOffset(center, assetSize, textSize, TextPos.right);
      // Right edge is at x=120; with spacing 8, label left = 128.
      expect(off.dx, greaterThan(120));
    });

    test('left-positioned label sits to the left of the asset', () {
      final off = labelOffset(center, assetSize, textSize, TextPos.left);
      // Left edge is at x=80; with spacing 8 and text width 12, label x = 60.
      expect(off.dx + textSize.width, lessThan(80));
    });

    test('above-positioned label sits above the asset', () {
      final off = labelOffset(center, assetSize, textSize, TextPos.above);
      // Top edge is at y=90; label bottom must be above that.
      expect(off.dy + textSize.height, lessThanOrEqualTo(90));
    });

    test('below-positioned label sits below the asset', () {
      final off = labelOffset(center, assetSize, textSize, TextPos.below);
      // Bottom edge is at y=110; label top must be below that.
      expect(off.dy, greaterThanOrEqualTo(110));
    });
  });
}
