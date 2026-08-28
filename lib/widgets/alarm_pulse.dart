/// The alarm pulse, as painters.
///
/// One drawing, two places: the Alarm beacon asset an operator drops on a
/// mimic page ([AlarmPulsePainter] at asset size), and the badge the
/// navigation bar puts on a page's icon when an alarm fires on a page nobody
/// is looking at ([AlarmPulsePainter] at badge size). They must read as the
/// same signal, so they are the same painter rather than two look-alikes that
/// drift apart.
///
/// Painters live here, outside `page_creator/`, so the app shell can draw the
/// pulse without importing the asset library.
library;

import 'dart:math' show min;

import 'package:flutter/material.dart';

/// The active pulse: a solid centre dot plus [rings] concentric rings that
/// expand from the dot to the edge and fade out, staggered evenly in phase so
/// one ring is always mid-flight.
///
/// [progress] is the animation phase in [0, 1); the painter is pure so a
/// static frame (palette thumbnail, config preview, goldens) is just a fixed
/// progress value.
///
/// Takes the alarm system's (background, foreground) pair from
/// `alarmLevelColors`. The rings and the dot fill carry [color] — the
/// container role the alarm card is painted in, i.e. the colour operators
/// already read as "this alarm" (Solarized: yellow warning, red error). The
/// dot is outlined in [dotOutlineColor] for definition. The rings must NOT use
/// the foreground role: it is chosen for contrast against the card surface,
/// not the page — in the Solarized light theme it is the same cream as the
/// scaffold, which made the rings vanish.
class AlarmPulsePainter extends CustomPainter {
  final Color color;
  final Color dotOutlineColor;
  final double progress;
  final int rings;

  /// Centre dot radius as a fraction of the drawing's radius.
  ///
  /// The default suits the beacon, which is drawn at asset size. A badge is an
  /// order of magnitude smaller, and the same fraction there puts the dot
  /// under two pixels across — it has to claim proportionally more of a small
  /// drawing to stay a dot at all.
  final double dotRadiusFactor;

  /// Width of the outline separating the dot from what is behind it, in
  /// pixels — it is a separator, so it does not scale with the drawing.
  ///
  /// It does have to stay thinner than the dot it outlines, though: at badge
  /// size the beacon's 2 px stroke is wider than the dot's diameter and eats
  /// it, leaving a hollow smudge instead of an alarm.
  final double dotOutlineWidth;

  AlarmPulsePainter({
    required this.color,
    required this.dotOutlineColor,
    required this.progress,
    this.rings = 3,
    this.dotRadiusFactor = 0.22,
    this.dotOutlineWidth = 2.0,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2;
    final dotRadius = maxRadius * dotRadiusFactor;

    for (var i = 0; i < rings; i++) {
      final t = (progress + i / rings) % 1.0;
      // Linear fade: quadratic killed the ring before it reached the edge,
      // so the expansion — the whole point of the beacon — went unseen.
      final fade = (1 - t) * 0.9;
      final paint = Paint()
        ..color = color.withValues(alpha: fade)
        ..style = PaintingStyle.stroke
        // Rings thin out as they expand — reads as energy dissipating.
        ..strokeWidth = 1.0 + 3.0 * (1 - t);
      canvas.drawCircle(
        center,
        dotRadius + (maxRadius - dotRadius) * t,
        paint,
      );
    }

    canvas.drawCircle(
      center,
      dotRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      dotRadius,
      Paint()
        ..color = dotOutlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = dotOutlineWidth,
    );
  }

  @override
  bool shouldRepaint(AlarmPulsePainter oldDelegate) =>
      color != oldDelegate.color ||
      dotOutlineColor != oldDelegate.dotOutlineColor ||
      progress != oldDelegate.progress ||
      rings != oldDelegate.rings ||
      dotRadiusFactor != oldDelegate.dotRadiusFactor ||
      dotOutlineWidth != oldDelegate.dotOutlineWidth;
}

/// The idle marker: a small dot inside a thin outline ring. Faint on purpose —
/// an inactive alarm must not compete with live process graphics, it only has
/// to be findable (and tappable, to read what the beacon watches).
class AlarmIdlePainter extends CustomPainter {
  final Color color;

  /// Outer ring radius as a fraction of the drawing's radius (`min(w,h)/2`).
  ///
  /// This is the marker's visible extent, so it also defines how big a tap
  /// target the idle beacon offers: `AlarmVisibility` sizes its hit region
  /// from the same factor (`maxRadius * outerRingFactor`, floored at a
  /// finger-sized minimum) so the two never drift apart. Keep them tied — a
  /// hit area much larger than the drawing is an invisible click target over
  /// empty space, which is exactly what this factor is here to prevent.
  static const double outerRingFactor = 0.4;

  AlarmIdlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, maxRadius * outerRingFactor, paint);
    canvas.drawCircle(
      center,
      maxRadius * 0.12,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(AlarmIdlePainter oldDelegate) =>
      color != oldDelegate.color;
}
