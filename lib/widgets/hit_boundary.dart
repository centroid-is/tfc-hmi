/// The outline of what actually takes a tap.
///
/// Every other way of drawing a boundary around an asset re-derives it: the
/// editor's selection border is the asset's `w×h` box turned by its angle,
/// the AI proposal outline is the same box dashed. That is a second opinion
/// about the asset's shape, and second opinions drift — a conveyor turn is an
/// arc across a box it fills maybe a third of, a straight belt with an
/// explicit width is a band down the middle, and a rectangle around either
/// claims far more than the operator can actually hit
/// (`ConveyorPainter.hitTest` takes only the painted belt).
///
/// There are two ways to get the real shape here, and they are for different
/// jobs.
///
/// **At runtime, the asset says so.** An asset whose hit test is a path
/// publishes that same path — the object its `hitTest` consults, not a copy
/// of it — with [AssetHitShape]. The plant view flattens it, stands it off
/// and draws it: exact, analytic, and free. An asset that publishes nothing
/// is a box and gets one, which is the truth for most of them.
///
/// **In tests, the asset is interrogated.** [HitMask.probe] samples a hit
/// test over a grid and [hitBoundarySegments] traces the line between the
/// points that answered and the points that did not, so a declared shape can
/// be held against what the widget really does. That is the drift alarm: it
/// is what stops a published path from quietly becoming a third opinion, and
/// it costs ten thousand hit tests, which is why it belongs in CI and not
/// under an operator's finger.
///
/// The sampling is pure given a predicate and the tracing is pure given a
/// mask, so both are tested against shapes with known outlines rather than
/// against a live widget tree.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A grid of yes/no answers over [area], one per cell centre.
@immutable
class HitMask {
  /// The rectangle that was sampled, in the probed box's own coordinates.
  final Rect area;

  /// Distance between neighbouring samples.
  final double cell;

  final int cols;
  final int rows;

  /// Row-major, one byte per sample. A [Uint8List] rather than `List<bool>`
  /// because a full-page conveyor is a few thousand samples and this is
  /// allocated on every probe.
  final Uint8List _hits;

  const HitMask._({
    required this.area,
    required this.cell,
    required this.cols,
    required this.rows,
    required Uint8List hits,
  }) : _hits = hits;

  /// Whether the sample at [col], [row] was a hit. Out-of-range is a miss,
  /// which is what makes the border of the grid a clean edge to trace against.
  bool at(int col, int row) {
    if (col < 0 || row < 0 || col >= cols || row >= rows) return false;
    return _hits[row * cols + col] != 0;
  }

  /// Where the sample at [col], [row] was taken.
  Offset centreOf(int col, int row) => Offset(
        area.left + (col + 0.5) * cell,
        area.top + (row + 0.5) * cell,
      );

  bool get isEmpty {
    for (final hit in _hits) {
      if (hit != 0) return false;
    }
    return true;
  }

  /// Sample spacing for a box of [size].
  ///
  /// Fine enough that a sensor dot is not reduced to four samples, coarse
  /// enough that a belt running the width of the page does not cost tens of
  /// thousands of hit tests. The budget is a total, so the spacing follows
  /// the asset's area rather than its longest side.
  static double cellFor(Size size, {int budget = 6000}) {
    final area = math.max(size.width * size.height, 1);
    return (math.sqrt(area / budget)).clamp(2.0, 12.0);
  }

  /// Runs [hit] over a grid covering [area].
  ///
  /// [area] is inflated by two cells first, so a hit region that reaches the
  /// edge of the area still has misses beyond it to be traced against —
  /// otherwise the outline is left open along that edge.
  static HitMask probe({
    required Rect area,
    required double cell,
    required bool Function(Offset point) hit,
  }) {
    final padded = area.inflate(cell * 2);
    final cols = math.max(1, (padded.width / cell).ceil());
    final rows = math.max(1, (padded.height / cell).ceil());
    final hits = Uint8List(cols * rows);
    final mask = HitMask._(
      area: padded,
      cell: cell,
      cols: cols,
      rows: rows,
      hits: hits,
    );
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if (hit(mask.centreOf(col, row))) hits[row * cols + col] = 1;
      }
    }
    return mask;
  }

}

