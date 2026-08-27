/// Asks a widget where it really takes taps.
///
/// The plant view does not do this — assets publish their tappable shape and
/// the mark draws that (see `hit_boundary.dart`). This is how the published
/// shape is held to account: sweep the widget's real hit test point by point
/// and compare. It costs thousands of hit tests, which CI has and an operator
/// opening a pane does not.
library;

import 'package:flutter/rendering.dart' show BoxHitTestResult;
import 'package:flutter/widgets.dart';

/// Whether a pointer at [point] reaches anything inside [box].
///
/// Deliberately not `box.hitTest(...)`'s return value:
/// [HitTestBehavior.translucent] returns *false* while still putting itself
/// on the result path, and it will still get the tap. Several assets are
/// built that way, so the answer that matches what an operator experiences is
/// whether anything landed on the path at all.
bool pointerReaches(RenderBox box, Offset point) {
  final result = BoxHitTestResult();
  box.hitTest(result, position: point);
  return result.path.isNotEmpty;
}

/// The box whose hit test decides whether a tap lands on an asset.
///
/// `AssetStack` puts a hit-permissive box at the top of every asset's visual
/// subtree — it forwards positions the asset's own geometry then accepts or
/// rejects, including positions outside the box, which is how a rotated asset
/// stays tappable where it is painted. Everything below it is the asset
/// deciding for itself, so it is the right thing to interrogate.
RenderBox? assetHitBox(Element assetSubtree) {
  RenderBox? found;
  void visit(Element element) {
    if (found != null) return;
    final ro = element.renderObject;
    if (ro is RenderBox &&
        ro.hasSize &&
        ro.runtimeType.toString().contains('HitPermissive')) {
      found = ro;
      return;
    }
    element.visitChildElements(visit);
  }

  assetSubtree.visitChildElements(visit);
  return found;
}

/// Every sampled point where [box] does and does not answer a pointer.
///
/// Sampled a margin beyond the box as well: an asset may paint — and take
/// taps — outside its own rect, which is exactly the kind of thing worth
/// knowing about.
({List<Offset> hits, List<Offset> misses}) sweepHitTest(
  RenderBox box, {
  double step = 3,
  double margin = 8,
}) {
  final hits = <Offset>[];
  final misses = <Offset>[];
  for (var y = -margin; y <= box.size.height + margin; y += step) {
    for (var x = -margin; x <= box.size.width + margin; x += step) {
      final point = Offset(x, y);
      (pointerReaches(box, point) ? hits : misses).add(point);
    }
  }
  return (hits: hits, misses: misses);
}
