// STBPDT3100 body painter + widget — Schneider Advantys STB 24 VDC power
// distribution module.
//
// Locked by `.planning/phases/04-stbpdt3100-power-distribution/04-CONTEXT.md`:
//
// - SINGLE optional bool key (`inputOkKey`) drives ONE LED:
//     stream emits true → green; false / null / stale / errored → dim grey.
//   No distinction between fault, stale, and disconnected — all render dim
//   grey (consistent with Phases 1–2 collapse semantics).
//
// - Aspect ratio per the PDT3100 DXF bounding box (114.5914794492 ×
//   162.0650923639 mm ≈ 0.7071 width / height). Taller and slightly wider
//   than NIP2311 (which is 58 × 82 mm). Width-to-height ratio ≈ 1/√2.
//
// - Body layout (top → bottom, fractions of `size.height`):
//     1. Top blue label strip  (~10%)   "PDT3100" white text, left-justified.
//     2. "IN" decorative band  (~10%)   Small black "IN" label centered.
//     3. INPUT LED row         (~14%)   Single LED (left) + "INPUT" caption
//                                        (right). Bound to `inputOk` bool.
//     4. Schneider blue band   (~7%)    "24 VDC POWER" subtitle.
//     5. Input terminal area   (~38%)   Decorative two terminal blocks with
//                                        "INPUT +" / "INPUT -" small labels.
//     6. Bottom whitespace     (~21%)   Intentionally blank since BATCH2 fixes
//                                        removed the decorative voltage rating
//                                        and vendor branding (Defects D + F).
//
// Conventions:
// - Body cream from `bodyColor` (re-exported through io16.dart from Beckhoff —
//   QUAL-02 fixed body color, not theme-driven).
// - Schneider blue (`stbAccentBlue`) imported from ddi3725.dart — same
//   constant as the I/O modules so the family stays visually coherent.
// - Status LED palette: green = `Color(0xFF6CA545)` (operator-recognizable
//   live green, matches the NIP2311 RUN/PWR LED + DDI3725 RDY indicator);
//   dim grey = `Colors.grey.shade400` (matches the stale/disconnected
//   treatment from the I/O modules).
//
// `shouldRepaint` returns false when the painter's inputs (`nameOrId`,
// `inputOk`) are unchanged. Cross-runtimeType comparisons return true
// (Pitfall 3 guard).

import 'package:flutter/material.dart';

import 'ddi3725.dart' show stbAccentBlue, kStbCornerRadiusFraction;
import 'io16.dart' show bodyColor;

/// Aspect ratio width / height for the PDT3100 body.
///
/// BATCH2 Defect E: switched from the DXF-derived 114.59/162.07 ≈ 0.707
/// (wide+squat) to a slim ~1:3 ratio (`1.0 / 3.0`) so the power module reads
/// as a real DIN-rail block beside the slim I/O modules. The panel reference
/// photo (`.planning/research/photos/momentum_stack_in_panel.png`) shows the
/// PDT3100 at roughly 2× the width of an I/O module — `2/6 = 1/3`.
const double kPDT3100AspectRatio = 1.0 / 3.0;

/// Widget wrapper around [STBPDT3100BodyPainter]. Bound to an optional
/// `inputOk` bool — `true` lights the single front-panel LED green; any
/// other state (false / null / stale / disconnected) renders it dim grey.
///
/// Aspect ratio is locked at the PDT3100 DXF bounding box (~114.59 × 162.07
/// mm ≈ 0.7071) so the module visually reads as the slim cream PDT3100
/// beside the wider I/O modules in a stack.
class STBPDT3100Widget extends StatelessWidget {
  final String nameOrId;
  final bool? inputOk;
  final double height;

  // Asserts ban a const constructor here — same pattern as the I/O module
  // widgets in this package. The lint is intentionally silenced.
  // ignore: prefer_const_constructors_in_immutables
  STBPDT3100Widget({
    super.key,
    required this.nameOrId,
    required this.inputOk,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    final width = height * kPDT3100AspectRatio;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: STBPDT3100BodyPainter(
          nameOrId: nameOrId,
          inputOk: inputOk,
        ),
      ),
    );
  }
}

/// Body painter for the PDT3100 module faceplate. Owns the cream body
/// chrome, the top Schneider-blue label strip, the "IN" decorative band, the
/// single LED (bound to `inputOk`), the Schneider-blue subtitle band, the
/// decorative input terminal pair, and the bottom power footer.
class STBPDT3100BodyPainter extends CustomPainter {
  final String nameOrId;
  final bool? inputOk;

  STBPDT3100BodyPainter({required this.nameOrId, required this.inputOk});

