import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'ethernet.dart';
import 'usb.dart';
import 'io8.dart';

class CXxxxx extends CustomPainter {
  final double widthMm = 105.5;
  final double heightMm = 100;

  final String name;
  final Color fillColor;
  final Color pwrColor; // PWR box color
  final Color tcColor; // TC box color
  final Color hddColor; // HDD box color
  final Color fb1Color; // FB1 box color
  final Color fb2Color; // FB2 box color

  CXxxxx({
    required this.name,
    this.fillColor = bodyColor,
    this.pwrColor = Colors.transparent,
    this.tcColor = Colors.transparent,
    this.hddColor = Colors.transparent,
    this.fb1Color = Colors.transparent,
    this.fb2Color = Colors.transparent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Base "design" pixels from mm (keeps all your geometry in a consistent design space).
    const double pxPerMm = 96.0 / 25.4;
    final double designW = widthMm * pxPerMm;
    final double designH = heightMm * pxPerMm;

    // Global fit-to-box transform
    final double gScale = math.min(size.width / designW, size.height / designH);
    final double dx = (size.width - designW * gScale) / 2.0;
    final double dy = (size.height - designH * gScale) / 2.0;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(gScale);

    // Strokes that remain ~1px visually
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / gScale;

    final backgroundFill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    // Design-space origin now at (0,0)
    const double left = 0.0;
    const double top = 0.0;
    final double widthPixels = designW;
    final double heightPixels = designH;

    // Outer rectangle
    final rect = Rect.fromLTWH(left, top, widthPixels, heightPixels);
    canvas.drawRect(rect, backgroundFill);
    canvas.drawRect(rect, stroke);

    // Inner rectangle (32×40 mm) at 2.5mm/6mm offsets
    final double innerLeft = left + (2.5 * pxPerMm);
    final double innerTop = top + (6.0 * pxPerMm);
    final double innerWidthPixels = 32.0 * pxPerMm;
    final double innerHeightPixels = 40.0 * pxPerMm;

    final innerRect = Rect.fromLTWH(
      innerLeft,
      innerTop,
      innerWidthPixels,
      innerHeightPixels,
    );
    canvas.drawRect(innerRect, backgroundFill);
    canvas.drawRect(innerRect, stroke);

    // Ethernet (top)
    final double ethernetLeft = innerLeft + (1.0 * pxPerMm);
    final double ethernetTop = innerTop + (2.0 * pxPerMm);
    final double ethernetWidthPixels = 15.0 * pxPerMm;

    canvas.save();
    canvas.translate(ethernetLeft, ethernetTop);
    canvas.scale(ethernetWidthPixels / 100.0, ethernetWidthPixels / 100.0);
    final ethernetPainter =
        EthernetPortPainter(color: Colors.black, strokeWidthPx: 1.0);
    ethernetPainter.paint(canvas, const Size(100, 100));
    canvas.restore();

    // Ethernet (bottom)
    final double ethernet2Top =
        innerTop + innerHeightPixels - (2.0 * pxPerMm) - ethernetWidthPixels;

    canvas.save();
    canvas.translate(ethernetLeft, ethernet2Top);
    canvas.scale(ethernetWidthPixels / 100.0, ethernetWidthPixels / 100.0);
    ethernetPainter.paint(canvas, const Size(100, 100));
    canvas.restore();

    // USB ports (top row)
    final double usbLeft = ethernetLeft + ethernetWidthPixels;
    final double usbWidthPixels = 6.5 * pxPerMm;
    final double usbHeightPixels = 14.0 * pxPerMm;
    final double usbTop =
        ethernetTop + (ethernetWidthPixels / 2) - (usbHeightPixels / 2);

    final usbPainter = UsbPortPainter(strokeWidthPx: 1.0);
    canvas.save();
    canvas.translate(usbLeft, usbTop);
    canvas.scale(usbWidthPixels / 24.0, usbHeightPixels / 52.0);
    usbPainter.paint(canvas, const Size(24, 52));
    canvas.restore();

    final double usb2Left = usbLeft + usbWidthPixels + (2.0 * pxPerMm);
    canvas.save();
    canvas.translate(usb2Left, usbTop);
    canvas.scale(usbWidthPixels / 24.0, usbHeightPixels / 52.0);
    usbPainter.paint(canvas, const Size(24, 52));
    canvas.restore();

    // USB ports (bottom row)
    final double usbBottomLeft = ethernetLeft + ethernetWidthPixels;
    final double usbBottomTop =
        ethernet2Top + (ethernetWidthPixels / 2) - (usbHeightPixels / 2);

    canvas.save();
    canvas.translate(usbBottomLeft, usbBottomTop);
    canvas.scale(usbWidthPixels / 24.0, usbHeightPixels / 52.0);
    usbPainter.paint(canvas, const Size(24, 52));
    canvas.restore();

    final double usbBottom2Left =
        usbBottomLeft + usbWidthPixels + (2.0 * pxPerMm);
    canvas.save();
    canvas.translate(usbBottom2Left, usbBottomTop);
    canvas.scale(usbWidthPixels / 24.0, usbHeightPixels / 52.0);
    usbPainter.paint(canvas, const Size(24, 52));
    canvas.restore();

    // Vertical line 40mm from left
    final double lineLeft = left + (40.0 * pxPerMm);
    canvas.drawLine(
      Offset(lineLeft, top),
      Offset(lineLeft, top + heightPixels),
      stroke,
    );

    // Air-duct box (12×95mm), centered vertically, 62mm from left
    final double boxLeft = left + (62.0 * pxPerMm);
    final double boxWidthPixels = 12.0 * pxPerMm;
    final double boxHeightPixels = 95.0 * pxPerMm;
    final double boxTop = top + (heightPixels - boxHeightPixels) / 2;

    final boxRect =
        Rect.fromLTWH(boxLeft, boxTop, boxWidthPixels, boxHeightPixels);
    canvas.drawRect(boxRect, backgroundFill);
    canvas.drawRect(boxRect, stroke);

    // Split into 39 sections, fill every second
    final double sectionHeight = boxHeightPixels / 39.0;
    final filledPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 39; i++) {
      final double y = boxTop + i * sectionHeight;
      if (i > 0) {
        canvas.drawLine(
            Offset(boxLeft, y), Offset(boxLeft + boxWidthPixels, y), stroke);
      }
      if (i.isOdd) {
        canvas.drawRect(
            Rect.fromLTWH(boxLeft, y, boxWidthPixels, sectionHeight),
            filledPaint);
      }
    }

    // New box (15×27mm) that partially covers the duct; 54mm from left, 9.8mm from top
    final double newBoxLeft = left + (54.0 * pxPerMm);
    final double newBoxTop = top + (9.8 * pxPerMm);
    final double newBoxWidthPixels = 15.0 * pxPerMm;
    final double newBoxHeightPixels = 27.0 * pxPerMm;

    final newBoxRect = Rect.fromLTWH(
      newBoxLeft,
      newBoxTop,
      newBoxWidthPixels,
      newBoxHeightPixels,
    );

    final hidePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    canvas.drawRect(newBoxRect, hidePaint);
    canvas.drawRect(newBoxRect, stroke);

    // Five small boxes 4.1×4.1mm, 1.3mm from right, evenly spaced
    final double smallBoxSize = 4.1 * pxPerMm;
    final double rightMargin = 1.3 * pxPerMm;
    final double leftStart =
        newBoxLeft + newBoxWidthPixels - rightMargin - smallBoxSize;
    final double totalBoxesHeight = 5 * smallBoxSize;
    final double remainingHeight = newBoxHeightPixels - totalBoxesHeight;
    final double gapSize = remainingHeight / 5.0;
    final double startY = newBoxTop + (gapSize / 2.0);

    final List<Color> smallBoxColors = [
      pwrColor,
      tcColor,
      hddColor,
      fb1Color,
      fb2Color,
    ];

    for (int i = 0; i < 5; i++) {
      final double boxY = startY + i * (smallBoxSize + gapSize);
      final smallBoxRect =
          Rect.fromLTWH(leftStart, boxY, smallBoxSize, smallBoxSize);
      final sbPaint = Paint()
        ..color = smallBoxColors[i]
        ..style = PaintingStyle.fill;
      canvas.drawRect(smallBoxRect, sbPaint);
      canvas.drawRect(smallBoxRect, stroke);
    }

    // Text labels to the left of the small boxes
    final List<String> labels = ['PWR', 'TC', 'HDD', 'FB1', 'FB2'];

    const fontScale = 1.0;

    for (int i = 0; i < 5; i++) {
      final double boxY = startY + i * (smallBoxSize + gapSize);
      final double textY = boxY + (smallBoxSize / 2.0);

      final textPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(
            color: Colors.black,
            fontSize: 8.0 * fontScale,
            fontWeight: FontWeight.normal,
            fontFamily: 'Roboto',
          ),
        ),
      );
      textPainter.layout();

