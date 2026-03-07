import 'dart:math';

import 'package:flutter/material.dart';

import 'package:tfc/page_creator/assets/conveyor_gate.dart';

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

  static const _cylinderColor = Color(0xFF9E9E9E);
  static const _rodColor = Color(0xFFBDBDBD);
  static const _cylinderDarkShade = Color(0xFF757575);

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
    final rodX = side == GateSide.left
        ? cylinderX + cylinderWidth / 2 - rodDiameter / 2
        : cylinderX + cylinderWidth / 2 - rodDiameter / 2;
    final rodStartY = cylinderY + cylinderHeight;
    final rodEndY = rodStartY + rodExtension;

    // ── 1. Draw cylinder body (always metallic grey) ──
    final cylinderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(cylinderX, cylinderY, cylinderWidth, cylinderHeight),
      const Radius.circular(3.0),
    );
    canvas.drawRRect(
      cylinderRect,
      Paint()..color = _cylinderColor,
    );
    // Subtle 3D shading on cylinder
    canvas.drawRRect(
      cylinderRect,
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
        ).createShader(cylinderRect.outerRect),
    );
    // Cylinder border
    canvas.drawRRect(
      cylinderRect,
      Paint()
        ..color = _cylinderDarkShade
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // ── 2. Draw extending rod ──
    final rodRect = Rect.fromLTWH(
      rodX,
      rodStartY,
      rodDiameter,
      rodExtension.clamp(1.0, double.infinity),
    );
    canvas.drawRect(rodRect, Paint()..color = _rodColor);
    canvas.drawRect(
      rodRect,
      Paint()
        ..color = _cylinderDarkShade.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
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
    final hingeDot = side == GateSide.left
        ? const Offset(0, 0)
        : const Offset(0, 0);
    canvas.drawCircle(
      Offset(hingeDot.dx, flapThickness / 2),
      flapThickness * 0.4,
      Paint()..color = _cylinderDarkShade,
    );
    canvas.drawCircle(
      Offset(hingeDot.dx, flapThickness / 2),
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
