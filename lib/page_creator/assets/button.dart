import 'dart:math';
import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;

import 'common.dart';
import '../../providers/state_man.dart';
import '../../core/state_man.dart';
import '../../converter/color_converter.dart';
part 'button.g.dart';

@JsonSerializable()
class FeedbackConfig {
  String key = "Default";
  @ColorConverter()
  Color color = Colors.green;

  FeedbackConfig();

  factory FeedbackConfig.fromJson(Map<String, dynamic> json) =>
      _$FeedbackConfigFromJson(json);
  Map<String, dynamic> toJson() => _$FeedbackConfigToJson(this);
}

@JsonEnum()
enum ButtonType {
  circle,
  square,
}

@JsonSerializable()
class ButtonConfig extends BaseAsset {
  String key;
  FeedbackConfig? feedback;
  @ColorConverter()
  @JsonKey(name: 'outward_color')
  Color outwardColor;
  @ColorConverter()
  @JsonKey(name: 'inward_color')
  Color inwardColor;
  @JsonKey(name: 'button_type')
  ButtonType buttonType;

  @override
  Widget build(BuildContext context) {
    return Button(this);
  }

  @override
  Widget configure(BuildContext context) {
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
          color: Theme.of(context).dialogBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  ButtonConfig({
    required this.key,
    required this.outwardColor,
    required this.inwardColor,
    required this.buttonType,
  });

  static const previewStr = 'Button preview';

  ButtonConfig.preview()
      : key = previewStr,
        outwardColor = Colors.green,
        inwardColor = Colors.green,
        buttonType = ButtonType.circle {
    textPos = TextPos.right;
  }

  factory ButtonConfig.fromJson(Map<String, dynamic> json) =>
      _$ButtonConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ButtonConfigToJson(this);
}

class Button extends ConsumerStatefulWidget {
  final ButtonConfig config;

  const Button(this.config, {super.key});

  @override
  ConsumerState<Button> createState() => _ButtonState();
}

class _ButtonState extends ConsumerState<Button> {
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

  final _pressedController = StreamController<bool>.broadcast();
  bool _isPressed = false;
  bool _feedbackActive = false;

  @override
  void dispose() {
    _pressedController.close();
    super.dispose();
  }

  // Call this in onTapDown, onTapUp, onTapCancel
  void _setPressed(bool value) {
    if (_isPressed != value) {
      setState(() => _isPressed = value);
      _pressedController.add(value);
    }
  }

  Stream<Color> colorStream(StateMan stateMan) {
    final feedbackStream = widget.config.feedback == null
        ? Stream<bool>.value(false)
        : stateMan
            .subscribe(widget.config.feedback!.key)
            .asStream()
            .asyncExpand((s) => s)
            .map((value) => value?.asBool ?? false)
            .startWith(_feedbackActive);

    final pressedStream = _pressedController.stream.startWith(_isPressed);

    return Rx.combineLatest2<bool, bool, Color>(
      feedbackStream,
      pressedStream,
      (feedbackActive, isPressed) {
        _feedbackActive = feedbackActive;
        if (feedbackActive) {
          return widget.config.feedback!.color;
        }
        return isPressed
            ? widget.config.inwardColor
            : widget.config.outwardColor;
      },
    );
  }

