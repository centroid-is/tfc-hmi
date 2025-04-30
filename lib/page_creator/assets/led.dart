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
  String? text;
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

  static const previewStr = 'Led preview';

  LEDConfig.preview()
      : key = previewStr,
        onColor = Colors.green,
        offColor = Colors.green,
        textPos = TextPos.right;

  @override
  Widget build(BuildContext context) {
    return Led(this);
  }

  @override
  Widget configure(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: _ConfigContent(config: this),
      ),
    );
  }

  factory LEDConfig.fromJson(Map<String, dynamic> json) =>
      _$LEDConfigFromJson(json);
  Map<String, dynamic> toJson() => _$LEDConfigToJson(this);
}

class _ConfigContent extends StatefulWidget {
  final LEDConfig config;

  const _ConfigContent({required this.config});

  @override
  State<_ConfigContent> createState() => _ConfigContentState();
}

class _ConfigContentState extends State<_ConfigContent> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyField(
          initialValue: widget.config.key,
          onChanged: (value) {
            setState(() {
              widget.config.key = value;
            });
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: widget.config.text,
          decoration: const InputDecoration(
            labelText: 'Text',
          ),
          onChanged: (value) {
            setState(() {
              widget.config.text = value;
            });
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('On Color'),
            const SizedBox(width: 8),
            Expanded(
              child: BlockPicker(
                pickerColor: widget.config.onColor,
                onColorChanged: (value) {
                  setState(() {
                    widget.config.onColor = value;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Off Color'),
            const SizedBox(width: 8),
            Expanded(
              child: BlockPicker(
                pickerColor: widget.config.offColor,
                onColorChanged: (value) {
                  setState(() {
                    widget.config.offColor = value;
                  });
                },
              ),
            ),
          ],
        ),
        DropdownButton<TextPos>(
          value: widget.config.textPos,
          isExpanded: true,
          onChanged: (value) {
            setState(() {
              widget.config.textPos = value!;
            });
          },
          items: TextPos.values
              .map((e) =>
                  DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Size: '),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: TextFormField(
                initialValue:
                    (widget.config.size.width * 100).toStringAsFixed(2),
                decoration: const InputDecoration(
                  suffixText: '%',
                  isDense: true,
                  helperText: '0.01-50%',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  final percentage = double.tryParse(value) ?? 0.0;
                  if (percentage >= 0.01 && percentage <= 50.0) {
                    setState(() {
                      widget.config.size = RelativeSize(
                        width: percentage / 100,
                        height: percentage / 100,
                      );
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
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
    if (widget.config.key == LEDConfig.previewStr) {
      return _buildLED(true);
    }

    final clientAsync = ref.watch(stateManProvider);

    return clientAsync.when(
      data: (client) => FutureBuilder<bool>(
        future: client.read(widget.config.key).then((value) => value.asBool),
        builder: (context, initialSnapshot) {
          _log.d(
              'Initial value for ${widget.config.key}: ${initialSnapshot.data}');

          return FutureBuilder<Stream<bool>>(
            future: client
                .subscribe(widget.config.key)
                .then((stream) => stream.map((value) => value.asBool)),
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
      ),
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => _buildLED(null),
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
      child: buildWithText(
          led, widget.config.text ?? widget.config.key, widget.config.textPos),
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
