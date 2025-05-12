import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ModuleWidget extends StatelessWidget {
  final List<bool> ledStates;
  final double height;
  final bool disconnected;
  final bool selected;
  final (String, String) topLabels;

  ModuleWidget(
      {required this.ledStates,
      this.height = 300,
      this.disconnected = false,
      this.selected = false,
      this.topLabels = ('', '')})
      : assert(ledStates.length == 8);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height / 6,
      height: height,
      child: CustomPaint(
          painter: ModulePainter(
              ledStates: ledStates,
              disconnected: disconnected,
              selected: selected,
              topLabels: topLabels)),
    );
  }
}

class LedBlockWidget extends StatelessWidget {
  final List<bool> ledStates;
  final double height;

  LedBlockWidget({required this.ledStates, this.height = 200});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height / 1.3,
      child: CustomPaint(
        painter: LedBlockPainter(ledStates: ledStates),
      ),
    );
  }
}

class ModulePainter extends CustomPainter {
  final List<bool> ledStates;
  final bool disconnected;
  final bool selected;
  final (String, String) topLabels;
  ModulePainter({
    required this.ledStates,
    this.disconnected = false,
    this.selected = false,
    this.topLabels = ('', ''),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.03;
    // Colors
    final bodyColor = Color(0xFFF7F5E6);
    final labelYellow = Color(0xFFC0C040);
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
        String text, Offset pos, double w, double h, double fs) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: Colors.black,
                fontSize: fs,
                fontWeight: FontWeight.bold)),
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
    for (int i = 0; i < 2; i++) {
      double x = pad + i * (labelW + pad);
      final rect = Rect.fromLTWH(x, pad, labelW, labelH);
      canvas.drawRect(rect, Paint()..color = labelYellow);
      canvas.drawRect(rect, innerBorderPaint);
      drawLabel(i == 0 ? topLabels.$1 : topLabels.$2, Offset(x, pad), labelW,
          labelH, labelH * 0.6);
    }

    // --- Draw LED block ---
    final ledBlock =
        Rect.fromLTWH(pad, ledBlockY, size.width - pad * 2, ledBlockH);
    canvas.save();
    canvas.clipRect(ledBlock);
    canvas.translate(ledBlock.left, ledBlock.top);
    LedBlockPainter(ledStates: ledStates)
        .paint(canvas, Size(ledBlock.width, ledBlock.height));
    canvas.restore();

    // --- Draw I/O sections ---
    for (int s = 0; s < 4; s++) {
      double top = ioAreaY + s * sectionH;
      for (int c = 0; c < 2; c++) {
        double x = pad + c * (labelW + pad);
        // I-label
        final labelRect = Rect.fromLTWH(x, top, labelW, labelH);
        canvas.drawRect(labelRect, Paint()..color = labelYellow);
        canvas.drawRect(labelRect, innerBorderPaint);
        drawLabel(
            'I${s * 2 + c + 1}', Offset(x, top), labelW, labelH, labelH * 0.6);

        // Hole area calculation
        double holeArea = sectionH - labelH;
        double sqSize = holeArea * 0.35;
        double crSize = holeArea * 0.35;
        double gap = holeArea * 0.1;
        double vertPad = (holeArea - sqSize - crSize - gap) / 2;

        // Square slot
        double sqY = top + labelH + vertPad;
        Rect sq = Rect.fromLTWH(
          x + (labelW - sqSize) / 2,
          sqY,
          sqSize,
          sqSize,
        );
        canvas.drawRect(sq, Paint()..color = Colors.grey.shade300);
        canvas.drawRect(sq, innerBorderPaint);

        // Round wire hole
        double crY = sqY + sqSize + gap;
        Offset crCenter = Offset(x + labelW / 2, crY + crSize / 2);
        canvas.drawCircle(
            crCenter, crSize / 2, Paint()..color = Colors.grey.shade300);
        canvas.drawCircle(crCenter, crSize / 2, innerBorderPaint);
      }
    }

    // --- Draw bottom labels ---
    double textLeft = pad;
    double textWidth = size.width - textLeft * 2;
    double beckhoffY = size.height - pad * 1.2 - beckhoffH;
    double el1008Y = beckhoffY - el1008H + 1;

    TextPainter drawLeftLabel(
        String text, Offset pos, double w, double h, double fs) {
      final tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: Colors.black,
                fontSize: fs,
                fontWeight: FontWeight.bold)),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: w, maxWidth: w);
      tp.paint(canvas, Offset(pos.dx, pos.dy + (h - tp.height) / 2));
      return tp;
    }

    drawLeftLabel(
        'EL1008', Offset(textLeft, el1008Y), textWidth, el1008H, el1008H);
    drawLeftLabel('BECKHOFF', Offset(textLeft, beckhoffY), textWidth, beckhoffH,
        beckhoffH);

    // ... keep your original drawLabel for all other labels ...
  }

  @override
  bool shouldRepaint(covariant ModulePainter old) =>
      !listEquals(old.ledStates, ledStates) ||
      old.selected != selected ||
      old.disconnected != disconnected;
}

class LedBlockPainter extends CustomPainter {
  final List<bool> ledStates;
  final (String, String) topLabels;

  LedBlockPainter({
    required this.ledStates,
    this.topLabels = ('', ''),
  }) : assert(ledStates.length == 8);

  @override
  void paint(Canvas canvas, Size size) {
    // Colors
    final backgroundColor = Color(0xFFDDDDDD);
    final borderColor = Colors.grey.shade700;
    final activeColor = Color(0xFF6CA545);
    final inactiveTopColor = Color(0xFFF0F0F0);
    final inactiveBottomColor = Color(0xFFCCCCCC);

    // Calculate dimensions
    final pad = size.width * 0.05;
    final cols = 2;
    final rows = 4;
    final cellW = (size.width - pad * (cols + 1)) / cols;
    final cellH = (size.height - pad * (rows + 1)) / rows;

    // Draw background
    final blockRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(blockRect, Paint()..color = backgroundColor);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;
    canvas.drawRect(blockRect, borderPaint);

    // Draw LEDs
    for (int i = 0; i < 8; i++) {
      int r = i ~/ cols, c = i % cols;
      double cx = pad + c * (cellW + pad);
      double cy = pad + r * (cellH + pad);
      final cellRect = Rect.fromLTWH(cx, cy, cellW, cellH);

      if (ledStates[i]) {
        canvas.drawRect(cellRect, Paint()..color = activeColor);
      } else {
        canvas.drawRect(
          cellRect,
          Paint()
            ..shader = LinearGradient(
              colors: [inactiveTopColor, inactiveBottomColor],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(cellRect),
        );
      }
      canvas.drawRect(cellRect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LedBlockPainter old) =>
      !listEquals(old.ledStates, ledStates);
}
