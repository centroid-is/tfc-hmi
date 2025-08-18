import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'io8.dart';

class EK1100 extends CustomPainter {
  final double widthMm = 44.0;
  final double heightMm = 100.0;

  final String name;
  final Color fillColor;

  EK1100({
    required this.name,
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

    final backgroundFill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    // Design-space origin now at (0,0)
    const double left = 0.0;
    const double top = 0.0;
    final double widthPixels = designW;
    final double heightPixels = designH;

    // Main box
    final rect = Rect.fromLTWH(left, top, widthPixels, heightPixels);
    canvas.drawRect(rect, backgroundFill);
    canvas.drawRect(rect, stroke);

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
    return name != old.name || fillColor != old.fillColor;
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

class EthernetPortPainter extends CustomPainter {
  final Color strokeColor;
  final double strokeWidth;
  final bool drawFills;

  EthernetPortPainter({
    this.strokeColor = Colors.black,
    this.strokeWidth = 1.0,
    this.drawFills = false,
  });

  // Raw geometry in DXF coordinates (unscaled, unflipped)
  static const double _minX = 321.29203;
  static const double _minY = 528.911365;
  static const double _maxX = 374.77203;
  static const double _maxY = 593.541365;
  static const double _width = 53.48;
  static const double _height = 64.63;

  static final List<Rect> _rects = <Rect>[
    Rect.fromLTWH(321.29203, 528.911365, 53.48, 64.63),
  ];

  // Pairs of points per line: [p0, p1, p2, p3, ...]
  static final List<Offset> _linePoints = <Offset>[];

  // Each polyline is a list of Offsets. Closed polylines include the end=begin point.
  static final List<List<Offset>> _polylines = <List<Offset>>[
    [Offset(322.19903, 592.029365), Offset(322.19903, 530.423365)],
    [Offset(321.29203, 591.769365), Offset(322.19903, 591.769365)],
    [
      Offset(326.73403, 575.437365),
      Offset(326.73403, 588.665365),
      Offset(334.48303, 588.665365),
    ],
    [
      Offset(326.73403, 533.825365),
      Offset(326.73403, 547.053365),
      Offset(334.48303, 547.053365),
    ],
    [Offset(322.57703, 530.045365), Offset(373.22303, 530.045365)],
    [
      Offset(334.48303, 588.665365),
      Offset(334.48303, 575.437365),
      Offset(326.73403, 575.437365),
    ],
    [
      Offset(334.48303, 547.053365),
      Offset(334.48303, 533.825365),
      Offset(326.73403, 533.825365),
    ],
    [Offset(335.80503, 538.549365), Offset(335.80503, 548.376365)],
    [Offset(343.36403, 538.549365), Offset(335.80503, 538.549365)],
    [Offset(343.36403, 537.604365), Offset(343.36403, 538.549365)],
    [Offset(355.08103, 537.604365), Offset(343.36403, 537.604365)],
    [Offset(355.08103, 538.549365), Offset(355.08103, 537.604365)],
    [Offset(362.64003, 538.549365), Offset(355.08103, 538.549365)],
    [Offset(362.64003, 583.941365), Offset(362.64003, 538.549365)],
    [Offset(355.08103, 583.941365), Offset(362.64003, 583.941365)],
    [Offset(355.08103, 584.886365), Offset(355.08103, 583.941365)],
    [Offset(343.36403, 584.886365), Offset(355.08103, 584.886365)],
    [Offset(373.60103, 530.423365), Offset(373.60103, 592.029365)],
    [Offset(373.22303, 592.407365), Offset(322.57703, 592.407365)],
    [
      Offset(335.80503, 548.376365),
      Offset(330.13603, 548.376365),
      Offset(330.13603, 552.155365),
      Offset(323.14403, 552.155365),
      Offset(323.14403, 570.335365),
      Offset(330.13603, 570.335365),
      Offset(330.13603, 574.114365),
      Offset(335.80503, 574.114365),
      Offset(335.80503, 583.941365),
      Offset(343.36403, 583.941365),
      Offset(343.36403, 584.886365),
    ],
    [Offset(333.38603, 592.407365), Offset(333.38603, 593.541365)],
    [Offset(327.39603, 546.864365), Offset(333.82103, 546.864365)],
    [Offset(327.01803, 534.391365), Offset(327.01803, 546.486365)],
    [Offset(333.82103, 534.014365), Offset(327.39603, 534.014365)],
    [Offset(334.19903, 546.486365), Offset(334.19903, 534.391365)],
    [Offset(327.39603, 588.477365), Offset(333.82103, 588.477365)],
    [Offset(327.01803, 576.004365), Offset(327.01803, 588.099365)],
    [Offset(333.82103, 575.626365), Offset(327.39603, 575.626365)],
    [Offset(334.19903, 588.099365), Offset(334.19903, 576.004365)],
    [Offset(373.22303, 592.029365), Offset(373.22303, 530.423365)],
    [Offset(322.57703, 592.029365), Offset(373.22303, 592.029365)],
    [Offset(322.57703, 530.423365), Offset(322.57703, 592.029365)],
    [Offset(373.22303, 530.423365), Offset(322.57703, 530.423365)],
    [Offset(322.57703, 592.029365), Offset(322.19903, 592.029365)],
    [
      Offset(322.19903, 530.423365),
      Offset(322.57703, 530.423365),
      Offset(322.57703, 530.045365),
    ],
    [Offset(373.22303, 530.045365), Offset(373.22303, 530.423365)],
    [Offset(373.22303, 592.029365), Offset(373.22303, 592.407365)],
    [Offset(322.57703, 592.407365), Offset(322.57703, 592.029365)],
    [Offset(373.22303, 530.423365), Offset(373.60103, 530.423365)],
    [Offset(373.60103, 592.029365), Offset(373.22303, 592.029365)],
  ];

  // Circles: [cx, cy, r]
  static final List<List<double>> _circles = <List<double>>[];

  // Arcs: [cx, cy, r, startDeg, endDeg]
  static final List<List<double>> _arcs = <List<double>>[];

  @override
  void paint(Canvas canvas, Size size) {
    // Compute uniform scale to fit inside size with 5% padding
    const pad = 0.05;
    final availW = size.width * (1 - 2 * pad);
    final availH = size.height * (1 - 2 * pad);
    final sx = availW / _width;
    final sy = availH / _height;
    final scale = sx < sy ? sx : sy;

    // Center within the canvas
    final drawW = _width * scale;
    final drawH = _height * scale;
    final tx = (size.width - drawW) / 2;
    final ty = (size.height - drawH) / 2;

    // DXF Y is up; Flutter Y is down. We flip Y via canvas.scale(1, -1)
    canvas.save();
    // Move to drawing area origin
    canvas.translate(
      tx,
      ty + drawH,
    ); // after Y-flip, origin at bottom-left of draw rect
    canvas.scale(scale, -scale);
    // Translate the DXF min to (0,0)
    canvas.translate(-_minX, -_minY);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..color = strokeColor
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = strokeColor.withOpacity(0.08);

    // Rectangles
    for (final r in _rects) {
      if (drawFills) canvas.drawRect(r, fillPaint);
      canvas.drawRect(r, paint);
    }

    // Lines
    for (int i = 0; i + 1 < _linePoints.length; i += 2) {
      canvas.drawLine(_linePoints[i], _linePoints[i + 1], paint);
    }

    // Polylines
    for (final poly in _polylines) {
      if (poly.isEmpty) continue;
      final path = Path()..moveTo(poly.first.dx, poly.first.dy);
      for (int i = 1; i < poly.length; i++) {
        path.lineTo(poly[i].dx, poly[i].dy);
      }
      if (drawFills) canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, paint);
    }

    // Circles
    for (final c in _circles) {
      final center = Offset(c[0], c[1]);
      final r = c[2];
      if (drawFills) canvas.drawCircle(center, r, fillPaint);
      canvas.drawCircle(center, r, paint);
    }

    // Arcs
    for (final a in _arcs) {
      final center = Offset(a[0], a[1]);
      final r = a[2];
      final startRad = a[3] * math.pi / 180.0;
      final sweepRad = (a[4] - a[3]) * math.pi / 180.0;
      final rect = Rect.fromCircle(center: center, radius: r);
      final path = Path()..addArc(rect, startRad, sweepRad);
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EthernetPortPainter oldDelegate) {
    return oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.drawFills != drawFills;
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
