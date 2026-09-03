import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'hardware.dart';

/// The ELxxxx housing. Beckhoff moulds these in a light neutral grey, not the
/// cream this drawing carried for years — put the mimic beside a photo of an
/// EL1008 and the old colour was the most obviously wrong thing on the page.
const bodyColor = Color(0xFFEAEAE6);

/// The housing Beckhoff gives its TwinSAFE hardware — EL2912 in the rack,
/// EP1918 out in the field. Safety terminals are yellow and everything else
/// is cream, which is how an electrician picks them out of a rack from across
/// the room, so the mimic keeps the distinction.
const twinSafeBodyColor = Color(0xFFF2C200);

/// The printed terminal markers — the yellow-green tags across the top of a
/// terminal and beside each contact pair.
const ioLabelColor = Color(0xFFC7D62E);

/// The recess the indicator LEDs sit in. Dark, because it is on the real
/// terminal: the window is a shadowed pocket and the lamps are the only
/// bright thing in it. Drawing it light meant an unlit lamp had to be drawn
/// lighter still, which is the opposite of what a dark LED looks like.
const ledWindowColor = Color(0xFF6E7573);

/// An unlit indicator. A dead LED is a dark lens, not a white tile.
const ledOffColor = Color(0xFF474E4C);

enum IOState { low, high, forcedLow, forcedHigh, error }

class IO8Widget extends AnimatedWidget {
  final List<IOState> ledStates;
  final double height;
  final bool disconnected;
  final bool selected;
  final (String, String) topLabels;
  final List<String> ioLabels;
  final List<Color> ioLabelColors;
  final String name;

  /// The slice's configured name or id, worn as a single marker tag above
  /// the LED block — the same spot the printed terminal markers sit on the
  /// real hardware. Empty draws nothing; [topLabels], when set, wins the
  /// band.
  final String markerLabel;

  /// Housing colour. Beckhoff's TwinSAFE terminals (EL2912, EP1918) are
  /// yellow rather than the cream every other EL terminal wears, and on a
  /// rack mimic that colour is the fastest way to tell a safety terminal
  /// from a standard one.
  final Color housingColor;
  IO8Widget({
    required this.ledStates,
    this.height = 300,
    this.disconnected = false,
    this.selected = false,
    this.topLabels = ('', ''),
    this.markerLabel = '',
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
    this.housingColor = bodyColor,
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
          markerLabel: markerLabel,
          name: name,
          animation: animation,
          ioLabels: ioLabels,
          ioLabelColors: ioLabelColors,
          housingColor: housingColor,
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

  /// Single marker tag above the LED block — see [IO8Widget.markerLabel].
  final String markerLabel;

  /// Housing colour — see [IO8Widget.housingColor].
  final Color housingColor;
  IO8Painter({
    required this.ledStates,
    this.disconnected = false,
    this.selected = false,
    this.topLabels = ('', ''),
    this.markerLabel = '',
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
    this.housingColor = bodyColor,
    required this.animation,
    required this.name,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.03;
    // Colors
    final outerBorderPaint = Paint()
      ..color = selected ? Colors.orange : Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final innerBorderPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    // Draw module body. The fill runs the full box and the outline sits a
    // stroke inside it, as it always did; what is new is that the fill is a
    // moulding rather than a flat cream, so a rack row shows a seam at every
    // join instead of merging into one slab.
    final moduleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(size.width * 0.06),
    );
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.width * 0.06),
    );
    canvas.drawRRect(fillRect, housingPaint(fillRect.outerRect, housingColor));
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
            // Named, as ek1100.dart names it. A null family falls back to the
            // platform default in the app — which is this same face — but
            // renders as the test font's boxes under `flutter test`, so every
            // golden of an EL terminal had a black smear where its type name
            // should be and pinned nothing about the labels.
            fontFamily: 'Roboto',
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
    } else if (markerLabel.isNotEmpty) {
      // The slice's configured name or id, as one marker tag spanning the
      // band the two printed terminal markers would occupy.
      final rect =
          Rect.fromLTWH(pad, pad, size.width - pad * 2, labelH);
      canvas.drawRect(rect, Paint()..color = ioLabelColor);
      canvas.drawRect(rect, innerBorderPaint);
      // Not `drawLabel`: a plant id can outgrow the tag, and the shared
      // helper wraps onto a second line that paints over the LED block
      // below. One line — shrunk to fit first, because ids like
      // `ST301.A1.09` are told apart by their tail and an ellipsis eats
      // exactly that. Only a name too long even at the floor is ellipsized.
      TextPainter layoutAt(double fs, {bool clamp = false}) => TextPainter(
            text: TextSpan(
              text: markerLabel,
              style: TextStyle(
                color: Colors.black,
                fontSize: fs,
                fontWeight: FontWeight.bold,
                // Named for the same reason the other labels name it — a
                // null family renders as the test font's boxes under
                // `flutter test`.
                fontFamily: 'Roboto',
              ),
            ),
            maxLines: 1,
            ellipsis: '…',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          )..layout(
              minWidth: clamp ? rect.width : 0,
              maxWidth: clamp ? rect.width : double.infinity,
            );

      final baseFs = labelH * 0.6;
      final natural = layoutAt(baseFs).width;
      var fs = baseFs;
      if (natural > rect.width) {
        fs = (baseFs * rect.width / natural).clamp(labelH * 0.34, baseFs);
      }
      final tp = layoutAt(fs, clamp: true);
      tp.paint(
          canvas, Offset(rect.left, rect.top + (labelH - tp.height) / 2));
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

        // The two openings of a spring terminal point: the square actuator
        // the screwdriver goes into, and the round bore the conductor goes
        // into. Both are holes in a cream moulding on the real part, so both
        // are drawn dark — they used to be lighter than the housing, which
        // made the one feature an electrician aims at look like a sticker.
        double sqY = top + labelH + vertPad;
        Rect sq = Rect.fromLTWH(x + (labelW - sqSize) / 2, sqY, sqSize, sqSize);
        paintActuationSlot(canvas, sq, strokeWidth: strokeWidth);

        double crY = sqY + sqSize + gap;
        Offset crCenter = Offset(x + labelW / 2, crY + crSize / 2);
        paintContactHole(canvas, crCenter, crSize / 2,
            strokeWidth: strokeWidth);
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
            // Named, as ek1100.dart names it. A null family falls back to the
            // platform default in the app — which is this same face — but
            // renders as the test font's boxes under `flutter test`, so every
            // golden of an EL terminal had a black smear where its type name
            // should be and pinned nothing about the labels.
            fontFamily: 'Roboto',
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
  bool shouldRepaint(covariant IO8Painter old) =>
      !listEquals(old.ledStates, ledStates) ||
      old.disconnected != disconnected ||
      old.selected != selected ||
      old.topLabels != topLabels ||
      old.markerLabel != markerLabel ||
      old.name != name ||
      old.animation.value != animation.value ||
      !listEquals(old.ioLabels, ioLabels) ||
      !listEquals(old.ioLabelColors, ioLabelColors) ||
      old.housingColor != housingColor;
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
    drawBackground(canvas, size);
    drawLeds(canvas, size);
  }

