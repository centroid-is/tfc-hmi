import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Third-party equipment painters — one CustomPainter per equipment kind.
//
// Each paints a SIMPLIFIED PLAN VIEW (looking straight down) of a machine we
// do not control, drawn from the manufacturer's own photos and spec sheets so
// an operator recognises which box on the line they are looking at. They are
// hand-authored in normalised unit coordinates rather than exported from CAD
// (contrast `widgets/baader.dart`, a real DXF export) — we have no drawings
// for third-party gear.
//
// Sources for the geometry, per kind:
//   Multivac      R 245 spec sheet + machine photo — 5437 x 1002 mm,
//                 320 mm nominal web width, 280 mm max forming width,
//                 ~330 mm cross-cut zone, 800 mm discharge belt.
//   SpeedBatcher  Jón's sketch of the station as actually built on this line
//                 (buffers, infeed flat + step-up conveyors, two
//                 checkweighers) — NOT the Marel brochure, whose batcher head
//                 is a guarded cube with nothing visible from above.
//   Box erector   generic RSC erector (Eastey ERX-15 class) — 2395 x 2083 mm,
//                 side-loading blank magazine, 8-cup vacuum pick, flap
//                 folders, bottom centre-seal tape head, side-belt discharge.
//   Strapping     Afak SL-15-3 with Strapex heads — 2665 x 1815 mm, three
//                 arches in series over one belt, three coil dispensers on a
//                 rear gantry, ~530 mm boxes at 15/min.
//
// Painters are PURE — primitives in, pixels out. ZERO subscriptions, ZERO
// Riverpod, ZERO state. Same contract as `sensor_painter.dart`.
//
// Every painter draws the SAME dotted boundary box (the "not our scope of
// supply" marker, and the tap-target hint) and then its own machine glyph
// inside [thirdPartyMachineArea]. The run-status LED is NOT painted here — it
// is a real `LEDPainter` composited over the top-left header strip by the
// widget in `third_party.dart`, so it looks identical to every other LED on
// the page.
//
// Detail is drawn at the configured stroke width, NOT scaled with the asset,
// so a small asset degrades into a legible silhouette rather than a grey
// smudge. These layouts reward being placed at their true aspect ratio — see
// `ThirdPartyEquipmentKind.aspectRatio` in `third_party.dart`.
// ---------------------------------------------------------------------------

/// Dotted-boundary "on" segment length (absolute pixels).
const double kBoundaryDashOnPx = 5.0;

/// Dotted-boundary "off" segment length (absolute pixels).
const double kBoundaryDashOffPx = 4.0;

/// Corner radius of the dotted boundary box (x shortestSide).
const double kBoundaryRadiusFraction = 0.06;

/// Opacity applied to the machine colour when drawing the dotted boundary, so
/// the boundary reads as chrome rather than as part of the machine.
const double kBoundaryAlpha = 0.55;

/// Opacity for secondary detail (rollers, flights, chains, cavity grids) so
/// the machine's primary silhouette still dominates at a glance.
const double kDetailAlpha = 0.65;

/// Run-status LED diameter (x shortestSide), clamped to a legible range.
const double kLedDiameterFraction = 0.18;

/// Gap between the dotted boundary and the LED (x shortestSide).
const double kLedInsetFraction = 0.05;

/// Boundary inset from the asset rect (x shortestSide). Keeps the dashes fully
/// inside the layout box so they are not clipped by a tight parent.
const double kBoundaryInsetFraction = 0.03;

/// Padding between the dotted boundary and the machine glyph (x shortestSide).
const double kMachinePadFraction = 0.05;

/// Diameter of the run-status LED for an asset of [size].
double thirdPartyLedDiameter(Size size) =>
    (size.shortestSide * kLedDiameterFraction).clamp(8.0, 26.0);

/// Offset of the LED from the top-left corner of the dotted boundary.
double thirdPartyLedInset(Size size) => size.shortestSide * kLedInsetFraction;

/// The dotted boundary rect for an asset of [size].
Rect thirdPartyBoundaryRect(Size size) {
  final inset = size.shortestSide * kBoundaryInsetFraction;
  return Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
}

