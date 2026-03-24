import 'package:flutter/material.dart';

/// Paints a dashed border rectangle.
///
/// Used across all editors to visually mark AI-proposed items.
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashGap;

  DashedBorderPainter({
    this.color = Colors.amber,
    this.strokeWidth = 2.0,
    this.dashWidth = 6.0,
    this.dashGap = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Convert path to dashed path
    final dashedPath = _dashPath(path, dashWidth, dashGap);
    canvas.drawPath(dashedPath, paint);
  }

  Path _dashPath(Path source, double dashWidth, double dashGap) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        result.addPath(
          metric.extractPath(distance, end.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = end + dashGap;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      dashWidth != oldDelegate.dashWidth ||
      dashGap != oldDelegate.dashGap;
}

/// Small AI sparkle badge icon. Positioned top-right on proposed items.
class ProposalBadge extends StatelessWidget {
  final double size;

  const ProposalBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(200),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.auto_awesome, color: Colors.white, size: size),
    );
  }
}

/// Consistent BoxDecoration for AI-proposed items across all editors.
///
/// Semi-transparent amber background with amber border.
BoxDecoration proposalDecoration() => BoxDecoration(
      color: Colors.amber.withAlpha(25),
      border: Border.all(color: Colors.amber, width: 1.5),
      borderRadius: BorderRadius.circular(8),
    );
