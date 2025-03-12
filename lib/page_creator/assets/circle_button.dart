import 'package:json_annotation/json_annotation.dart';
import 'dart:ui' show Color, Size;
import 'package:flutter/material.dart';
import 'dart:math';
import 'common.dart';

part 'circle_button.g.dart';

@JsonSerializable()
class CircleButtonConfig extends BaseAsset {
  final String key;
  @ColorConverter()
  @JsonKey(name: 'outward_color')
  final Color outwardColor;
  @ColorConverter()
  @JsonKey(name: 'inward_color')
  final Color inwardColor;
  @JsonKey(name: 'text_pos')
  final TextPos textPos;

  @override
  Widget build(BuildContext context) {
    final containerSize = MediaQuery.of(context).size;
    final actualSize = size.toSize(containerSize);
    final buttonSize = min(actualSize.width, actualSize.height);

    final button = SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            // Handle tap event
          },
          child: CustomPaint(
            painter: CircleButtonPainter(
              outwardColor: outwardColor,
              inwardColor: inwardColor,
              isPressed: false,
            ),
          ),
        ),
      ),
    );

    return Align(
      alignment: FractionalOffset(
        coordinates.x,
        coordinates.y,
      ),
      child: buildWithText(button, key, textPos),
    );
  }

  @override
  Widget configure(BuildContext context) {
    return const Text('TODO implement configure');
  }

  CircleButtonConfig({
    required this.key,
    required this.outwardColor,
    required this.inwardColor,
    required this.textPos,
  });

  CircleButtonConfig.preview()
      : key = 'Circle button preview',
        outwardColor = Colors.green,
        inwardColor = Colors.green,
        textPos = TextPos.right;

  factory CircleButtonConfig.fromJson(Map<String, dynamic> json) =>
      _$CircleButtonConfigFromJson(json);
  Map<String, dynamic> toJson() => _$CircleButtonConfigToJson(this);
}

class CircleButtonPainter extends CustomPainter {
  final Color? outwardColor;
  final Color? inwardColor;
  final bool isPressed;

  CircleButtonPainter({
    required this.outwardColor,
    required this.inwardColor,
    this.isPressed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(
      center + const Offset(0, 2),
      radius,
      shadowPaint,
    );

    // Draw button with gradient
    if (outwardColor != null && inwardColor != null) {
      final buttonPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            isPressed ? outwardColor! : inwardColor!,
            isPressed ? inwardColor! : outwardColor!,
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, buttonPaint);

      // Draw border
      final borderPaint = Paint()
        ..color = outwardColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, borderPaint);
    } else {
      // Draw error state (gray with exclamation mark)
      final errorPaint = Paint()
        ..color = Colors.grey
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, errorPaint);

      // Draw border
      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, borderPaint);

      // Draw exclamation mark
      final textPainter = TextPainter(
        text: TextSpan(
          text: '!',
          style: TextStyle(
            color: Colors.white,
            fontSize: size.height * 0.6,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(CircleButtonPainter oldDelegate) =>
      outwardColor != oldDelegate.outwardColor ||
      inwardColor != oldDelegate.inwardColor ||
      isPressed != oldDelegate.isPressed;
}
