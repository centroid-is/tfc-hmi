import 'package:flutter/material.dart';

class TroutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.orange;

    // Main body
    final body = Path()
      ..moveTo(size.width * 0.2, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.2, size.width * 0.5,
          size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.7, size.height * 0.6, size.width * 0.8,
          size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.7, size.height * 0.5, size.width * 0.2,
          size.height * 0.4)
      ..close();

    canvas.drawPath(body, paint..color = const Color(0xFF4B739D));

    // Tail
    final tail = Path()
      ..moveTo(size.width * 0.8, size.height * 0.4)
      ..lineTo(size.width * 0.95, size.height * 0.3)
      ..lineTo(size.width * 0.95, size.height * 0.5)
      ..close();
    canvas.drawPath(tail, paint..color = const Color(0xFF2F4F6F));

    // Dorsal fin
    final dorsalFin = Path()
      ..moveTo(size.width * 0.3, size.height * 0.35)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.15,
          size.width * 0.5, size.height * 0.35)
      ..quadraticBezierTo(size.width * 0.6, size.height * 0.15,
          size.width * 0.7, size.height * 0.35)
      ..close();
    canvas.drawPath(dorsalFin, paint..color = const Color(0xFF3B5E7A));

    // Pectoral fin
    final pectoralFin = Path()
      ..moveTo(size.width * 0.35, size.height * 0.45)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.5,
          size.width * 0.45, size.height * 0.45)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.6,
          size.width * 0.35, size.height * 0.45)
      ..close();
    canvas.drawPath(pectoralFin, paint..color = const Color(0xFF2F4F6F));

    // Eye
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.4),
      size.width * 0.03,
      paint..color = Colors.black,
    );

    // Spots
    final spotPaint = Paint()
      ..color = const Color(0xFF6B8EA3)
      ..style = PaintingStyle.fill;

    List<Offset> spots = [
      Offset(size.width * 0.35, size.height * 0.38),
      Offset(size.width * 0.45, size.height * 0.42),
      Offset(size.width * 0.55, size.height * 0.38),
      Offset(size.width * 0.65, size.height * 0.42),
    ];

    for (var spot in spots) {
      canvas.drawCircle(spot, size.width * 0.015, spotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TroutWidget extends StatelessWidget {
  final double size;

  const TroutWidget({super.key, this.size = 200});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 0.5),
      painter: TroutPainter(),
    );
  }
}
