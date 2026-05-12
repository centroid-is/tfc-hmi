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
///
/// Reduced from 0.30 to 0.18 (SENS-17 follow-up): at 0.30 the label
/// font dominated the glyph at typical golden canvas sizes
/// (e.g. 38px tall on a 128px shortestSide) and forced the label band
/// to eat enough vertical room that the geometry visibly shrank. 0.18
/// keeps the tag legible while leaving a clean separation between the
/// glyph and the label.
const double kLabelFontFraction = 0.18;

/// Fraction of `size.height` reserved as a bottom band for the label
/// when the painter has a non-empty `label`. The geometry rect handed
/// to each painter shrinks by this fraction so the painted glyph (puck +
/// beam / cone / bubble) sits ABOVE the label band — no overlap on the
/// inductive bubble or the optic cone base at the configured size.
///
/// 0.25 is the smallest value that clears the inductive-field bubble
/// (which extends to `0.80 * h_glyph` from its centre at `0.50 * h_glyph`).
const double kLabelBandFraction = 0.25;

// ---------------------------------------------------------------------------
// Shared paint helpers (file-private)
// ---------------------------------------------------------------------------

/// Returns the height of the geometry rect for the glyph — full `size.height`
/// when there is no label, otherwise `size.height * (1 - kLabelBandFraction)`
/// so a bottom band is reserved for the label.
///
/// All three painters call this BEFORE computing geometry so the puck +
/// field / beam fit above the label band cleanly. Mirrors the
/// `ConveyorGate` painter pattern where the painter respects a reserved
/// region rather than overdrawing.
double _glyphHeight(Size size, String? label) {
  if (label == null || label.isEmpty) return size.height;
  return size.height * (1 - kLabelBandFraction);
}

/// Draws an optional centred label inside the bottom band reserved by
/// [_glyphHeight]. Vertically centred within the band so the label is
/// clearly separated from the glyph above.
///
/// Skipped silently when `label` is null or empty (which is the common case —
/// `BaseAsset.text` is also rendered separately by the page editor chrome,
/// so the painter label is opt-in for kinds that want a tag baked into the
/// glyph itself).
void _paintLabel(Canvas canvas, Size size, String? label, Color color) {
  if (label == null || label.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: color,
        fontSize: size.shortestSide * kLabelFontFraction,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final glyphH = _glyphHeight(size, label);
  final bandTop = glyphH;
  final bandHeight = size.height - glyphH;
  tp.paint(
    canvas,
    Offset(
      (size.width - tp.width) / 2,
      bandTop + (bandHeight - tp.height) / 2,
    ),
  );
}

/// Draws a horizontal dashed line from `a` to `b` using absolute on/off
/// segment lengths. Both endpoints share `a.dy` (the y-coord on `b` is
/// ignored — the line is constrained to horizontal so the dash phase is
/// deterministic regardless of slope).
void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
  final dx = b.dx - a.dx;
  if (dx == 0) return;
  final total = dx.abs();
  final dir = dx >= 0 ? 1.0 : -1.0;
  double drawn = 0;
  bool on = true;
  double cursor = a.dx;
  final cy = a.dy;
  while (drawn < total) {
    final segLen = on ? kDashOnPx : kDashOffPx;
    final clamped = segLen.clamp(0, total - drawn).toDouble();
    final next = cursor + dir * clamped;
    if (on) {
      canvas.drawLine(Offset(cursor, cy), Offset(next, cy), paint);
    }
    cursor = next;
    drawn += segLen;
    on = !on;
  }
}

/// Housing fill colour — slightly lighter than the border so the puck reads
/// as solid against the dark UI background. Stale flag overrides to a single
/// `Colors.grey` value (no shade nuance).
Color _housingFill({required bool isStale}) =>
    isStale ? Colors.grey : Colors.grey.shade300;

