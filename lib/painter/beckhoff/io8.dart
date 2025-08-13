import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

const bodyColor = Color(0xFFF7F5E6);
const ioLabelColor = Color(0xFFC0C040);

enum IOState { low, high, forcedLow, forcedHigh }

class IO8Widget extends AnimatedWidget {
  final List<IOState> ledStates;
  final double height;
  final bool disconnected;
  final bool selected;
  final (String, String) topLabels;
  final List<String> ioLabels;
  final List<Color> ioLabelColors;
  final String name;
  IO8Widget({
    required this.ledStates,
    this.height = 300,
    this.disconnected = false,
    this.selected = false,
    this.topLabels = ('', ''),
    this.ioLabels = const ['I1', 'I2', 'I3', 'I4', 'I5', 'I6', 'I7', 'I8'],
    this.ioLabelColors = const [
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
    ],
    required this.name,
    required Animation<int> animation,
  })  : assert(ledStates.length == 8 || ledStates.length == 6),
        super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<int>;
    return SizedBox(
      width: height / 6,
      height: height,
      child: CustomPaint(
        painter: IO8Painter(
          ledStates: ledStates,
          disconnected: disconnected,
          selected: selected,
          topLabels: topLabels,
          name: name,
          animation: animation,
          ioLabels: ioLabels,
          ioLabelColors: ioLabelColors,
        ),
      ),
    );
  }
}

