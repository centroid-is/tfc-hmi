// STBNIP2311 body painter + widget — Schneider Advantys STB Ethernet
// Modbus/TCP network interface module (decorative head adapter).
//
// Locked by `.planning/phases/03-stbnip2311-ethernet-head-adapter/03-CONTEXT.md`:
//
// - DECORATIVE ONLY: no PLC state keys. The body painter renders the five
//   status LEDs (RUN / PWR / ERR / ST / TEST) in a FIXED "normal" state —
//   RUN+PWR green, ERR+ST+TEST dim grey. Real-hardware status is firmware-
//   driven and NOT exposed as Modbus coils. The HMI asset is the visual
//   identity anchor, not a live status surface.
//
// - Aspect ratio per the NIP2311 DXF bounding box (~58 × 82 mm — smaller
//   than the IO modules' 107 × 152 mm). Width-to-height ratio ≈ 0.71.
//
// - Body layout (top → bottom, fractions of `size.height`):
//     1. Top label strip       (~10%)  Schneider blue, "NIP2311" white text
//                                       + MAC ID placeholder.
//     2. Status LED strip      (~30%)  Five labeled LEDs (column-stacked).
//     3. Schneider blue band   (~7%)   "Ethernet Modbus/TCP 10/100T" subtitle.
//     4. Dual RJ45 ports       (~38%)  Stacked vertically via `EthernetPortPainter`
//                                       reused VERBATIM from beckhoff/ek1100.dart
//                                       (cross-vendor reuse is intentional — the
//                                       RJ45 jack glyph is shared between
//                                       Schneider and Beckhoff).
//     5. Bottom whitespace     (~15%)  Intentionally blank since BATCH2 fixes
//                                       removed the decorative voltage rating
//                                       and vendor branding (Defects D + F).
//
// Conventions:
// - Body cream from `bodyColor` (re-exported through io16.dart from Beckhoff —
//   QUAL-02 fixed body color, not theme-driven).
// - Schneider blue (`stbAccentBlue`) imported from ddi3725.dart — same
//   constant as the I/O modules so the family stays visually coherent.
// - Status LED palette: green = `Color(0xFF6CA545)` (operator-recognizable
//   live green, matches the RDY indicator in ddi3725.dart); dim grey =
//   `Colors.grey.shade400` (matches the stale/disconnected treatment).
//
// `shouldRepaint` returns false when the painter's only input — `nameOrId` —
// is unchanged. Cross-runtimeType comparisons return true (Pitfall 3 guard).

import 'package:flutter/material.dart';

import 'ddi3725.dart' show stbAccentBlue, kStbCornerRadiusFraction, stbBodyStrokeWidth, stbBodyBorderColor;
import 'io16.dart' show bodyColor;
import 'package:tfc/painter/beckhoff/ek1100.dart' show EthernetPortPainter;

/// Aspect ratio width / height for the NIP2311 body.
///
/// BATCH2 Defect E: switched from the DXF-derived 58/82 ≈ 0.707 (wide+squat)
/// Real Schneider STBNIP2311 dimensions: 38.85 mm wide × 128.25 mm tall →
/// aspect ≈ 0.303. The NIP head is the widest in the Advantys STB family
/// (head adapter with dual RJ45 ports needs more horizontal real estate
/// than a 16-channel I/O module). The DXF for NIP2311 is corrupted/wrong
/// in `.planning/research/dxf/` so we use the datasheet dimensions.
const double kNIP2311AspectRatio = 0.303;

/// Widget wrapper around [STBNIP2311BodyPainter]. Decorative-only: takes
/// just a `nameOrId` (rendered as a small caption above the body so
/// operators can distinguish multiple stacked head adapters).
///
/// Aspect ratio is locked at the NIP2311 DXF bounding box (~58 × 82 mm) so
/// the module visually reads as the narrower head module beside the wider
/// I/O modules in a stack.
class STBNIP2311Widget extends StatelessWidget {
  final String nameOrId;
  final double height;

