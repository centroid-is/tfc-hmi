/// The outline of what actually takes a tap.
///
/// Every other way of drawing a boundary around an asset re-derives it: the
/// editor's selection border is the asset's `w×h` box turned by its angle,
/// the AI proposal outline is the same box dashed. That is a second opinion
/// about the asset's shape, and second opinions drift — a conveyor turn is an
/// arc across a box it fills maybe a third of, a straight belt with an
/// explicit width is a band down the middle, and both used to be framed by a
/// rectangle that claimed far more than the operator can actually hit
/// (`ConveyorPainter.hitTest` takes only the painted belt).
///
/// So this module does not describe the asset at all. It *asks* it: sample
/// the hit test over a grid, and trace the line between the points that
/// answered and the points that did not. Whatever the asset really takes
/// taps on is what gets drawn — including, usefully, a hit area that has come
/// adrift from the glyph, which then shows up as a ring around empty space.
///
/// The sampling is pure given a predicate ([HitMask.probe]) and the tracing
/// is pure given a mask ([hitBoundarySegments]), so both are tested against
/// shapes with known outlines rather than against a live widget tree.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

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

  /// The same mask grown by [cells] samples in every direction.
  ///
  /// Two jobs: it lifts the outline clear of the glyph, so the ring sits
  /// around what you can tap instead of on top of it, and it closes the
  /// one-sample gaps a coarse grid leaves in a thin belt — a boundary broken
  /// into fragments reads as noise, not as a shape.
  HitMask dilated(int cells) {
    if (cells <= 0) return this;
    final grown = Uint8List(cols * rows);
    final reach = cells * cells;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if (!at(col, row)) continue;
        for (var dy = -cells; dy <= cells; dy++) {
          for (var dx = -cells; dx <= cells; dx++) {
            // Round rather than square: a square structuring element leaves
            // corners on every bend of the outline.
            if (dx * dx + dy * dy > reach) continue;
            final c = col + dx;
            final r = row + dy;
            if (c < 0 || r < 0 || c >= cols || r >= rows) continue;
            grown[r * cols + c] = 1;
          }
        }
      }
    }
    return HitMask._(
      area: area,
      cell: cell,
      cols: cols,
      rows: rows,
      hits: grown,
    );
  }
}

/// The line between the samples that hit and the samples that did not.
///
/// Marching squares over the sample grid, each segment running between the
/// midpoints of the cell edges it crosses. The segments come back loose
/// rather than assembled into loops: consecutive segments already share
/// endpoints exactly, so stroking them with round caps draws as one
/// continuous outline, and the alternative — chaining them into polylines —
/// is bookkeeping that nothing here needs.
///
/// A shape with a hole gives the outer and the inner boundary both, which is
/// the honest answer: both are edges of what takes a tap.
List<(Offset, Offset)> hitBoundarySegments(HitMask mask) {
  final segments = <(Offset, Offset)>[];
  // One square per group of four neighbouring samples.
  for (var row = -1; row < mask.rows; row++) {
    for (var col = -1; col < mask.cols; col++) {
      final tl = mask.at(col, row);
      final tr = mask.at(col + 1, row);
      final br = mask.at(col + 1, row + 1);
      final bl = mask.at(col, row + 1);

      final code = (tl ? 1 : 0) | (tr ? 2 : 0) | (br ? 4 : 0) | (bl ? 8 : 0);
      if (code == 0 || code == 15) continue;

      final a = mask.centreOf(col, row);
      final c = mask.centreOf(col + 1, row + 1);
      final half = mask.cell / 2;
      // Midpoints of the four edges of the square.
      final top = Offset(a.dx + half, a.dy);
      final right = Offset(c.dx, a.dy + half);
      final bottom = Offset(a.dx + half, c.dy);
      final left = Offset(a.dx, a.dy + half);

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

/// The rings of [mask], traced and smoothed — the whole pipeline.
List<List<Offset>> hitBoundaryContours(HitMask mask, {int smoothing = 2}) => [
      for (final ring in traceContours(hitBoundarySegments(mask)))
        smoothContour(ring, iterations: smoothing),
    ];

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
