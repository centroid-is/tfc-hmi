import 'dart:math';

import 'package:flutter/material.dart';

import 'package:tfc/page_creator/assets/conveyor_gate.dart';

// ---------------------------------------------------------------------------
// Shared metallic cylinder colors used by all gate painters.
// ---------------------------------------------------------------------------
const _cylinderColor = Color(0xFF9E9E9E);
const _rodColor = Color(0xFFBDBDBD);
const _cylinderDarkShade = Color(0xFF757575);

/// Draws a metallic cylinder body with 3D shading and border.
///
/// Shared by all three gate painters. The cylinder represents the pneumatic
/// or hydraulic actuator housing in a 2D top-down HMI view.
void _drawCylinder(Canvas canvas, Rect rect) {
  final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(3.0));
  // Fill
  canvas.drawRRect(rRect, Paint()..color = _cylinderColor);
  // 3D shading
  canvas.drawRRect(
    rRect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.2),
          Colors.transparent,
          _cylinderDarkShade.withValues(alpha: 0.3),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(rect),
  );
  // Border
  canvas.drawRRect(
    rRect,
    Paint()
      ..color = _cylinderDarkShade
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0,
  );
}

/// Draws a rod extending from a cylinder.
///
/// The rod represents the piston rod that connects the cylinder actuator
/// to the moving gate element.
void _drawRod(Canvas canvas, Rect rect) {
  canvas.drawRect(rect, Paint()..color = _rodColor);
  canvas.drawRect(
    rect,
    Paint()
      ..color = _cylinderDarkShade.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5,
  );
}

// ---------------------------------------------------------------------------
// PneumaticDiverterPainter
// ---------------------------------------------------------------------------

/// Paints a pneumatic diverter gate as a 2D top-down representation.
///
/// The gate consists of three visual elements:
/// 1. A metallic grey cylinder body (pneumatic actuator) at the top
/// 2. A rod extending from the cylinder, length proportional to [progress]
/// 3. A hinged flap that swings open/closed, filled with [stateColor]
///
/// The [progress] ValueNotifier drives animation (0.0 = closed, 1.0 = open)
/// and is used as the repaint listenable for efficient frame updates.
///
/// [side] determines which edge the flap hinges from:
/// - [GateSide.left]: hinge on the left edge
/// - [GateSide.right]: hinge on the right edge (geometry mirrored)
class PneumaticDiverterPainter extends CustomPainter {
  final ValueNotifier<double> progress;
  final Color stateColor;
  final double openAngleDegrees;
  final GateSide side;

