import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../client_provider.dart';
import 'dart:async';
import 'package:logger/logger.dart';

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

  const LEDConfig({
    required this.key,
    required this.onColor,
    required this.offColor,
    required this.textPos,
    required this.coordinates,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Led(this);
  }

  factory LEDConfig.fromJson(Map<String, dynamic> json) =>
      _$LEDConfigFromJson(json);
  Map<String, dynamic> toJson() => _$LEDConfigToJson(this);
}

class Led extends ConsumerStatefulWidget {
  final LEDConfig config;

  const Led(this.config, {super.key});

  @override
  ConsumerState<Led> createState() => _LedState();
}

class _LedState extends ConsumerState<Led> {
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final client = ref.read(stateManProvider);

    return FutureBuilder<bool>(
      future: client.read<bool>(widget.config.key),
      builder: (context, initialSnapshot) {
        _log.d(
            'Initial value for ${widget.config.key}: ${initialSnapshot.data}');

        return FutureBuilder<Stream<bool>>(
          future: client.subscribe<bool>(widget.config.key),
          builder: (context, streamSnapshot) {
            if (streamSnapshot.hasError) {
              _log.e('Stream setup error for ${widget.config.key}',
                  error: streamSnapshot.error);
              return _buildLED(null);
            }

            if (!streamSnapshot.hasData) {
              _log.d(
                  'Waiting for stream, showing initial value: ${initialSnapshot.data}');
              return _buildLED(initialSnapshot.data);
            }

            return StreamBuilder<bool>(
              stream: streamSnapshot.data,
              initialData: initialSnapshot.data,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  _log.e('Stream error for ${widget.config.key}',
                      error: snapshot.error);
                  return _buildLED(null);
                }

                final isOn = snapshot.data;
                _log.t('LED ${widget.config.key} value update: $isOn');
                return _buildLED(isOn);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLED(bool? isOn) {
    final color = isOn == null
        ? null
        : (isOn ? widget.config.onColor : widget.config.offColor);
    final ledSize = min(widget.config.size.width, widget.config.size.height);

    Widget led = SizedBox(
      width: ledSize,
      height: ledSize,
      child: CustomPaint(
        painter: LEDPainter(color: color),
      ),
    );

    Widget text = Text(widget.config.key);

    return Align(
      alignment: FractionalOffset(
          widget.config.coordinates.x, widget.config.coordinates.y),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: widget.config.textPos == TextPos.above
            ? [text, led]
            : widget.config.textPos == TextPos.below
                ? [led, text]
                : widget.config.textPos == TextPos.right
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
