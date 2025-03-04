import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'common.dart';

part 'led.g.dart';

@JsonSerializable()
class LEDConfig with AutoAssetName implements Asset {
  final String key;
  @ColorConverter()
  @JsonKey(name: 'on_color')
  final Color onColor;
  @ColorConverter()
  @JsonKey(name: 'off_color')
  final Color offColor;
  @JsonKey(name: 'text_pos')
  final TextPos textPos;
  @JsonKey(name: 'coordinates')
  final Coordinates coordinates;
  @SizeConverter()
  @JsonKey(name: 'size')
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Led(this).build(context);
  }

  const LEDConfig({
    required this.key,
    required this.onColor,
    required this.offColor,
    required this.textPos,
    required this.coordinates,
    required this.size,
  });

  factory LEDConfig.fromJson(Map<String, dynamic> json) =>
      _$LEDConfigFromJson(json);
  Map<String, dynamic> toJson() => _$LEDConfigToJson(this);
}

class Led {
  final LEDConfig config;
  final bool? isOn = null;

  Led(this.config);

  Widget build(BuildContext context) {
    final color =
        isOn == null ? null : (isOn! ? config.onColor : config.offColor);

    // Make LED circular by using the minimum dimension
    final ledSize = min(config.size.width, config.size.height);

    Widget led = SizedBox(
      width: ledSize,
      height: ledSize,
      child: CustomPaint(
        painter: LEDPainter(color: color),
      ),
    );

    Widget text = Text(config.key);

    // Use fractional positioning instead of absolute
    return Align(
      alignment: FractionalOffset(config.coordinates.x, config.coordinates.y),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: config.textPos == TextPos.above
            ? [text, led]
            : config.textPos == TextPos.below
                ? [led, text]
                : config.textPos == TextPos.right
                    ? [
                        Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [led, text])
                      ]
                    : [
                        Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [text, led])
                      ],
      ),
    );
  }
}

class LEDPainter extends CustomPainter {
  final Color? color;

  LEDPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color ?? Colors.grey
      ..style = PaintingStyle.fill;

    // Draw circle
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      paint,
    );

    // Draw border
    paint.color = Colors.black;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      paint,
    );

    if (color == null) {
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
  bool shouldRepaint(LEDPainter oldDelegate) => color != oldDelegate.color;
}
