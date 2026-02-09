import 'dart:math';
import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:rxdart/rxdart.dart';

import 'common.dart';
import '../../providers/state_man.dart';
import 'package:tfc/converter/color_converter.dart';

part 'led.g.dart';

@JsonEnum()
enum LEDType {
  circle,
  square,
}

@JsonSerializable(explicitToJson: true)
class LEDConfig extends BaseAsset {
  @override
  String get displayName => 'LED';
  @override
  String get category => 'Basic Indicators';

  String key;
  @ColorConverter()
  @JsonKey(name: 'on_color')
  Color onColor;
  @ColorConverter()
  @JsonKey(name: 'off_color')
  Color offColor;
  @JsonKey(name: 'led_type')
  LEDType ledType = LEDType.circle;

  LEDConfig({
    required this.key,
    required this.onColor,
    required this.offColor,
  });

  static const previewStr = 'Led preview';

  LEDConfig.preview()
      : key = previewStr,
        onColor = Colors.green,
        offColor = Colors.green {
    textPos = TextPos.right;
  }

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
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9; // Use 90% of screen width
    final maxHeight = media.height * 0.8; // Use 80% of screen height

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          minWidth: 320,
          minHeight: 200,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
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
                  const SizedBox(height: 16),
                  DropdownButton<TextPos>(
                    value: widget.config.textPos,
                    isExpanded: true,
                    onChanged: (value) {
                      setState(() {
                        widget.config.textPos = value!;
                      });
                    },
                    items: TextPos.values
                        .map((e) => DropdownMenuItem<TextPos>(
                            value: e, child: Text(e.name)))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<LEDType>(
                    value: widget.config.ledType,
                    isExpanded: true,
                    onChanged: (value) {
                      setState(() {
                        widget.config.ledType = value!;
                      });
                    },
                    items: LEDType.values
                        .map((e) => DropdownMenuItem<LEDType>(
                              value: e,
                              child: Text(e.name[0].toUpperCase() +
                                  e.name.substring(1)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  SizeField(
                    initialValue: widget.config.size,
                    useSingleSize: widget.config.ledType == LEDType.circle,
                    onChanged: (value) {
                      setState(() {
                        widget.config.size = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  CoordinatesField(
                    initialValue: widget.config.coordinates,
                    onChanged: (c) =>
                        setState(() => widget.config.coordinates = c),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Led extends ConsumerWidget {
  final LEDConfig config;

  const Led(this.config, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (config.key.isEmpty || config.key == LEDConfig.previewStr) {
      return LedRaw(config, value: null);
    }
    return StreamBuilder<bool>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
            (stateMan) => stateMan
                .subscribe(config.key)
                .asStream()
                .switchMap((s) => s)
                .map((dynamicValue) => dynamicValue.asBool),
          ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          stderr.writeln(
              'Stream setup error for ${config.key}, error: ${snapshot.error}');
          return LedRaw(config, value: null);
        }
        if (snapshot.hasData == false) {
          return LedRaw(config, value: null);
        }

        return LedRaw(config, value: snapshot.data);
      },
    );
  }
}

class LedRaw extends ConsumerWidget {
  final LEDConfig config;
  final bool? value;

  const LedRaw(this.config, {super.key, this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool? isOn = value;
    if (config.key == LEDConfig.previewStr) {
      isOn = true;
    }
    final color =
        isOn == null ? null : (isOn ? config.onColor : config.offColor);

    return CustomPaint(
      painter: LEDPainter(color: color, ledType: config.ledType),
    );
  }
}

class LEDPainter extends CustomPainter {
  final Color? color;
  final LEDType ledType;

  LEDPainter({required this.color, required this.ledType});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color ?? Colors.grey
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);

    // Draw shape based on type
    if (ledType == LEDType.circle) {
      // Draw circle
      canvas.drawCircle(
        center,
        (min(size.width, size.height) / 2),
        paint,
      );

      // Draw border
      paint.color = Colors.black;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
      canvas.drawCircle(
        center,
        (min(size.width, size.height) / 2),
        paint,
      );
    } else {
      // Draw rounded rectangle
      final rect = Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      );
      final borderRadius = Radius.circular(
          size.shortestSide * 0.2); // 20% of shortest side like conveyor
      final rrect = RRect.fromRectAndRadius(rect, borderRadius);

      // Draw filled rounded rectangle
      canvas.drawRRect(rrect, paint);

      // Draw border
      paint.color = Colors.black;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2;
      canvas.drawRRect(rrect, paint);
    }

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
  bool shouldRepaint(LEDPainter oldDelegate) =>
      color != oldDelegate.color || ledType != oldDelegate.ledType;
}