class IO8Painter extends CustomPainter {
  final List<IOState> ledStates;
  final bool disconnected;
  final bool selected;
  final (String, String) topLabels;
  final (Color?, Color?) topLabelColors;
  final List<String> ioLabels;
  final List<Color> ioLabelColors;
  final String bottomLabel;
  final Animation<int> animation;
  final String name;
  IO8Painter({
    required this.ledStates,
    this.disconnected = false,
    this.selected = false,
    this.topLabels = ('', ''),
    this.topLabelColors = (
      ioLabelColor,
      ioLabelColor,
    ), // Default yellow for both
    this.ioLabels = const ['I1', 'I2', 'I3', 'I4', 'I5', 'I6', 'I7', 'I8'],
    this.ioLabelColors = const [
      ioLabelColor, // Default yellow for all
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
      ioLabelColor,
    ],
    this.bottomLabel = 'BECKHOFF',
    required this.animation,
    required this.name,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.03;
    // Colors
    final bodyColor = Color(0xFFF7F5E6);
    final outerBorderPaint = Paint()
      ..color = selected ? Colors.orange : Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final innerBorderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final fillPaint = Paint()..color = bodyColor;

    // Draw module body
    final moduleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(size.width * 0.06),
    );
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.width * 0.06),
    );
    canvas.drawRRect(fillRect, fillPaint);
    canvas.drawRRect(moduleRect, outerBorderPaint);

    // Draw exclamation mark if disconnected
    if (disconnected) {
      final iconSize = size.width * 0.3;
      final iconPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      // Draw the dot
      canvas.drawCircle(
        Offset(size.width / 2, size.height * 0.15),
        iconSize * 0.15,
        iconPaint,
      );

      // Draw the line
      final lineRect = Rect.fromLTWH(
        size.width / 2 - iconSize * 0.1,
        size.height * 0.15 + iconSize * 0.2,
        iconSize * 0.2,
        iconSize * 0.5,
      );
      canvas.drawRect(lineRect, iconPaint);
    }

    double pad = size.width * 0.05;
    double labelH = size.height * 0.06;
    double labelW = (size.width - pad * 3) / 2;

    // Text painter helper
    TextPainter drawLabel(
      String text,
      Offset pos,
      double w,
      double h,
      double fs,
    ) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fs,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: w, maxWidth: w);
      tp.paint(canvas, Offset(pos.dx, pos.dy + (h - tp.height) / 2));
      return tp;
    }

    // --- Calculate heights for all elements ---
    double topLabelsH = labelH + pad * 2;
    double ledBlockH = size.height * 0.22;
    double ledBlockY = topLabelsH;
    double ledBlockBottom = ledBlockY + ledBlockH;

    // Reserve space for bottom labels and padding
    double bottomLabelH = labelH * 0.85;
    double bottomPad = pad * 0.7;
    double el1008H = labelH * 0.5;
    double beckhoffH = labelH * 0.34;
    double bottomLabelsTotal = el1008H + beckhoffH + bottomPad;

    // Calculate available height for I/O sections (wire thingy gets all extra space)
    double ioAreaY = ledBlockBottom + pad;
    double ioAreaH = size.height - ioAreaY - bottomLabelsTotal;
    double sectionH =
        ioAreaH / 4; // Each I/O section gets 1/4 of the available space

    // --- Draw top labels (07/08) ---
    if (topLabels.$1 != '' && topLabels.$2 != '') {
      for (int i = 0; i < 2; i++) {
        double x = pad + i * (labelW + pad);
        final rect = Rect.fromLTWH(x, pad, labelW, labelH);
        canvas.drawRect(
          rect,
          Paint()
            ..color = i == 0
                ? topLabelColors.$1 ?? Colors.transparent
                : topLabelColors.$2 ?? Colors.transparent,
        ); // Use tuple access
        canvas.drawRect(rect, innerBorderPaint);
        drawLabel(
          i == 0 ? topLabels.$1 : topLabels.$2,
          Offset(x, pad),
          labelW,
          labelH,
          labelH * 0.6,
        );
      }
    }

    // --- Draw LED block ---
    final ledBlock = Rect.fromLTWH(
      0, // Start from left edge instead of pad
      ledBlockY,
      size.width - pad,
      ledBlockH,
    );

    // Draw the LED block at ledBlockY position without clipping
    canvas.save();
    canvas.translate(0, ledBlockY);

    // Choose the appropriate painter based on LED count
    if (ledStates.length == 6) {
      IO6LedBlockPainter(
        ledStates: ledStates,
        animation: animation,
      ).paint(canvas, Size(ledBlock.width, ledBlock.height));
    } else {
      IO8LedBlockPainter(
        ledStates: ledStates,
        animation: animation,
      ).paint(canvas, Size(ledBlock.width, ledBlock.height));
    }

    canvas.restore();

    // --- Draw I/O sections ---
    for (int s = 0; s < 4; s++) {
      double top = ioAreaY + s * sectionH;
      for (int c = 0; c < 2; c++) {
        double x = pad + c * (labelW + pad);
        int labelIndex = s * 2 + c;

        // I-label
        final labelRect = Rect.fromLTWH(x, top, labelW, labelH);
        canvas.drawRect(
          labelRect,
          Paint()..color = ioLabelColors[labelIndex],
        ); // Use color from array
        canvas.drawRect(labelRect, innerBorderPaint);
        drawLabel(
          ioLabels[labelIndex],
          Offset(x, top),
          labelW,
          labelH,
          labelH * 0.5,
        );

        // Hole area calculation
        double holeArea = sectionH - labelH;
        double sqSize = holeArea * 0.35;
        double crSize = holeArea * 0.35;
        double gap = holeArea * 0.1;
        double vertPad = (holeArea - sqSize - crSize - gap) / 2;

        // Square slot
        double sqY = top + labelH + vertPad;
        Rect sq = Rect.fromLTWH(x + (labelW - sqSize) / 2, sqY, sqSize, sqSize);
        canvas.drawRect(sq, Paint()..color = Colors.grey.shade300);
        canvas.drawRect(sq, innerBorderPaint);

        // Round wire hole
        double crY = sqY + sqSize + gap;
        Offset crCenter = Offset(x + labelW / 2, crY + crSize / 2);
        canvas.drawCircle(
          crCenter,
          crSize / 2,
          Paint()..color = Colors.grey.shade300,
        );
        canvas.drawCircle(crCenter, crSize / 2, innerBorderPaint);
      }
    }

    // --- Draw bottom labels ---
    double textLeft = pad;
    double textWidth = size.width - textLeft * 2;
    double beckhoffY = size.height - pad * 1.2 - beckhoffH;
    double el1008Y = beckhoffY - el1008H + 1;

    TextPainter drawLeftLabel(
      String text,
      Offset pos,
      double w,
      double h,
      double fs,
    ) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            fontSize: fs,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: w, maxWidth: w);
      tp.paint(canvas, Offset(pos.dx, pos.dy + (h - tp.height) / 2));
      return tp;
    }

    drawLeftLabel(name, Offset(textLeft, el1008Y), textWidth, el1008H, el1008H);
    drawLeftLabel(
      bottomLabel,
      Offset(textLeft, beckhoffY),
      textWidth,
      beckhoffH,
      beckhoffH,
    );

    // ... keep your original drawLabel for all other labels ...
  }

  @override
  bool shouldRepaint(covariant IO8Painter old) => true;
}