/// The rect the machine glyph is drawn into.
///
/// The top edge is pushed down by a header strip tall enough to clear the
/// run-status LED, so the LED never lands on top of the machine drawing no
/// matter which kind is selected.
Rect thirdPartyMachineArea(Size size) {
  final boundary = thirdPartyBoundaryRect(size);
  final pad = size.shortestSide * kMachinePadFraction;
  final header = thirdPartyLedInset(size) * 2 + thirdPartyLedDiameter(size);
  final rect = Rect.fromLTRB(
    boundary.left + pad,
    boundary.top + header,
    boundary.right - pad,
    boundary.bottom - pad,
  );
  // Degenerate guard: a very small asset rect can invert the header push.
  if (rect.width <= 0 || rect.height <= 0) return boundary;
  return rect;
}

// ---------------------------------------------------------------------------
// Unit-space helper
// ---------------------------------------------------------------------------

/// Maps normalised `0..1` machine coordinates onto a device-pixel [Rect].
///
/// Machine layouts are authored in unit space — `x` runs along the machine in
/// the direction of product flow (left to right for every kind here), `y` runs
/// across its depth, rear at `0` — so they read the same at any asset size.
///
/// Mapping happens here rather than via `canvas.scale` on purpose: a
/// non-uniform `scale` stretches stroke widths differently on the two axes,
/// and these machines are drawn in wide, non-square boxes.
class UnitSpace {
  const UnitSpace(this.area);

  /// Device-pixel rect that unit `(0,0)..(1,1)` maps onto.
  final Rect area;

  double get shortest => area.shortestSide;

  Offset p(double ux, double uy) =>
      Offset(area.left + ux * area.width, area.top + uy * area.height);

  Rect r(double ul, double ut, double ur, double ub) =>
      Rect.fromPoints(p(ul, ut), p(ur, ub));

  RRect rr(double ul, double ut, double ur, double ub, double radius) =>
      RRect.fromRectAndRadius(
          r(ul, ut, ur, ub), Radius.circular(shortest * radius));

  /// Radius in device pixels from a fraction of the shortest side, so circles
  /// stay circular in a stretched box.
  double rad(double f) => shortest * f;
}

// ---------------------------------------------------------------------------
// Base painter — dotted boundary + per-kind machine glyph
// ---------------------------------------------------------------------------

/// Shared base for the third-party equipment glyphs.
///
/// Subclasses implement [paintMachine] only; the dotted boundary is painted
/// here so every kind carries the same "third-party, tap me" affordance.
abstract class ThirdPartyMachinePainter extends CustomPainter {
  const ThirdPartyMachinePainter({
    required this.color,
    required this.strokeWidth,
  });

  /// Outline colour of the machine drawing. The dotted boundary and the
  /// secondary detail are drawn in the same colour at reduced opacity.
  final Color color;

  /// Outline stroke width in logical pixels.
  final double strokeWidth;

  /// Draws the machine glyph in unit space [u].
  ///
  /// [stroke] is the primary outline paint; [detail] is the same colour at
  /// [kDetailAlpha] and a thinner width, for rollers, chains and grids.
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    _paintBoundary(canvas, size);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final detail = Paint()
      ..color = color.withValues(alpha: kDetailAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    paintMachine(
        canvas, UnitSpace(thirdPartyMachineArea(size)), stroke, detail);
  }

  void _paintBoundary(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: kBoundaryAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rrect = RRect.fromRectAndRadius(
      thirdPartyBoundaryRect(size),
      Radius.circular(size.shortestSide * kBoundaryRadiusFraction),
    );
    _drawDashedPath(canvas, Path()..addRRect(rrect), paint);
  }