/// Housing border colour. Same stale override rule as the fill.
Color _housingBorder({required bool isStale}) =>
    isStale ? Colors.grey : Colors.grey.shade600;

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
    final w = size.width;
    // Geometry uses the glyph height — shrunk when a label is present so
    // the painted shape sits cleanly above the reserved label band (SENS-17).
    final h = _glyphHeight(size, label);
    final s = h < size.shortestSide ? h : size.shortestSide;

    final puckRadius = s * kHousingFraction / 2;
    final emitterCentre = Offset(0.15 * w, 0.5 * h);
    final receiverCentre = Offset(0.85 * w, 0.5 * h);

    final housingFill = Paint()
      ..color = _housingFill(isStale: isStale)
      ..style = PaintingStyle.fill;
    final housingBorder = Paint()
      ..color = _housingBorder(isStale: isStale)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * kBorderStrokeWidth;

    // Beam first (drawn under the pucks so the stroke endpoints are tucked
    // beneath the housings — looks cleaner at small sizes).
    final beamStart = Offset(emitterCentre.dx + puckRadius, 0.5 * h);
    final beamEnd = Offset(receiverCentre.dx - puckRadius, 0.5 * h);
    final beamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * kBeamStrokeWidth
      ..strokeCap = StrokeCap.round;

    if (isStale) {
      beamPaint.color = Colors.grey;
      canvas.drawLine(beamStart, beamEnd, beamPaint);
    } else if (!isActive) {
      // Clear — solid neutral grey beam line (UI-SPEC).
      beamPaint.color = Colors.grey.shade600;
      canvas.drawLine(beamStart, beamEnd, beamPaint);
    } else {
      // Broken — dashed activeColor line, 6-on/4-off absolute pixels.
      beamPaint
        ..color = activeColor
        ..strokeCap = StrokeCap.butt;
      _drawDashedLine(canvas, beamStart, beamEnd, beamPaint);
    }

    // Pucks
    canvas.drawCircle(emitterCentre, puckRadius, housingFill);
    canvas.drawCircle(emitterCentre, puckRadius, housingBorder);
    canvas.drawCircle(receiverCentre, puckRadius, housingFill);
    canvas.drawCircle(receiverCentre, puckRadius, housingBorder);

    // Label (if any) — operator-facing tag must contrast against the
    // panel. Plan 04-02 visual review caught labels disappearing into
    // grey panels when this used `inactiveColor`. SENS-13 lock:
    // stale → grey, else `Colors.black87`.
    final labelColour = isStale ? Colors.grey : Colors.black87;
    _paintLabel(canvas, size, label, labelColour);
  }

  /// Test-visibility hook for the locked label-colour formula
  /// (SENS-13). NOT used by paint() — paint() inlines the same
  /// expression. Kept in sync with the inlined site.
  @visibleForTesting
  Color get debugLabelColour => isStale ? Colors.grey : Colors.black87;

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
    final w = size.width;
    // Geometry uses the glyph height — shrunk when a label is present so
    // the cone base sits above the reserved label band (SENS-17).
    final h = _glyphHeight(size, label);
    final s = h < size.shortestSide ? h : size.shortestSide;

    // Housing rectangle on the left.
    final housingRect = Rect.fromLTRB(0.05 * w, 0.30 * h, 0.30 * w, 0.70 * h);
    final housingFill = Paint()
      ..color = _housingFill(isStale: isStale)
      ..style = PaintingStyle.fill;
    final housingBorder = Paint()
      ..color = _housingBorder(isStale: isStale)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * kBorderStrokeWidth;
    canvas.drawRect(housingRect, housingFill);
    canvas.drawRect(housingRect, housingBorder);

    // Cone path: apex at housing right-centre, base spans 0.20·h..0.80·h
    // on the right edge.
    final cone = Path()
      ..moveTo(0.30 * w, 0.50 * h)
      ..lineTo(0.95 * w, 0.20 * h)
      ..lineTo(0.95 * w, 0.80 * h)
      ..close();

    if (isStale) {
      // Stale: outlined cone in grey (no fill).
      canvas.drawPath(
        cone,
        Paint()
          ..color = Colors.grey
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * kFieldStrokeWidth,
      );
    } else if (isActive) {
      // Active: fill α=0.40 + activeColor outline ON TOP so the outline
      // remains visible underneath the translucent fill (UI-SPEC).
      canvas.drawPath(
        cone,
        Paint()
          ..color = activeColor.withValues(alpha: kFieldFillAlpha)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        cone,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * kFieldStrokeWidth,
      );
    } else {
      // Inactive: outlined in inactiveColor, no fill.
      canvas.drawPath(
        cone,
        Paint()
          ..color = inactiveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * kFieldStrokeWidth,
      );
    }

    // SENS-13: label must contrast against the panel — see Plan 04-02.
    final labelColour = isStale ? Colors.grey : Colors.black87;
    _paintLabel(canvas, size, label, labelColour);
  }

  /// Test-visibility hook for the locked label-colour formula
  /// (SENS-13). Mirrors the inlined paint() expression.
  @visibleForTesting
  Color get debugLabelColour => isStale ? Colors.grey : Colors.black87;

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
    final w = size.width;
    // Geometry uses the glyph height — shrunk when a label is present so
    // the bubble ellipse sits above the reserved label band. This is the
    // root-cause fix for the inductive-sensor label overlap reported by
    // operators (SENS-17).
    final h = _glyphHeight(size, label);
    final s = h < size.shortestSide ? h : size.shortestSide;

    final puckRadius = s * kHousingFraction / 2;
    final puckCentre = Offset(0.30 * w, 0.50 * h);

    // Housing puck (drawn first so the bubble sits visually beside it).
    final housingFill = Paint()
      ..color = _housingFill(isStale: isStale)
      ..style = PaintingStyle.fill;
    final housingBorder = Paint()
      ..color = _housingBorder(isStale: isStale)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * kBorderStrokeWidth;
    canvas.drawCircle(puckCentre, puckRadius, housingFill);
    canvas.drawCircle(puckCentre, puckRadius, housingBorder);

    // Bubble: ellipse rx=0.25·w, ry=0.30·h centred at (0.65·w, 0.50·h).
    final bubble = Rect.fromCenter(
      center: Offset(0.65 * w, 0.50 * h),
      width: 2 * 0.25 * w,
      height: 2 * 0.30 * h,
    );

    if (isStale) {
      canvas.drawOval(
        bubble,
        Paint()
          ..color = Colors.grey
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * kFieldStrokeWidth,
      );
    } else if (isActive) {
      canvas.drawOval(
        bubble,
        Paint()
          ..color = activeColor.withValues(alpha: kFieldFillAlpha)
          ..style = PaintingStyle.fill,
      );
      canvas.drawOval(
        bubble,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * kFieldStrokeWidth,
      );
    } else {
      canvas.drawOval(
        bubble,
        Paint()
          ..color = inactiveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * kFieldStrokeWidth,
      );
    }

    // SENS-13: label must contrast against the panel — see Plan 04-02.
    final labelColour = isStale ? Colors.grey : Colors.black87;
    _paintLabel(canvas, size, label, labelColour);
  }

  /// Test-visibility hook for the locked label-colour formula
  /// (SENS-13). Mirrors the inlined paint() expression.
  @visibleForTesting
  Color get debugLabelColour => isStale ? Colors.grey : Colors.black87;

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

