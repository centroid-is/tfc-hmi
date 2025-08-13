import 'package:flutter/material.dart';
import 'dart:math' as math;

// Usage example widget
class USBIconWidget extends StatelessWidget {
  final double size;
  const USBIconWidget({super.key, this.size = 100.0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size), painter: UsbPortPainter());
  }
}

Path buildUsbPortPath() {
  final Path path = Path();

  // Main outer shell (keeping same aspect ratio)
  path.addRect(Rect.fromLTWH(0, 0, 24, 52));

  // Center connector pins area (keeping same proportions)
  path.addRect(Rect.fromLTWH(6, 6, 8, 39));

  return path;
}

class UsbPortPainter extends CustomPainter {
  final double strokeWidthPx;

  const UsbPortPainter({this.strokeWidthPx = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildUsbPortPath();
    final b = path.getBounds();
    final scale = math.min(size.width / b.width, size.height / b.height);
    final dx = (size.width - b.width * scale) / 2 - b.left * scale;
    final dy = (size.height - b.height * scale) / 2 - b.top * scale;
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    // Draw outer shell with background color
    final outerPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, 24, 52), outerPaint);

    // // Draw inner connector with background color
    // final innerPaint = Paint()
    //   ..color = Colors.white
    //   ..style = PaintingStyle.fill;
    // canvas.drawRect(Rect.fromLTWH(6, 6, 8, 39), innerPaint);

    // Draw outline with stroke color
    final strokePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidthPx / scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Draw both rectangles as outlines
    canvas.drawRect(Rect.fromLTWH(0, 0, 24, 52), strokePaint);
    canvas.drawRect(Rect.fromLTWH(6, 6, 8, 39), strokePaint);
  }

  @override
  bool shouldRepaint(covariant UsbPortPainter oldDelegate) =>
      oldDelegate.strokeWidthPx != strokeWidthPx;
}