// Base class with shared functionality
abstract class BaseLedBlockPainter extends CustomPainter {
  final List<IOState> ledStates;
  final (String, String) topLabels;
  final Animation<int> animation;

  BaseLedBlockPainter({
    required this.ledStates,
    this.topLabels = ('', ''),
    required this.animation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawBorder(canvas, size);
    _drawLeds(canvas, size);
  }

  // Shared methods
  void _drawBackground(Canvas canvas, Size size) {
    final backgroundColor = Color(0xFFDDDDDD);
    final blockRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(blockRect, Paint()..color = backgroundColor);
  }

  void _drawBorder(Canvas canvas, Size size) {
    final borderColor = Colors.grey.shade700;
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;

    final blockRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(blockRect, borderPaint);
  }

  void _drawLed(Canvas canvas, Rect rect, IOState state, Paint borderPaint) {
    final activeColor = Color(0xFF6CA545);
    final inactiveTopColor = Color(0xFFF0F0F0);
    final inactiveBottomColor = Color(0xFFCCCCCC);

    // Draw LED fill
    if (state == IOState.high || state == IOState.forcedHigh) {
      canvas.drawRect(rect, Paint()..color = activeColor);
    } else {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [inactiveTopColor, inactiveBottomColor],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(rect),
      );
    }

    // Draw LED border
    Paint thisBorder = Paint.from(borderPaint)
      ..color = state == IOState.forcedHigh || state == IOState.forcedLow
          ? Colors.red.withAlpha(animation.value)
          : borderPaint.color;
    canvas.drawRect(rect, thisBorder);
  }

  // Abstract method that each subclass must implement
  void _drawLeds(Canvas canvas, Size size);

  @override
  bool shouldRepaint(covariant BaseLedBlockPainter old) =>
      !listEquals(old.ledStates, ledStates) ||
      old.animation.value != animation.value;
}

// 8-LED implementation (original layout)
class IO8LedBlockPainter extends BaseLedBlockPainter {
  IO8LedBlockPainter({
    required super.ledStates,
    super.topLabels,
    required super.animation,
  }) : assert(ledStates.length == 8);

  @override
  void _drawLeds(Canvas canvas, Size size) {
    final pad = size.width * 0.05;
    const cols = 2;
    const rows = 4;
    final cellW = (size.width - pad * (cols + 1)) / cols;
    final cellH = (size.height - pad * (rows + 1)) / rows;

    final borderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;

    // Draw LEDs in 2x4 grid
    for (int i = 0; i < 8; i++) {
      int r = i ~/ cols, c = i % cols;
      double cx = pad + c * (cellW + pad);
      double cy = pad + r * (cellH + pad);
      final cellRect = Rect.fromLTWH(cx, cy, cellW, cellH);
      _drawLed(canvas, cellRect, ledStates[i], borderPaint);
    }
  }
}

// 6-LED implementation (new layout)
class IO6LedBlockPainter extends BaseLedBlockPainter {
  IO6LedBlockPainter({
    required super.ledStates,
    super.topLabels,
    required super.animation,
  }) : assert(ledStates.length == 6);

  @override
  void _drawLeds(Canvas canvas, Size size) {
    final pad = size.width * 0.05;
    final topBottomHeight = size.height * 0.25;
    const cols = 2;
    const rows = 4;
    final middleCellW = (size.width - pad * (cols + 1)) / cols;
    final middleCellH = (size.height - pad * (rows + 1)) / rows;

    final borderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;

    // Top LED (big)
    final topRect =
        Rect.fromLTWH(pad, pad, size.width - pad * 2, topBottomHeight - pad);
    _drawLed(canvas, topRect, ledStates[0], borderPaint);

    // Middle LEDs (2x2 grid)
    for (int i = 0; i < 4; i++) {
      int r = (i + 2) ~/ 2, c = (i + 2) % 2;
      double cx = pad + c * (middleCellW + pad);
      double cy = pad + r * (middleCellH + pad);
      final cellRect = Rect.fromLTWH(cx, cy, middleCellW, middleCellH);
      _drawLed(canvas, cellRect, ledStates[i + 1], borderPaint);
    }

    // Bottom LED (big)
    final bottomRect = Rect.fromLTWH(pad, size.height - topBottomHeight,
        size.width - pad * 2, topBottomHeight - pad);
    _drawLed(canvas, bottomRect, ledStates[5], borderPaint);
  }
}
