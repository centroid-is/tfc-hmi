import 'dart:math' as math;
import 'package:flutter/material.dart';

class ATV320 extends CustomPainter {
  final double widthMm = 45.0;
  final double heightMm = 215.0;
  static const schneiderGreen = Color(0xFF009639);
  static const schneiderLogoGreen = Color(0xFF009E4D);
  static const atvBodyGrey = Color(0xFF383E42);

  final String name;
  final String displayText; // Add this field
  final String topLabel; // Add this field for the top label
  final Color fillColor = atvBodyGrey;

  ATV320({
    required this.name,
    this.displayText = 'ATV3',
    this.topLabel = '',
  }); // Add topLabel parameter

// Segment order: [top, top-right, bottom-right, bottom, bottom-left, top-left, middle]
  static const Map<String, List<bool>> sevenSegmentMap = {
    // Numbers
    '0': [true, true, true, true, true, true, false],
    '1': [false, true, true, false, false, false, false],
    '2': [true, true, false, true, true, false, true],
    '3': [true, true, true, true, false, false, true],
    '4': [false, true, true, false, false, true, true],
    '5': [true, false, true, true, false, true, true],
    '6': [true, false, true, true, true, true, true],
    '7': [true, true, true, false, false, false, false],
    '8': [true, true, true, true, true, true, true],
    '9': [true, true, true, true, false, true, true],

    // Symbols
    '-': [false, false, false, false, false, false, true],
    ' ': [false, false, false, false, false, false, false],

    // Uppercase letters that make sense on 7-seg
    'A': [true, true, true, false, true, true, true],
    'C': [true, false, false, true, true, true, false],
    'E': [true, false, false, true, true, true, true],
    'F': [true, false, false, false, true, true, true],
    'H': [false, true, true, false, true, true, true],
    'I': [false, true, true, false, false, false, false], // like "1"
    'J': [false, true, true, true, false, false, false],
    'L': [false, false, false, true, true, true, false],
    'O': [true, true, true, true, true, true, false], // same shape as "0"
    'P': [true, true, false, false, true, true, true],
    'S': [true, false, true, true, false, true, true],
    'U': [false, true, true, true, true, true, false],
    'Y': [false, true, true, true, false, true, true],
    'Z': [true, true, false, true, true, false, true],

    // Lowercase letters that make sense on 7-seg
    'a': [true, true, true, true, true, false, true],
    'b': [false, false, true, true, true, true, true],
    'c': [false, false, false, true, true, false, true],
    'd': [false, true, true, true, true, false, true],
    'e': [true, false, false, true, true, true, true],
    'f': [true, false, false, false, true, true, true],
    'h': [false, false, true, false, true, true, true],
    'i': [false, false, true, false, false, false, false],
    'j': [false, true, true, true, false, false, false],
    'l': [false, false, false, true, true, true, false],
    'n': [false, false, true, false, true, false, true],
    'o': [false, true, true, true, true, false, false],
    'p': [true, true, false, false, true, true, true],
    'q': [true, true, true, true, false, true, true],
    'r': [false, false, false, false, true, false, true],
    't': [false, false, false, true, true, true, true],
    'u': [false, false, true, true, true, false, false],
    'y': [false, true, true, true, false, true, true],
  };

