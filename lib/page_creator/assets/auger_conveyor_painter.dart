import 'dart:math';
import 'package:flutter/material.dart';

/// Which end of the auger is the viewer-facing opening.
enum AugerOpenEnd { left, right }

/// A CustomPainter that renders an auger/screw conveyor in the same
/// industrial-flat style as the other HMI assets.
///
/// Both ends have an elliptical shape. The [openEnd] side draws the
/// ellipse on top with a shadow inside (looking into the pipe).
/// The far end's ellipse sits behind the body.
///
/// [pitchCount] controls how many screw flights ("shovels") are visible.
/// [phaseOffset] in radians animates the rotation (0→2π = one revolution).
class AugerConveyorPainter extends CustomPainter {
  final Color stateColor;
  final ValueNotifier<double> phaseNotifier;
  final bool showAuger;
  final int pitchCount;
  final AugerOpenEnd? openEnd;

  AugerConveyorPainter({
    required this.stateColor,
    required this.phaseNotifier,
    this.showAuger = true,
    this.pitchCount = 6,
    this.openEnd = AugerOpenEnd.right,
  }) : super(repaint: phaseNotifier);

  double get phaseOffset => phaseNotifier.value;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showAuger) {
      _paintFlatConveyor(canvas, size);
      return;
    }
    _paintAugerConveyor(canvas, size);
  }

  void _paintFlatConveyor(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final borderRadius = Radius.circular(size.shortestSide * 0.2);
    final rrect = RRect.fromRectAndRadius(rect, borderRadius);

    canvas.drawRRect(rrect, Paint()..color = stateColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintAugerConveyor(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final centerY = h / 2;
    final stroke = (h * 0.02).clamp(1.0, 3.0);

    // Geometry
    final tubeRadius = h * 0.45;
    final flightRadius = tubeRadius * 0.88;
    final shaftRadius = tubeRadius * 0.18;
    final capWidth = h * 0.18;

    // Body is inset on both sides for elliptical ends
    final bodyLeft = capWidth;
    final bodyRight = w - capWidth;

    // Derive shades from the state color
    final HSLColor hsl = HSLColor.fromColor(stateColor);
    final darkShade =
        hsl.withLightness((hsl.lightness * 0.35).clamp(0.0, 1.0)).toColor();
    final lightShade =
        hsl.withLightness((hsl.lightness * 0.55 + 0.35).clamp(0.0, 0.95))
            .toColor();

    // Ellipse rects for each end
    final leftCapRect = Rect.fromLTRB(bodyLeft - capWidth,
        centerY - tubeRadius, bodyLeft + capWidth, centerY + tubeRadius);
    final rightCapRect = Rect.fromLTRB(bodyRight - capWidth,
        centerY - tubeRadius, bodyRight + capWidth, centerY + tubeRadius);

    // ── 1. End cap ellipses (behind body) ──
    _paintEndCap(canvas, leftCapRect, stateColor, darkShade);
    _paintEndCap(canvas, rightCapRect, stateColor, darkShade);

    // ── 2. Body shape (with elliptical arcs at ends) ──
    final bodyRect =
        Rect.fromLTRB(bodyLeft, centerY - tubeRadius, bodyRight, centerY + tubeRadius);
    final bodyPath = Path();
    bodyPath.moveTo(bodyLeft, centerY - tubeRadius);
    bodyPath.lineTo(bodyRight, centerY - tubeRadius);
    bodyPath.arcTo(rightCapRect, -pi / 2, pi, false);
    bodyPath.lineTo(bodyLeft, centerY + tubeRadius);
    bodyPath.arcTo(leftCapRect, pi / 2, pi, false);
    bodyPath.close();

    canvas.drawPath(bodyPath, Paint()..color = stateColor);

    // Subtle cylindrical gradient
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.15),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(bodyRect),
    );

    // Clip screw internals to body shape
    canvas.save();
    canvas.clipPath(bodyPath);

    // ── 3. Back helix ──
    _paintHelix(
      canvas: canvas,
      bodyLeft: 0,
      bodyWidth: w,
      centerY: centerY,
      outerRadius: flightRadius,
      innerRadius: shaftRadius,
      color: darkShade.withValues(alpha: 0.35),
      strokeWidth: stroke,
      isFront: false,
    );

    // ── 4. Central shaft ──
    final shaftRect = Rect.fromLTRB(
        0, centerY - shaftRadius, w, centerY + shaftRadius);
    canvas.drawRect(
      shaftRect,
      Paint()..color = darkShade.withValues(alpha: 0.5),
    );
    canvas.drawLine(
      Offset(0, centerY - shaftRadius * 0.3),
      Offset(w, centerY - shaftRadius * 0.3),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..strokeWidth = stroke * 0.5,
    );
    final shaftEdgePaint = Paint()
      ..color = darkShade.withValues(alpha: 0.6)
      ..strokeWidth = stroke * 0.5;
    canvas.drawLine(Offset(0, centerY - shaftRadius),
        Offset(w, centerY - shaftRadius), shaftEdgePaint);
    canvas.drawLine(Offset(0, centerY + shaftRadius),
        Offset(w, centerY + shaftRadius), shaftEdgePaint);

    // ── 5. Front helix ──
    _paintHelix(
      canvas: canvas,
      bodyLeft: 0,
      bodyWidth: w,
      centerY: centerY,
      outerRadius: flightRadius,
      innerRadius: shaftRadius,
      color: darkShade,
      strokeWidth: stroke * 1.5,
      isFront: true,
    );

    // ── 6. Front helix filled ribbons ──
    _paintHelixRibbons(
      canvas: canvas,
      bodyLeft: 0,
      bodyWidth: w,
      centerY: centerY,
      outerRadius: flightRadius,
      innerRadius: shaftRadius,
      color: lightShade.withValues(alpha: 0.25),
    );

    canvas.restore();

    // ── 7. Body outline with elliptical arcs at both ends ──
    final outlinePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final outlinePath = Path();
    outlinePath.moveTo(bodyLeft, centerY - tubeRadius);
    outlinePath.lineTo(bodyRight, centerY - tubeRadius);
    // Right arc
    outlinePath.arcTo(rightCapRect, -pi / 2, pi, false);
    // Bottom line
    outlinePath.lineTo(bodyLeft, centerY + tubeRadius);
    // Left arc
    outlinePath.arcTo(leftCapRect, pi / 2, pi, false);

    canvas.drawPath(outlinePath, outlinePaint);

    // ── 8. Open-end ellipse on top (full border + tiny shadow) ──
    if (openEnd == AugerOpenEnd.left) {
      _paintOpenEndCap(canvas, leftCapRect, stateColor, darkShade);
    } else if (openEnd == AugerOpenEnd.right) {
      _paintOpenEndCap(canvas, rightCapRect, stateColor, darkShade);
    }
  }

  /// Open-end ellipse: full border with a tiny radial shadow inside.
  void _paintOpenEndCap(
      Canvas canvas, Rect capRect, Color fill, Color darkShade) {
    // Fill
    canvas.drawOval(
      capRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill, darkShade.withValues(alpha: 0.5)],
        ).createShader(capRect),
    );
    // Tiny shadow inside
    canvas.drawOval(
      capRect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            darkShade.withValues(alpha: 0.3),
            Colors.transparent,
          ],
        ).createShader(capRect),
    );
    // Border
    canvas.drawOval(
      capRect,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  /// End-cap ellipse: filled with state color gradient, drawn behind body.
  void _paintEndCap(
      Canvas canvas, Rect capRect, Color fill, Color darkShade) {
    canvas.drawOval(
      capRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fill,
            darkShade.withValues(alpha: 0.7),
          ],
        ).createShader(capRect),
    );
  }

  /// Draws a sinusoidal helix curve (outer edge) as a stroke path.
  void _paintHelix({
    required Canvas canvas,
    required double bodyLeft,
    required double bodyWidth,
    required double centerY,
    required double outerRadius,
    required double innerRadius,
    required Color color,
    required double strokeWidth,
    required bool isFront,
  }) {
    final pixelStep = 2.0;
    final totalSteps = (bodyWidth / pixelStep).ceil();
    if (totalSteps < 2) return;

    final path = Path();
    bool drawing = false;

    for (int i = 0; i <= totalSteps; i++) {
      final x = bodyLeft + (i / totalSteps) * bodyWidth;
      final t = (i / totalSteps) * pitchCount * 2 * pi + phaseOffset;
      final sinVal = sin(t);

      final visible = isFront ? sinVal >= 0 : sinVal < 0;

      if (visible) {
        final yOuter = centerY + outerRadius * sinVal;
        if (!drawing) {
          path.moveTo(x, yOuter);
          drawing = true;
        } else {
          path.lineTo(x, yOuter);
        }
      } else {
        drawing = false;
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Blade edges at zero crossings
    final bladePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (int p = 0; p <= pitchCount; p++) {
      for (int edge = 0; edge < 2; edge++) {
        final targetPhase = edge == 0 ? p * 2 * pi : p * 2 * pi + pi;
        final x = bodyLeft +
            ((targetPhase - phaseOffset) / (pitchCount * 2 * pi)) * bodyWidth;

        if (x < bodyLeft || x > bodyLeft + bodyWidth) continue;

        final isFrontEdge = edge == (isFront ? 0 : 1);
        if (!isFrontEdge) continue;

        canvas.drawLine(
          Offset(x, centerY - outerRadius),
          Offset(x, centerY - innerRadius),
          bladePaint,
        );
        canvas.drawLine(
          Offset(x, centerY + innerRadius),
          Offset(x, centerY + outerRadius),
          bladePaint,
        );
      }
    }
  }

  /// Fills the front-facing ribbon areas between outer and inner curves.
  void _paintHelixRibbons({
    required Canvas canvas,
    required double bodyLeft,
    required double bodyWidth,
    required double centerY,
    required double outerRadius,
    required double innerRadius,
    required Color color,
  }) {
    final pixelStep = 2.0;
    final totalSteps = (bodyWidth / pixelStep).ceil();
    if (totalSteps < 2) return;

    final outerPts = <Offset>[];
    final innerPts = <Offset>[];
    bool inSegment = false;

    for (int i = 0; i <= totalSteps; i++) {
      final x = bodyLeft + (i / totalSteps) * bodyWidth;
      final t = (i / totalSteps) * pitchCount * 2 * pi + phaseOffset;
      final sinVal = sin(t);

      if (sinVal >= 0) {
        outerPts.add(Offset(x, centerY + outerRadius * sinVal));
        innerPts.add(Offset(x, centerY + innerRadius * sinVal));
        inSegment = true;
      } else if (inSegment) {
        _fillRibbon(canvas, outerPts, innerPts, color);
        outerPts.clear();
        innerPts.clear();
        inSegment = false;
      }
    }
    if (inSegment && outerPts.length >= 2) {
      _fillRibbon(canvas, outerPts, innerPts, color);
    }
  }

  void _fillRibbon(Canvas canvas, List<Offset> outer, List<Offset> inner,
      Color color) {
    if (outer.length < 2) return;
    final path = Path();
    path.moveTo(outer.first.dx, outer.first.dy);
    for (int i = 1; i < outer.length; i++) {
      path.lineTo(outer[i].dx, outer[i].dy);
    }
    for (int i = inner.length - 1; i >= 0; i--) {
      path.lineTo(inner[i].dx, inner[i].dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant AugerConveyorPainter oldDelegate) =>
      oldDelegate.stateColor != stateColor ||
      oldDelegate.showAuger != showAuger ||
      oldDelegate.pitchCount != pitchCount ||
      oldDelegate.openEnd != openEnd;
}