  @override
  bool shouldRepaint(covariant ThirdPartyMachinePainter oldDelegate) =>
      oldDelegate.runtimeType != runtimeType ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// Walks [path] with a `PathMetric` and emits alternating on/off segments.
///
/// Works for any path — the boundary is a rounded rect, so a per-edge line
/// dasher would drop the corner arcs.
void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
  for (final metric in path.computeMetrics()) {
    double distance = 0;
    bool on = true;
    while (distance < metric.length) {
      final len = on ? kBoundaryDashOnPx : kBoundaryDashOffPx;
      final next = (distance + len).clamp(0.0, metric.length);
      if (on) {
        canvas.drawPath(metric.extractPath(distance, next), paint);
      }
      distance = next;
      on = !on;
    }
  }
}

// ---------------------------------------------------------------------------
// Shared plan-view idioms
// ---------------------------------------------------------------------------

/// `count` evenly spaced ticks ACROSS the flow direction — plan-view shorthand
/// for conveyor rollers, chain links, belt flights, or a stack of blanks.
void _crossTicks(
  Canvas canvas,
  UnitSpace u,
  Paint paint, {
  required double ul,
  required double ur,
  required double ut,
  required double ub,
  required int count,
}) {
  if (count <= 0) return;
  final step = (ur - ul) / (count + 1);
  for (int i = 1; i <= count; i++) {
    final x = ul + step * i;
    canvas.drawLine(u.p(x, ut), u.p(x, ub), paint);
  }
}

/// `count` evenly spaced ticks ALONG the flow direction — the transverse
/// counterpart of [_crossTicks], for machines drawn portrait (rollers and
/// cleats on a lane running up the page).
void _lengthwiseTicks(
  Canvas canvas,
  UnitSpace u,
  Paint paint, {
  required double ul,
  required double ur,
  required double ut,
  required double ub,
  required int count,
}) {
  if (count <= 0) return;
  final step = (ub - ut) / (count + 1);
  for (int i = 1; i <= count; i++) {
    final y = ut + step * i;
    canvas.drawLine(u.p(ul, y), u.p(ur, y), paint);
  }
}

/// Three flow chevrons down a lane, pointing up or down the page.
///
/// Drawn at full stroke: on a machine with two parallel lanes running in
/// OPPOSITE directions, direction is the one thing the boxes cannot tell you.
void _chevrons(
  Canvas canvas,
  UnitSpace u,
  Paint paint, {
  required double cx,
  required double top,
  required double bottom,
  required bool pointingDown,
  int count = 3,
}) {
  const halfWidth = 0.055;
  final span = bottom - top;
  final height = span / (count * 1.8);
  for (int i = 0; i < count; i++) {
    final base = top + span * (i + 0.5) / count - height / 2;
    final tip = pointingDown ? base + height : base;
    final tail = pointingDown ? base : base + height;
    final path = Path()
      ..moveTo(u.p(cx - halfWidth, tail).dx, u.p(cx - halfWidth, tail).dy)
      ..lineTo(u.p(cx, tip).dx, u.p(cx, tip).dy)
      ..lineTo(u.p(cx + halfWidth, tail).dx, u.p(cx + halfWidth, tail).dy);
    canvas.drawPath(path, paint);
  }
}

/// A `rows x cols` grid of small rounded cells — plan-view shorthand for the
/// cavities in a thermoforming tool.
void _cavityGrid(
  Canvas canvas,
  UnitSpace u,
  Paint paint, {
  required double ul,
  required double ut,
  required double ur,
  required double ub,
  required int rows,
  required int cols,
}) {
  const gap = 0.22; // fraction of a cell left as web between cavities
  final cellW = (ur - ul) / cols;
  final cellH = (ub - ut) / rows;
  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final l = ul + cellW * (col + gap / 2);
      final t = ut + cellH * (row + gap / 2);
      canvas.drawRRect(
        u.rr(l, t, l + cellW * (1 - gap), t + cellH * (1 - gap), 0.015),
        paint,
      );
    }
  }
}

