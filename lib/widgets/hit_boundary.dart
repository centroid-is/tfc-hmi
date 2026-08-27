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
/// So the asset says so instead. An asset whose hit test is a path publishes
/// that same path — the object its `hitTest` consults, not a copy of it —
/// with [AssetHitShape]. The plant view flattens it ([flattenPath]), stands
/// it off ([offsetContour]) and draws it: exact, analytic, and costing one
/// path per pane rather than the ten thousand hit tests it took to discover
/// the same shape by interrogation. An asset that publishes nothing takes
/// taps on its whole face, and its face is what gets marked, which for most
/// of them is the truth rather than an approximation of it.
///
/// What stops a published path from quietly becoming a third opinion is
/// `hit_boundary_drift_test`, which probes the real hit test the expensive
/// way and holds it against the published one. That is a CI cost, not an
/// operator's.
library;

import 'package:flutter/widgets.dart';

/// Moves every point of [ring] [distance] away from the region it encloses.
///
/// Along each point's own normal, so the clearance is the same the whole way
/// round whatever the shape does — the mark stands off a belt's long edges
/// and its rounded ends by the same 4px.
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
  ///
  /// A callback, not a path: the shape is wanted about once a minute, when an
  /// operator opens a pane, and this is built on every frame the asset
  /// rebuilds on. Resolving a turned belt's outline eagerly measured 145µs
  /// per build, on top of the 123µs its geometry already costs — doubling the
  /// price of a belt to publish something almost nobody asks for. The painter
  /// keeps the path once it has built it, so the mark and `hitTest` still get
  /// the same object.
  final ValueGetter<Path> shape;

  final Widget child;

  const AssetHitShape({super.key, required this.shape, required this.child});

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
