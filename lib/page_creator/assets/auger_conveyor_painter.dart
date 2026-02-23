import 'dart:math';
import 'package:flutter/material.dart';

enum AugerEndCaps { both, left, right, none }

/// A CustomPainter that renders a 3D auger/screw conveyor.
///
/// The auger is drawn as a cylindrical tube housing with a central shaft
/// and helical screw flights rendered as sinusoidal curves with metallic
/// 3D shading. The [phaseOffset] parameter drives the rotation animation.
class AugerConveyorPainter extends CustomPainter {
  /// State color for the conveyor (green=auto, blue=clean, etc.)
  final Color stateColor;

  /// Phase offset in radians — animate 0→2π for one full screw revolution.
  final double phaseOffset;

  /// Whether to show the auger screw (false = flat conveyor style).
  final bool showAuger;

  /// Number of visible screw pitches across the conveyor length.
  final int pitchCount;

  /// Which end caps to draw.
  final AugerEndCaps endCaps;

  AugerConveyorPainter({
    required this.stateColor,
    this.phaseOffset = 0.0,
    this.showAuger = true,
    this.pitchCount = 6,
    this.endCaps = AugerEndCaps.both,
    super.repaint,
  });

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

    // Geometry ratios
    final tubeRadius = h * 0.45;
    final flightRadius = tubeRadius * 0.92;
    final shaftRadius = tubeRadius * 0.22;
    final endCapWidth = w * 0.04; // elliptical end cap half-width
    final hasLeft = endCaps == AugerEndCaps.both || endCaps == AugerEndCaps.left;
    final hasRight = endCaps == AugerEndCaps.both || endCaps == AugerEndCaps.right;
    final bodyLeft = hasLeft ? endCapWidth : 0.0;
    final bodyRight = hasRight ? w - endCapWidth : w;
    final bodyWidth = bodyRight - bodyLeft;

    // ── 1. Back half of tube (dark steel) ──
    _paintTubeBack(canvas, bodyLeft, bodyRight, centerY, tubeRadius, endCapWidth);

    // ── 2. Back helix flights (dimmed, behind shaft) ──
    _paintHelixFlights(
      canvas: canvas,
      bodyLeft: bodyLeft,
      bodyWidth: bodyWidth,
      centerY: centerY,
      flightRadius: flightRadius,
      shaftRadius: shaftRadius,
      isFront: false,
    );

    // ── 3. Central shaft ──
    _paintShaft(canvas, bodyLeft, bodyRight, centerY, shaftRadius);

    // ── 4. Front helix flights (bright, in front of shaft) ──
    _paintHelixFlights(
      canvas: canvas,
      bodyLeft: bodyLeft,
      bodyWidth: bodyWidth,
      centerY: centerY,
      flightRadius: flightRadius,
      shaftRadius: shaftRadius,
      isFront: true,
    );

    // ── 5. Front half of tube (with state color tint + transparency) ──
    _paintTubeFront(canvas, bodyLeft, bodyRight, centerY, tubeRadius, endCapWidth, w, h);

    // ── 6. End caps ──
    if (hasLeft) {
      _paintEndCap(canvas, bodyLeft, centerY, tubeRadius, endCapWidth, isLeft: true);
    }
    if (hasRight) {
      _paintEndCap(canvas, bodyRight, centerY, tubeRadius, endCapWidth, isLeft: false);
    }