  Widget _buildButton(Color color) {
    final isPreview = widget.config.key == ButtonConfig.previewStr;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: widget.config.buttonType == ButtonType.circle
            ? const CircleBorder()
            : const RoundedRectangleBorder(),
        onTapDown: (_) async {
          _setPressed(true);
          if (isPreview) return;
          final client = await ref.read(stateManProvider.future);
          try {
            await client.write(widget.config.key,
                DynamicValue(value: true, typeId: NodeId.boolean));
            _log.d('Button ${widget.config.key} pressed');
          } catch (e) {
            _log.e('Error writing button press', error: e);
          }
        },
        onTapUp: (_) async {
          _setPressed(false);
          if (isPreview) return;
          final client = await ref.read(stateManProvider.future);
          try {
            await client.write(widget.config.key,
                DynamicValue(value: false, typeId: NodeId.boolean));
            _log.d('Button ${widget.config.key} released');
          } catch (e) {
            _log.e('Error writing button release', error: e);
          }
        },
        onTapCancel: () async {
          _setPressed(false);
          if (isPreview) return;
          final client = await ref.read(stateManProvider.future);
          try {
            await client.write(widget.config.key,
                DynamicValue(value: false, typeId: NodeId.boolean));
            _log.d('Button ${widget.config.key} tap cancelled');
          } catch (e) {
            _log.e('Error writing button cancel', error: e);
          }
        },
        child: CustomPaint(
          painter: ButtonPainter(
            color: color,
            isPressed: _isPressed,
            buttonType: widget.config.buttonType,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stateManAsync = ref.watch(stateManProvider);

    return stateManAsync.when(
      data: (stateMan) {
        return StreamBuilder<Color>(
          stream: colorStream(stateMan),
          builder: (context, snapshot) {
            final color = snapshot.data ?? widget.config.outwardColor;
            return _buildButton(color);
          },
        );
      },
      loading: () => _buildButton(widget.config.outwardColor),
      error: (_, __) => _buildButton(widget.config.outwardColor),
    );
  }
}

class ButtonPainter extends CustomPainter {
  final Color color;
  final bool isPressed;
  final ButtonType buttonType;

  ButtonPainter({
    required this.color,
    this.isPressed = false,
    required this.buttonType,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final borderRadius = Radius.circular(
        size.shortestSide * 0.2); // 20% of shortest side like LED and conveyor

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        isPressed ? 2 : 4,
      );

    // Draw button and shadow based on type
    if (buttonType == ButtonType.circle) {
      canvas.drawCircle(
        center + Offset(0, isPressed ? 1 : 2),
        radius * (isPressed ? 0.9 : 1.0),
        shadowPaint,
      );
    } else {
      final shadowRect = Rect.fromCenter(
        center: center + Offset(0, isPressed ? 1 : 2),
        width: size.width * (isPressed ? 0.9 : 1.0),
        height: size.height * (isPressed ? 0.9 : 1.0),
      );
      final shadowRRect = RRect.fromRectAndRadius(shadowRect, borderRadius);
      canvas.drawRRect(shadowRRect, shadowPaint);
    }

    // Draw button fill
    final buttonPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    if (buttonType == ButtonType.circle) {
      canvas.drawCircle(
        center,
        radius * (isPressed ? 0.95 : 1.0),
        buttonPaint,
      );
    } else {
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * (isPressed ? 0.95 : 1.0),
        height: size.height * (isPressed ? 0.95 : 1.0),
      );
      final rrect = RRect.fromRectAndRadius(rect, borderRadius);
      canvas.drawRRect(rrect, buttonPaint);
    }

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    if (buttonType == ButtonType.circle) {
      canvas.drawCircle(
        center,
        radius * (isPressed ? 0.95 : 1.0),
        borderPaint,
      );
    } else {
      final rect = Rect.fromCenter(
        center: center,
        width: size.width * (isPressed ? 0.95 : 1.0),
        height: size.height * (isPressed ? 0.95 : 1.0),
      );
      final rrect = RRect.fromRectAndRadius(rect, borderRadius);
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(ButtonPainter oldDelegate) =>
      color != oldDelegate.color ||
      isPressed != oldDelegate.isPressed ||
      buttonType != oldDelegate.buttonType;
}

class _ConfigContent extends StatefulWidget {
  final ButtonConfig config;

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
          onChanged: (value) => setState(() => widget.config.key = value),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: widget.config.text,
          onChanged: (value) => setState(() => widget.config.text = value),
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (c) => setState(() => widget.config.coordinates = c),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Outward Color'),
            const SizedBox(width: 8),
            Expanded(
              child: BlockPicker(
                pickerColor: widget.config.outwardColor,
                onColorChanged: (value) {
                  setState(() {
                    widget.config.outwardColor = value;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Inward Color'),
            const SizedBox(width: 8),
            Expanded(
              child: BlockPicker(
                pickerColor: widget.config.inwardColor,
                onColorChanged: (value) {
                  setState(() {
                    widget.config.inwardColor = value;
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
              .map((e) =>
                  DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
              .toList(),
        ),
        const SizedBox(height: 16),
        // Button type selector
        DropdownButton<ButtonType>(
          value: widget.config.buttonType,
          isExpanded: true,
          onChanged: (value) {
            setState(() {
              widget.config.buttonType = value!;
              // Optionally, sync height and width if switching to circle
              if (value == ButtonType.circle) {
                final avg =
                    (widget.config.size.width + widget.config.size.height) / 2;
                widget.config.size = RelativeSize(width: avg, height: avg);
              }
            });
          },
          items: ButtonType.values
              .map((e) => DropdownMenuItem<ButtonType>(
                    value: e,
                    child: Text(e.name[0].toUpperCase() + e.name.substring(1)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(widget.config.buttonType == ButtonType.square
                ? 'Width: '
                : 'Size: '),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
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
                  final widthPercent = double.tryParse(value) ?? 0.0;
                  if (widthPercent >= 0.01 && widthPercent <= 50.0) {
                    setState(() {
                      widget.config.size = RelativeSize(
                        width: widthPercent / 100,
                        height: widget.config.buttonType == ButtonType.square
                            ? widget.config.size.height
                            : widthPercent / 100,
                      );
                    });
                  }
                },
              ),
            ),
            if (widget.config.buttonType == ButtonType.square) ...[
              const SizedBox(width: 16),
              const Text('Height: '),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue:
                      (widget.config.size.height * 100).toStringAsFixed(2),
                  decoration: const InputDecoration(
                    suffixText: '%',
                    isDense: true,
                    helperText: '0.01-50%',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    final heightPercent = double.tryParse(value) ?? 0.0;
                    if (heightPercent >= 0.01 && heightPercent <= 50.0) {
                      setState(() {
                        widget.config.size = RelativeSize(
                          width: widget.config.size.width,
                          height: heightPercent / 100,
                        );
                      });
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Feedback config fields
        Row(
          children: [
            const Text('Feedback Key'),
            const SizedBox(width: 8),
            Expanded(
              child: KeyField(
                initialValue: widget.config.feedback?.key ?? '',
                onChanged: (value) {
                  setState(() {
                    if (widget.config.feedback == null) {
                      widget.config.feedback = FeedbackConfig();
                    }
                    widget.config.feedback!.key = value;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Feedback Color'),
            const SizedBox(width: 8),
            Expanded(
              child: BlockPicker(
                pickerColor: widget.config.feedback?.color ?? Colors.green,
                onColorChanged: (value) {
                  setState(() {
                    if (widget.config.feedback == null) {
                      widget.config.feedback = FeedbackConfig();
                    }
                    widget.config.feedback!.color = value;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