/// A film reel whose axis runs ACROSS the machine.
///
/// Seen from directly above, such a reel is a rectangle (the roll's
/// cylindrical face), not a circle — the giveaway is the mandrel shaft poking
/// out past both flanges, which is what this draws.
void _transverseReel(
  Canvas canvas,
  UnitSpace u,
  Paint stroke,
  Paint detail, {
  required double cx,
  required double cy,
  required double halfLen,
  required double halfWidth,
}) {
  canvas.drawRect(
      u.r(cx - halfLen, cy - halfWidth, cx + halfLen, cy + halfWidth), stroke);
  // Mandrel shaft, protruding past both flanges.
  canvas.drawLine(
      u.p(cx, cy - halfWidth * 1.4), u.p(cx, cy + halfWidth * 1.4), detail);
  // Flange edges.
  canvas.drawLine(u.p(cx - halfLen * 0.55, cy - halfWidth),
      u.p(cx - halfLen * 0.55, cy + halfWidth), detail);
  canvas.drawLine(u.p(cx + halfLen * 0.55, cy - halfWidth),
      u.p(cx + halfLen * 0.55, cy + halfWidth), detail);
}

// ---------------------------------------------------------------------------
// Multivac — R 245 class thermoforming packaging machine
// ---------------------------------------------------------------------------

/// Plan view of a Multivac thermoformer, product flowing left to right.
///
/// Station order follows the R-series web path: lower film unwind, forming
/// station, loading area (the long open stretch where product is placed into
/// the formed pockets), upper film unwind, sealing station, cross cutter,
/// longitudinal rotary knives, discharge belt. The two transport chains run
/// the full length down either side of the web.
///
/// True footprint is ~5437 x 1002 mm — a very long, narrow machine. Place the
/// asset near that aspect ratio or the stations bunch up.
class MultivacPainter extends ThirdPartyMachinePainter {
  const MultivacPainter({required super.color, required super.strokeWidth});

  @override
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail) {
    // Main frame, from the unwind end to the start of the discharge belt.
    canvas.drawRRect(u.rr(0.0, 0.14, 0.88, 0.86, 0.03), stroke);

    // Transport chains — two rails carrying the web the whole length. They run
    // just inside the tool footprints and just outside the cavities, which is
    // where they sit on the real machine (they grip the web edges).
    canvas.drawLine(u.p(0.10, 0.245), u.p(0.86, 0.245), detail);
    canvas.drawLine(u.p(0.10, 0.755), u.p(0.86, 0.755), detail);

    // Lower film unwind at the infeed end.
    _transverseReel(canvas, u, stroke, detail,
        cx: 0.05, cy: 0.50, halfLen: 0.035, halfWidth: 0.24);

    // Forming station tool and its cavities.
    canvas.drawRect(u.r(0.13, 0.18, 0.29, 0.82), stroke);
    _cavityGrid(canvas, u, detail,
        ul: 0.145, ut: 0.30, ur: 0.275, ub: 0.70, rows: 2, cols: 2);

    // Loading area — formed pockets travelling open through the long stretch
    // where product is placed. Same cavity pitch as the forming tool.
    _cavityGrid(canvas, u, detail,
        ul: 0.31, ut: 0.30, ur: 0.55, ub: 0.70, rows: 2, cols: 4);

    // Upper film unwind, mounted at the rear just ahead of the sealing
    // station, with its feed line down onto the web.
    _transverseReel(canvas, u, stroke, detail,
        cx: 0.50, cy: 0.05, halfLen: 0.03, halfWidth: 0.045);
    canvas.drawLine(u.p(0.53, 0.05), u.p(0.60, 0.18), detail);

    // Sealing station tool and the sealed packs under it.
    canvas.drawRect(u.r(0.58, 0.18, 0.72, 0.82), stroke);
    _cavityGrid(canvas, u, detail,
        ul: 0.593, ut: 0.30, ur: 0.707, ub: 0.70, rows: 2, cols: 2);

    // Cross cutter — a narrow band across the full web width.
    canvas.drawRect(u.r(0.755, 0.16, 0.80, 0.84), stroke);

    // Longitudinal rotary knives, slitting the web between the pack lanes and
    // trimming both edges. They sit in the short run between the cross cutter
    // and the discharge, at full stroke — crossing them over the cross-cutter
    // band just reads as a smudge.
    for (final y in [0.30, 0.50, 0.70]) {
      canvas.drawLine(u.p(0.81, y), u.p(0.87, y), stroke);
    }

    // Discharge belt with rollers.
    canvas.drawRect(u.r(0.88, 0.30, 1.0, 0.70), stroke);
    _crossTicks(canvas, u, detail,
        ul: 0.88, ur: 1.0, ut: 0.30, ub: 0.70, count: 3);

    // Control cabinet along the rear, beside the sealing station, with the
    // signal light column on its corner.
    canvas.drawRect(u.r(0.58, 0.0, 0.76, 0.13), stroke);
    canvas.drawCircle(u.p(0.79, 0.06), u.rad(0.035), detail);
  }
}

