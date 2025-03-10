import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:math';
import 'common.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import '../../providers/state_man.dart';

part 'led.g.dart';

@JsonSerializable(explicitToJson: true)
class LEDConfig extends BaseAsset {
  String key;
  @ColorConverter()
  @JsonKey(name: 'on_color')
  Color onColor;
  @ColorConverter()
  @JsonKey(name: 'off_color')
  Color offColor;
  @JsonKey(name: 'text_pos')
  TextPos textPos;

  LEDConfig({
    required this.key,
    required this.onColor,
    required this.offColor,
    required this.textPos,
  });

  LEDConfig.preview()
      : key = 'Led preview',
        onColor = Colors.green,
        offColor = Colors.green,
        textPos = TextPos.right;

  @override
  Widget build(BuildContext context) {
    return Led(this);
  }

  @override
  Widget configure(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          initialValue: key,
          onChanged: (value) {
            key = value;
          },
        ),
        Row(
          children: [
            const Text('On Color'),
            ColorPicker(
              pickerColor: onColor,
              onColorChanged: (value) {
                onColor = value;
              },
            ),
          ],
        ),
        Row(
          children: [
            const Text('Off Color'),
            ColorPicker(
              pickerColor: offColor,
              onColorChanged: (value) {
                offColor = value;
              },
            ),
          ],
        ),
        DropdownButton<TextPos>(
          value: textPos,
          onChanged: (value) {
            textPos = value!;
          },
          items: TextPos.values
              .map((e) =>
                  DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
              .toList(),
        ),
        Row(
          children: [
            const Text('Size'),
            Slider(
              value: size.width,
              onChanged: (value) {
                size = RelativeSize(width: value, height: value);
              },
            ),
          ],
        ),
      ],
    );
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

    // Get container size from MediaQuery
    final containerSize = MediaQuery.of(context).size;
    final actualSize = widget.config.size.toSize(containerSize);
    final ledSize = min(actualSize.width, actualSize.height);

    final led = SizedBox(
      width: ledSize,
      height: ledSize,
      child: CustomPaint(
        painter: LEDPainter(color: color),
      ),
    );

    return Align(
      alignment: FractionalOffset(
          widget.config.coordinates.x, widget.config.coordinates.y),
      child: buildWithText(led, widget.config.key, widget.config.textPos),
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
