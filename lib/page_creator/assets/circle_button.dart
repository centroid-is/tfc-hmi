import 'dart:ui' show Color, Size;
import 'dart:math';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'common.dart';
import '../../providers/state_man.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;

part 'circle_button.g.dart';

@JsonSerializable()
class CircleButtonConfig extends BaseAsset {
  String key;
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
    return CircleButton(this);
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

  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final client = ref.read(stateManProvider);
    final containerSize = MediaQuery.of(context).size;
    final actualSize = widget.config.size.toSize(containerSize);
    final buttonSize = min(actualSize.width, actualSize.height);

    final button = SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTapDown: (_) async {
            setState(() => _isPressed = true);
            final client = ref.read(stateManProvider);
            try {
              await client.write(widget.config.key,
                  DynamicValue(value: true, typeId: NodeId.boolean));
              _log.d('Button ${widget.config.key} pressed');
            } catch (e) {
              _log.e('Error writing button press', error: e);
            }
          },
          onTapUp: (_) async {
            setState(() => _isPressed = false);
            final client = ref.read(stateManProvider);
            try {
              await client.write(widget.config.key,
                  DynamicValue(value: false, typeId: NodeId.boolean));
              _log.d('Button ${widget.config.key} released');
            } catch (e) {
              _log.e('Error writing button release', error: e);
            }
          },
          onTapCancel: () async {
            setState(() => _isPressed = false);
            final client = ref.read(stateManProvider);
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
              color: _isPressed
                  ? widget.config.inwardColor
                  : widget.config.outwardColor,
              isPressed: _isPressed,
            ),
          ),
        ),
      ),
    );

    return Align(
      alignment: FractionalOffset(
        widget.config.coordinates.x,
        widget.config.coordinates.y,
      ),
      child: buildWithText(button, widget.config.key, widget.config.textPos),
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
      ],
    );
  }
}
