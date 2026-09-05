import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'hardware.dart';
import 'io8.dart';

class EK1100 extends CustomPainter {
  final double widthMm = 44.0;
  final double heightMm = 100.0;

  final String name;
  /// The device's configured name or id, worn as a marker tag over the
  /// terminal-marker band of the block's own I/O slice — the same tag, in the
  /// same place, that an EL terminal beside it wears. Empty draws nothing, so
  /// an unnamed block is the drawing it always was.
  final String markerLabel;
  final Color fillColor;

  EK1100({
    required this.name,
    this.markerLabel = '',
    this.fillColor = bodyColor,
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

    // Design-space origin now at (0,0)
    const double left = 0.0;
    const double top = 0.0;
    final double widthPixels = designW;
    final double heightPixels = designH;

    // Main box, as a moulding rather than a flat fill, so the coupler reads
    // as the same kind of object as the EL terminals clipped to its right.
    final rect = Rect.fromLTWH(left, top, widthPixels, heightPixels);
    paintHousing(
      canvas,
      RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
      color: fillColor,
      strokeWidth: 1.0 / gScale,
      outline: Colors.black,
    );

    // Vertical line 20mm from left
    final double lineLeft = left + (20.0 * pxPerMm);
    canvas.drawLine(
      Offset(lineLeft, top),
      Offset(lineLeft, top + heightPixels),
      stroke,
    );

    // Ethernet port centered at 10mm from left, 26mm from top
    final double ethernetCenterX = left + (10.0 * pxPerMm);
    final double ethernetCenterY = top + (26.0 * pxPerMm);
    final double ethernetSize = 18 * pxPerMm;

    canvas.save();
    canvas.translate(
      ethernetCenterX - ethernetSize / 2,
      ethernetCenterY - ethernetSize / 2,
    );
    canvas.scale(ethernetSize / 100.0, ethernetSize / 100.0);
    final ethernetPainter = EthernetPortPainter(
      strokeColor: Colors.black,
      strokeWidth: 1.0,
    );
    ethernetPainter.paint(canvas, const Size(100, 100));
    canvas.restore();

    // Second ethernet port 30mm below the first (center to center)
    final double ethernet2CenterY = ethernetCenterY + (30.0 * pxPerMm);

    canvas.save();
    canvas.translate(
      ethernetCenterX - ethernetSize / 2,
      ethernet2CenterY - ethernetSize / 2,
    );
    canvas.scale(ethernetSize / 100.0, ethernetSize / 100.0);
    ethernetPainter.paint(canvas, const Size(100, 100));
    canvas.restore();

    // Text labels to the right of the vertical line
    const fontScale = 1.0;

    // "BECKHOFF" (red, bigger, rotated 90°)
    final beckhoffPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      text: TextSpan(
        text: 'BECKHOFF',
        style: TextStyle(
          color: const Color(0xFFE30613), // Beckhoff red
          fontSize: 17.0 * fontScale,
          fontWeight: FontWeight.bold,
          fontFamily: 'Roboto',
        ),
      ),
    );
    beckhoffPainter.layout();

    final double beckhoffX = lineLeft;
    final double beckhoffY = top + heightPixels - (1.0 * pxPerMm);

    canvas.save();
    canvas.translate(beckhoffX, beckhoffY);
    canvas.rotate(-90 * math.pi / 180.0);
    beckhoffPainter.paint(canvas, const Offset(0, 0));
    canvas.restore();

    // "EK1100" (black, smaller, rotated 90°)
    final ekPainter = TextPainter(
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
    ekPainter.layout();

    final double ekX = lineLeft + (4.0 * pxPerMm);
    final double ekY = top + heightPixels - (1.0 * pxPerMm);

    canvas.save();
    canvas.translate(ekX, ekY);
    canvas.rotate(-90 * math.pi / 180.0);
    ekPainter.paint(canvas, const Offset(0, 0));
    canvas.restore();

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
      markerLabel: markerLabel,
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

    // Done
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EK1100 old) {
    return name != old.name ||
        markerLabel != old.markerLabel ||
        fillColor != old.fillColor;
  }
}

class EK1100Widget extends StatelessWidget {
  final String name;
  final Color? fillColor;
  final double? width;
  final double? height;

  const EK1100Widget({
    super.key,
    required this.name,
    this.fillColor,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? 200, // Default width if none specified
      height: height ?? 400, // Default height if none specified
      child: CustomPaint(
        painter: EK1100(name: name, fillColor: fillColor ?? bodyColor),
      ),
    );
  }
}

/// An RJ45 socket at the aspect the Beckhoff jacks are drawn at.
///
/// Was a DXF trace — forty polylines of hairline that added up to a wireframe
/// outline. What an electrician recognises a jack by is the dark opening, the
/// latch keyway and the gold contacts, none of which an outline has, so the
/// geometry now comes from [paintRj45] and this class is the shim that keeps
/// the call sites (EK1100, EK1110, CX, PS2001, CU2508, and the Advantys
/// NIP2311) unchanged.
class EthernetPortPainter extends CustomPainter {
  final Color strokeColor;
  final double strokeWidth;

  /// Retained for source compatibility. The socket is drawn as a solid part
  /// now, so there is no outline-only mode left to opt out of.
  final bool drawFills;

  EthernetPortPainter({
    this.strokeColor = Colors.black,
    this.strokeWidth = 1.0,
    this.drawFills = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The original fitted its drawing inside 5% padding; keep that so every
    // caller's port lands where it always did.
    paintRj45(
      canvas,
      Rect.fromLTWH(0, 0, size.width, size.height).deflate(
        math.min(size.width, size.height) * 0.05,
      ),
      outline: strokeColor,
      strokeScale: strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant EthernetPortPainter oldDelegate) {
    return oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

// Example usage widget
class EthernetPortIcon extends StatelessWidget {
  final double size;
  final Color color;
  const EthernetPortIcon({
    super.key,
    this.size = 128,
    this.color = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: EthernetPortPainter(strokeColor: color, strokeWidth: 2.0),
    );
  }
}
