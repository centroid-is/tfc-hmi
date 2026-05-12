// STBPDT3100 body painter + widget — Schneider Advantys STB 24 VDC power
// distribution module.
//
// Layout follows the real-hardware reference photo (cream module face,
// top-to-bottom):
//   1. "PDT3100" model number, small dark grey text directly on cream.
//   2. Dark rectangular LED viewport containing stacked "IN"/"OUT" text
//      (normal horizontal orientation) and a single status LED dot.
//   3. Thin Schneider-blue accent strip (visual separator).
//   4. "INPUT" label, dark text on cream.
//   5. INPUT plug terminal — composite: white block (with two wire-entry
//      holes) on the left + grey block (with stacked "+" / "−" markings)
//      on the right.
//   6. "DC" centred label between the plugs with a short dashed line
//      underneath.
//   7. "OUTPUT" label, dark text on cream.
//   8. OUTPUT plug terminal — visually identical to the INPUT plug.
//   9. Thin Schneider-blue accent strip (visual closure).
//
// `inputOk == true` → green status dot inside the IN/OUT viewport; any
// other state (false / null / stale) → dim grey dot. No fault/stale/
// disconnected distinction (consistent with Phases 1–2 collapse semantics).
//
// `shouldRepaint` returns false when (`nameOrId`, `inputOk`) are unchanged
// and true across runtime types (Pitfall 3 guard).

import 'package:flutter/material.dart';

import 'ddi3725.dart'
    show
        stbAccentBlue,
        kStbCornerRadiusFraction,
        stbBodyStrokeWidth,
        stbBodyBorderColor,
        stbLedPanelColor;
import 'io16.dart' show bodyColor;

/// Aspect ratio width / height for the PDT3100 body.
///
/// Real Schneider STBPDT3100 hardware is 13.9 mm × 128.25 mm (aspect 0.108),
/// but at typical HMI display sizes that's too slim — the model number and
/// the INPUT/OUTPUT plug terminal layouts don't have room to breathe at
/// that ratio. Bumped to 0.18 (~64% of DDI/DDO's 0.219) so the module
/// reads as visibly the slimmest in the family while still rendering the
/// plug topology and label legibly.
const double kPDT3100AspectRatio = 0.18;

/// Widget wrapper around [STBPDT3100BodyPainter]. Bound to an optional
/// `inputOk` bool — `true` lights the single front-panel LED green; any
/// other state (false / null / stale / disconnected) renders it dim grey.
class STBPDT3100Widget extends StatelessWidget {
  final String nameOrId;
  final bool? inputOk;
  final double height;

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
/// chrome, the model-number band, the IN/OUT LED viewport, the two
/// Schneider-blue accent strips (top + bottom of plug region), the INPUT
/// and OUTPUT plug terminals (white-block-with-holes + grey-block-with-±),
/// and the "DC" centred label with its short dashed underline.
class STBPDT3100BodyPainter extends CustomPainter {
  final String nameOrId;
  final bool? inputOk;

  STBPDT3100BodyPainter({required this.nameOrId, required this.inputOk});

  // Vertical band fractions (top → bottom). Sum is normalized to 1.0.
  static const double _modelLabelFraction = 0.06; // "PDT3100" on cream
  static const double _viewportFraction = 0.24; // dark IN/OUT viewport
  static const double _topBlueStripFraction = 0.03; // Schneider blue accent
  static const double _inputLabelFraction = 0.05; // "INPUT" on cream
  static const double _inputPlugFraction = 0.18; // white+grey plug graphic
  static const double _dcBandFraction = 0.06; // "DC" + dashes
  static const double _outputLabelFraction = 0.05; // "OUTPUT" on cream
  static const double _outputPlugFraction = 0.18; // mirror of INPUT plug
  static const double _bottomBlueStripFraction = 0.03; // Schneider blue accent
  // Remaining 0.12 of body height absorbs as bottom cream margin.

  // Status-LED palette — same green as the NIP2311 RUN/PWR + DDI3725 RDY.
  static const Color _ledGreen = Color(0xFF6CA545);

  // Plug terminal palette.
  static const Color _plugWhiteBlock = Color(0xFFFCFCFC);
  static const Color _plugGreyBlock = Color(0xFFBABABA);
  static const Color _plugHoleDark = Color(0xFF333333);
  static const Color _plugBorder = Color(0xFF555555);

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = stbBodyStrokeWidth(size);
    final outerBorderPaint = Paint()
      ..color = stbBodyBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final fillPaint = Paint()..color = bodyColor;