  // Shared methods — library-public (no leading underscore) so sibling
  // subclasses in other libraries (e.g. lib/painter/advantys_stb/io16.dart)
  // can override `drawLeds` and reuse `drawLed`. Treat as protected-by-
  // convention: external callers should still drive the painter via `paint()`.
  /// The LED window is a pocket sunk into the housing, not a grey panel laid
  /// on top of it, so it gets the shaded near wall and lit far wall that say
  /// "recess" — and the unlit lamps inside it stop reading as tiles.
  void drawBackground(Canvas canvas, Size size) {
    final blockRect = Rect.fromLTWH(0, 0, size.width, size.height);
    paintRecess(
      canvas,
      RRect.fromRectAndRadius(blockRect, Radius.circular(size.width * 0.03)),
      face: ledWindowColor,
      strokeWidth: size.width * 0.03,
    );
  }

  void drawLed(Canvas canvas, Rect rect, IOState state, Paint borderPaint) {
    const activeColor = Color(0xFF6CA545);
    const errorColor = Colors.red;

    final lit = state == IOState.high ||
        state == IOState.forcedHigh ||
        state == IOState.error;

    // The forced-state border still flashes red — that is the repo's override
    // convention and the animation drives it.
    final Paint border = Paint.from(borderPaint)
      ..color = state == IOState.forcedHigh || state == IOState.forcedLow
          ? Colors.red.withAlpha(animation.value)
          : borderPaint.color;

    paintLed(
      canvas,
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.min(rect.width, rect.height) * 0.12),
      ),
      color: switch (state) {
        IOState.error => errorColor,
        IOState.high || IOState.forcedHigh => activeColor,
        IOState.low || IOState.forcedLow => ledOffColor,
      },
      lit: lit,
      strokeWidth: borderPaint.strokeWidth,
      border: border,
    );
  }

  // Abstract method that each subclass must implement. Library-public so
  // subclasses in other libraries can override it (see io16.dart).
  void drawLeds(Canvas canvas, Size size);

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
  void drawLeds(Canvas canvas, Size size) {
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
      drawLed(canvas, cellRect, ledStates[i], borderPaint);
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
  void drawLeds(Canvas canvas, Size size) {
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
    drawLed(canvas, topRect, ledStates[0], borderPaint);

    // Middle LEDs (2x2 grid)
    for (int i = 0; i < 4; i++) {
      int r = (i + 2) ~/ 2, c = (i + 2) % 2;
      double cx = pad + c * (middleCellW + pad);
      double cy = pad + r * (middleCellH + pad);
      final cellRect = Rect.fromLTWH(cx, cy, middleCellW, middleCellH);
      drawLed(canvas, cellRect, ledStates[i + 1], borderPaint);
    }

    // Bottom LED (big)
    final bottomRect = Rect.fromLTWH(pad, size.height - topBottomHeight,
        size.width - pad * 2, topBottomHeight - pad);
    drawLed(canvas, bottomRect, ledStates[5], borderPaint);
  }
}