/// The line between the samples that hit and the samples that did not.
///
/// Marching squares over the sample grid. Each segment runs between the two
/// cell edges the boundary crosses, and where it crosses them is found by
/// [refine] rather than assumed to be halfway: a grid answers only to within
/// half a cell, so an edge halfway between two samples and an edge just past
/// one of them come out in the same place. That error is not even — it
/// depends on where the shape happens to fall against the grid — so a belt
/// centred in its box was traced 2px clear of it above and 3px clear below.
/// Bisecting the same predicate the samples came from puts each crossing
/// within a twentieth of a pixel of the real edge, and the outline sits
/// evenly around what it is tracing.
///
/// Without [refine] the crossings fall back to the midpoints, which is the
/// grid's own answer — enough to see a shape, not enough to draw around one.
///
/// The segments come back loose rather than assembled: consecutive segments
/// share endpoints exactly (a shared cell edge bisects to the same point from
/// either side), so [traceContours] can chain them by identity.
///
/// A shape with a hole gives the outer and the inner boundary both, which is
/// the honest answer: both are edges of what takes a tap.
List<(Offset, Offset)> hitBoundarySegments(
  HitMask mask, {
  bool Function(Offset point)? refine,
}) {
  final segments = <(Offset, Offset)>[];

  /// Where the boundary crosses the cell edge between two neighbouring
  /// samples, exactly one of which is a hit.
  Offset crossing(int c1, int r1, int c2, int r2) {
    final p1 = mask.centreOf(c1, r1);
    final p2 = mask.centreOf(c2, r2);
    final midpoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    if (refine == null) return midpoint;
    var inside = mask.at(c1, r1) ? p1 : p2;
    var outside = mask.at(c1, r1) ? p2 : p1;
    // Six halvings of one cell: past a twentieth of a pixel at the finest
    // spacing this samples at, and deterministic, so the two squares either
    // side of this edge agree on the point to the bit.
    for (var i = 0; i < 6; i++) {
      final mid = Offset(
        (inside.dx + outside.dx) / 2,
        (inside.dy + outside.dy) / 2,
      );
      if (refine(mid)) {
        inside = mid;
      } else {
        outside = mid;
      }
    }
    return Offset(
      (inside.dx + outside.dx) / 2,
      (inside.dy + outside.dy) / 2,
    );
  }

  // One square per group of four neighbouring samples.
  for (var row = -1; row < mask.rows; row++) {
    for (var col = -1; col < mask.cols; col++) {
      final tl = mask.at(col, row);
      final tr = mask.at(col + 1, row);
      final br = mask.at(col + 1, row + 1);
      final bl = mask.at(col, row + 1);

      final code = (tl ? 1 : 0) | (tr ? 2 : 0) | (br ? 4 : 0) | (bl ? 8 : 0);
      if (code == 0 || code == 15) continue;

      // Crossings on the four edges of the square, each found only if the
      // case at hand actually crosses that edge.
      late final top = crossing(col, row, col + 1, row);
      late final right = crossing(col + 1, row, col + 1, row + 1);
      late final bottom = crossing(col, row + 1, col + 1, row + 1);
      late final left = crossing(col, row, col, row + 1);

      switch (code) {
        case 1:
        case 14:
          segments.add((left, top));
        case 2:
        case 13:
          segments.add((top, right));
        case 3:
        case 12:
          segments.add((left, right));
        case 4:
        case 11:
          segments.add((right, bottom));
        case 6:
        case 9:
          segments.add((top, bottom));
        case 7:
        case 8:
          segments.add((left, bottom));
        // The two saddles: opposite corners hit, the other two not. Either
        // reading is defensible; joining each hit corner to its own pair of
        // edges keeps the two regions separate, which is the reading that
        // does not invent a bridge across a gap the operator cannot tap.
        case 5:
          segments.add((left, top));
          segments.add((right, bottom));
        case 10:
          segments.add((top, right));
          segments.add((left, bottom));
      }
    }
  }
  return segments;
}