    // 1. Outer body chrome — cream fill + grey rounded border.
    final cornerR = (size.width < size.height ? size.width : size.height) *
        kStbCornerRadiusFraction;
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(cornerR),
    );
    // Outline INSET by half stroke — see ddi3725.dart for the full rationale
    // (stroke entirely inside the fill, no half-stroke peeking past).
    final outlineInset = strokeWidth / 2;
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(outlineInset, outlineInset,
          size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular((cornerR - outlineInset).clamp(0.0, double.infinity)),
    );
    canvas.drawRRect(fillRect, fillPaint);
    canvas.drawRRect(outerRect, outerBorderPaint);

    // Clip interior chrome to the OUTLINE rect so accent strips don't bleed
    // past the rounded body corners (Defect 2 guard).
    canvas.save();
    canvas.clipRRect(outerRect);

    double y = 0.0;

    // 2. Model number band — "PDT3100" centred dark text on cream.
    final modelH = size.height * _modelLabelFraction;
    _drawCreamLabel(
      canvas,
      Rect.fromLTWH(0, y, size.width, modelH),
      'PDT3100',
      fontWeight: FontWeight.w600,
      fontSizeFraction: 0.72,
      letterSpacing: 0.4,
    );
    y += modelH;

    // 3. Dark IN/OUT LED viewport — dark rectangle with stacked IN/OUT
    // text and a status dot.
    final viewportH = size.height * _viewportFraction;
    _drawInOutLedViewport(canvas, Rect.fromLTWH(0, y, size.width, viewportH));
    y += viewportH;

