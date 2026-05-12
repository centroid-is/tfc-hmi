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
//     1. Top blue label strip      (~10%)  "PDT3100" white text, left-justified.
//     2. IN/OUT LED viewport       (~18%)  Small dark rectangular window showing
//                                           a single status LED dot (green when
//                                           `inputOk` true). Replaces the old
//                                           "IN" caption + cream LED row.
//     3. Schneider blue band       (~7%)   "24 VDC POWER" subtitle.
//     4. INPUT plug terminal block (~24%)  Horizontal plug-style connector
//                                           labeled "INPUT" with two internal
//                                           terminal holes (small "+" / "−"
//                                           markings inside the plug) + spring
//                                           clip lever on the right edge.
//     5. "DC" centred label        (~5%)   Black "DC" between plug blocks.
//     6. OUTPUT plug terminal      (~24%)  Mirror of #4 labeled "OUTPUT".
//     7. Bottom whitespace         (~12%)  Intentionally blank since BATCH2
//                                           fixes removed the decorative
//                                           voltage rating and vendor branding
//                                           (Defects D + F).
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
/// chrome, the top Schneider-blue label strip, the IN/OUT LED viewport
/// (bound to `inputOk`), the Schneider-blue subtitle band, the INPUT and
/// OUTPUT plug terminal blocks, a centred "DC" inter-block label, and a
/// blank trailing whitespace region (the decorative voltage rating and
/// vendor branding were removed at the user's request — BATCH2 Defects
/// D + F).
class STBPDT3100BodyPainter extends CustomPainter {
  final String nameOrId;
  final bool? inputOk;

  STBPDT3100BodyPainter({required this.nameOrId, required this.inputOk});

  // Layout fractions, top → bottom. Sum is normalized to 1.0; minor padding
  // is absorbed inside each region. BATCH2 Defect C: re-cut to make room
  // for the new IN/OUT LED viewport + two horizontal plug terminal blocks
  // labeled INPUT/OUTPUT (each with internal "+"/"−" holes and a spring
  // clip lever) + a centred "DC" label between them.
  static const double _topStripFraction = 0.10;
  static const double _viewportFraction = 0.18;
  static const double _subtitleBandFraction = 0.07;
  static const double _inputPlugFraction = 0.24;
  static const double _dcLabelFraction = 0.05;
  static const double _outputPlugFraction = 0.24;
  // ignore: unused_field
  static const double _bottomWhitespaceFraction = 0.12;

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

    // 3. BATCH2 Defect C: IN/OUT LED viewport — small dark rectangle with
    // a single status LED dot. Green when `inputOk == true`; dim grey
    // otherwise. The viewport sits on the cream body with horizontal
    // padding so it reads as a recessed window on the faceplate.
    final viewportH = size.height * _viewportFraction;
    final viewportRect = Rect.fromLTWH(0, y, size.width, viewportH);
    _drawInOutLedViewport(canvas, viewportRect);
    y += viewportH;

    // 4. Schneider blue subtitle band ("24 VDC POWER").
    final subtitleH = size.height * _subtitleBandFraction;
    final subtitleRect = Rect.fromLTWH(0, y, size.width, subtitleH);
    canvas.drawRect(subtitleRect, Paint()..color = stbAccentBlue);
    _drawSubtitleText(canvas, subtitleRect);
    y += subtitleH;

    // 5. BATCH2 Defect C: INPUT plug terminal block.
    final inputPlugH = size.height * _inputPlugFraction;
    final inputPlugRect = Rect.fromLTWH(0, y, size.width, inputPlugH);
    _drawPlugTerminal(canvas, inputPlugRect, 'INPUT');
    y += inputPlugH;

    // 6. BATCH2 Defect C: centred "DC" label between the two plug blocks.
    final dcLabelH = size.height * _dcLabelFraction;
    final dcLabelRect = Rect.fromLTWH(0, y, size.width, dcLabelH);
    _drawDcLabel(canvas, dcLabelRect);
    y += dcLabelH;

    // 7. BATCH2 Defect C: OUTPUT plug terminal block (mirror of INPUT).
    final outputPlugH = size.height * _outputPlugFraction;
    final outputPlugRect = Rect.fromLTWH(0, y, size.width, outputPlugH);
    _drawPlugTerminal(canvas, outputPlugRect, 'OUTPUT');
    y += outputPlugH;