/// Chains loose [segments] into rings.
///
/// Marching squares emits each crossing on its own, and consecutive
/// crossings share endpoints exactly (both are midpoints of the same cell
/// edge), so the chaining is a walk over shared endpoints rather than a
/// nearest-neighbour search. What comes back is one closed ring per edge of
/// the region — one for a belt, two for a shape with a hole.
///
/// Rings are what [smoothContour] needs: a ring can be smoothed, a bag of
/// segments cannot.
List<List<Offset>> traceContours(List<(Offset, Offset)> segments) {
  if (segments.isEmpty) return const [];

  // Endpoints are exact copies rather than near-misses, but they are computed
  // by arithmetic, so they are keyed on a rounded value rather than on
  // equality of doubles.
  String key(Offset p) =>
      '${(p.dx * 1000).round()}:${(p.dy * 1000).round()}';

  final ends = <String, List<int>>{};
  for (var i = 0; i < segments.length; i++) {
    ends.putIfAbsent(key(segments[i].$1), () => []).add(i);
    ends.putIfAbsent(key(segments[i].$2), () => []).add(i);
  }

  final used = List<bool>.filled(segments.length, false);
  final contours = <List<Offset>>[];

  for (var start = 0; start < segments.length; start++) {
    if (used[start]) continue;
    used[start] = true;
    final ring = <Offset>[segments[start].$1, segments[start].$2];
    var head = segments[start].$2;

    while (true) {
      final candidates = ends[key(head)];
      if (candidates == null) break;
      var advanced = false;
      for (final i in candidates) {
        if (used[i]) continue;
        final (from, to) = segments[i];
        // A junction — the saddle cases put four segment ends on one point —
        // is resolved by taking whichever unused segment is found first. Both
        // readings trace a real edge; neither leaves one out.
        head = key(from) == key(head) ? to : from;
        used[i] = true;
        ring.add(head);
        advanced = true;
        break;
      }
      if (!advanced) break;
      if (key(head) == key(ring.first)) {
        // Closed: the ring already ends where it began, so drop the repeat.
        ring.removeLast();
        break;
      }
    }
    // Two points are a single crossing with nothing either side of it —
    // sampling noise, not an edge of anything.
    if (ring.length > 2) contours.add(ring);
  }
  return contours;
}

/// Chaikin corner cutting, run [iterations] times over a closed ring.
///
/// The traced ring steps from sample to sample, so a diagonal edge comes out
/// as a staircase — true to the grid, and wrong about the belt, which is
/// straight. Cutting the corners converges on the line the samples are
/// standing along. Two passes is enough to read as drawn rather than
/// sampled; more only costs points.
///
/// The ring moves by at most a quarter of a cell doing this, which is well
/// inside what the sampling already rounded off.
List<Offset> smoothContour(List<Offset> ring, {int iterations = 2}) {
  if (ring.length < 4 || iterations <= 0) return ring;
  var current = ring;
  for (var pass = 0; pass < iterations; pass++) {
    final next = <Offset>[];
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = current[(i + 1) % current.length];
      next.add(Offset(
        a.dx * 0.75 + b.dx * 0.25,
        a.dy * 0.75 + b.dy * 0.25,
      ));
      next.add(Offset(
        a.dx * 0.25 + b.dx * 0.75,
        a.dy * 0.25 + b.dy * 0.75,
      ));
    }
    current = next;
  }
  return current;
}

/// Moves every point of [ring] [distance] away from the region it encloses.
///
/// The standoff is applied here, to the finished ring, rather than by growing
/// the sample grid before tracing: a grid can only grow in whole cells, so
/// the clearance came out as whatever the spacing happened to be — 3px on one
/// asset, 12px on a bigger one, and uneven around a single shape. Offsetting
/// along the local normal gives the same clearance everywhere.
///
/// Which way is out is settled by asking [inside] rather than by the ring's
/// winding, so the boundary of a hole moves into the hole — also away from
/// the material, which is what the eye expects.
List<Offset> offsetContour(
  List<Offset> ring,
  double distance, {
  required bool Function(Offset point) inside,
}) {
  if (ring.length < 3 || distance == 0) return ring;

  final normals = <Offset>[
    for (var i = 0; i < ring.length; i++)
      () {
        final before = ring[(i - 1 + ring.length) % ring.length];
        final after = ring[(i + 1) % ring.length];
        final tangent = after - before;
        final length = tangent.distance;
        return length == 0
            ? Offset.zero
            : Offset(tangent.dy / length, -tangent.dx / length);
      }(),
  ];

  // One probe settles the whole ring: the normals are consistent along it, so
  // the side that is outside at one point is outside at all of them.
  var sign = 1.0;
  for (var i = 0; i < ring.length; i++) {
    final normal = normals[i];
    if (normal == Offset.zero) continue;
    final ahead = inside(ring[i] + normal * 1.5);
    final behind = inside(ring[i] - normal * 1.5);
    if (ahead == behind) continue; // Grazing the edge here; try another point.
    sign = ahead ? -1.0 : 1.0;
    break;
  }

  return [
    for (var i = 0; i < ring.length; i++) ring[i] + normals[i] * distance * sign,
  ];
}

