import 'package:json_annotation/json_annotation.dart';
import 'dart:ui' show Color, Size;
import 'package:flutter/material.dart';
import 'dart:math';
import 'common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../../providers/state_man.dart';

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
    return CircleButton(this);
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
              await client.write(widget.config.key, true);
              _log.d('Button ${widget.config.key} pressed');
            } catch (e) {
              _log.e('Error writing button press', error: e);
            }
          },
          onTapUp: (_) async {
            setState(() => _isPressed = false);
            final client = ref.read(stateManProvider);
            try {
              await client.write(widget.config.key, false);
              _log.d('Button ${widget.config.key} released');
            } catch (e) {
              _log.e('Error writing button release', error: e);
            }
          },
          onTapCancel: () async {
            setState(() => _isPressed = false);
            final client = ref.read(stateManProvider);
            try {
              await client.write(widget.config.key, false);
              _log.d('Button ${widget.config.key} tap cancelled');
            } catch (e) {
              _log.e('Error writing button cancel', error: e);
            }
          },
          child: CustomPaint(
            painter: CircleButtonPainter(
              outwardColor: widget.config.outwardColor,
              inwardColor: widget.config.inwardColor,
              isPressed: _isPressed, // Use local state for visual feedback
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
      ..color = Colors.black.withOpacity(isPressed ? 0.1 : 1)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        isPressed ? 2 : 4,
      );

    // Shadow offset changes when pressed
    canvas.drawCircle(
      center + Offset(0, isPressed ? 1 : 3),
      radius * (isPressed ? 0.95 : 1.0), // Shadow shrinks slightly when pressed
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
        ).createShader(Rect.fromCircle(
          center: center,
          radius: radius *
              (isPressed ? 0.95 : 1.0), // Button shrinks slightly when pressed
        ));

      canvas.drawCircle(
        center,
        radius * (isPressed ? 0.95 : 1.0),
        buttonPaint,
      );

      // Draw border
      final borderPaint = Paint()
        ..color = outwardColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(
        center,
        radius * (isPressed ? 0.95 : 1.0),
        borderPaint,
      );
    } else {
      // Error state remains the same
      final errorPaint = Paint()
        ..color = Colors.grey
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, errorPaint);

      final borderPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, borderPaint);

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
        Offset((size.width - textPainter.width) / 2,
            (size.height - textPainter.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(CircleButtonPainter oldDelegate) =>
      outwardColor != oldDelegate.outwardColor ||
      inwardColor != oldDelegate.inwardColor ||
      isPressed != oldDelegate.isPressed;
}