// ---------------------------------------------------------------------------
// SpeedBatcher station
// ---------------------------------------------------------------------------

/// Plan view of the SpeedBatcher station as it is actually built on this line.
///
/// Drawn from Jón's sketch of the real installation, NOT from a Marel
/// brochure. The published SpeedBatcher literature shows the batcher head on
/// its own — a cube on legs whose weigh hoppers and selection bins are all
/// under the guarding and invisible from above. What an operator looking down
/// at this station actually sees is the conveyor-and-checkweigher layout
/// below, so that is what gets drawn.
///
/// This one is PORTRAIT: product runs up the page, not left to right.
///
///   flow:  infeed flat conveyor (left lane, running DOWN)
///            -> buffers across the infeed end
///            -> drop onto the step-up conveyor (right lane, running UP)
///            -> checkweigher 1
///            -> checkweigher 2
///
/// So the product path is a U-turn: down the left lane, across the buffers,
/// back up the right lane. The chevrons carry that — without them the two
/// parallel lanes read as two independent lines.
///
/// There is also a buffer between the step-up drop and checkweigher 1 on the
/// real machine. It is left out of the drawing: as a full-width band it read
/// as a third checkweigher and crowded the two that matter.
///
/// The two conveyor lanes are drawn as light beds rather than full-stroke
/// machinery on purpose: they are the intended home for live `ConveyorConfig`
/// children driven by the real drive frequencies. Drop a conveyor asset on a
/// lane and it sits in its bed; leave it empty and the bed still reads as a
/// conveyor.
class SpeedBatcherPainter extends ThirdPartyMachinePainter {
  const SpeedBatcherPainter({required super.color, required super.strokeWidth});

  /// Buffer cells across the infeed end (2 columns x 2 rows in the sketch).
  static const int bufferColumns = 2;
  static const int bufferRows = 2;

  /// Unit rect of the infeed flat conveyor lane — where a live Conveyor child
  /// is meant to sit. Exposed so the editor can offer a one-tap "drop a
  /// conveyor on this lane" without duplicating the geometry.
  static const Rect infeedLane = Rect.fromLTRB(0.02, 0.46, 0.47, 0.84);

  /// Unit rect of the step-up conveyor lane.
  static const Rect stepUpLane = Rect.fromLTRB(0.53, 0.46, 0.98, 0.84);