  // Layout fractions, top → bottom. Sum is normalized to 1.0; minor padding
  // is absorbed inside each region.
  static const double _topStripFraction = 0.10;
  static const double _inLabelFraction = 0.10;
  static const double _ledRowFraction = 0.14;
  static const double _subtitleBandFraction = 0.07;
  static const double _terminalFraction = 0.38;
  // Retained-but-unused: 21% trailing slice formerly held the decorative
  // voltage rating + vendor branding (BATCH2 Defects D + F removed it).
  // Preserved as whitespace so the other layout fractions are stable.
  // ignore: unused_field
  static const double _bottomFooterFraction = 0.21;

  // Status-LED palette — same green as the NIP2311 RUN/PWR + DDI3725 RDY.
  static const Color _ledGreen = Color(0xFF6CA545);

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.025;
    final outerBorderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final fillPaint = Paint()..color = bodyColor;

    // 1. Outer body chrome — cream fill + grey rounded border.
    // BATCH2 Defect B: subtle chamfer (Beckhoff parity).
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

    // Clip interior chrome to body RRect — DEFECT-1 (top header overshooting
    // the chamfer) is eliminated when every subsequent fill is constrained
    // to the rounded body shape.
    canvas.save();
    canvas.clipRRect(fillRect);

    double y = 0.0;

    // 2. Top blue label strip with "PDT3100".
    final topStripH = size.height * _topStripFraction;
    final topStripRect = Rect.fromLTWH(0, y, size.width, topStripH);
    canvas.drawRect(topStripRect, Paint()..color = stbAccentBlue);
    _drawTopLabelText(canvas, topStripRect);
    y += topStripH;

    // 3. "IN" decorative band (cream — no fill change; just text).
    final inBandH = size.height * _inLabelFraction;
    final inBandRect = Rect.fromLTWH(0, y, size.width, inBandH);
    _drawInLabel(canvas, inBandRect);
    y += inBandH;

    // 4. Single LED row — green when inputOk == true; dim grey otherwise.
    final ledRowH = size.height * _ledRowFraction;
    final ledRowRect = Rect.fromLTWH(0, y, size.width, ledRowH);
    _drawLedRow(canvas, ledRowRect);
    y += ledRowH;

    // 5. Schneider blue subtitle band.
    final subtitleH = size.height * _subtitleBandFraction;
    final subtitleRect = Rect.fromLTWH(0, y, size.width, subtitleH);
    canvas.drawRect(subtitleRect, Paint()..color = stbAccentBlue);
    _drawSubtitleText(canvas, subtitleRect);
    y += subtitleH;

    // 6. Input terminal area — decorative two terminal blocks.
    final terminalH = size.height * _terminalFraction;
    final terminalRect = Rect.fromLTWH(0, y, size.width, terminalH);
    _drawTerminals(canvas, terminalRect);
    y += terminalH;

