import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ModuleWidget extends StatelessWidget {
  final List<bool> ledStates;
  final double width;
  final bool disconnected;
  ModuleWidget(
      {required this.ledStates, this.width = 80, this.disconnected = false})
      : assert(ledStates.length == 8);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: width * 6.0,
        child: CustomPaint(painter: ModulePainter(ledStates: ledStates)),
      );
}

class ModulePainter extends CustomPainter {
  final List<bool> ledStates;
  ModulePainter({required this.ledStates});

  @override
  void paint(Canvas canvas, Size size) {
    // Colors
    final bodyColor = Color(0xFFF7F5E6);
    final labelYellow = Color(0xFFC0C040);
    final borderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.03;
    final fillPaint = Paint()..color = bodyColor;

    // Draw module body
    final moduleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.width * 0.06),
    );
    canvas.drawRRect(moduleRect, fillPaint);
    canvas.drawRRect(moduleRect, borderPaint);

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
      canvas.drawRect(rect, borderPaint);
      drawLabel(
          i == 0 ? '07' : '08', Offset(x, pad), labelW, labelH, labelH * 0.6);
    }

    // --- Draw LED block ---
    final ledBlock =
        Rect.fromLTWH(pad, ledBlockY, size.width - pad * 2, ledBlockH);
    canvas.drawRect(ledBlock, Paint()..color = Color(0xFFDDDDDD));
    canvas.drawRect(ledBlock, borderPaint);

    // Draw LEDs
    int cols = 2, rows = 4;
    double cellW = (ledBlock.width - pad * (cols + 1)) / cols;
    double cellH = (ledBlock.height - pad * (rows + 1)) / rows;
    for (int i = 0; i < 8; i++) {
      int r = i ~/ cols, c = i % cols;
      double cx = ledBlock.left + pad + c * (cellW + pad);
      double cy = ledBlock.top + pad + r * (cellH + pad);
      final cellRect = Rect.fromLTWH(cx, cy, cellW, cellH);
      if (ledStates[i]) {
        canvas.drawRect(cellRect, Paint()..color = Color(0xFF6CA545));
      } else {
        canvas.drawRect(
          cellRect,
          Paint()
            ..shader = LinearGradient(
              colors: [Color(0xFFF0F0F0), Color(0xFFCCCCCC)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(cellRect),
        );
      }
      canvas.drawRect(cellRect, borderPaint);
    }

    // --- Draw I/O sections ---
    for (int s = 0; s < 4; s++) {
      double top = ioAreaY + s * sectionH;
      for (int c = 0; c < 2; c++) {
        double x = pad + c * (labelW + pad);
        // I-label
        final labelRect = Rect.fromLTWH(x, top, labelW, labelH);
        canvas.drawRect(labelRect, Paint()..color = labelYellow);
        canvas.drawRect(labelRect, borderPaint);
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
        canvas.drawRect(sq, borderPaint);

        // Round wire hole
        double crY = sqY + sqSize + gap;
        Offset crCenter = Offset(x + labelW / 2, crY + crSize / 2);
        canvas.drawCircle(
            crCenter, crSize / 2, Paint()..color = Colors.grey.shade300);
        canvas.drawCircle(crCenter, crSize / 2, borderPaint);
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
      !listEquals(old.ledStates, ledStates);
}