  // Asserts ban a const constructor here — same pattern as the I/O module
  // widgets in this package. The lint is intentionally silenced.
  // ignore: prefer_const_constructors_in_immutables
  STBNIP2311Widget({
    super.key,
    required this.nameOrId,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    final width = height * kNIP2311AspectRatio;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        size: Size(width, height),
        painter: STBNIP2311BodyPainter(nameOrId: nameOrId),
      ),
    );
  }
}

/// Body painter for the NIP2311 module faceplate. Owns the cream body
/// chrome, the top Schneider-blue label strip, the five fixed-state status
/// LEDs, the Schneider-blue subtitle band, the dual RJ45 ports (delegated
/// to [EthernetPortPainter]), and the bottom decorative power footer.
class STBNIP2311BodyPainter extends CustomPainter {
  final String nameOrId;

  STBNIP2311BodyPainter({required this.nameOrId});

  // Layout fractions, top → bottom. Sum is normalized to ~1.0; minor padding
  // is absorbed inside each region.
  static const double _topStripFraction = 0.10;
  static const double _ledStripFraction = 0.30;
  static const double _subtitleBandFraction = 0.07;
  static const double _ethernetFraction = 0.38;
  // Slice retained for layout-stability — the 15% trailing band that used
  // to carry the decorative voltage / vendor footer (removed by BATCH2
  // Defects D + F) is preserved as blank whitespace below the RJ45 ports
  // so the rest of the painter's layout fractions do not need to shift.
  // ignore: unused_field
  static const double _bottomFooterFraction = 0.15;

  // Status-LED palette — fixed normal state.
  static const Color _ledGreen = Color(0xFF6CA545);
  static const List<String> _ledLabels = <String>[
    'RUN',
    'PWR',
    'ERR',
    'ST',
    'TEST',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = stbBodyStrokeWidth(size);
    final outerBorderPaint = Paint()
      ..color = stbBodyBorderColor
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
    // Outline INSET by half stroke — see ddi3725.dart for the full
    // rationale. Eliminates the recurring "cream extends past the
    // border" symptom.
    final outlineInset = strokeWidth / 2;
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(outlineInset, outlineInset,
          size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(
          (cornerR - outlineInset).clamp(0.0, double.infinity)),
    );
    canvas.drawRRect(fillRect, fillPaint);
    canvas.drawRRect(outerRect, outerBorderPaint);

    // Interior chrome clipped to OUTLINE rect (not fillRect) so the
    // Schneider-blue strip + subtitle band + ethernet-port region all
    // stay strictly inside the painted border.
    canvas.save();
    canvas.clipRRect(outerRect);

    double y = 0.0;

    // 2. Top blue label strip with "NIP2311" + MAC ID placeholder.
    final topStripH = size.height * _topStripFraction;
    final topStripRect = Rect.fromLTWH(0, y, size.width, topStripH);
    canvas.drawRect(topStripRect, Paint()..color = stbAccentBlue);
    _drawTopLabelText(canvas, topStripRect);
    y += topStripH;

    // 3. Status LED strip — 5 LEDs in a vertical column.
    final ledStripH = size.height * _ledStripFraction;
    final ledStripRect = Rect.fromLTWH(0, y, size.width, ledStripH);
    _drawLedStrip(canvas, ledStripRect);
    y += ledStripH;

    // 4. Schneider blue subtitle band.
    final subtitleH = size.height * _subtitleBandFraction;
    final subtitleRect = Rect.fromLTWH(0, y, size.width, subtitleH);
    canvas.drawRect(subtitleRect, Paint()..color = stbAccentBlue);
    _drawSubtitleText(canvas, subtitleRect);
    y += subtitleH;

    // 5. Dual RJ45 ports — two stacked vertically.
    final ethernetH = size.height * _ethernetFraction;
    final ethernetRect = Rect.fromLTWH(0, y, size.width, ethernetH);
    _drawEthernetPorts(canvas, ethernetRect);
    y += ethernetH;

    // 6. BATCH2 Defects D + F: bottom-footer region intentionally left
    // blank — the previous decorative voltage-rating and vendor-branding
    // text was removed at the user's request. The `_bottomFooterFraction`
    // slice of the body height is preserved as whitespace so the rest of
    // the layout (header, LEDs, subtitle, ports) does not need to reflow.
    canvas.restore();
  }

