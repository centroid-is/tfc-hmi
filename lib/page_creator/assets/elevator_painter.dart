import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'elevator_layout.dart';

// ---------------------------------------------------------------------------
// Elevator painter — rails + platform deck, no children, no shaft cage.
//
// Painter is PURE — primitives in (progress notifier, isStale, colour),
// pixels out. ZERO subscriptions, ZERO Riverpod, ZERO state. Locked by
// PITFALLS Pitfall 2 + ARCHITECTURE Pattern 3.
//
// Children are NOT painted here — they are positioned in a Stack overlay
// by the Elevator widget (Plan 02-04 + Phase 3). This painter is rails +
// deck only. Locked by ARCHITECTURE.md §Component Responsibilities and
// Anti-Pattern 1 (no switching on child type in elevator layout code).
// ---------------------------------------------------------------------------

/// Stroke width of vertical rails (× shortestSide).
const double kRailStrokeFraction = 0.04;

/// Platform-deck height (× bboxHeight) — 8% per CONTEXT specifics.
const double kPlatformHeightFraction = 0.08;

/// Rails horizontal inset: left rail at 10% width, right rail at 90%.
const double kLeftRailFraction = 0.10;
const double kRightRailFraction = 0.90;

/// Default render colour when active (test fixture default; widgets
/// override per Theme.colorScheme.primary in Plan 02-04).
const Color _kDefaultActive = Color(0xFF1976D2); // Material blue 700

/// Stale render colour. Mirrors sensor convention which mirrors
/// conveyor_gate.dart:325.
const Color _kStaleColor = Color(0xFF9E9E9E); // Colors.grey shade500

class ElevatorPainter extends CustomPainter {
  /// Live progress 0..1, tween-driven by the widget. Painter rebuilds
  /// scoped to this notifier via super(repaint:).
  final ValueListenable<double> progress;

  /// When true, render rails and deck in [_kStaleColor] regardless of
  /// `activeColor`. Closes ELEV-14.
  final bool isStale;

  /// Active render colour for rails + deck. Defaults to a fixed test
  /// fixture; widget passes Theme.colorScheme.primary at runtime.
  final Color activeColor;

  ElevatorPainter({
    required this.progress,
    this.isStale = false,
    this.activeColor = _kDefaultActive,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final colour = isStale ? _kStaleColor : activeColor;
    final shortest = size.shortestSide;
    final railStroke = shortest * kRailStrokeFraction;

    final leftRailX = size.width * kLeftRailFraction;
    final rightRailX = size.width * kRightRailFraction;

    // Rails — two vertical lines flanking the platform.
    final railPaint = Paint()
      ..color = colour
      ..strokeWidth = railStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(leftRailX, 0),
      Offset(leftRailX, size.height),
      railPaint,
    );
    canvas.drawLine(
      Offset(rightRailX, 0),
      Offset(rightRailX, size.height),
      railPaint,
    );

    // Platform deck — filled rectangle inset from rails by half rail-stroke.
    final platformHeight = size.height * kPlatformHeightFraction;
    final dy = platformOffsetTop(
      progress.value.clamp(0.0, 1.0),
      size.height,
      platformHeight,
    );

    // Inset slightly past each rail's outer edge (visually ON the rails).
    final platformLeft = leftRailX - railStroke * 0.5;
    final platformRight = rightRailX + railStroke * 0.5;

    final deckRect = Rect.fromLTWH(
      platformLeft,
      dy,
      platformRight - platformLeft,
      platformHeight,
    );
    final deckPaint = Paint()..color = colour;
    canvas.drawRect(deckRect, deckPaint);

    // Optional thin border to make the deck readable when colour
    // matches a busy background (defence in depth for stale → grey).
    final deckBorder = Paint()
      ..color = colour.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = railStroke * 0.5;
    canvas.drawRect(deckRect, deckBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) {
    if (old.runtimeType != runtimeType) return true;
    final o = old as ElevatorPainter;
    return !identical(progress, o.progress) ||
        isStale != o.isStale ||
        activeColor != o.activeColor;
  }
}