  // Draw a single 7-segment character
  void _drawSevenSegment(
    Canvas canvas,
    String char,
    double x,
    double y,
    double width,
    double height,
  ) {
    final segments = sevenSegmentMap[char] ?? sevenSegmentMap[' ']!;

    final segmentPaint = Paint()
      ..color = const Color(0xFF00FF00) // Green segments
      ..style = PaintingStyle.fill;

    final double segmentWidth = width * 0.1; // 10% of character width
    final double segmentHeight = height * 0.08; // 8% of character height
    final double horizontalSegmentWidth = width * 0.6; // 60% of character width
    final double verticalSegmentHeight =
        height * 0.4; // 40% of character height

    // Segment positions (7-segment layout):
    //    0
    //  5   1
    //    6
    //  4   2
    //    3

    // Top horizontal (0)
    if (segments[0]) {
      final rect = Rect.fromLTWH(
        x + (width - horizontalSegmentWidth) / 2,
        y,
        horizontalSegmentWidth,
        segmentHeight,
      );
      canvas.drawRect(rect, segmentPaint);
    }

    // Top right vertical (1)
    if (segments[1]) {
      final rect = Rect.fromLTWH(
        x + width - segmentWidth,
        y + segmentHeight,
        segmentWidth,
        verticalSegmentHeight,
      );
      canvas.drawRect(rect, segmentPaint);
    }

    // Bottom right vertical (2)
    if (segments[2]) {
      final rect = Rect.fromLTWH(
        x + width - segmentWidth,
        y + segmentHeight + verticalSegmentHeight + segmentHeight,
        segmentWidth,
        verticalSegmentHeight,
      );
      canvas.drawRect(rect, segmentPaint);
    }

    // Bottom horizontal (3)
    if (segments[3]) {
      final rect = Rect.fromLTWH(
        x + (width - horizontalSegmentWidth) / 2,
        y + height - segmentHeight,
        horizontalSegmentWidth,
        segmentHeight,
      );
      canvas.drawRect(rect, segmentPaint);
    }

    // Bottom left vertical (4)
    if (segments[4]) {
      final rect = Rect.fromLTWH(
        x,
        y + segmentHeight + verticalSegmentHeight + segmentHeight,
        segmentWidth,
        verticalSegmentHeight,
      );
      canvas.drawRect(rect, segmentPaint);
    }

    // Top left vertical (5)
    if (segments[5]) {
      final rect = Rect.fromLTWH(
        x,
        y + segmentHeight,
        segmentWidth,
        verticalSegmentHeight,
      );
      canvas.drawRect(rect, segmentPaint);
    }

    // Middle horizontal (6)
    if (segments[6]) {
      final rect = Rect.fromLTWH(
        x + (width - horizontalSegmentWidth) / 2,
        y + (height - segmentHeight) / 2,
        horizontalSegmentWidth,
        segmentHeight,
      );
      canvas.drawRect(rect, segmentPaint);
    }
  }

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

    // Add a small radius for rounded corners (about 2mm)
    final double radius = 2.0 * pxPerMm;

    // Create a path with rounded corners and curved top edge
    final path = Path();

    // Start from bottom-left (with rounded corner)
    path.moveTo(left + radius, top + heightPixels);

    // Draw bottom edge
    path.lineTo(left + widthPixels - radius, top + heightPixels);

    // Draw bottom-right rounded corner
    path.arcToPoint(
      Offset(left + widthPixels, top + heightPixels - radius),
      radius: Radius.circular(radius),
      clockwise: false,
    );

    // Draw right edge
    path.lineTo(left + widthPixels, top + radius);

    // Draw top-right rounded corner
    path.arcToPoint(
      Offset(left + widthPixels - radius, top),
      radius: Radius.circular(radius),
      clockwise: false,
    );

    // Draw curved top edge (slight curve down in the middle)
    final double curveDepth = -4.0 * pxPerMm;
    path.quadraticBezierTo(
      left + widthPixels / 2, // control point x (middle)
      top + curveDepth, // control point y (curved down)
      left + radius, // end point x (left edge + radius)
      top, // end point y (top)
    );

    // Draw top-left rounded corner
    path.arcToPoint(
      Offset(left, top + radius),
      radius: Radius.circular(radius),
      clockwise: false,
    );

    // Draw left edge
    path.lineTo(left, top + heightPixels - radius);

    // Draw bottom-left rounded corner
    path.arcToPoint(
      Offset(left + radius, top + heightPixels),
      radius: Radius.circular(radius),
      clockwise: false,
    );

    // Close the path
    path.close();

    // Draw the filled shape
    canvas.drawPath(path, backgroundFill);
    canvas.drawPath(path, stroke);