    // 7. BATCH2 Defects D + F: bottom-footer region intentionally left
    // blank — voltage-rating and vendor-branding text removed at the
    // user's request. The `_bottomFooterFraction` slice of the body height
    // is preserved as whitespace so the rest of the layout does not reflow.
    canvas.restore();
  }

  void _drawTopLabelText(Canvas canvas, Rect strip) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'PDT3100',
        style: TextStyle(
          color: Colors.white,
          fontSize: strip.height * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: strip.width * 0.95);
    final dy = strip.top + (strip.height - tp.height) / 2;
    tp.paint(canvas, Offset(strip.left + strip.width * 0.08, dy));
  }

  void _drawInLabel(Canvas canvas, Rect band) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'IN',
        style: TextStyle(
          color: Colors.black87,
          fontSize: band.height * 0.55,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: band.width, maxWidth: band.width);
    tp.paint(
      canvas,
      Offset(band.left, band.top + (band.height - tp.height) / 2),
    );
  }

  void _drawLedRow(Canvas canvas, Rect rect) {
    // Single LED: left-aligned circle + "INPUT" caption to the right.
    final dotR = rect.height * 0.28;
    final dotCx = rect.left + rect.width * 0.26;
    final dotCy = rect.top + rect.height / 2;

    final ringPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = dotR * 0.18;

    final Color dotColor = (inputOk == true) ? _ledGreen : Colors.grey.shade400;

    canvas.drawCircle(Offset(dotCx, dotCy), dotR, Paint()..color = dotColor);
    canvas.drawCircle(Offset(dotCx, dotCy), dotR, ringPaint);

    final labelLeft = dotCx + dotR + rect.width * 0.08;
    final labelMaxW = rect.right - labelLeft - rect.width * 0.05;
    final tp = TextPainter(
      text: TextSpan(
        text: 'INPUT',
        style: TextStyle(
          color: Colors.black,
          fontSize: rect.height * 0.40,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: labelMaxW);
    tp.paint(canvas, Offset(labelLeft, dotCy - tp.height / 2));
  }

  void _drawSubtitleText(Canvas canvas, Rect band) {
    final tp = TextPainter(
      text: TextSpan(
        text: '24 VDC POWER',
        style: TextStyle(
          color: Colors.white,
          fontSize: band.height * 0.50,
          fontWeight: FontWeight.w500,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: band.width, maxWidth: band.width);
    tp.paint(
      canvas,
      Offset(band.left, band.top + (band.height - tp.height) / 2),
    );
  }

  void _drawTerminals(Canvas canvas, Rect rect) {
    // Two stacked decorative terminal blocks with "+" and "-" labels. Each
    // block is a rounded rectangle with a small inner screw circle to read
    // as a Schneider clamp terminal — consistent with the visual cue
    // operators use to identify input wiring.
    final pad = rect.width * 0.12;
    final innerW = rect.width - pad * 2;
    final gap = rect.height * 0.08;
    final blockH = (rect.height - gap) / 2;
    final screwR = blockH * 0.20;
    final terminalPaint = Paint()..color = Colors.grey.shade300;
    final terminalStroke = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.012;
    final screwPaint = Paint()..color = Colors.grey.shade500;
    final screwStroke = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.width * 0.008;

    // Right-edge of the terminal block — labels must NEVER cross this so they
    // sit fully INSIDE the rounded rectangle (DEFECT-4 fix).
    final blockRight = rect.left + pad + innerW;
    // Anchor labels just to the right of the screw, but reserve a small
    // safety margin (4% of innerW) inside the right edge.
    final labelLeft = rect.left + pad + innerW * 0.50;
    final labelMaxW = blockRight - labelLeft - innerW * 0.04;

    // Top block (+).
    final topBlockRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left + pad, rect.top, innerW, blockH),
      Radius.circular(blockH * 0.18),
    );
    canvas.drawRRect(topBlockRect, terminalPaint);
    canvas.drawRRect(topBlockRect, terminalStroke);
    final topScrewCx = rect.left + pad + innerW * 0.25;
    final topScrewCy = rect.top + blockH / 2;
    canvas.drawCircle(Offset(topScrewCx, topScrewCy), screwR, screwPaint);
    canvas.drawCircle(Offset(topScrewCx, topScrewCy), screwR, screwStroke);
    _drawTerminalLabel(
      canvas,
      Offset(labelLeft, topScrewCy),
      blockH,
      labelMaxW,
      'INPUT +',
    );

    // Bottom block (−).
    final bottomTop = rect.top + blockH + gap;
    final bottomBlockRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left + pad, bottomTop, innerW, blockH),
      Radius.circular(blockH * 0.18),
    );
    canvas.drawRRect(bottomBlockRect, terminalPaint);
    canvas.drawRRect(bottomBlockRect, terminalStroke);
    final bottomScrewCx = rect.left + pad + innerW * 0.25;
    final bottomScrewCy = bottomTop + blockH / 2;
    canvas.drawCircle(
        Offset(bottomScrewCx, bottomScrewCy), screwR, screwPaint);
    canvas.drawCircle(
        Offset(bottomScrewCx, bottomScrewCy), screwR, screwStroke);
    _drawTerminalLabel(
      canvas,
      Offset(labelLeft, bottomScrewCy),
      blockH,
      labelMaxW,
      'INPUT −',
    );
  }

  /// Draws the terminal label inside the block, with the font auto-shrunk
  /// to fit `maxWidth`. DEFECT-4 fix — the old layout used a fixed font size
  /// of `blockH * 0.32` and let the painted text overflow the right edge of
  /// the terminal block and even the body box itself. The new layout caps
  /// the font size at `blockH * 0.28` and then iteratively scales it down
  /// (in 5% increments) until the laid-out text width fits inside `maxWidth`,
  /// guaranteeing the painted text stays inside the rounded terminal block.
  void _drawTerminalLabel(Canvas canvas, Offset anchor, double blockH,
      double maxWidth, String text) {
    double fontSize = blockH * 0.28;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width <= maxWidth || fontSize < 4) break;
      fontSize *= 0.95;
    }
    tp.paint(canvas, Offset(anchor.dx, anchor.dy - tp.height / 2));
  }


  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! STBPDT3100BodyPainter) return true;
    return oldDelegate.nameOrId != nameOrId || oldDelegate.inputOk != inputOk;
  }
}