  void _drawTopLabelText(Canvas canvas, Rect strip) {
    // Auto-shrink the title font until it fits in the strip's usable width.
    // See ddi3725.dart for the design rationale.
    final maxW = strip.width * 0.88;
    double fontSize = strip.height * 0.42;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: 'NIP2311',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (tp.width <= maxW || fontSize < 4) break;
      fontSize *= 0.92;
    }
    final dy = strip.top + (strip.height - tp.height) / 2;
    final dx = strip.left + (strip.width - tp.width) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  void _drawLedStrip(Canvas canvas, Rect rect) {
    // Five LEDs evenly distributed top-to-bottom. Each row: dot on left,
    // label on right. The dot occupies ~22% of the row height; labels use
    // ~55% of the row height as font size.
    final rowH = rect.height / _ledLabels.length;
    final dotR = rowH * 0.22;
    final dotCx = rect.left + rect.width * 0.18;
    final labelLeft = rect.left + rect.width * 0.32;
    final labelMaxW = rect.width - (labelLeft - rect.left) - rect.width * 0.05;

    final ringPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = dotR * 0.18;

    for (int i = 0; i < _ledLabels.length; i++) {
      final rowY = rect.top + i * rowH;
      final dotCy = rowY + rowH / 2;

      // Fixed normal state: RUN (0) + PWR (1) green, ERR/ST/TEST (2..4) dim grey.
      final Color dotColor = (i < 2) ? _ledGreen : Colors.grey.shade400;

      canvas.drawCircle(
        Offset(dotCx, dotCy),
        dotR,
        Paint()..color = dotColor,
      );
      canvas.drawCircle(Offset(dotCx, dotCy), dotR, ringPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: _ledLabels[i],
          style: TextStyle(
            color: Colors.black,
            fontSize: rowH * 0.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: labelMaxW);
      tp.paint(
        canvas,
        Offset(labelLeft, dotCy - tp.height / 2),
      );
    }
  }

  void _drawSubtitleText(Canvas canvas, Rect band) {
    // Auto-shrink so the long "Ethernet Modbus/TCP 10/100T" caption fits
    // on a single line inside the band — slim aspect ratios used to push
    // the caption past the band's blue background.
    final maxW = band.width * 0.94;
    double fontSize = band.height * 0.50;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
          text: 'Ethernet Modbus/TCP 10/100T',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
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

  void _drawEthernetPorts(Canvas canvas, Rect rect) {
    // Two ports stacked vertically. EthernetPortPainter is square; size the
    // port to fit horizontal padding while leaving a small inter-port gap.
    final pad = rect.width * 0.18;
    final innerW = rect.width - pad * 2;
    final gap = rect.height * 0.08;
    final portH = (rect.height - gap) / 2;
    final portSize = portH < innerW ? portH : innerW;
    final portLeft = rect.left + (rect.width - portSize) / 2;

    final painter = EthernetPortPainter(
      strokeColor: Colors.black,
      strokeWidth: 1.0,
    );

    // Top port.
    canvas.save();
    canvas.translate(portLeft, rect.top + (portH - portSize) / 2);
    painter.paint(canvas, Size(portSize, portSize));
    canvas.restore();

    // Bottom port.
    canvas.save();
    canvas.translate(
      portLeft,
      rect.top + portH + gap + (portH - portSize) / 2,
    );
    painter.paint(canvas, Size(portSize, portSize));
    canvas.restore();
  }


  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! STBNIP2311BodyPainter) return true;
    return oldDelegate.nameOrId != nameOrId;
  }
}
