// STBDDO3705 body painter + widget — Schneider Advantys STB 16-channel DO.
//
// Layout follows `.planning/research/photos/DDO3705_front_clean.png`. The
// DDO3705 shares the same physical base form factor as the DDI3725
// (`IO_BASE_DDI3725_DDO3705` DXF bounding box), so this painter clones
// `STBDDI3725BodyPainter` and swaps two things:
//
//   1. Top label strip text: "DDO3705" instead of "DDI3725".
//   2. Output-style legend differentiator: a small "▸" arrow glyph rendered
//      above the LED block as an operator-recognizable hint that this is the
//      output module (CONTEXT.md §Visual Differentiation from DDI3725).
//
// All other regions (Schneider blue strips, RDY indicator, LED block via
// `IO16LedBlockPainter`, terminal blocks, disconnected exclamation overlay)
// are bit-for-bit identical to DDI3725.
//
// Bit-ordering: this painter consumes the same `kSTBChannelBitOrder` constant
// from `io16.dart` as DDI3725 — there is NO module-local re-declaration. The
// bit-order parity canary test in `advantys_stb_test.dart` is the compile-time
// guard against accidental drift between DI and DO conventions.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ddi3725.dart' show stbAccentBlue, kStbCornerRadiusFraction;
import 'io16.dart' show IO16LedBlockPainter, bodyColor;
import 'package:tfc/painter/beckhoff/io8.dart' show IOState;

/// Widget wrapper around [STBDDO3705BodyPainter] that handles the [SizedBox]
/// sizing + [CustomPaint] plumbing. Aspect ratio matches the
/// `IO_BASE_DDI3725_DDO3705` DXF (107 × 152 mm) — identical to DDI3725.
class STBDDO3705Widget extends AnimatedWidget {
  final List<IOState> ledStates;
  final bool isStale;
  final bool isDisconnected;
  final double height;

  // ignore: prefer_const_constructors_in_immutables
  STBDDO3705Widget({
    super.key,
    required this.ledStates,
    required this.isStale,
    required this.isDisconnected,
    this.height = 300,
    required Animation<int> animation,
  })  : assert(ledStates.length == 16,
            'STBDDO3705 requires exactly 16 LED states (got ${ledStates.length})'),
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
        painter: STBDDO3705BodyPainter(
          ledStates: ledStates,
          isStale: isStale,
          isDisconnected: isDisconnected,
          animation: animation,
        ),
      ),
    );
  }
}

/// Body painter for the DDO3705 module faceplate. Structurally identical to
/// [STBDDI3725BodyPainter] but ships output-style branding:
///   - "DDO3705" in the top label strip
///   - Small "▸" arrow glyph above the LED block (output-recognizable legend)
///
/// All other regions (Schneider blue strips, RDY dot, LED block via
/// [IO16LedBlockPainter], terminal blocks, disconnected exclamation overlay)
/// are bit-for-bit identical to DDI3725.
class STBDDO3705BodyPainter extends CustomPainter {
  final List<IOState> ledStates;
  final bool isStale;
  final bool isDisconnected;
  final Animation<int> animation;

  STBDDO3705BodyPainter({
    required this.ledStates,
    required this.isStale,
    required this.isDisconnected,
    required this.animation,
  })  : assert(ledStates.length == 16),
        super(repaint: animation);

  // Layout fractions — match DDI3725 exactly (same physical form factor).
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
    // BATCH2 Defect B: subtle chamfer (Beckhoff parity). See
    // `kStbCornerRadiusFraction` in ddi3725.dart.
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

    // Clip interior chrome to body RRect — DEFECT-1: top blue strip used to
    // overshoot the chamfered corners. Clipping keeps it inside the curve.
    canvas.save();
    canvas.clipRRect(fillRect);

    // 2. Top blue label strip with "DDO3705" + RDY indicator.
    final topStripH = size.height * _topStripFraction;
    final topStripRect = Rect.fromLTWH(0, 0, size.width, topStripH);
    canvas.drawRect(topStripRect, Paint()..color = stbAccentBlue);
    _drawTopLabelText(canvas, topStripRect);
    _drawOutputArrowGlyph(canvas, topStripRect);
    _drawRdyIndicator(canvas, topStripRect);

    // 3. LED block region — delegate to IO16LedBlockPainter.
    final ledBlockY = topStripH;
    final ledBlockH = size.height * _ledBlockFraction;
    final pad = size.width * 0.05;
    final ledBlockRect =
        Rect.fromLTWH(0, ledBlockY, size.width - pad, ledBlockH);
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

    canvas.restore();

    // 6. Disconnected indicator — red exclamation overlay in upper-center.
    if (isDisconnected) {
      _drawDisconnectedIcon(canvas, size);
    }
  }

  void _drawTopLabelText(Canvas canvas, Rect strip) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'DDO3705',
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

  /// Renders the "▸" arrow glyph immediately to the LEFT of the "DDO3705"
  /// label text — operator-recognizable as the output module without reading
  /// the printed module name (CONTEXT.md §Visual Differentiation).
  ///
  /// The glyph is half the strip height and uses the same white text colour
  /// as the label. This is the dominant visual differentiator vs DDI3725 at
  /// the same channel state in the golden pair — the LED block beneath is
  /// otherwise pixel-identical between DI and DO.
  void _drawOutputArrowGlyph(Canvas canvas, Rect strip) {
    final tp = TextPainter(
      text: TextSpan(
        text: '▸ ', // ▸ — Unicode BLACK RIGHT-POINTING SMALL TRIANGLE
        style: TextStyle(
          color: Colors.white,
          fontSize: strip.height * 0.55,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dy = strip.top + (strip.height - tp.height) / 2;
    // Place glyph just to the left of the "DDO3705" label (at strip.width * 0.02).
    tp.paint(canvas, Offset(strip.left + strip.width * 0.015, dy));
  }

  void _drawRdyIndicator(Canvas canvas, Rect strip) {
    // Stale + disconnected both push RDY to grey; the body painter does not
    // distinguish. Matches DDI3725.
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
    final blockW = (size.width - pad * 3) / 2;
    final labelH = (height * 0.05).clamp(8.0, 18.0);
    final positionsY = top + labelH;
    final positionsH = height - labelH;

    final rowH = positionsH / _terminalRowsPerColumn;
    final sqSize = rowH * 0.55;
    final crSize = rowH * 0.45;

    for (int col = 0; col < 2; col++) {
      final blockX = pad + col * (blockW + pad);
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
        final sqX = blockX + (blockW - sqSize) / 2;
        final sqY = rowY + (rowH - sqSize - crSize) * 0.3;
        final sq = Rect.fromLTWH(sqX, sqY, sqSize, sqSize);
        canvas.drawRect(sq, Paint()..color = Colors.grey.shade400);
        canvas.drawRect(sq, innerBorderPaint);
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
    // Mirrors IO8Painter at io8.dart:126-147 — same as DDI3725.
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
    if (oldDelegate is! STBDDO3705BodyPainter) return true;
    return !listEquals(oldDelegate.ledStates, ledStates) ||
        oldDelegate.isStale != isStale ||
        oldDelegate.isDisconnected != isDisconnected ||
        oldDelegate.animation.value != animation.value;
  }
}
