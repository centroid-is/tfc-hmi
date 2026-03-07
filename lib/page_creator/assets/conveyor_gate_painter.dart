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

/// Draws a solid rectangular lid/plate with shading and border.
///
/// Used by the slider gate painter for the sliding lid element.
void _drawLid(Canvas canvas, Rect rect, Color color) {
  final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(2.0));
  // Fill with state color
  canvas.drawRRect(rRect, Paint()..color = color);
  // 3D shading
  canvas.drawRRect(
    rRect,
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
      ).createShader(rect),
  );
  // Border
  canvas.drawRRect(
    rRect,
    Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0,
  );
}

// ---------------------------------------------------------------------------
// PneumaticDiverterPainter
// ---------------------------------------------------------------------------

/// Paints a pneumatic diverter gate as a 2D top-down representation.
///
/// The gate is a hinged deflector arm with a concave scoop shape. The arm
/// has an asymmetric profile: one edge is concave (the "catching" side that
/// redirects product) and the other edge is convex (the outer edge).
///
/// No pneumatic actuator is drawn -- the diverter uses a pivot mechanism.
///
/// The [progress] ValueNotifier drives animation (0.0 = closed, 1.0 = open)
/// and is used as the repaint listenable for efficient frame updates.
///
/// [side] determines which edge the flap hinges from and which side is
/// concave:
/// - [GateSide.left]: hinge on the left, concave on top (scoops downward)
/// - [GateSide.right]: hinge on the right, concave on bottom (scoops upward)
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

    // Concave deflector arm: asymmetric profile where one edge scoops inward.
    // No actuator/cylinder -- just the diverter arm with pivot hub.

    final pivotRadius = h * 0.12; // large circle at hinge
    final tipWidth = h * 0.025; // narrow tip
    final armLength = w; // spans full belt width

    // Hinge point: the edge where the arm pivots, centered vertically
    final hingeX = side == GateSide.left ? 0.0 : w;
    final hingeY = h * 0.5;

    // Animation angle
    final angle = openAngleDegrees * (pi / 180) * progress.value;
    final signedAngle = side == GateSide.left ? -angle : angle;

    canvas.save();
    canvas.translate(hingeX, hingeY);
    canvas.rotate(signedAngle);

    // Direction: left hinge draws arm to the right, right hinge to the left
    final dir = side == GateSide.left ? 1.0 : -1.0;

    // Build asymmetric deflector arm path:
    // - Concave edge: curves inward (the catching/scooping side)
    // - Convex edge: curves outward (the outer/back side)
    //
    // For left-hinged gates: top edge is concave (scoops product downward)
    // For right-hinged gates: bottom edge is concave (scoops product upward)
    // This is handled by swapping which edge gets which curve shape.

    final path = Path();

    // Start at top of pivot circle
    path.moveTo(0, -pivotRadius);

    if (side == GateSide.left) {
      // Left hinge: top edge = concave (scoop), bottom edge = convex (outer)

      // Top edge (CONCAVE): pulls inward toward arm centerline
      path.cubicTo(
        dir * armLength * 0.25, -pivotRadius * 0.3, // ctrl1: pull inward quickly
        dir * armLength * 0.65, -tipWidth * 1.2, // ctrl2: gentle approach to tip
        dir * armLength, -tipWidth, // end: narrow tip top
      );
    } else {
      // Right hinge: top edge = convex (outer), bottom edge = concave (scoop)

      // Top edge (CONVEX): bulges outward away from arm centerline
      path.cubicTo(
        dir * armLength * 0.30, -pivotRadius * 1.3, // ctrl1: push outward
        dir * armLength * 0.60, -tipWidth * 3.0, // ctrl2: wide curve
        dir * armLength, -tipWidth, // end: narrow tip top
      );
    }

    // Rounded tip
    path.arcToPoint(
      Offset(dir * armLength, tipWidth),
      radius: Radius.circular(tipWidth),
      clockwise: dir > 0,
    );

    if (side == GateSide.left) {
      // Left hinge: bottom edge = convex (outer, bulges outward)
      path.cubicTo(
        dir * armLength * 0.60, tipWidth * 3.0, // ctrl1: push outward
        dir * armLength * 0.30, pivotRadius * 1.3, // ctrl2: wide curve
        0, pivotRadius, // end: back to pivot
      );
    } else {
      // Right hinge: bottom edge = concave (scoop, pulls inward)
      path.cubicTo(
        dir * armLength * 0.65, tipWidth * 1.2, // ctrl1: pull inward
        dir * armLength * 0.25, pivotRadius * 0.3, // ctrl2: quick approach
        0, pivotRadius, // end: back to pivot
      );
    }

    // Close with pivot circle arc
    path.arcToPoint(
      Offset(0, -pivotRadius),
      radius: Radius.circular(pivotRadius),
      clockwise: dir > 0,
    );

    path.close();

    // Fill
    canvas.drawPath(path, Paint()..color = stateColor);

    // Border
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Shading for depth
    final bounds = path.getBounds();
    canvas.drawPath(
      path,
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
        ).createShader(bounds),
    );

    // Pivot circle: metallic hub at hinge point
    canvas.drawCircle(
      Offset.zero,
      pivotRadius * 0.6,
      Paint()..color = _cylinderDarkShade,
    );
    canvas.drawCircle(
      Offset.zero,
      pivotRadius * 0.4,
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
/// 1. An elongated, thin pneumatic actuator cylinder on one side
/// 2. A rod connecting the actuator to a solid sliding lid
/// 3. A solid rectangular lid that covers the belt opening
///
/// At [progress] = 0 (closed): lid covers the belt area.
/// At [progress] = 1 (open): lid has slid away from belt, pushed by actuator.
///
/// The lid slides as a solid piece -- it does NOT retract into the actuator.
///
/// [side] determines which edge the actuator sits on:
/// - [GateSide.left]: actuator on the left, lid covers right portion
/// - [GateSide.right]: actuator on the right, lid covers left portion
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

    // Elongated thin actuator + rod + solid lid layout.
    //
    // Left-side layout: [Actuator] --- [Rod] --- [Lid]
    // Actuator: elongated and thin (w * 0.30 wide, h * 0.18 tall)
    // Rod: thin connector between actuator and lid
    // Lid: solid rectangular plate (h * 0.08 thick, h * 0.85 tall)

    final actuatorWidth = w * 0.30;
    final actuatorHeight = h * 0.18;
    final actuatorY = (h - actuatorHeight) / 2;

    final rodDiameter = actuatorHeight * 0.25;
    final rodCenterY = h * 0.5;

    final lidThickness = h * 0.08;
    final lidHeight = h * 0.85;
    final lidY = (h - lidHeight) / 2;

    // Belt area = space beyond the actuator where the lid operates
    final beltArea = w - actuatorWidth;

    // The lid slides: at progress=0 it covers the belt edge,
    // at progress=1 it has slid away from the belt.
    final lidTravel = beltArea;
    final slideOffset = lidTravel * progress.value;

    if (side == GateSide.left) {
      // Actuator on the left
      _drawCylinder(
        canvas,
        Rect.fromLTWH(0, actuatorY, actuatorWidth, actuatorHeight),
      );

      // Lid position: starts at belt area (right of actuator), slides further right
      final lidX = actuatorWidth + slideOffset;

      // Rod: connects actuator right edge to lid left edge
      final rodStart = actuatorWidth;
      final rodEnd = lidX;
      final rodLength = (rodEnd - rodStart).clamp(0.0, double.infinity);
      if (rodLength > 0) {
        _drawRod(
          canvas,
          Rect.fromLTWH(
            rodStart,
            rodCenterY - rodDiameter / 2,
            rodLength,
            rodDiameter,
          ),
        );
      }

      // Solid lid
      _drawLid(
        canvas,
        Rect.fromLTWH(lidX, lidY, lidThickness, lidHeight),
        stateColor,
      );
    } else {
      // Actuator on the right
      _drawCylinder(
        canvas,
        Rect.fromLTWH(w - actuatorWidth, actuatorY, actuatorWidth, actuatorHeight),
      );

      // Lid position: starts at belt area (left of actuator), slides further left
      final lidX = (w - actuatorWidth - lidThickness) - slideOffset;

      // Rod: connects actuator left edge to lid right edge
      final rodEnd = w - actuatorWidth;
      final rodStart = lidX + lidThickness;
      final rodLength = (rodEnd - rodStart).clamp(0.0, double.infinity);
      if (rodLength > 0) {
        _drawRod(
          canvas,
          Rect.fromLTWH(
            rodStart,
            rodCenterY - rodDiameter / 2,
            rodLength,
            rodDiameter,
          ),
        );
      }

      // Solid lid
      _drawLid(
        canvas,
        Rect.fromLTWH(lidX, lidY, lidThickness, lidHeight),
        stateColor,
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
/// 1. An elongated, thin metallic grey cylinder body on one side
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

    // Elongated thin actuator proportions:
    // - Cylinder body: w * 0.30 width, h * 0.22 height (longer and thinner)
    // - Rod: extends from cylinder center, diameter ~15% of cylinder height
    // - Blade: wide (~85% of width when fully extended), thickness ~12% of height

    final cylinderWidth = w * 0.30;
    final cylinderHeight = h * 0.22;
    final cylinderY = (h - cylinderHeight) / 2;

    final rodDiameter = cylinderHeight * 0.18;
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