/// The rings of [mask]: traced, smoothed, and stood off — the whole pipeline.
///
/// [refine] is the predicate the mask was sampled with. Given it, crossings
/// are bisected onto the real edge instead of being left at the grid's
/// resolution, and the standoff can be measured from that edge. Without it
/// the rings are the grid's own answer and [standoff] is ignored, since there
/// is nothing to ask which way is out.
List<List<Offset>> hitBoundaryContours(
  HitMask mask, {
  bool Function(Offset point)? refine,
  double standoff = 0,
  int smoothing = 2,
}) =>
    [
      for (final ring in traceContours(hitBoundarySegments(mask, refine: refine)))
        if (refine == null || standoff == 0)
          smoothContour(ring, iterations: smoothing)
        else
          offsetContour(
            smoothContour(ring, iterations: smoothing),
            standoff,
            inside: refine,
          ),
    ];

/// Publishes the shape this subtree takes taps on.
///
/// Wrap the widget whose box the shape is measured in — the `CustomPaint`
/// whose painter hit-tests against it — and hand over **the path the hit test
/// itself consults**. Handing over a second path drawn to look right would
/// put the mark back where it started: a picture of where an asset is
/// supposed to be tappable, which is not evidence of anything and is exactly
/// what drifts.
///
/// Assets that take taps on their whole face publish nothing. A box is the
/// truth for them, and the plant view draws one.
///
/// Not an [InheritedWidget]: nothing below this needs to read it. The plant
/// view finds it by walking down into the asset, the same way it finds the
/// box to measure, so the shape can be published from wherever the geometry
/// already exists rather than plumbed up to the asset's config.
class AssetHitShape extends StatelessWidget {
  /// The tappable shape, in the coordinates of [child]'s render box.
  final Path path;

  final Widget child;

  const AssetHitShape({super.key, required this.path, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Walks [path] into rings of points, one per closed subpath.
///
/// [step] is the spacing along the path; the curve is already smooth, so this
/// only has to be fine enough that a straight line between neighbours is
/// indistinguishable from the arc it replaces.
List<List<Offset>> flattenPath(Path path, {double step = 2}) {
  final rings = <List<Offset>>[];
  for (final metric in path.computeMetrics()) {
    final ring = <Offset>[];
    for (var distance = 0.0; distance < metric.length; distance += step) {
      final tangent = metric.getTangentForOffset(distance);
      if (tangent != null) ring.add(tangent.position);
    }
    if (ring.length > 2) rings.add(ring);
  }
  return rings;
}

/// Draws [contours] as a quiet ring: a blurred stroke with a fine line on it.
///
/// Deliberately two strokes rather than a [BoxDecoration] with a `boxShadow`
/// — that shadow is a filled, blurred copy of the shape, and with nothing
/// filling the shape on top of it the asset ends up under a grey wash. The
/// blur here is on the stroke, so the middle is left alone: an asset's colour
/// is its equipment state and has to come through untouched.
class HitBoundaryPainter extends CustomPainter {
  /// The rings, already in this painter's coordinates.
  final List<List<Offset>> contours;

  /// The ink to draw them in. Alpha comes from here, not from the caller.
  final Color color;

  const HitBoundaryPainter({required this.contours, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (contours.isEmpty) return;
    final path = Path();
    for (final ring in contours) {
      if (ring.length < 2) continue;
      path.moveTo(ring.first.dx, ring.first.dy);
      for (final point in ring.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(HitBoundaryPainter oldDelegate) =>
      oldDelegate.color != color ||
      !identical(oldDelegate.contours, contours);
}

/// Whether a pointer at [point] reaches anything inside [box].
///
/// The predicate [HitMask.probe] is given for a live widget, and the reason
/// it is not simply `box.hitTest(...)` is
/// [HitTestBehavior.translucent]: a detector with that behaviour returns
/// *false* while still putting itself on the result path, and it will still
/// get the tap. Several assets are built that way — the runtime label, the
/// conveyor's own body — so the answer that matches what an operator
/// experiences is whether anything landed on the path at all.
bool pointerReaches(RenderBox box, Offset point) {
  final result = BoxHitTestResult();
  box.hitTest(result, position: point);
  return result.path.isNotEmpty;
}
