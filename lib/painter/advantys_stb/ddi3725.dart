// STBDDI3725 body painter + widget — Schneider Advantys STB 16-channel DI.
//
// Layout follows `.planning/research/photos/DDI3725_front_clean.png` (canonical
// for terminal-block geometry — the DXF at
// `.planning/research/dxf/IO_BASE_DDI3725_DDO3705_mcadid0005033.dxf` is
// inaccurate for the terminal blocks per CONTEXT.md).
//
// Vertical regions, top-to-bottom (fractions of `size.height`):
//   1. Top blue label strip (~7%) — Schneider blue background, "DDI3725"
//      label in white + small RDY indicator dot on the right.
//   2. LED block (~22%) — delegates to `IO16LedBlockPainter` from `io16.dart`.
//      Renders the 2×8 column-major LED grid.
//   3. Bottom blue accent strip (~2.5%) — visual separator above the
//      terminal blocks.
//   4. Dual terminal blocks (remainder) — 2 columns × 18 rows of dark-grey
//      squares + wire-hole circles. Column labels "A" / "B" sit above each
//      column. Mirror the IO8 single-block style but scaled to 16-ch.
//
// Aspect ratio: `width = height * (107 / 152)`, sourced from the
// `IO_BASE_DDI3725_DDO3705` DXF bounding box (the DXF outline IS accurate
// even though the terminal positions inside it are not).
//
// Conventions:
// - Body cream from `bodyColor` (re-exported through io16.dart from Beckhoff —
//   QUAL-02 fixed body color, not theme-driven).
// - Schneider blue (`stbAccentBlue`, `Color(0xFF003B71)`) used for top label
//   strip + bottom accent strip. Phase 2/3 import via `show stbAccentBlue`
//   from this file when they land.
// - Disconnected indicator (red exclamation) mirrors `IO8Painter` at
//   `lib/painter/beckhoff/io8.dart:126-147`.
// - `shouldRepaint` follows `IO8Painter` (per-field equality + animation value
//   comparison) with the cross-runtimeType short-circuit (Pitfall 3 guard).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'io16.dart' show IO16LedBlockPainter, bodyColor;
import 'package:tfc/painter/beckhoff/io8.dart' show IOState;

/// Schneider corporate blue used by the DDI3725 top label strip + bottom
/// accent. Operator-recognizable. Exported so Phase 2 DDO3705 + Phase 3
/// NIP2311 can reuse it via `show stbAccentBlue`.
const Color stbAccentBlue = Color(0xFF003B71);

/// Subtle chamfer radius — fraction of the shorter body dimension. Mirrors
/// Beckhoff's visual subtlety on slim DIN-rail modules. At a typical
/// slim 50×300 px STB module this lands at 1.5 px — a barely-visible chamfer
/// (Beckhoff parity); on the legacy wide form factor (200×280) the result is
/// ~6 px, also subtle. Shared by all four STB body painters via `show`.
const double kStbCornerRadiusFraction = 0.03;

/// Dark inset panel colour for the DDI3725 / DDO3705 LED windows. Real
/// Schneider hardware uses a near-black faceplate inset that contrasts with
/// the cream body to make the channel LEDs read clearly. BATCH2 Defect G.
const Color stbLedPanelColor = Color(0xFF1A1A1A);

/// Widget wrapper around [STBDDI3725BodyPainter] that handles the [SizedBox]
/// sizing + [CustomPaint] plumbing. Aspect ratio matches the
/// `IO_BASE_DDI3725_DDO3705` DXF (107 × 152 mm).
class STBDDI3725Widget extends AnimatedWidget {
  final List<IOState> ledStates;
  final bool isStale;
  final bool isDisconnected;
  final double height;

  // Asserts in the constructor body prevent a const declaration, which is
  // why the prefer_const_constructors_in_immutables lint is silenced here.
  // Matches the IO8Widget pattern in `lib/painter/beckhoff/io8.dart`.
  // ignore: prefer_const_constructors_in_immutables
  STBDDI3725Widget({
    super.key,
    required this.ledStates,
    required this.isStale,
    required this.isDisconnected,
    this.height = 300,
    required Animation<int> animation,
  })  : assert(ledStates.length == 16,
            'STBDDI3725 requires exactly 16 LED states (got ${ledStates.length})'),
        super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<int>;
    final width = height * (107.0 / 152.0);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: STBDDI3725BodyPainter(
          ledStates: ledStates,
          isStale: isStale,
          isDisconnected: isDisconnected,
          animation: animation,
        ),
      ),
    );
  }
}