    // ── 7. Tube outline ──
    _paintTubeOutline(canvas, bodyLeft, bodyRight, centerY, tubeRadius, endCapWidth);
  }

  void _paintTubeBack(Canvas canvas, double left, double right, double centerY, double radius, double capW) {
    final backPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF505860),
          const Color(0xFF3A4048),
          const Color(0xFF505860),
        ],
      ).createShader(Rect.fromLTRB(left, centerY - radius, right, centerY + radius));

    final backRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(left, centerY - radius, right, centerY + radius),
      Radius.circular(2),
    );
    canvas.drawRRect(backRect, backPaint);
  }

  void _paintShaft(Canvas canvas, double left, double right, double centerY, double shaftRadius) {
    final shaftGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF808890),
        const Color(0xFFA0A8B0),
        const Color(0xFF606870),
        const Color(0xFF404848),
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );

    final shaftRect = Rect.fromLTRB(
      left, centerY - shaftRadius, right, centerY + shaftRadius,
    );

    canvas.drawRect(
      shaftRect,
      Paint()..shader = shaftGradient.createShader(shaftRect),
    );

    // Shaft highlight line
    canvas.drawLine(
      Offset(left, centerY - shaftRadius * 0.4),
      Offset(right, centerY - shaftRadius * 0.4),
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..strokeWidth = 1.0,
    );
  }

  void _paintHelixFlights({
    required Canvas canvas,
    required double bodyLeft,
    required double bodyWidth,
    required double centerY,
    required double flightRadius,
    required double shaftRadius,
    required bool isFront,
  }) {
    final steps = (bodyWidth * 1.5).toInt().clamp(100, 600);
    final dx = bodyWidth / steps;

    for (int pitch = 0; pitch < pitchCount; pitch++) {
      final pitchWidth = bodyWidth / pitchCount;
      final pitchStart = pitch * pitchWidth;

      // Each pitch draws one "ribbon" face of the helix
      // We draw half-pitches: 0→π is front-facing, π→2π is back-facing
      final halfSteps = (pitchWidth / dx).toInt();
      if (halfSteps < 2) continue;

      // Front face: phase 0→π, Back face: phase π→2π
      final startPhase = isFront ? 0.0 : pi;
      final endPhase = isFront ? pi : 2 * pi;

      final path = Path();
      final outerPoints = <Offset>[];
      final innerPoints = <Offset>[];

      for (int i = 0; i <= halfSteps; i++) {
        final t = i / halfSteps;
        final localPhase = startPhase + t * (endPhase - startPhase);
        final angle = localPhase + phaseOffset;
        final x = bodyLeft + pitchStart + t * pitchWidth;

        final yOuter = centerY + flightRadius * sin(angle);
        final yInner = centerY + shaftRadius * sin(angle);

        outerPoints.add(Offset(x, yOuter));
        innerPoints.add(Offset(x, yInner));
      }

      if (outerPoints.length < 2) continue;

      // Build the ribbon shape: outer edge forward, inner edge backward
      path.moveTo(outerPoints.first.dx, outerPoints.first.dy);
      for (int i = 1; i < outerPoints.length; i++) {
        path.lineTo(outerPoints[i].dx, outerPoints[i].dy);
      }
      for (int i = innerPoints.length - 1; i >= 0; i--) {
        path.lineTo(innerPoints[i].dx, innerPoints[i].dy);
      }
      path.close();

      // Shading: front faces are brighter, back faces are dimmer
      final baseColor = isFront
          ? const Color(0xFFA8B0B8)
          : const Color(0xFF606870);
      final highlightColor = isFront
          ? const Color(0xFFD0D8E0)
          : const Color(0xFF787878);

      // Gradient along the ribbon for curvature shading
      final ribbonRect = path.getBounds();
      final ribbonPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [highlightColor, baseColor, baseColor.withValues(alpha: 0.8)],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(ribbonRect);

      canvas.drawPath(path, ribbonPaint);

      // Draw outer edge highlight
      final edgePath = Path();
      edgePath.moveTo(outerPoints.first.dx, outerPoints.first.dy);
      for (int i = 1; i < outerPoints.length; i++) {
        edgePath.lineTo(outerPoints[i].dx, outerPoints[i].dy);
      }

      canvas.drawPath(
        edgePath,
        Paint()
          ..color = isFront
              ? const Color(0xFFE0E8F0)
              : const Color(0xFF888888)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isFront ? 1.5 : 0.8,
      );
    }
  }

  void _paintTubeFront(Canvas canvas, double left, double right,
      double centerY, double radius, double capW, double w, double h) {
    // Semi-transparent tube front with state color tint
    final tubeRect = Rect.fromLTRB(left, centerY - radius, right, centerY + radius);

    // Glass-like front: state color tinted, translucent
    final HSLColor hsl = HSLColor.fromColor(stateColor);
    final tintColor = hsl.withLightness((hsl.lightness * 0.7).clamp(0.0, 1.0)).toColor();

    // Top highlight strip
    canvas.drawRect(
      Rect.fromLTRB(left, centerY - radius, right, centerY - radius * 0.7),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tintColor.withValues(alpha: 0.35),
            tintColor.withValues(alpha: 0.08),
          ],
        ).createShader(tubeRect),
    );

    // Bottom shadow strip
    canvas.drawRect(
      Rect.fromLTRB(left, centerY + radius * 0.7, right, centerY + radius),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tintColor.withValues(alpha: 0.08),
            tintColor.withValues(alpha: 0.4),
          ],
        ).createShader(tubeRect),
    );

    // Specular highlight near top
    canvas.drawLine(
      Offset(left + capW, centerY - radius * 0.85),
      Offset(right - capW, centerY - radius * 0.85),
      Paint()
        ..color = const Color(0x30FFFFFF)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintEndCap(Canvas canvas, double x, double centerY, double radius,
      double capW, {required bool isLeft}) {
    final capRect = Rect.fromLTRB(
      x - capW, centerY - radius, x + capW, centerY + radius,
    );

    // Metallic end cap gradient
    final capGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFFB0B8C0),
        const Color(0xFF808890),
        const Color(0xFF606870),
      ],
    );

    canvas.drawOval(capRect, Paint()..shader = capGradient.createShader(capRect));
    canvas.drawOval(
      capRect,
      Paint()
        ..color = const Color(0xFF404040)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _paintTubeOutline(Canvas canvas, double left, double right,
      double centerY, double radius, double capW) {
    final outlinePaint = Paint()
      ..color = const Color(0xFF303030)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Top line
    canvas.drawLine(
      Offset(left, centerY - radius),
      Offset(right, centerY - radius),
      outlinePaint,
    );
    // Bottom line
    canvas.drawLine(
      Offset(left, centerY + radius),
      Offset(right, centerY + radius),
      outlinePaint,
    );
  }

  @override
  bool shouldRepaint(covariant AugerConveyorPainter oldDelegate) =>
      oldDelegate.stateColor != stateColor ||
      oldDelegate.phaseOffset != phaseOffset ||
      oldDelegate.showAuger != showAuger ||
      oldDelegate.pitchCount != pitchCount ||
      oldDelegate.endCaps != endCaps;
}