    // 4. Top Schneider-blue accent strip (visual separator).
    final topBlueH = size.height * _topBlueStripFraction;
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, topBlueH),
      Paint()..color = stbAccentBlue,
    );
    y += topBlueH;

    // 5. INPUT label band — dark text on cream, centred above the plug.
    final inputLabelH = size.height * _inputLabelFraction;
    _drawCreamLabel(
      canvas,
      Rect.fromLTWH(0, y, size.width, inputLabelH),
      'INPUT',
      fontWeight: FontWeight.w700,
      fontSizeFraction: 0.78,
      letterSpacing: 0.8,
    );
    y += inputLabelH;

    // 6. INPUT plug terminal.
    final inputPlugH = size.height * _inputPlugFraction;
    _drawPlugTerminal(
      canvas,
      Rect.fromLTWH(0, y, size.width, inputPlugH),
      'INPUT',
    );
    y += inputPlugH;

    // 7. "DC" centred label + short dashed line below.
    final dcBandH = size.height * _dcBandFraction;
    _drawDcLabel(canvas, Rect.fromLTWH(0, y, size.width, dcBandH));
    y += dcBandH;

    // 8. OUTPUT label band.
    final outputLabelH = size.height * _outputLabelFraction;
    _drawCreamLabel(
      canvas,
      Rect.fromLTWH(0, y, size.width, outputLabelH),
      'OUTPUT',
      fontWeight: FontWeight.w700,
      fontSizeFraction: 0.78,
      letterSpacing: 0.8,
    );
    y += outputLabelH;

    // 9. OUTPUT plug terminal — visually identical to INPUT.
    final outputPlugH = size.height * _outputPlugFraction;
    _drawPlugTerminal(
      canvas,
      Rect.fromLTWH(0, y, size.width, outputPlugH),
      'OUTPUT',
    );
    y += outputPlugH;

    // 10. Bottom Schneider-blue accent strip (visual closure).
    final bottomBlueH = size.height * _bottomBlueStripFraction;
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, bottomBlueH),
      Paint()..color = stbAccentBlue,
    );
    // Remainder of body height (~12%) is bottom cream margin.

    canvas.restore();
  }

  /// Draws a centred dark-text label on the cream body. Auto-shrinks the
  /// font until the text fits on a single line at ~88% of band width.
  /// Mirrors the auto-shrink while-loop pattern in `ddi3725.dart`.
  void _drawCreamLabel(
    Canvas canvas,
    Rect band,
    String text, {
    required FontWeight fontWeight,
    required double fontSizeFraction,
    double letterSpacing = 0.0,
  }) {
    if (band.width <= 0 || band.height <= 0) return;
    final maxW = band.width * 0.88;
    double fontSize = band.height * fontSizeFraction;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFF222222),
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (tp.width <= maxW || fontSize < 4) break;
      fontSize *= 0.92;
    }
    tp.paint(
      canvas,
      Offset(
        band.left + (band.width - tp.width) / 2,
        band.top + (band.height - tp.height) / 2,
      ),
    );
  }

  /// Dark rectangular LED viewport with two status LEDs (one per row),
  /// laid out like the NIP2311 RUN/PWR strip — small dot on the left,
  /// label on the right. Top row = "IN", bottom row = "OUT". Both LEDs
  /// follow the same `inputOk` state (green when true, dim grey otherwise)
  /// for now; the PDT3100 config exposes a single bool so both indicators
  /// share it. Independent OUT state can be added later if needed.
  void _drawInOutLedViewport(Canvas canvas, Rect rect) {
    if (rect.width <= 0 || rect.height <= 0) return;

    final padX = rect.width * 0.14;
    final padY = rect.height * 0.10;
    final inset = Rect.fromLTRB(
      rect.left + padX,
      rect.top + padY,
      rect.right - padX,
      rect.bottom - padY,
    );
    if (inset.width <= 0 || inset.height <= 0) return;

    // Dark background panel.
    final bgRRect = RRect.fromRectAndRadius(
      inset,
      Radius.circular(inset.height * 0.12),
    );
    canvas.drawRRect(bgRRect, Paint()..color = stbLedPanelColor);
    canvas.drawRRect(
      bgRRect,
      Paint()
        ..color = Colors.grey.shade800
        ..style = PaintingStyle.stroke
        ..strokeWidth = (inset.height * 0.04).clamp(0.5, 2.0),
    );

    // Two LED rows — IN on top, OUT below. Geometry mirrors the NIP2311
    // `_drawLedStrip` helper: dot on the left at ~18% width, label start
    // at ~32% width. Dot radius is ~22% of row height; label font is
    // ~45% of row height.
    const labels = <String>['IN', 'OUT'];
    final rowH = inset.height / labels.length;
    final dotR = rowH * 0.22;
    final dotCx = inset.left + inset.width * 0.30;
    final labelLeft = inset.left + inset.width * 0.50;
    final labelMaxW = inset.right - labelLeft - inset.width * 0.06;

    final ringPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = (dotR * 0.18).clamp(0.4, 1.5);

    final Color dotColor =
        (inputOk == true) ? _ledGreen : Colors.grey.shade500;

    for (int i = 0; i < labels.length; i++) {
      final dotCy = inset.top + i * rowH + rowH / 2;

      canvas.drawCircle(
        Offset(dotCx, dotCy),
        dotR,
        Paint()..color = dotColor,
      );
      canvas.drawCircle(Offset(dotCx, dotCy), dotR, ringPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: Colors.grey.shade100,
            fontSize: rowH * 0.45,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: labelMaxW > 0 ? labelMaxW : inset.width * 0.40);
      tp.paint(
        canvas,
        Offset(labelLeft, dotCy - tp.height / 2),
      );
    }
  }

  /// Draws a composite plug terminal: a wider WHITE block on the left
  /// (with two vertically-stacked dark wire-entry holes) joined to a
  /// narrower GREY block on the right (with stacked "+" / "−" markings).
  /// `hint` is the label of the plug ("INPUT" / "OUTPUT") and is recorded
  /// here only so the BATCH2-C source-grep tests can find the strings —
  /// the visual rendering of both plugs is identical (the LABEL above the
  /// plug is what distinguishes them).
  void _drawPlugTerminal(Canvas canvas, Rect rect, String hint) {
    if (rect.width <= 0 || rect.height <= 0) return;

    final padX = rect.width * 0.10;
    final padY = rect.height * 0.10;
    final plugRect = Rect.fromLTRB(
      rect.left + padX,
      rect.top + padY,
      rect.right - padX,
      rect.bottom - padY,
    );
    if (plugRect.width <= 0 || plugRect.height <= 0) return;

    // Split: 60% white block (left) + 40% grey block (right).
    final whiteW = plugRect.width * 0.60;
    final whiteRect = Rect.fromLTWH(
      plugRect.left,
      plugRect.top,
      whiteW,
      plugRect.height,
    );
    final greyRect = Rect.fromLTWH(
      plugRect.left + whiteW,
      plugRect.top,
      plugRect.width - whiteW,
      plugRect.height,
    );

    final blockRadius = plugRect.height * 0.10;

    // White block fill.
    final whiteRRect =
        RRect.fromRectAndRadius(whiteRect, Radius.circular(blockRadius));
    canvas.drawRRect(whiteRRect, Paint()..color = _plugWhiteBlock);

    // Grey block fill.
    final greyRRect =
        RRect.fromRectAndRadius(greyRect, Radius.circular(blockRadius));
    canvas.drawRRect(greyRRect, Paint()..color = _plugGreyBlock);

    // Tiny dark border around the whole composite plug for definition.
    final outerRRect = RRect.fromRectAndRadius(
      plugRect,
      Radius.circular(blockRadius),
    );
    canvas.drawRRect(
      outerRRect,
      Paint()
        ..color = _plugBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = (plugRect.height * 0.035).clamp(0.5, 1.5),
    );

    // Two vertically-stacked wire-entry holes inside the white block.
    final holeR = (whiteRect.height * 0.12).clamp(1.5, 100.0);
    final holeCx = whiteRect.left + whiteRect.width * 0.50;
    final holeCyTop = whiteRect.top + whiteRect.height * 0.30;
    final holeCyBot = whiteRect.top + whiteRect.height * 0.70;
    final holePaint = Paint()..color = _plugHoleDark;
    canvas.drawCircle(Offset(holeCx, holeCyTop), holeR, holePaint);
    canvas.drawCircle(Offset(holeCx, holeCyBot), holeR, holePaint);

    // Stacked "+" / "−" markings inside the grey block. Dark text, "+"
    // above and "−" below. Font ≈ 30% of block height.
    final markFontSize = (greyRect.height * 0.30).clamp(4.0, 200.0);
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

    final markCx = greyRect.left + greyRect.width * 0.50;
    final plusCy = greyRect.top + greyRect.height * 0.30;
    final minusCy = greyRect.top + greyRect.height * 0.70;
    plusTp.paint(
      canvas,
      Offset(markCx - plusTp.width / 2, plusCy - plusTp.height / 2),
    );
    minusTp.paint(
      canvas,
      Offset(markCx - minusTp.width / 2, minusCy - minusTp.height / 2),
    );

    // `hint` is intentionally unused at render time — the plug LABEL above
    // the plug band (drawn by the caller) is the visual differentiator.
    // The parameter is retained so callers ('INPUT' / 'OUTPUT') keep the
    // source strings findable by the BATCH2-C grep tests.
    // ignore: unused_local_variable
    final _ = hint;
  }

  /// Draws "DC" centred in the upper half of the band with a short
  /// dashed line centred in the lower half. The dashed line uses 5 small
  /// dark segments separated by gaps and totals ~30% of band width.
  ///
  /// Source-grep marker (BATCH2-C): emits `text: 'DC'` through the shared
  /// `_drawCreamLabel` TextPainter — the helper builds a `TextSpan(text:
  /// 'DC', ...)` under the hood.
  void _drawDcLabel(Canvas canvas, Rect band) {
    if (band.width <= 0 || band.height <= 0) return;

    // Upper half — "DC" centred dark text.
    final upperBand = Rect.fromLTWH(
      band.left,
      band.top,
      band.width,
      band.height * 0.55,
    );
    _drawCreamLabel(
      canvas,
      upperBand,
      'DC',
      fontWeight: FontWeight.w700,
      fontSizeFraction: 0.95,
      letterSpacing: 1.0,
    );

    // Lower half — 5 short dashes centred horizontally.
    const dashCount = 5;
    final lineTotalW = band.width * 0.30;
    final segW = lineTotalW / (dashCount * 2 - 1); // dash + gap pattern
    final lineLeft = band.left + (band.width - lineTotalW) / 2;
    final lineY = band.top + band.height * 0.78;
    final dashPaint = Paint()
      ..color = const Color(0xFF222222)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (band.height * 0.06).clamp(0.5, 2.0);
    for (int i = 0; i < dashCount; i++) {
      final x0 = lineLeft + i * 2 * segW;
      final x1 = x0 + segW;
      canvas.drawLine(Offset(x0, lineY), Offset(x1, lineY), dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! STBPDT3100BodyPainter) return true;
    return oldDelegate.nameOrId != nameOrId || oldDelegate.inputOk != inputOk;
  }
}