  PneumaticDiverterPainter({
    required this.progress,
    required this.stateColor,
    required this.openAngleDegrees,
    required this.side,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Proportions (Claude's discretion for 2D top-down HMI):
    // The gate is viewed from above looking down at a conveyor belt.
    // The flap spans the belt width horizontally and swings open.
    // The cylinder sits at one edge, perpendicular to the flap.

    final cylinderHeight = h * 0.15;
    final cylinderWidth = w * 0.25;
    final rodDiameter = cylinderHeight * 0.3;
    final flapThickness = h * 0.08;
    final flapLength = w; // spans full belt width

    // Hinge point: the edge where the flap pivots
    final hingeX = side == GateSide.left ? 0.0 : w;
    final flapY = h * 0.55; // flap sits in the lower portion

    // Animation angle: 0 at closed, openAngleDegrees at fully open
    final angle = openAngleDegrees * (pi / 180) * progress.value;
    // Sign depends on side: left hinge swings clockwise (positive),
    // right hinge swings counter-clockwise (negative from its perspective)
    final signedAngle = side == GateSide.left ? -angle : angle;

    // Cylinder position: above the hinge point, offset inward
    final cylinderX = side == GateSide.left
        ? 0.0
        : w - cylinderWidth;
    final cylinderY = flapY - cylinderHeight - h * 0.05;

    // Rod extends from cylinder toward the flap.
    // At progress=0 (closed), rod is retracted. At progress=1 (open), rod is extended.
    final rodMaxExtension = cylinderHeight * 0.8;
    final rodExtension = rodMaxExtension * progress.value;
    final rodX = cylinderX + cylinderWidth / 2 - rodDiameter / 2;
    final rodStartY = cylinderY + cylinderHeight;

    // ── 1. Draw cylinder body (always metallic grey) ──
    _drawCylinder(
      canvas,
      Rect.fromLTWH(cylinderX, cylinderY, cylinderWidth, cylinderHeight),
    );

    // ── 2. Draw extending rod ──
    _drawRod(
      canvas,
      Rect.fromLTWH(
        rodX,
        rodStartY,
        rodDiameter,
        rodExtension.clamp(1.0, double.infinity),
      ),
    );

    // ── 3. Draw hinged flap ──
    canvas.save();

    // Translate to hinge point, rotate, then draw the flap
    canvas.translate(hingeX, flapY);
    canvas.rotate(signedAngle);

    // Flap extends from hinge point outward
    final flapRect = side == GateSide.left
        ? Rect.fromLTWH(0, 0, flapLength, flapThickness)
        : Rect.fromLTWH(-flapLength, 0, flapLength, flapThickness);

    // Flap fill
    final flapRRect = RRect.fromRectAndRadius(flapRect, const Radius.circular(2.0));
    canvas.drawRRect(flapRRect, Paint()..color = stateColor);

    // Flap border
    canvas.drawRRect(
      flapRRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Flap shading for depth
    canvas.drawRRect(
      flapRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.1),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(flapRect),
    );

    // Hinge circle indicator
    canvas.drawCircle(
      Offset(0, flapThickness / 2),
      flapThickness * 0.4,
      Paint()..color = _cylinderDarkShade,
    );
    canvas.drawCircle(
      Offset(0, flapThickness / 2),
      flapThickness * 0.25,
      Paint()..color = _cylinderColor,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(PneumaticDiverterPainter oldDelegate) =>
      stateColor != oldDelegate.stateColor ||
      openAngleDegrees != oldDelegate.openAngleDegrees ||
      side != oldDelegate.side;
}

// ---------------------------------------------------------------------------
// SliderGatePainter
// ---------------------------------------------------------------------------

/// Paints a slider gate as a 2D top-down representation.
///
/// The gate consists of:
/// 1. A metallic grey cylinder body on one side (~25% width)
/// 2. A horizontal plate that slides sideways from the cylinder
///
/// At [progress] = 0 (closed): plate covers the full belt opening.
/// At [progress] = 1 (open): plate retracted into the cylinder side.
///
/// [side] determines which edge the cylinder sits on:
/// - [GateSide.left]: cylinder on the left, plate slides right-to-left to retract
/// - [GateSide.right]: cylinder on the right, plate slides left-to-right to retract
class SliderGatePainter extends CustomPainter {
  final ValueNotifier<double> progress;
  final Color stateColor;
  final GateSide side;

  SliderGatePainter({
    required this.progress,
    required this.stateColor,
    required this.side,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Proportions:
    // - Cylinder body: ~25% of width, ~60% of height, centered vertically
    // - Plate: slides across belt opening from cylinder side
    // - Plate thickness: ~10% of height, centered vertically at ~55%

    final cylinderWidth = w * 0.25;
    final cylinderHeight = h * 0.60;
    final cylinderY = (h - cylinderHeight) / 2;

    final plateThickness = h * 0.10;
    final plateY = h * 0.55 - plateThickness / 2;

    // Maximum plate extension = belt opening (width minus cylinder)
    final beltOpening = w - cylinderWidth;
    // At progress=0 (closed): plate covers full opening
    // At progress=1 (open): plate retracted (zero extension)
    final plateExtension = beltOpening * (1.0 - progress.value);

    if (side == GateSide.left) {
      // Cylinder on the left
      _drawCylinder(
        canvas,
        Rect.fromLTWH(0, cylinderY, cylinderWidth, cylinderHeight),
      );

      // Plate extends from right edge of cylinder toward the right
      final plateX = cylinderWidth;
      final plateRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(plateX, plateY, plateExtension.clamp(1.0, double.infinity), plateThickness),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(plateRect, Paint()..color = stateColor);
      canvas.drawRRect(
        plateRect,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // Plate shading
      canvas.drawRRect(
        plateRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.15),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.1),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(plateRect.outerRect),
      );
    } else {
      // Cylinder on the right
      _drawCylinder(
        canvas,
        Rect.fromLTWH(w - cylinderWidth, cylinderY, cylinderWidth, cylinderHeight),
      );

      // Plate extends from left edge of cylinder toward the left
      final plateRight = w - cylinderWidth;
      final plateX = plateRight - plateExtension;
      final plateRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(plateX.clamp(0.0, double.infinity), plateY, plateExtension.clamp(1.0, double.infinity), plateThickness),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(plateRect, Paint()..color = stateColor);
      canvas.drawRRect(
        plateRect,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // Plate shading
      canvas.drawRRect(
        plateRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.15),
              Colors.transparent,
              Colors.black.withValues(alpha: 0.1),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(plateRect.outerRect),
      );
    }
  }

  @override
  bool shouldRepaint(SliderGatePainter oldDelegate) =>
      stateColor != oldDelegate.stateColor ||
      side != oldDelegate.side;
}

// ---------------------------------------------------------------------------
// PusherGatePainter
// ---------------------------------------------------------------------------

/// Paints a pusher gate as a 2D top-down representation.
///
/// The gate consists of:
/// 1. A metallic grey cylinder body on one side (~20% width)
/// 2. A rod extending from the cylinder proportional to [progress]
/// 3. A wide blade (snow-plow style) at the tip of the rod
///
/// At [progress] = 0 (closed): blade retracted, belt clear.
/// At [progress] = 1 (open): blade fully extended across belt (~85% width).
///
/// "Open" means actively diverting (blade extended). "Closed" means clear path.
///
/// [side] determines which edge the cylinder sits on:
/// - [GateSide.left]: cylinder on left, blade pushes toward right
/// - [GateSide.right]: cylinder on right, blade pushes toward left
class PusherGatePainter extends CustomPainter {
  final ValueNotifier<double> progress;
  final Color stateColor;
  final GateSide side;

  PusherGatePainter({
    required this.progress,
    required this.stateColor,
    required this.side,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Proportions:
    // - Cylinder body: ~20% of width, ~40% of height, centered vertically
    // - Rod: extends from cylinder center, diameter ~15% of cylinder height
    // - Blade: wide (~85% of width when fully extended), thickness ~12% of height

    final cylinderWidth = w * 0.20;
    final cylinderHeight = h * 0.40;
    final cylinderY = (h - cylinderHeight) / 2;

    final rodDiameter = cylinderHeight * 0.15;
    final rodCenterY = h * 0.50;

    final bladeWidth = h * 0.12;
    final bladeMaxExtension = w * 0.85;
    final bladeExtension = bladeMaxExtension * progress.value;

    // Rod length = how far from cylinder edge to blade front
    final rodLength = bladeExtension;

    if (side == GateSide.left) {
      // Cylinder on the left
      _drawCylinder(
        canvas,
        Rect.fromLTWH(0, cylinderY, cylinderWidth, cylinderHeight),
      );

      // Rod extends from right edge of cylinder
      if (rodLength > 0) {
        _drawRod(
          canvas,
          Rect.fromLTWH(
            cylinderWidth,
            rodCenterY - rodDiameter / 2,
            rodLength.clamp(1.0, double.infinity),
            rodDiameter,
          ),
        );
      }

      // Blade at rod tip (perpendicular to rod, i.e., vertical bar)
      if (progress.value > 0.01) {
        final bladeX = cylinderWidth + bladeExtension - bladeWidth / 2;
        final bladeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(bladeX, h * 0.10, bladeWidth, h * 0.80),
          const Radius.circular(2.0),
        );
        canvas.drawRRect(bladeRect, Paint()..color = stateColor);
        canvas.drawRRect(
          bladeRect,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        // Blade shading
        canvas.drawRRect(
          bladeRect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withValues(alpha: 0.15),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.1),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bladeRect.outerRect),
        );
      }
    } else {
      // Cylinder on the right
      _drawCylinder(
        canvas,
        Rect.fromLTWH(w - cylinderWidth, cylinderY, cylinderWidth, cylinderHeight),
      );

      // Rod extends from left edge of cylinder toward the left
      if (rodLength > 0) {
        _drawRod(
          canvas,
          Rect.fromLTWH(
            (w - cylinderWidth - rodLength).clamp(0.0, double.infinity),
            rodCenterY - rodDiameter / 2,
            rodLength.clamp(1.0, double.infinity),
            rodDiameter,
          ),
        );
      }

      // Blade at rod tip
      if (progress.value > 0.01) {
        final bladeX = w - cylinderWidth - bladeExtension - bladeWidth / 2;
        final bladeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(bladeX, h * 0.10, bladeWidth, h * 0.80),
          const Radius.circular(2.0),
        );
        canvas.drawRRect(bladeRect, Paint()..color = stateColor);
        canvas.drawRRect(
          bladeRect,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        // Blade shading
        canvas.drawRRect(
          bladeRect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withValues(alpha: 0.15),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.1),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bladeRect.outerRect),
        );
      }
    }
  }

  @override
  bool shouldRepaint(PusherGatePainter oldDelegate) =>
      stateColor != oldDelegate.stateColor ||
      side != oldDelegate.side;
}