    // Add customizable label on top of the device
    if (topLabel.isNotEmpty) {
      // Simple approach: limit to max characters and use monospace font
      const int maxCharsPerLine = 14; // Adjust this number as needed
      final words = topLabel.trim().split(' ');

      if (words.length > 1) {
        // Split into 2 lines with character limit
        String line1 = '';
        String line2 = '';
        bool hasMoreWords = false; // Flag to track if there are more words

        for (final word in words) {
          if (line1.length + word.length + 1 <= maxCharsPerLine &&
              line2.isEmpty) {
            line1 += (line1.isEmpty ? '' : ' ') + word;
          } else if (line2.length + word.length + 1 <= maxCharsPerLine) {
            line2 += (line2.isEmpty ? '' : ' ') + word;
          } else {
            // Both lines are full, but we still have more words
            hasMoreWords = true;
            break;
          }
        }

        // Add "..." to lines that are truncated
        if (hasMoreWords) {
          if (line2.isNotEmpty) {
            line2 = '${line2.substring(0, maxCharsPerLine - 3)}...';
          }
        }

        // Draw both lines
        final line1Painter = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          text: TextSpan(
            text: line1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier', // Monospace font
            ),
          ),
        );
        line1Painter.layout();

        final line2Painter = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          text: TextSpan(
            text: line2,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier', // Monospace font
            ),
          ),
        );
        line2Painter.layout();

        final double line1Y = top + (8.0 * pxPerMm);
        final double line2Y = top + (15.0 * pxPerMm);

        final double line1X =
            left + (widthPixels / 2.0) - (line1Painter.width / 2.0);
        final double line2X =
            left + (widthPixels / 2.0) - (line2Painter.width / 2.0);

        line1Painter.paint(canvas, Offset(line1X, line1Y));
        line2Painter.paint(canvas, Offset(line2X, line2Y));
      } else {
        // Single line - truncate if too long
        String displayLabel = topLabel;
        if (topLabel.length > maxCharsPerLine) {
          displayLabel = '${topLabel.substring(0, maxCharsPerLine)}...';
        }

        final labelTextPainter = TextPainter(
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          text: TextSpan(
            text: displayLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier', // Monospace font
            ),
          ),
        );
        labelTextPainter.layout();

        final double labelX =
            left + (widthPixels / 2.0) - (labelTextPainter.width / 2.0);
        final double labelY = top + (8.0 * pxPerMm);
        labelTextPainter.paint(canvas, Offset(labelX, labelY));
      }
    }

    // Add old-fashioned LCD screen
    final double screenWidth = 40.0 * pxPerMm; // 40mm wide
    final double screenHeight = 25.0 * pxPerMm; // 25mm tall
    final double screenTop = top +
        (48.0 * pxPerMm) -
        (screenHeight / 2.0); // 48mm from top, centered
    final double screenLeft = left +
        (widthPixels / 2.0) -
        (screenWidth / 2.0); // centered horizontally

    // LCD screen background (dark green/black typical of old LCDs)
    final lcdBackground = Paint()
      ..color = const Color(0xFF1A2F1A)
      ..style = PaintingStyle.fill;

    final lcdRect = Rect.fromLTWH(
      screenLeft,
      screenTop,
      screenWidth,
      screenHeight,
    );
    canvas.drawRect(lcdRect, lcdBackground);
    canvas.drawRect(lcdRect, stroke);

    // Draw 7-segment characters
    final int maxChars = 4;
    final double charWidth = screenWidth / maxChars;
    final double charHeight =
        screenHeight * 0.8; // Use 80% of screen height for characters
    final double charY = screenTop + (screenHeight - charHeight) / 2;

    // Add spacing between characters
    const double spacing = 4.0 * pxPerMm; // 4mm spacing between characters
    final double totalSpacing =
        spacing * (maxChars - 1); // Total spacing for all gaps
    final double availableWidth = screenWidth - totalSpacing;
    final double adjustedCharWidth = availableWidth / maxChars;

    // Find decimal point position and remove it from text
    int? decimalIndex;
    String textWithoutDot = displayText;
    if (displayText.contains('.')) {
      decimalIndex = displayText.indexOf('.');
      textWithoutDot = displayText.replaceAll('.', '');
    }

    // Take only first 4 characters (excluding the dot), pad with spaces if needed
    final String displayChars =
        textWithoutDot.padLeft(maxChars, ' ').substring(0, maxChars);

    // Draw characters from right to left for right alignment
    for (int i = 0; i < maxChars; i++) {
      final double charX = screenLeft + i * (adjustedCharWidth + spacing);
      _drawSevenSegment(
        canvas,
        displayChars[i],
        charX,
        charY,
        adjustedCharWidth,
        charHeight,
      );
    }

    // Draw decimal point at the correct position if it exists
    if (decimalIndex != null) {
      final dotPaint = Paint()
        ..color = const Color(0xFF00FF00) // Green dot
        ..style = PaintingStyle.fill;

      const double dotRadius = 1.0 * pxPerMm; // 1mm radius

      // Calculate dot position based on the actual decimal index
      // Adjust for the fact that we're showing maxChars characters
      final int adjustedIndex = decimalIndex.clamp(0, maxChars - 1);
      final double dotX = screenLeft +
          adjustedIndex * (adjustedCharWidth + spacing) +
          adjustedCharWidth +
          (spacing / 2); // Between characters

      final double dotY = screenTop +
          screenHeight -
          (4.0 * pxPerMm); // Positioned near bottom of screen

      canvas.drawCircle(Offset(dotX, dotY), dotRadius, dotPaint);
    }

    // Add circular ESC button on the right side, 5mm from edge
    final double buttonRadius = 4.0 * pxPerMm; // 4mm radius
    final double buttonCenterX = left +
        widthPixels -
        (3.0 * pxPerMm) -
        buttonRadius; // 5mm from right edge
    final double buttonCenterY =
        screenTop + screenHeight + (8.0 * pxPerMm); // 8mm below screen

    // Button background (slightly darker than device body)
    final buttonPaint = Paint()
      ..color = const Color(0xFF2A2F2A)
      ..style = PaintingStyle.fill;

    // Draw circular button
    final buttonCircle = Rect.fromCircle(
      center: Offset(buttonCenterX, buttonCenterY),
      radius: buttonRadius,
    );
    canvas.drawCircle(
      Offset(buttonCenterX, buttonCenterY),
      buttonRadius,
      buttonPaint,
    );
    canvas.drawCircle(
      Offset(buttonCenterX, buttonCenterY),
      buttonRadius,
      stroke,
    );

    // Add "ESC" text on the button
    final escTextPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: const TextSpan(
        text: 'ESC',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10.0,
          fontWeight: FontWeight.bold,
          fontFamily: 'Roboto',
        ),
      ),
    );
    escTextPainter.layout();

    final double escTextX = buttonCenterX - (escTextPainter.width / 2.0);
    final double escTextY = buttonCenterY - (escTextPainter.height / 2.0);
    escTextPainter.paint(canvas, Offset(escTextX, escTextY));

    // Add green LED above the screen on the left side (inside the device)
    final double ledRadius = 1.5 * pxPerMm; // 3mm diameter = 1.5mm radius
    final double ledCenterX =
        screenLeft + (3.0 * pxPerMm); // 8mm from left edge of screen
    final double ledCenterY = screenTop - (3.0 * pxPerMm); // 3mm above screen

    // LED background (bright green)
    final ledPaint = Paint()
      ..color = const Color(0xFF00FF00) // Bright green LED
      ..style = PaintingStyle.fill;

    // Draw LED circle
    canvas.drawCircle(Offset(ledCenterX, ledCenterY), ledRadius, ledPaint);
    canvas.drawCircle(Offset(ledCenterX, ledCenterY), ledRadius, stroke);

    // Add scroll wheel below the screen, centered
    final double wheelRadius = 12.0 * pxPerMm; // 20mm diameter = 10mm radius
    final double wheelCenterX =
        screenLeft + (screenWidth / 2.0); // Centered with screen
    final double wheelCenterY =
        screenTop + screenHeight + (20.0 * pxPerMm); // 25mm below screen

    // Wheel background (slightly darker than device body)
    final wheelPaint = Paint()
      ..color = schneiderGreen
      ..style = PaintingStyle.fill;

    // Draw main wheel circle
    canvas.drawCircle(
      Offset(wheelCenterX, wheelCenterY),
      wheelRadius,
      wheelPaint,
    );
    canvas.drawCircle(Offset(wheelCenterX, wheelCenterY), wheelRadius, stroke);

    // Draw 16 ticks around the wheel circumference
    final tickPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / gScale;

    final double tickLength = 2.0 * pxPerMm; // 2mm long ticks
    final double tickWidth = 0.5 * pxPerMm; // 0.5mm wide ticks

    for (int i = 0; i < 16; i++) {
      final double angle =
          (i * 2 * math.pi) / 16; // Evenly spaced around circle

      // Calculate tick start and end points
      final double tickStartX =
          wheelCenterX + (wheelRadius - tickLength) * math.cos(angle);
      final double tickStartY =
          wheelCenterY + (wheelRadius - tickLength) * math.sin(angle);
      final double tickEndX = wheelCenterX + wheelRadius * math.cos(angle);
      final double tickEndY = wheelCenterY + wheelRadius * math.sin(angle);

      // Draw tick line
      canvas.drawLine(
        Offset(tickStartX, tickStartY),
        Offset(tickEndX, tickEndY),
        tickPaint,
      );
    }

    // Add ethernet port on the right side, 5mm from edge, 109mm from top
    final double ethernetWidth = 15.0 * pxPerMm; // 15mm wide
    final double ethernetHeight = 15.0 * pxPerMm; // 15mm tall
    final double ethernetLeft = left +
        widthPixels -
        (5.0 * pxPerMm) -
        ethernetWidth; // 5mm from right edge

    // Position ethernet port at 109mm from top, ensuring it's within device bounds
    final double ethernetTop =
        top + (240 * pxPerMm); // 109mm from top (no centering offset)

    // Use the SimpleEthernetPainter for the ethernet port
    final ethernetPainter = SimpleEthernetPainter(
      strokeColor: Colors.black,
      strokeWidth: 1.0,
      fillColor: const Color(0xFF2A2F2A), // Dark gray fill
    );

    canvas.save();
    canvas.translate(ethernetLeft, ethernetTop);
    canvas.scale(
      ethernetWidth / 149.276032,
      ethernetHeight / 172.848911,
    ); // Scale to fit the ethernet dimensions
    ethernetPainter.paint(canvas, const Size(149.276032, 172.848911));
    canvas.restore();

    // Done
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ATV320 old) {
    return name != old.name ||
        displayText != old.displayText ||
        topLabel != old.topLabel ||
        fillColor != old.fillColor;
  }
}