      final double textX = leftStart - 2.0 * pxPerMm;
      final double textYOffset = textY - (textPainter.height / 2.0);
      textPainter.paint(canvas, Offset(textX - textPainter.width, textYOffset));
    }

    // Right-side red box (12×95mm) touching the air duct on the right
    final double rightBoxLeft = boxLeft + boxWidthPixels;
    final double rightBoxTop = boxTop;

    final rightBoxRect = Rect.fromLTWH(
      rightBoxLeft,
      rightBoxTop,
      boxWidthPixels,
      boxHeightPixels,
    );

    final beckhoffRedPaint = Paint()
      ..color = const Color(0xFFE30613)
      ..style = PaintingStyle.fill;

    canvas.drawRect(rightBoxRect, beckhoffRedPaint);
    canvas.drawRect(rightBoxRect, stroke);

    // IO8 widget on far right (16mm wide, full height)
    final double io8Width = 16.0 * pxPerMm;
    final double io8Height = heightPixels;
    final double io8Left = left + widthPixels - io8Width;
    final double io8Top = top;

    final io8Painter = IO8Painter(
      ledStates: List.filled(8, IOState.low),
      disconnected: false,
      selected: false,
      topLabels: ('', ''),
      topLabelColors: (null, null),
      name: '',
      bottomLabel: '',
      ioLabels: const ['24V', '0V', '+', '+', '-', '-', 'PE', 'PE'],
      ioLabelColors: const [
        Colors.red,
        Colors.blue,
        Colors.red,
        Colors.red,
        Colors.blue,
        Colors.blue,
        Colors.yellow,
        Colors.yellow,
      ],
      animation: const AlwaysStoppedAnimation(0),
    );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(io8Left, io8Top, io8Width, io8Height));
    canvas.translate(io8Left, io8Top);
    // IO8 aspect is width = height / 6
    canvas.scale(io8Width / (io8Height / 6.0), io8Height / io8Height);
    io8Painter.paint(canvas, Size(io8Height / 6.0, io8Height));
    canvas.restore();

    // Text inside red box (rotated 90°)
    // "BECKHOFF" (white, bigger)
    final beckhoffPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      text: TextSpan(
        text: 'BECKHOFF',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17.0 * fontScale,
          fontWeight: FontWeight.bold,
          fontFamily: 'Roboto',
        ),
      ),
    );
    beckhoffPainter.layout();

    final double beckhoffX = rightBoxLeft + (1.0 * pxPerMm);
    final double beckhoffY = rightBoxTop + boxHeightPixels - (1.0 * pxPerMm);

    canvas.save();
    canvas.translate(beckhoffX, beckhoffY);
    canvas.rotate(-90 * math.pi / 180.0);
    beckhoffPainter.paint(canvas, const Offset(0, 0));
    canvas.restore();

    // "CX5010" (black, smaller; actually whatever `name` is)
    final cxPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      text: TextSpan(
        text: name,
        style: TextStyle(
          color: Colors.black,
          fontSize: 12.0 * fontScale,
          fontWeight: FontWeight.w800,
          fontFamily: 'Roboto',
        ),
      ),
    );
    cxPainter.layout();

    final double cxX = rightBoxLeft + (7.0 * pxPerMm);
    final double cxY = rightBoxTop + boxHeightPixels - (1.0 * pxPerMm);

    canvas.save();
    canvas.translate(cxX, cxY);
    canvas.rotate(-90 * math.pi / 180.0);
    cxPainter.paint(canvas, const Offset(0, 0));
    canvas.restore();

    // Done
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CXxxxx old) {
    return name != old.name ||
        fillColor != old.fillColor ||
        pwrColor != old.pwrColor ||
        tcColor != old.tcColor ||
        hddColor != old.hddColor ||
        fb1Color != old.fb1Color ||
        fb2Color != old.fb2Color;
  }
}

class CXxxxxWidget extends StatelessWidget {
  final String name;
  final Color? pwrColor;
  final Color? tcColor;
  final Color? hddColor;
  final Color? fb1Color;
  final Color? fb2Color;

  const CXxxxxWidget({
    super.key,
    required this.name,
    this.pwrColor,
    this.tcColor,
    this.hddColor,
    this.fb1Color,
    this.fb2Color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CXxxxx(
        name: name,
        pwrColor: pwrColor ?? Colors.transparent,
        tcColor: tcColor ?? Colors.transparent,
        hddColor: hddColor ?? Colors.transparent,
        fb1Color: fb1Color ?? Colors.transparent,
        fb2Color: fb2Color ?? Colors.transparent,
      ),
      // Let parent size it; if you want a fixed preview, set size here.
    );
  }
}
