import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Sensor painters — one CustomPainter per SensorKind.
//
// Painters are PURE — primitives in, pixels out. ZERO subscriptions, ZERO
// Riverpod, ZERO state. Locked by `01-UI-SPEC.md` §Painter Decomposition and
// `PITFALLS.md` Pitfall 2.
//
// One class per kind (no `switch (kind)` inside any `paint()` method) — this
// is what closes Pitfall 3 (painter state leakage on kind change). The
// `shouldRepaint` cross-runtimeType guard enforces it at the framework level.
// ---------------------------------------------------------------------------

/// Diameter of optic / inductive housing puck and red-light pucks (× shortestSide).
const double kHousingFraction = 0.25;

/// Stroke width of the beam line (red light kind) (× shortestSide).
const double kBeamStrokeWidth = 0.06;

/// Outline stroke for inactive field shape (optic / inductive) (× shortestSide).
const double kFieldStrokeWidth = 0.04;

/// Housing border stroke (× shortestSide).
const double kBorderStrokeWidth = 0.05;

/// Dashed beam-line "on" segment length (absolute pixels).
const double kDashOnPx = 6.0;

/// Dashed beam-line "off" segment length (absolute pixels).
const double kDashOffPx = 4.0;

/// Active-state field-shape fill opacity.
const double kFieldFillAlpha = 0.40;

/// Label text size as fraction of `size.shortestSide`.
const double kLabelFontFraction = 0.30;

// ---------------------------------------------------------------------------
// RedLightBeamPainter
// ---------------------------------------------------------------------------

/// Paints a paired red-light photoelectric sensor: emitter puck on the left,
/// receiver puck on the right, beam line spanning their centres.
///
/// Visual contract (from UI-SPEC §Color matrix):
/// - `isActive == false` (clear): solid neutral grey beam line.
/// - `isActive == true`  (broken): dashed `activeColor` beam line (6-on/4-off).
/// - `isStale == true`: entire glyph rendered in `Colors.grey`.
///
/// Polarity inversion happens BEFORE this painter sees `isActive` — see
/// `sensorIsActive(rawBool, invertActivePolarity)` in `sensor.dart`.
class RedLightBeamPainter extends CustomPainter {
  RedLightBeamPainter({
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.label,
    this.isStale = false,
  });

  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final String? label;
  final bool isStale;

  @override
  void paint(Canvas canvas, Size size) {
    // STUB — full implementation in Task 4 (post golden RED).
    final p = Paint()..color = Colors.transparent;
    canvas.drawRect(Offset.zero & size, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate.runtimeType != runtimeType) return true;
    final o = oldDelegate as RedLightBeamPainter;
    return o.isActive != isActive ||
        o.activeColor != activeColor ||
        o.inactiveColor != inactiveColor ||
        o.label != label ||
        o.isStale != isStale;
  }
}

// ---------------------------------------------------------------------------
// OpticFieldPainter
// ---------------------------------------------------------------------------

/// Paints an optic-field sensor: housing rectangle on the left, fanning cone
/// extending rightward.
///
/// Visual contract (from UI-SPEC §Color matrix):
/// - `isActive == false`: cone outlined in `inactiveColor` (no fill).
/// - `isActive == true`:  cone filled with `activeColor` at α=0.40, with
///   `activeColor` outline still visible underneath.
/// - `isStale == true`:   entire glyph in `Colors.grey`.
class OpticFieldPainter extends CustomPainter {
  OpticFieldPainter({
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.label,
    this.isStale = false,
  });

  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final String? label;
  final bool isStale;

  @override
  void paint(Canvas canvas, Size size) {
    // STUB — full implementation in Task 4 (post golden RED).
    final p = Paint()..color = Colors.transparent;
    canvas.drawRect(Offset.zero & size, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate.runtimeType != runtimeType) return true;
    final o = oldDelegate as OpticFieldPainter;
    return o.isActive != isActive ||
        o.activeColor != activeColor ||
        o.inactiveColor != inactiveColor ||
        o.label != label ||
        o.isStale != isStale;
  }
}

// ---------------------------------------------------------------------------
// InductiveFieldPainter
// ---------------------------------------------------------------------------

/// Paints an inductive-field (proximity) sensor: small housing puck with a
/// near-field bubble ellipse projecting outward.
///
/// Visual contract (from UI-SPEC §Color matrix):
/// - `isActive == false`: bubble outlined in `inactiveColor` (no fill).
/// - `isActive == true`:  bubble filled with `activeColor` at α=0.40 with
///   `activeColor` outline still visible.
/// - `isStale == true`:   entire glyph in `Colors.grey`.
class InductiveFieldPainter extends CustomPainter {
  InductiveFieldPainter({
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.label,
    this.isStale = false,
  });

  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final String? label;
  final bool isStale;

  @override
  void paint(Canvas canvas, Size size) {
    // STUB — full implementation in Task 4 (post golden RED).
    final p = Paint()..color = Colors.transparent;
    canvas.drawRect(Offset.zero & size, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate.runtimeType != runtimeType) return true;
    final o = oldDelegate as InductiveFieldPainter;
    return o.isActive != isActive ||
        o.activeColor != activeColor ||
        o.inactiveColor != inactiveColor ||
        o.label != label ||
        o.isStale != isStale;
  }
}