  @override
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail) {
    // Station frame.
    canvas.drawRRect(u.rr(0.0, 0.0, 1.0, 1.0, 0.03), stroke);

    // -- Checkweigher 2 (final station, at the discharge end) --
    _checkweigher(canvas, u, stroke, detail, top: 0.03, bottom: 0.17);

    // -- Checkweigher 1 --
    _checkweigher(canvas, u, stroke, detail, top: 0.21, bottom: 0.38);

    // The buffer between the step-up drop and checkweigher 1 is deliberately
    // NOT drawn. It is really there on the machine, but as a full-width band
    // it read as a third checkweigher and crowded the two that matter.
    //
    // -- Conveyor lanes --
    // Light beds; a live Conveyor child lands on top of these.
    canvas.drawRect(
        u.r(infeedLane.left, infeedLane.top, infeedLane.right,
            infeedLane.bottom),
        detail);
    canvas.drawRect(
        u.r(stepUpLane.left, stepUpLane.top, stepUpLane.right,
            stepUpLane.bottom),
        detail);

    // The step-up conveyor is cleated so product cannot roll back down the
    // incline — the rungs are what tells the two lanes apart from above.
    _lengthwiseTicks(canvas, u, detail,
        ul: stepUpLane.left,
        ur: stepUpLane.right,
        ut: stepUpLane.top,
        ub: stepUpLane.bottom,
        count: 7);

    // Flow chevrons: DOWN the infeed lane, UP the step-up lane. This is the
    // U-turn, and it is the one thing a reader cannot infer from the boxes.
    _chevrons(canvas, u, stroke,
        cx: infeedLane.center.dx, top: 0.54, bottom: 0.78, pointingDown: true);
    _chevrons(canvas, u, stroke,
        cx: stepUpLane.center.dx, top: 0.54, bottom: 0.78, pointingDown: false);

    // -- Buffers across the infeed end --
    const bufTop = 0.87;
    const bufBottom = 0.99;
    const bufLeft = 0.02;
    const bufRight = 0.98;
    canvas.drawRect(u.r(bufLeft, bufTop, bufRight, bufBottom), stroke);
    final colW = (bufRight - bufLeft) / bufferColumns;
    final rowH = (bufBottom - bufTop) / bufferRows;
    for (int c = 1; c < bufferColumns; c++) {
      canvas.drawLine(u.p(bufLeft + colW * c, bufTop),
          u.p(bufLeft + colW * c, bufBottom), stroke);
    }
    for (int r = 1; r < bufferRows; r++) {
      canvas.drawLine(u.p(bufLeft, bufTop + rowH * r),
          u.p(bufRight, bufTop + rowH * r), stroke);
    }

    // Adjustable feet at the four corners.
    for (final corner in const [
      Offset(0.03, 0.02),
      Offset(0.97, 0.02),
      Offset(0.03, 0.98),
      Offset(0.97, 0.98),
    ]) {
      canvas.drawCircle(u.p(corner.dx, corner.dy), u.rad(0.018), detail);
    }
  }

  /// One checkweigher: frame, weigh deck with its belt rollers, load cell and
  /// the reject pusher on the side.
  void _checkweigher(
    Canvas canvas,
    UnitSpace u,
    Paint stroke,
    Paint detail, {
    required double top,
    required double bottom,
  }) {
    canvas.drawRect(u.r(0.02, top, 0.98, bottom), stroke);

    final deckTop = top + (bottom - top) * 0.22;
    final deckBottom = bottom - (bottom - top) * 0.22;
    canvas.drawRect(u.r(0.12, deckTop, 0.88, deckBottom), detail);
    _lengthwiseTicks(canvas, u, detail,
        ul: 0.12, ur: 0.88, ut: deckTop, ub: deckBottom, count: 3);

    // Load cell under the deck centre.
    canvas.drawRect(
        u.r(0.46, deckTop - 0.012, 0.54, deckTop + 0.012), detail);

    // Reject pusher alongside the deck.
    canvas.drawRect(u.r(0.03, deckTop, 0.10, deckBottom), detail);
  }
}

// ---------------------------------------------------------------------------
// Box erector
// ---------------------------------------------------------------------------

/// Plan view of an automatic RSC case erector, product flowing left to right.
///
/// Blank magazine holding the flat-packed stack on edge, a vacuum pick head
/// that peels the leading blank open and squares it, the erecting station
/// where the minor then major bottom flaps fold in, the bottom centre-seal
/// tape head, and the side belts that grip the case and drive it out.
///
/// TODO(product-name): the make/model of the erector on this line has not been
/// identified yet. Geometry here follows a generic RSC erector of the Eastey
/// ERX-15 class (~2395 x 2083 mm). Once the real machine is known, redraw
/// against its own layout and rename this painter and the
/// `ThirdPartyEquipmentKind.boxErector` label — every other kind is named
/// after its manufacturer.
class BoxErectorPainter extends ThirdPartyMachinePainter {
  const BoxErectorPainter({required super.color, required super.strokeWidth});

  /// Flat blanks drawn in the magazine stack. Cosmetic — the real hopper holds
  /// a couple of hundred.
  static const int magazineBlanks = 9;

