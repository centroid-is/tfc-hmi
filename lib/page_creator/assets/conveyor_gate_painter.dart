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
  final rRect =
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height * 0.1));
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
  final rRect =
      RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide * 0.15));
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

    // Animation angle (includes small visual correction for asymmetric arm shape)
    final angle = openAngleDegrees * (pi / 180) * progress.value;
    final correction = 5.0 * (pi / 180);
    final signedAngle = -angle + correction;

    canvas.save();
    canvas.translate(hingeX, hingeY);
    canvas.rotate(signedAngle);

    // Direction: left hinge draws arm to the right, right hinge to the left
    final dir = side == GateSide.left ? 1.0 : -1.0;

    // Deflector arm: one edge straight (tapers from pivot to tip),
    // one edge concave (scoops inward).
    //
    // Left-hinged: top edge concave (scoops downward), bottom edge straight
    // Right-hinged: top edge straight, bottom edge concave (scoops upward)

    final path = Path();

    path.moveTo(0, -pivotRadius);

    if (side == GateSide.left) {
      // Top edge: concave scoop (scoops product downward)
      path.cubicTo(
        dir * armLength * 0.35, pivotRadius * 0.1,
        dir * armLength * 0.70, tipWidth * 0.5,
        dir * armLength, -tipWidth,
      );
    } else {
      // Top edge: straight taper
      path.lineTo(dir * armLength, -tipWidth);
    }

    // Rounded tip
    path.arcToPoint(
      Offset(dir * armLength, tipWidth),
      radius: Radius.circular(tipWidth),
      clockwise: dir > 0,
    );

    if (side == GateSide.left) {
      // Bottom edge: straight taper back to pivot
      path.lineTo(0, pivotRadius);
    } else {
      // Bottom edge: concave scoop (scoops product upward)
      path.cubicTo(
        dir * armLength * 0.70, -tipWidth * 0.5,
        dir * armLength * 0.35, -pivotRadius * 0.1,
        0, pivotRadius,
      );
    }

    // Pivot circle arc (through back side)
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
// Shared linear gate painting (actuator + rod + blade/lid)
// ---------------------------------------------------------------------------

/// Paints actuator + rod + blade at the rod tip.
///
/// Used by both [SliderGatePainter] (blade at 90° = horizontal lid) and
/// [PusherGatePainter] (blade at 0° = vertical pusher). The only visual
/// difference between slider and pusher is the blade angle.
void _paintLinearGate(
  Canvas canvas,
  Size size, {
  required Color stateColor,
  required GateSide side,
  required double slideProgress,
  double bladeAngleDegrees = 0.0,
  double bladeOffsetFraction = 0.0,
}) {
  final w = size.width;
  final h = size.height;

  final actuatorWidth = w * 0.30;
  final actuatorHeight = h * 0.18;
  final actuatorY = (h - actuatorHeight) / 2;
  final rodDiameter = actuatorHeight * 0.25;
  final rodCenterY = h * 0.5;

  // Minimum rod stub — always visible shaft from actuator
  final minStub = w * 0.05;
  final beltArea = w - actuatorWidth;
  final lidTravel = beltArea - minStub;
  final slideOffset = minStub + lidTravel * slideProgress;

  // Blade dimensions (before rotation)
  final bladeThickness = h * 0.08;
  final bladeHeight = h * 0.85;

  final double rodTipX;
  if (side == GateSide.left) {
    _drawCylinder(
        canvas, Rect.fromLTWH(0, actuatorY, actuatorWidth, actuatorHeight));
    _drawRod(
      canvas,
      Rect.fromLTWH(actuatorWidth, rodCenterY - rodDiameter / 2,
          slideOffset, rodDiameter),
    );
    rodTipX = actuatorWidth + slideOffset;
  } else {
    _drawCylinder(canvas,
        Rect.fromLTWH(w - actuatorWidth, actuatorY, actuatorWidth, actuatorHeight));
    rodTipX = w - actuatorWidth - slideOffset;
    _drawRod(
      canvas,
      Rect.fromLTWH(rodTipX, rodCenterY - rodDiameter / 2,
          slideOffset, rodDiameter),
    );
  }

  // Blade/lid at rod tip
  final bladeCenterY = h * 0.5 + h * bladeOffsetFraction;
  final sign = side == GateSide.left ? 1.0 : -1.0;
  canvas.save();
  canvas.translate(rodTipX, bladeCenterY);
  canvas.rotate(sign * bladeAngleDegrees * pi / 180);
  _drawLid(
    canvas,
    Rect.fromCenter(
      center: Offset.zero,
      width: bladeThickness,
      height: bladeHeight,
    ),
    stateColor,
  );
  canvas.restore();
}

// ---------------------------------------------------------------------------
// SliderGatePainter
// ---------------------------------------------------------------------------

/// Slider gate with actuator, connecting rod, and wide horizontal lid.
///
/// The lid slides horizontally to cover (closed) or reveal (open) the belt
/// area. Unlike the pusher which has a thin vertical blade, the slider draws
/// a wide rectangular plate.
class SliderGatePainter extends CustomPainter {
  final ValueNotifier<double> progress;
  final Color stateColor;
  final GateSide side;
  final bool activeOut;
  final double lidAngleDegrees;
  final double lidLengthFraction;

