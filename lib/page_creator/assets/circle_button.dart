import 'dart:ui' show Color, Size;
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
import '../client.dart';

part 'circle_button.g.dart';

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

@JsonSerializable()
class CircleButtonConfig extends BaseAsset {
  String key;
  FeedbackConfig? feedback;
  String? text;
  @ColorConverter()
  @JsonKey(name: 'outward_color')
  Color outwardColor;
  @ColorConverter()
  @JsonKey(name: 'inward_color')
  Color inwardColor;
  @JsonKey(name: 'text_pos')
  TextPos textPos;

  @override
  Widget build(BuildContext context) {
    return CircleButtonAligned(config: this);
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

  CircleButtonConfig({
    required this.key,
    required this.outwardColor,
    required this.inwardColor,
    required this.textPos,
  });

  static const previewStr = 'Circle button preview';

  CircleButtonConfig.preview()
      : key = previewStr,
        outwardColor = Colors.green,
        inwardColor = Colors.green,
        textPos = TextPos.right;

  factory CircleButtonConfig.fromJson(Map<String, dynamic> json) =>
      _$CircleButtonConfigFromJson(json);
  Map<String, dynamic> toJson() => _$CircleButtonConfigToJson(this);
}

class CircleButton extends ConsumerStatefulWidget {
  final CircleButtonConfig config;

  const CircleButton(this.config, {super.key});

  @override
  ConsumerState<CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends ConsumerState<CircleButton> {
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
        _log.d('Feedback active: $feedbackActive, isPressed: $isPressed');
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
    final isPreview = widget.config.key == CircleButtonConfig.previewStr;
    final containerSize = MediaQuery.of(context).size;
    final actualSize = widget.config.size.toSize(containerSize);
    final buttonSize = min(actualSize.width, actualSize.height);

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
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
            painter: CircleButtonPainter(
              color: color,
              isPressed: _isPressed,
            ),
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

class CircleButtonAligned extends StatelessWidget {
  final CircleButtonConfig config;

  const CircleButtonAligned({super.key, required this.config});

  factory CircleButtonAligned.preview() {
    return CircleButtonAligned(config: CircleButtonConfig.preview());
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: FractionalOffset(
        config.coordinates.x,
        config.coordinates.y,
      ),
      child: buildWithText(
        CircleButton(config),
        config.text ?? config.key,
        config.textPos,
      ),
    );
  }
}

class CircleButtonPainter extends CustomPainter {
  final Color color;
  final bool isPressed;

  CircleButtonPainter({
    required this.color,
    this.isPressed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        isPressed ? 2 : 4,
      );

    canvas.drawCircle(
      center + Offset(0, isPressed ? 1 : 2),
      radius * (isPressed ? 0.9 : 1.0),
      shadowPaint,
    );

    // Draw button
    final buttonPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      radius * (isPressed ? 0.95 : 1.0),
      buttonPaint,
    );

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(
      center,
      radius * (isPressed ? 0.95 : 1.0),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(CircleButtonPainter oldDelegate) =>
      color != oldDelegate.color || isPressed != oldDelegate.isPressed;
}

class _ConfigContent extends StatefulWidget {
  final CircleButtonConfig config;

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
        TextFormField(
          initialValue: widget.config.key,
          decoration: const InputDecoration(
            labelText: 'Key',
          ),
          onChanged: (value) {
            setState(() {
              widget.config.key = value;
            });
          },
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
        const SizedBox(height: 16),
        // Feedback config fields
        Row(
          children: [
            const Text('Feedback Key'),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: widget.config.feedback?.key ?? '',
                decoration: const InputDecoration(
                  labelText: 'Feedback Key',
                ),
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