  @override
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail) {
    // Machine frame.
    canvas.drawRRect(u.rr(0.0, 0.0, 1.0, 1.0, 0.03), stroke);

    // Blank magazine — the stack of flat cases seen on edge from above,
    // between two adjustable side guides with their handles.
    canvas.drawRect(u.r(0.02, 0.20, 0.30, 0.84), stroke);
    _crossTicks(canvas, u, detail,
        ul: 0.02, ur: 0.30, ut: 0.20, ub: 0.84, count: magazineBlanks);
    canvas.drawLine(u.p(0.02, 0.17), u.p(0.30, 0.17), detail);
    canvas.drawLine(u.p(0.02, 0.87), u.p(0.30, 0.87), detail);
    canvas.drawLine(u.p(0.06, 0.17), u.p(0.06, 0.12), detail);
    canvas.drawLine(u.p(0.06, 0.87), u.p(0.06, 0.92), detail);

    // Vacuum pick head — suction cups that peel the leading blank open.
    canvas.drawRect(u.r(0.32, 0.36, 0.40, 0.68), stroke);
    for (final cy in [0.44, 0.60]) {
      for (final cx in [0.343, 0.377]) {
        canvas.drawCircle(u.p(cx, cy), u.rad(0.022), detail);
      }
    }

    // Erecting station — the squared case with its four bottom flaps folded
    // in. The inner rectangle is the closed bottom; the diagonals are the
    // flap folds meeting it.
    canvas.drawRect(u.r(0.42, 0.14, 0.66, 0.90), stroke);
    final caseRect = u.r(0.46, 0.26, 0.62, 0.78);
    canvas.drawRect(caseRect, stroke);
    final inner = u.r(0.495, 0.36, 0.585, 0.68);
    canvas.drawRect(inner, detail);
    canvas.drawLine(caseRect.topLeft, inner.topLeft, detail);
    canvas.drawLine(caseRect.topRight, inner.topRight, detail);
    canvas.drawLine(caseRect.bottomLeft, inner.bottomLeft, detail);
    canvas.drawLine(caseRect.bottomRight, inner.bottomRight, detail);

    // Side belts that grip the erected case and drive it out.
    canvas.drawRect(u.r(0.66, 0.26, 1.0, 0.33), stroke);
    canvas.drawRect(u.r(0.66, 0.71, 1.0, 0.78), stroke);
    _crossTicks(canvas, u, detail,
        ul: 0.66, ur: 1.0, ut: 0.26, ub: 0.33, count: 4);
    _crossTicks(canvas, u, detail,
        ul: 0.66, ur: 1.0, ut: 0.71, ub: 0.78, count: 4);

    // Bottom tape head, centred under the case path, with its tape roll. It
    // sits below the case so it is drawn as detail, not as a hard outline.
    canvas.drawRect(u.r(0.73, 0.44, 0.91, 0.60), detail);
    canvas.drawCircle(u.p(0.82, 0.52), u.rad(0.055), detail);

    // Control panel at the rear.
    canvas.drawRect(u.r(0.42, 0.02, 0.60, 0.10), stroke);
  }
}

// ---------------------------------------------------------------------------
// Afak SL-15-3 strapping line (Strapex heads)
// ---------------------------------------------------------------------------

/// Plan view of the Afak SL-15-N strapping line, boxes flowing left to right.
///
/// One belt runs the length of the machine under [heads] Strapex arches in
/// series — the box is strapped once per arch as it indexes through, rather
/// than being strapped once and turned. Each arch has its own strap coil
/// dispenser on the rear gantry directly behind it. Cabinets run along the
/// front, and the control cabinet with the stack light sits at the discharge
/// end.
///
/// Afak sells the head count as separate models — SL-15-1, SL-15-2 and
/// SL-15-3 — and the real machines get shorter as heads come off. The drawing
/// still fills its box whatever the count (leaving whitespace inside the
/// dotted boundary would read as a rendering bug); the true proportions are
/// carried by `ThirdPartyEquipmentKind.aspectRatio`, which the editor's
/// "match proportions" button applies.
///
/// SL-15-3 footprint ~2665 x 1815 mm, 15 boxes/min, ~530 mm boxes.
class StrappingLinePainter extends ThirdPartyMachinePainter {
  const StrappingLinePainter({
    required super.color,
    required super.strokeWidth,
    this.heads = maxHeads,
  }) : assert(heads >= 1 && heads <= maxHeads);