    // 8. BATCH2 Defects D + F: bottom-whitespace region intentionally
    // left blank — voltage-rating and vendor-branding text removed at the
    // user's request. The `_bottomWhitespaceFraction` slice is preserved
    // so the rest of the layout does not need to reflow.
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

  /// BATCH2 Defect C: small dark-inset IN/OUT LED viewport. Mirrors the real
  /// PDT3100 hardware which has a single rectangular window showing the
  /// status indicator. Green when `inputOk == true`; dim grey otherwise.
  ///
  /// The viewport is centred horizontally with ~12% horizontal padding so it
  /// reads as a recessed window on the cream body.
  void _drawInOutLedViewport(Canvas canvas, Rect rect) {
    final padX = rect.width * 0.20;
    final padY = rect.height * 0.18;
    final inset = Rect.fromLTRB(
      rect.left + padX,
      rect.top + padY,
      rect.right - padX,
      rect.bottom - padY,
    );
    // Dark background.
    final bgPaint = Paint()..color = const Color(0xFF1A1A1A);
    final bgRRect = RRect.fromRectAndRadius(
      inset,
      Radius.circular(inset.height * 0.18),
    );
    canvas.drawRRect(bgRRect, bgPaint);
    // Subtle inner bezel stroke.
    canvas.drawRRect(
      bgRRect,
      Paint()
        ..color = Colors.grey.shade700
        ..style = PaintingStyle.stroke
        ..strokeWidth = inset.height * 0.07,
    );

    // Single LED dot centred horizontally inside the viewport.
    final dotR = inset.height * 0.30;
    final dotCx = inset.left + inset.width * 0.30;
    final dotCy = inset.center.dy;
    final Color dotColor =
        (inputOk == true) ? _ledGreen : Colors.grey.shade500;
    canvas.drawCircle(Offset(dotCx, dotCy), dotR, Paint()..color = dotColor);
    canvas.drawCircle(
      Offset(dotCx, dotCy),
      dotR,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = dotR * 0.15,
    );

    // "IN/OUT" caption to the right of the dot, in light text on the dark
    // viewport background.
    final captionLeft = dotCx + dotR + inset.width * 0.06;
    final captionMaxW = inset.right - captionLeft - inset.width * 0.05;
    final tp = TextPainter(
      text: TextSpan(
        text: 'IN/OUT',
        style: TextStyle(
          color: Colors.grey.shade100,
          fontSize: inset.height * 0.42,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: captionMaxW);
    tp.paint(canvas, Offset(captionLeft, dotCy - tp.height / 2));
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

  /// BATCH2 Defect C: draws ONE horizontal plug-style terminal connector
  /// (the real PDT3100 has two — one labeled "INPUT" stacked above one
  /// labeled "OUTPUT"). Each plug renders as:
  ///   * a darker rounded rectangle (the plug-block body),
  ///   * a small full-word label centred on the LEFT half ("INPUT"/"OUTPUT"),
  ///   * two internal terminal holes (small dark circles) on the RIGHT half
  ///     with inline "+" and "−" markings next to them, and
  ///   * a small spring-clip lever (a trapezoidal nub) sticking up past the
  ///     plug's right edge to signal "snap-in / cable-release" hardware.
  void _drawPlugTerminal(Canvas canvas, Rect rect, String label) {
    if (rect.height <= 0 || rect.width <= 0) return;

    final padX = rect.width * 0.10;
    final padY = rect.height * 0.10;
    final plugRect = Rect.fromLTRB(
      rect.left + padX,
      rect.top + padY,
      rect.right - padX,
      rect.bottom - padY,
    );
    if (plugRect.width <= 0 || plugRect.height <= 0) return;

    // Plug-block body (darker grey rounded rect with a stroke).
    final blockRRect = RRect.fromRectAndRadius(
      plugRect,
      Radius.circular(plugRect.height * 0.18),
    );
    canvas.drawRRect(blockRRect, Paint()..color = Colors.grey.shade400);
    canvas.drawRRect(
      blockRRect,
      Paint()
        ..color = Colors.grey.shade800
        ..style = PaintingStyle.stroke
        ..strokeWidth = plugRect.height * 0.04,
    );

    // Spring-clip lever — a small trapezoid sticking up past the plug's
    // top-right corner. Reads as a snap-in cable-release lever.
    final leverW = plugRect.width * 0.10;
    final leverH = plugRect.height * 0.30;
    final leverRight = plugRect.right - plugRect.width * 0.02;
    final leverLeft = leverRight - leverW;
    final leverTopY = plugRect.top - leverH * 0.65;
    final leverPath = Path()
      ..moveTo(leverLeft, plugRect.top)
      ..lineTo(leverLeft + leverW * 0.20, leverTopY)
      ..lineTo(leverRight - leverW * 0.20, leverTopY)
      ..lineTo(leverRight, plugRect.top)
      ..close();
    canvas.drawPath(leverPath, Paint()..color = Colors.grey.shade600);
    canvas.drawPath(
      leverPath,
      Paint()
        ..color = Colors.grey.shade800
        ..style = PaintingStyle.stroke
        ..strokeWidth = plugRect.height * 0.03,
    );

    // Layout: left half = label ("INPUT" / "OUTPUT"); right half = two
    // terminal holes with internal "+" and "−" markings.
    final leftHalfRight = plugRect.left + plugRect.width * 0.50;

    // Label centred in the left half, sized to fit. Iteratively shrink the
    // font if it overflows the available width.
    final labelMaxW = leftHalfRight - plugRect.left - plugRect.width * 0.08;
    double labelFontSize = plugRect.height * 0.55;
    TextPainter labelTp;
    while (true) {
      labelTp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.black,
            fontSize: labelFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout();
      if (labelTp.width <= labelMaxW || labelFontSize < 4) break;
      labelFontSize *= 0.95;
    }
    labelTp.paint(
      canvas,
      Offset(
        plugRect.left + plugRect.width * 0.06,
        plugRect.center.dy - labelTp.height / 2,
      ),
    );

    // Right half — two terminal holes, each with a "+" or "−" marking.
    final holeR = plugRect.height * 0.18;
    final holeCy = plugRect.center.dy;
    final holeCxLeft = leftHalfRight + plugRect.width * 0.12;
    final holeCxRight = plugRect.right - plugRect.width * 0.10;
    final holePaint = Paint()..color = const Color(0xFF1A1A1A);
    final holeStroke = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.stroke
      ..strokeWidth = holeR * 0.18;
    canvas.drawCircle(Offset(holeCxLeft, holeCy), holeR, holePaint);
    canvas.drawCircle(Offset(holeCxLeft, holeCy), holeR, holeStroke);
    canvas.drawCircle(Offset(holeCxRight, holeCy), holeR, holePaint);
    canvas.drawCircle(Offset(holeCxRight, holeCy), holeR, holeStroke);

    // "+" / "−" markings BELOW each hole so they read as polarity hints
    // without overlapping the dark hole pixels.
    final markFontSize = plugRect.height * 0.30;
    final plusTp = TextPainter(
      text: TextSpan(
        text: '+',
        style: TextStyle(
          color: Colors.black,
          fontSize: markFontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final minusTp = TextPainter(
      text: TextSpan(
        text: '−',
        style: TextStyle(
          color: Colors.black,
          fontSize: markFontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final markY = holeCy + holeR + plugRect.height * 0.02;
    plusTp.paint(
      canvas,
      Offset(holeCxLeft - plusTp.width / 2, markY),
    );
    minusTp.paint(
      canvas,
      Offset(holeCxRight - minusTp.width / 2, markY),
    );
  }

  /// BATCH2 Defect C: small centred "DC" label between the two plug blocks.
  void _drawDcLabel(Canvas canvas, Rect rect) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'DC',
        style: TextStyle(
          color: Colors.black87,
          fontSize: rect.height * 0.80,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: rect.width, maxWidth: rect.width);
    tp.paint(
      canvas,
      Offset(rect.left, rect.top + (rect.height - tp.height) / 2),
    );
  }


  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! STBPDT3100BodyPainter) return true;
    return oldDelegate.nameOrId != nameOrId || oldDelegate.inputOk != inputOk;
  }
}