  SliderGatePainter({
    required this.progress,
    required this.stateColor,
    required this.side,
    this.activeOut = true,
    this.lidAngleDegrees = 0.0,
    this.lidLengthFraction = 0.55,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Apply activeOut inversion (same behavior as before)
    final p = activeOut ? progress.value : 1.0 - progress.value;

    // Actuator dimensions (consistent with pusher)
    final actuatorWidth = w * 0.30;
    final lidHeight = h * 0.15;
    final actuatorHeight = lidHeight;
    final actuatorY = (h - actuatorHeight) / 2;
    final rodDiameter = actuatorHeight * 0.25;
    final rodCenterY = h * 0.5;

    // Lid dimensions -- thin horizontal plate (the key difference from pusher)
    final lidWidth = w * lidLengthFraction;

    // Rod/lid travel calculation
    final minStub = w * 0.05;
    final beltArea = w - actuatorWidth;
    final lidTravel = beltArea - minStub - lidWidth;
    // p=0 (closed): lid at far end covering belt
    // p=1 (open): lid pulled toward actuator
    final lidOffset = minStub + lidTravel * p;

    if (side == GateSide.left) {
      // Actuator on left
      _drawCylinder(canvas, Rect.fromLTWH(0, actuatorY, actuatorWidth, actuatorHeight));

      // Rod from actuator to lid
      final rodEnd = actuatorWidth + lidOffset;
      _drawRod(canvas, Rect.fromLTWH(
        actuatorWidth, rodCenterY - rodDiameter / 2,
        lidOffset, rodDiameter,
      ));

      // Lid at rod end (optionally tilted by lidAngleDegrees)
      if (lidAngleDegrees != 0.0) {
        canvas.save();
        canvas.translate(rodEnd + lidWidth / 2, h / 2);
        canvas.rotate(lidAngleDegrees * pi / 180);
        _drawLid(canvas, Rect.fromCenter(
          center: Offset.zero,
          width: lidWidth,
          height: lidHeight,
        ), stateColor);
        canvas.restore();
      } else {
        _drawLid(canvas, Rect.fromLTWH(
          rodEnd, (h - lidHeight) / 2,
          lidWidth, lidHeight,
        ), stateColor);
      }
    } else {
      // Actuator on right (mirrored)
      _drawCylinder(canvas, Rect.fromLTWH(
        w - actuatorWidth, actuatorY, actuatorWidth, actuatorHeight,
      ));

      final rodStart = w - actuatorWidth - lidOffset;
      _drawRod(canvas, Rect.fromLTWH(
        rodStart, rodCenterY - rodDiameter / 2,
        lidOffset, rodDiameter,
      ));

      // Lid to the left of rod
      if (lidAngleDegrees != 0.0) {
        canvas.save();
        canvas.translate(rodStart - lidWidth / 2, h / 2);
        canvas.rotate(-lidAngleDegrees * pi / 180);
        _drawLid(canvas, Rect.fromCenter(
          center: Offset.zero,
          width: lidWidth,
          height: lidHeight,
        ), stateColor);
        canvas.restore();
      } else {
        _drawLid(canvas, Rect.fromLTWH(
          rodStart - lidWidth, (h - lidHeight) / 2,
          lidWidth, lidHeight,
        ), stateColor);
      }
    }
  }

  @override
  bool shouldRepaint(SliderGatePainter oldDelegate) =>
      stateColor != oldDelegate.stateColor ||
      side != oldDelegate.side ||
      activeOut != oldDelegate.activeOut ||
      lidAngleDegrees != oldDelegate.lidAngleDegrees ||
      lidLengthFraction != oldDelegate.lidLengthFraction;
}

// ---------------------------------------------------------------------------
// PusherGatePainter
// ---------------------------------------------------------------------------

/// Pusher gate = actuator + rod + vertical blade (0° default).
class PusherGatePainter extends CustomPainter {
  final ValueNotifier<double> progress;
  final Color stateColor;
  final GateSide side;
  final double bladeAngleDegrees;
  final double bladeOffsetFraction;

  PusherGatePainter({
    required this.progress,
    required this.stateColor,
    required this.side,
    this.bladeAngleDegrees = 0.0,
    this.bladeOffsetFraction = 0.0,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    _paintLinearGate(
      canvas,
      size,
      stateColor: stateColor,
      side: side,
      slideProgress: progress.value,
      bladeAngleDegrees: bladeAngleDegrees,
      bladeOffsetFraction: bladeOffsetFraction,
    );
  }

  @override
  bool shouldRepaint(PusherGatePainter oldDelegate) =>
      stateColor != oldDelegate.stateColor ||
      side != oldDelegate.side ||
      bladeAngleDegrees != oldDelegate.bladeAngleDegrees ||
      bladeOffsetFraction != oldDelegate.bladeOffsetFraction;
}