  /// Largest model Afak lists in the SL-15 family.
  static const int maxHeads = 3;

  /// Number of Strapex arches — the `-N` in the SL-15-N model number.
  final int heads;

  /// Unit x-centre of each arch, spread evenly with a margin at both ends so
  /// the outermost arch never collides with the infeed or the cabinet.
  static List<double> archCentresFor(int heads) {
    const margin = 0.13;
    final span = 1.0 - margin * 2;
    return [
      for (int i = 0; i < heads; i++) margin + span * (i + 0.5) / heads,
    ];
  }

  @override
  bool shouldRepaint(covariant ThirdPartyMachinePainter oldDelegate) =>
      super.shouldRepaint(oldDelegate) ||
      (oldDelegate is StrappingLinePainter && oldDelegate.heads != heads);

  @override
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail) {
    // Machine frame.
    canvas.drawRRect(u.rr(0.0, 0.10, 1.0, 1.0, 0.03), stroke);

    // Rear gantry beam carrying the coil dispensers, on its two posts.
    canvas.drawLine(u.p(0.06, 0.05), u.p(0.94, 0.05), stroke);
    canvas.drawRect(u.r(0.05, 0.03, 0.09, 0.08), detail);
    canvas.drawRect(u.r(0.91, 0.03, 0.95, 0.08), detail);

    // Belt through the machine, with rollers. A ~530 mm box lane in a 1815 mm
    // deep machine, so the belt is a narrow band down the middle.
    canvas.drawRect(u.r(0.0, 0.42, 1.0, 0.68), stroke);
    _crossTicks(canvas, u, detail,
        ul: 0.0, ur: 1.0, ut: 0.42, ub: 0.68, count: 9);

    final centres = archCentresFor(heads);
    // Arch width shrinks a little as heads are added so three still breathe.
    final halfArch = (0.105 / heads).clamp(0.030, 0.055);

    for (final cx in centres) {
      // Strapex arch straddling the belt: the top crossbar spans the full
      // depth, with a heavier footprint where each upright lands.
      canvas.drawRect(u.r(cx - halfArch, 0.26, cx + halfArch, 0.84), stroke);
      canvas.drawRect(u.r(cx - halfArch, 0.26, cx + halfArch, 0.42), stroke);
      canvas.drawRect(u.r(cx - halfArch, 0.68, cx + halfArch, 0.84), stroke);

      // Strap coil dispenser on the gantry behind this arch, with its hub and
      // the strap feed running down to the arch.
      canvas.drawCircle(u.p(cx, 0.15), u.rad(0.085), stroke);
      canvas.drawCircle(u.p(cx, 0.15), u.rad(0.028), detail);
      canvas.drawLine(u.p(cx, 0.24), u.p(cx, 0.26), detail);
    }

    // Pneumatic pushers that stop and hold the box at the first arch. They
    // ride just ahead of it, so they follow the first arch rather than
    // sitting at a fixed spot that a 1-head machine would put them past.
    final pusherX = (centres.first - halfArch - 0.09).clamp(0.02, 0.90);
    canvas.drawRect(u.r(pusherX, 0.70, pusherX + 0.05, 0.76), detail);
    canvas.drawRect(u.r(pusherX, 0.34, pusherX + 0.05, 0.40), detail);

    // Cabinets along the front of the machine.
    canvas.drawRect(u.r(0.06, 0.88, 0.86, 1.0), stroke);
    canvas.drawLine(u.p(0.33, 0.88), u.p(0.33, 1.0), detail);
    canvas.drawLine(u.p(0.60, 0.88), u.p(0.60, 1.0), detail);

    // Control cabinet at the discharge end, with the stack light.
    canvas.drawRect(u.r(0.90, 0.72, 1.0, 1.0), stroke);
    canvas.drawCircle(u.p(0.95, 0.78), u.rad(0.035), detail);
  }
}