/// Body painter for the DDI3725 module faceplate. Owns the cream body chrome,
/// the top/bottom Schneider-blue strips, the synthetic RDY indicator dot, the
/// disconnected exclamation icon, and the dual terminal blocks. Delegates the
/// 16-LED render to [IO16LedBlockPainter].
class STBDDI3725BodyPainter extends CustomPainter {
  final List<IOState> ledStates;
  final bool isStale;
  final bool isDisconnected;
  final Animation<int> animation;

  STBDDI3725BodyPainter({
    required this.ledStates,
    required this.isStale,
    required this.isDisconnected,
    required this.animation,
  })  : assert(ledStates.length == 16),
        super(repaint: animation);

  // Layout fractions — these match the photo proportions, not pixel-perfect.
  static const double _topStripFraction = 0.07;
  static const double _ledBlockFraction = 0.22;
  static const double _bottomAccentFraction = 0.025;
  static const int _terminalRowsPerColumn = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.03;
    final outerBorderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final fillPaint = Paint()..color = bodyColor;

    // 1. Outer body chrome — cream fill + grey rounded border.
    // BATCH2 Defect B: corner radius reduced from `size.width * 0.06` to a
    // shorter-side fraction so the chamfer stays subtle on slim DIN-rail
    // aspect ratios (post-Defect-E). Mirrors Beckhoff's visual subtlety on
    // the 1:6 EL1008 footprint.
    final cornerR = (size.width < size.height ? size.width : size.height) *
        kStbCornerRadiusFraction;
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(cornerR),
    );
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(cornerR),
    );
    canvas.drawRRect(fillRect, fillPaint);
    canvas.drawRRect(outerRect, outerBorderPaint);

    // Clip ALL interior chrome (header strip, accent strips, LED block,
    // terminal blocks) to the body RRect so nothing overshoots the chamfer.
    // DEFECT-1 fix: the top blue strip used to render as a plain rect and
    // pokes out beyond the rounded corners; clipping to the body RRect
    // keeps it inside the chamfer.
    canvas.save();
    canvas.clipRRect(fillRect);

    // 2. Top blue label strip with "DDI3725" + RDY indicator.
    final topStripH = size.height * _topStripFraction;
    final topStripRect = Rect.fromLTWH(0, 0, size.width, topStripH);
    canvas.drawRect(topStripRect, Paint()..color = stbAccentBlue);
    _drawTopLabelText(canvas, topStripRect);
    _drawRdyIndicator(canvas, topStripRect);

    // 3. LED block region — delegate to IO16LedBlockPainter.
    final ledBlockY = topStripH;
    final ledBlockH = size.height * _ledBlockFraction;
    final pad = size.width * 0.05;
    final ledBlockRect = Rect.fromLTWH(0, ledBlockY, size.width - pad, ledBlockH);
    canvas.save();
    canvas.translate(0, ledBlockY);
    IO16LedBlockPainter(
      ledStates: ledStates,
      animation: animation,
    ).paint(canvas, Size(ledBlockRect.width, ledBlockH));
    canvas.restore();

    // 4. Bottom blue accent strip (above terminal blocks).
    final bottomAccentH = size.height * _bottomAccentFraction;
    final bottomAccentY = ledBlockY + ledBlockH;
    final bottomAccentRect =
        Rect.fromLTWH(0, bottomAccentY, size.width, bottomAccentH);
    canvas.drawRect(bottomAccentRect, Paint()..color = stbAccentBlue);

    // 5. Dual terminal blocks (Block A left, Block B right).
    final terminalsY = bottomAccentY + bottomAccentH;
    final terminalsH = size.height - terminalsY - (pad * 0.5);
    _drawTerminalBlocks(canvas, size, terminalsY, terminalsH);

    // End of body-RRect-clipped interior chrome.
    canvas.restore();

    // 6. Disconnected indicator — red exclamation overlay in upper-center.
    if (isDisconnected) {
      _drawDisconnectedIcon(canvas, size);
    }
  }

  void _drawTopLabelText(Canvas canvas, Rect strip) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'DDI3725',
        style: TextStyle(
          color: Colors.white,
          fontSize: strip.height * 0.55,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: strip.width * 0.75);
    final dy = strip.top + (strip.height - tp.height) / 2;
    tp.paint(canvas, Offset(strip.left + strip.width * 0.06, dy));
  }

  void _drawRdyIndicator(Canvas canvas, Rect strip) {
    // Small circular indicator dot — green when alive, dim grey when stale or
    // disconnected. Per CONTEXT.md §Visual State Semantics: stale and
    // disconnected both push RDY to grey; the body painter does not distinguish.
    final radius = strip.height * 0.22;
    final cx = strip.right - radius - strip.width * 0.06;
    final cy = strip.top + strip.height / 2;
    final color = (isStale || isDisconnected)
        ? Colors.grey.shade400
        : const Color(0xFF6CA545);
    canvas.drawCircle(Offset(cx, cy), radius, Paint()..color = color);
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = Colors.grey.shade700
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.15,
    );
  }

  void _drawTerminalBlocks(
    Canvas canvas,
    Size size,
    double top,
    double height,
  ) {
    if (height <= 0) return;
    final innerBorderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.015;

    final pad = size.width * 0.05;
    // Each block fills half the width (minus padding gutters).
    final blockW = (size.width - pad * 3) / 2;
    // Label slot above each block.
    final labelH = (height * 0.05).clamp(8.0, 18.0);
    final positionsY = top + labelH;
    final positionsH = height - labelH;

    // Per-row geometry (each row = small dark-grey square + wire-hole circle).
    final rowH = positionsH / _terminalRowsPerColumn;
    final sqSize = rowH * 0.55;
    final crSize = rowH * 0.45;

    for (int col = 0; col < 2; col++) {
      final blockX = pad + col * (blockW + pad);
      // Column label "A" / "B".
      final labelRect = Rect.fromLTWH(blockX, top, blockW, labelH);
      final labelTp = TextPainter(
        text: TextSpan(
          text: col == 0 ? 'A' : 'B',
          style: TextStyle(
            color: Colors.black,
            fontSize: labelH * 0.85,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: blockW, maxWidth: blockW);
      labelTp.paint(
        canvas,
        Offset(labelRect.left, labelRect.top + (labelH - labelTp.height) / 2),
      );

      for (int row = 0; row < _terminalRowsPerColumn; row++) {
        final rowY = positionsY + row * rowH;
        // Square slot (top half of the row).
        final sqX = blockX + (blockW - sqSize) / 2;
        final sqY = rowY + (rowH - sqSize - crSize) * 0.3;
        final sq = Rect.fromLTWH(sqX, sqY, sqSize, sqSize);
        canvas.drawRect(sq, Paint()..color = Colors.grey.shade400);
        canvas.drawRect(sq, innerBorderPaint);
        // Round wire hole (bottom half).
        final crCenterX = blockX + blockW / 2;
        final crCenterY = sqY + sqSize + crSize / 2 + rowH * 0.05;
        canvas.drawCircle(
          Offset(crCenterX, crCenterY),
          crSize / 2,
          Paint()..color = Colors.grey.shade300,
        );
        canvas.drawCircle(
          Offset(crCenterX, crCenterY),
          crSize / 2,
          innerBorderPaint,
        );
      }
    }
  }

  void _drawDisconnectedIcon(Canvas canvas, Size size) {
    // Mirrors IO8Painter at io8.dart:126-147.
    final iconSize = size.width * 0.3;
    final iconPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final dotY = size.height * 0.18;
    canvas.drawCircle(
      Offset(size.width / 2, dotY),
      iconSize * 0.15,
      iconPaint,
    );
    final lineRect = Rect.fromLTWH(
      size.width / 2 - iconSize * 0.1,
      dotY + iconSize * 0.2,
      iconSize * 0.2,
      iconSize * 0.5,
    );
    canvas.drawRect(lineRect, iconPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! STBDDI3725BodyPainter) return true;
    return !listEquals(oldDelegate.ledStates, ledStates) ||
        oldDelegate.isStale != isStale ||
        oldDelegate.isDisconnected != isDisconnected ||
        oldDelegate.animation.value != animation.value;
  }
}