class ATV320Widget extends StatelessWidget {
  final String name;
  final String displayText; // Add this field
  final String topLabel; // Add this field

  const ATV320Widget({
    super.key,
    required this.name,
    this.displayText = 'ATV3',
    this.topLabel = '',
  }); // Add topLabel parameter

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Handle infinite height by providing a reasonable default
        final height =
            constraints.maxHeight.isInfinite ? 400.0 : constraints.maxHeight;
        final width =
            constraints.maxWidth.isInfinite ? 200.0 : constraints.maxWidth;

        return SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: ATV320(
              name: name,
              displayText: displayText,
              topLabel: topLabel,
            ),
          ),
        );
      },
    );
  }
}

class SimpleEthernetPainter extends CustomPainter {
  final double strokeWidth;
  final Color strokeColor;
  final Color? fillColor; // optional fill for closed shapes
  const SimpleEthernetPainter({
    this.strokeWidth = 1.0,
    this.strokeColor = Colors.black,
    this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double _minX = 179.871662;
    const double _minY = 615.792125;
    const double _maxX = 329.147694;
    const double _maxY = 788.641036;
    const double _w = 149.27603200000001;
    const double _h = 172.84891099999993;
    if (_w == 0 || _h == 0) return;
    final double scale = math.min(size.width / _w, size.height / _h);
    final double dx = (size.width - _w * scale) / 2.0;
    final double dy = (size.height - _h * scale) / 2.0;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);
    // Map DXF coords (y up) -> canvas (y down)
    canvas.translate(-_minX, -_maxY);
    canvas.scale(1, -1);

    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..color = strokeColor;
    final Paint? fillPaint = (fillColor == null)
        ? null
        : (Paint()
          ..style = PaintingStyle.fill
          ..color = fillColor!);

    // Polyline #0 — 12 points — closed=true
    final Path p0 = Path();
    p0.moveTo(179.871662, 667.934419);
    p0.lineTo(179.871662, 736.498741);
    p0.lineTo(206.298089, 736.498741);
    p0.lineTo(206.298089, 750.785333);
    p0.lineTo(227.724204, 750.785333);
    p0.lineTo(227.724204, 788.641036);
    p0.lineTo(329.147694, 788.641036);
    p0.lineTo(329.147694, 615.792125);
    p0.lineTo(227.724204, 615.792125);
    p0.lineTo(227.724204, 653.647827);
    p0.lineTo(206.298089, 653.647827);
    p0.lineTo(206.298089, 667.934419);
    p0.close();
    if (fillPaint != null) canvas.drawPath(p0, fillPaint);
    canvas.drawPath(p0, strokePaint);

    // Polyline #1 — 2 points — closed=false
    final Path p1 = Path();
    p1.moveTo(329.147694, 745.785029);
    p1.lineTo(324.933532, 745.785029);
    canvas.drawPath(p1, strokePaint);

    // Polyline #2 — 2 points — closed=false
    final Path p2 = Path();
    p2.moveTo(329.147694, 747.213687);
    p2.lineTo(329.147694, 750.071006);
    canvas.drawPath(p2, strokePaint);

    // Polyline #3 — 2 points — closed=false
    final Path p3 = Path();
    p3.moveTo(324.933532, 751.499664);
    p3.lineTo(329.147694, 751.499664);
    canvas.drawPath(p3, strokePaint);

    // Polyline #4 — 2 points — closed=false
    final Path p4 = Path();
    p4.moveTo(329.147694, 731.498438);
    p4.lineTo(324.933532, 731.498438);
    canvas.drawPath(p4, strokePaint);

    // Polyline #5 — 2 points — closed=false
    final Path p5 = Path();
    p5.moveTo(329.147694, 732.927095);
    p5.lineTo(329.147694, 735.784411);
    canvas.drawPath(p5, strokePaint);

    // Polyline #6 — 2 points — closed=false
    final Path p6 = Path();
    p6.moveTo(324.933532, 737.213072);
    p6.lineTo(329.147694, 737.213072);
    canvas.drawPath(p6, strokePaint);

    // Polyline #7 — 2 points — closed=false
    final Path p7 = Path();
    p7.moveTo(329.147694, 717.215614);
    p7.lineTo(324.933532, 717.215614);
    canvas.drawPath(p7, strokePaint);

    // Polyline #8 — 2 points — closed=false
    final Path p8 = Path();
    p8.moveTo(329.147694, 718.644272);
    p8.lineTo(329.147694, 721.501591);
    canvas.drawPath(p8, strokePaint);

    // Polyline #9 — 2 points — closed=false
    final Path p9 = Path();
    p9.moveTo(324.933532, 722.93026);
    p9.lineTo(329.147694, 722.93026);
    canvas.drawPath(p9, strokePaint);

    // Polyline #10 — 2 points — closed=false
    final Path p10 = Path();
    p10.moveTo(329.147694, 702.929015);
    p10.lineTo(324.933532, 702.929015);
    canvas.drawPath(p10, strokePaint);

    // Polyline #11 — 2 points — closed=false
    final Path p11 = Path();
    p11.moveTo(329.147694, 704.357681);
    p11.lineTo(329.147694, 707.215);
    canvas.drawPath(p11, strokePaint);

    // Polyline #12 — 2 points — closed=false
    final Path p12 = Path();
    p12.moveTo(324.933532, 708.643657);
    p12.lineTo(329.147694, 708.643657);
    canvas.drawPath(p12, strokePaint);

    // Polyline #13 — 2 points — closed=false
    final Path p13 = Path();
    p13.moveTo(329.147694, 688.646203);
    p13.lineTo(324.933532, 688.646203);
    canvas.drawPath(p13, strokePaint);

    // Polyline #14 — 2 points — closed=false
    final Path p14 = Path();
    p14.moveTo(329.147694, 690.074861);
    p14.lineTo(329.147694, 692.932176);
    canvas.drawPath(p14, strokePaint);

    // Polyline #15 — 2 points — closed=false
    final Path p15 = Path();
    p15.moveTo(324.933532, 694.360845);
    p15.lineTo(329.147694, 694.360845);
    canvas.drawPath(p15, strokePaint);

    // Polyline #16 — 2 points — closed=false
    final Path p16 = Path();
    p16.moveTo(329.147694, 674.359608);
    p16.lineTo(324.933532, 674.359608);
    canvas.drawPath(p16, strokePaint);

    // Polyline #17 — 2 points — closed=false
    final Path p17 = Path();
    p17.moveTo(329.147694, 675.78827);
    p17.lineTo(329.147694, 678.645585);
    canvas.drawPath(p17, strokePaint);

    // Polyline #18 — 2 points — closed=false
    final Path p18 = Path();
    p18.moveTo(324.933532, 680.074254);
    p18.lineTo(329.147694, 680.074254);
    canvas.drawPath(p18, strokePaint);

    // Polyline #19 — 2 points — closed=false
    final Path p19 = Path();
    p19.moveTo(329.147694, 660.076789);
    p19.lineTo(324.933532, 660.076789);
    canvas.drawPath(p19, strokePaint);

    // Polyline #20 — 2 points — closed=false
    final Path p20 = Path();
    p20.moveTo(329.147694, 661.505458);
    p20.lineTo(329.147694, 664.362773);
    canvas.drawPath(p20, strokePaint);

    // Polyline #21 — 2 points — closed=false
    final Path p21 = Path();
    p21.moveTo(324.933532, 665.791431);
    p21.lineTo(329.147694, 665.791431);
    canvas.drawPath(p21, strokePaint);

    // Polyline #22 — 2 points — closed=false
    final Path p22 = Path();
    p22.moveTo(329.147694, 645.790197);
    p22.lineTo(324.933532, 645.790197);
    canvas.drawPath(p22, strokePaint);

    // Polyline #23 — 2 points — closed=false
    final Path p23 = Path();
    p23.moveTo(329.147694, 647.218855);
    p23.lineTo(329.147694, 650.07617);
    canvas.drawPath(p23, strokePaint);

    // Polyline #24 — 2 points — closed=false
    final Path p24 = Path();
    p24.moveTo(324.933532, 651.504839);
    p24.lineTo(329.147694, 651.504839);
    canvas.drawPath(p24, strokePaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SimpleEthernetPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor;
  }
}

// Quick preview widget
class SimpleEthernetWidget extends StatelessWidget {
  final double width;
  final double height;
  final Color strokeColor;
  final Color? fillColor;
  final double strokeWidth;
  const SimpleEthernetWidget({
    super.key,
    this.width = 200,
    this.height = 200,
    this.strokeColor = Colors.black,
    this.fillColor,
    this.strokeWidth = 1.0,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: SimpleEthernetPainter(
          strokeColor: strokeColor,
          strokeWidth: strokeWidth,
          fillColor: fillColor,
        ),
      ),
    );
  }
}
