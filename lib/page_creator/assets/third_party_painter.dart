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
//   SpeedBatcher  Marel SBM3000 — 2311 x 1270 mm, 508 mm infeed belt,
//                 4 static scales, 2 selection bins, 610 mm takeaway belt
//                 with 76 mm flights at 305 mm spacing.
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
// SpeedBatcher — Marel SBM3000 class batcher
// ---------------------------------------------------------------------------

/// Plan view of a Marel SpeedBatcher, product flowing left to right.
///
/// Three stacked levels, all drawn flat as a schematic plan: the infeed
/// weighing belt along the rear with its distribution chute, a row of static
/// weigh hoppers with drop-flap doors below it, two selection bins that
/// combine the chosen sub-weights, and the flighted takeaway belt across the
/// front that carries finished batches away.
///
/// The flighted belt is the giveaway — regular cross bars every 305 mm on a
/// 610 mm belt. True footprint ~2311 x 1270 mm.
class SpeedBatcherPainter extends ThirdPartyMachinePainter {
  const SpeedBatcherPainter({required super.color, required super.strokeWidth});

  /// Static weigh scales built into the batcher (SBM3000 has four).
  static const int scales = 4;

  /// Selection bins that assemble the final batch (SBM3000 has two).
  static const int selectionBins = 2;

  @override
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail) {
    // Machine frame.
    canvas.drawRRect(u.rr(0.0, 0.0, 1.0, 1.0, 0.03), stroke);

    // Infeed weighing belt along the rear, with belt rollers.
    canvas.drawRect(u.r(0.03, 0.05, 0.70, 0.26), stroke);
    _crossTicks(canvas, u, detail,
        ul: 0.03, ur: 0.70, ut: 0.05, ub: 0.26, count: 7);

    // Distribution chute that drops product off the belt into the hoppers.
    canvas.drawRect(u.r(0.30, 0.08, 0.40, 0.23), stroke);
    canvas.drawLine(u.p(0.30, 0.08), u.p(0.40, 0.23), detail);

    // Static weigh hoppers in a row, each with a drop flap hinged along its
    // front edge and a load cell at the back.
    const hopperTop = 0.32;
    const hopperBottom = 0.56;
    const hopperSpan = 0.70;
    final hopperSlot = hopperSpan / scales;
    for (int i = 0; i < scales; i++) {
      final l = 0.03 + hopperSlot * i + hopperSlot * 0.08;
      final r = 0.03 + hopperSlot * (i + 1) - hopperSlot * 0.08;
      canvas.drawRect(u.r(l, hopperTop, r, hopperBottom), stroke);
      canvas.drawLine(
          u.p(l, hopperBottom - 0.04), u.p(r, hopperBottom - 0.04), detail);
      canvas.drawLine(u.p((l + r) / 2, hopperTop),
          u.p((l + r) / 2, hopperTop - 0.04), detail);
    }

    // Selection bins that combine sub-weights into the final batch.
    const binTop = 0.60;
    const binBottom = 0.80;
    const binSpan = 0.66;
    final binSlot = binSpan / selectionBins;
    for (int i = 0; i < selectionBins; i++) {
      final l = 0.05 + binSlot * i + binSlot * 0.06;
      final r = 0.05 + binSlot * (i + 1) - binSlot * 0.06;
      canvas.drawRect(u.r(l, binTop, r, binBottom), stroke);
      canvas.drawLine(
          u.p(l, binBottom - 0.035), u.p(r, binBottom - 0.035), detail);
    }

    // Flighted takeaway belt across the front — batches ride in the pockets
    // between the flights. Runs past both ends of the frame. The flights are
    // drawn at full stroke, not as detail: they are what tells this machine
    // apart from any other box-with-conveyors at a glance.
    canvas.drawRect(u.r(0.0, 0.84, 1.0, 1.0), stroke);
    _crossTicks(canvas, u, stroke,
        ul: 0.0, ur: 1.0, ut: 0.84, ub: 1.0, count: 7);

    // Operator terminal on its swing arm, at the discharge end.
    canvas.drawRect(u.r(0.79, 0.10, 0.97, 0.30), stroke);
    canvas.drawRect(u.r(0.81, 0.13, 0.95, 0.27), detail);
    canvas.drawLine(u.p(0.79, 0.20), u.p(0.72, 0.20), detail);
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

/// Plan view of the Afak SL-15-3 strapping line, boxes flowing left to right.
///
/// One belt runs the length of the machine under THREE Strapex arches in
/// series — the box is strapped three times as it indexes through, rather than
/// being strapped once and turned. Each arch has its own strap coil dispenser
/// on the rear gantry directly behind it. Cabinets run along the front, and
/// the control cabinet with the stack light sits at the discharge end.
///
/// True footprint ~2665 x 1815 mm, 15 boxes/min, ~530 mm boxes.
class StrappingLinePainter extends ThirdPartyMachinePainter {
  const StrappingLinePainter({
    required super.color,
    required super.strokeWidth,
  });

  /// Unit x-centre of each Strapex arch, evenly spaced along the belt. The
  /// `-3` in SL-15-3 is the strap count, so the length of this list IS the
  /// model designation.
  static const List<double> archCentres = [0.28, 0.52, 0.76];

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

    for (final cx in archCentres) {
      // Strapex arch straddling the belt: the top crossbar spans the full
      // depth, with a heavier footprint where each upright lands.
      canvas.drawRect(u.r(cx - 0.035, 0.26, cx + 0.035, 0.84), stroke);
      canvas.drawRect(u.r(cx - 0.035, 0.26, cx + 0.035, 0.42), stroke);
      canvas.drawRect(u.r(cx - 0.035, 0.68, cx + 0.035, 0.84), stroke);

      // Strap coil dispenser on the gantry behind this arch, with its hub and
      // the strap feed running down to the arch.
      canvas.drawCircle(u.p(cx, 0.15), u.rad(0.085), stroke);
      canvas.drawCircle(u.p(cx, 0.15), u.rad(0.028), detail);
      canvas.drawLine(u.p(cx, 0.24), u.p(cx, 0.26), detail);
    }

    // Pneumatic pushers that stop and hold the box at the first arch.
    canvas.drawRect(u.r(0.17, 0.70, 0.22, 0.76), detail);
    canvas.drawRect(u.r(0.17, 0.34, 0.22, 0.40), detail);

    // Cabinets along the front of the machine.
    canvas.drawRect(u.r(0.06, 0.88, 0.86, 1.0), stroke);
    canvas.drawLine(u.p(0.33, 0.88), u.p(0.33, 1.0), detail);
    canvas.drawLine(u.p(0.60, 0.88), u.p(0.60, 1.0), detail);

    // Control cabinet at the discharge end, with the stack light.
    canvas.drawRect(u.r(0.90, 0.72, 1.0, 1.0), stroke);
    canvas.drawCircle(u.p(0.95, 0.78), u.rad(0.035), detail);
  }
}
