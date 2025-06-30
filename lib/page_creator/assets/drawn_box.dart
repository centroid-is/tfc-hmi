// A drawn box with configurable color, size, and position
// Dashed or solid
// Line width
// Hidable individual lines

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'common.dart';
import '../../converter/color_converter.dart';
part 'drawn_box.g.dart';

@JsonSerializable()
class DrawnBoxConfig extends BaseAsset {
  @ColorConverter()
  Color color;
  double lineWidth;
  bool isDashed;
  bool showTop;
  bool showRight;
  bool showBottom;
  bool showLeft;
  double? dashLength;
  double? dashSpacing;

  DrawnBoxConfig({
    this.color = Colors.black,
    this.lineWidth = 2.0,
    this.isDashed = false,
    this.showTop = true,
    this.showRight = true,
    this.showBottom = true,
    this.showLeft = true,
    this.dashLength = 5.0,
    this.dashSpacing = 5.0,
  });

  DrawnBoxConfig.preview()
      : color = Colors.black,
        lineWidth = 2.0,
        isDashed = true,
        showTop = true,
        showRight = true,
        showBottom = true,
        showLeft = true,
        dashLength = 5.0,
        dashSpacing = 5.0;

  factory DrawnBoxConfig.fromJson(Map<String, dynamic> json) =>
      _$DrawnBoxConfigFromJson(json);
  Map<String, dynamic> toJson() => _$DrawnBoxConfigToJson(this);

  @override
  Widget build(BuildContext context) => DrawnBox(config: this);

  @override
  Widget configure(BuildContext context) => _DrawnBoxConfigEditor(config: this);
}

class _DrawnBoxConfigEditor extends StatefulWidget {
  final DrawnBoxConfig config;
  const _DrawnBoxConfigEditor({required this.config});

  @override
  State<_DrawnBoxConfigEditor> createState() => _DrawnBoxConfigEditorState();
}

class _DrawnBoxConfigEditorState extends State<_DrawnBoxConfigEditor> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Color picker
          BlockPicker(
            pickerColor: widget.config.color,
            onColorChanged: (color) =>
                setState(() => widget.config.color = color),
          ),
          const SizedBox(height: 16),

          // Line width slider
          Row(
            children: [
              const Text('Line Width:'),
              Expanded(
                child: Slider(
                  value: widget.config.lineWidth,
                  min: 1.0,
                  max: 10.0,
                  divisions: 18,
                  label: widget.config.lineWidth.toStringAsFixed(1),
                  onChanged: (value) =>
                      setState(() => widget.config.lineWidth = value),
                ),
              ),
              Text('${widget.config.lineWidth.toStringAsFixed(1)}px'),
            ],
          ),

          // Dashed/Solid toggle
          SwitchListTile(
            title: const Text('Dashed Lines'),
            value: widget.config.isDashed,
            onChanged: (value) =>
                setState(() => widget.config.isDashed = value),
          ),

          // Dash settings (only visible when dashed is true)
          if (widget.config.isDashed) ...[
            Row(
              children: [
                const Text('Dash Length:'),
                Expanded(
                  child: Slider(
                    value: widget.config.dashLength ?? 5.0,
                    min: 2.0,
                    max: 20.0,
                    divisions: 36,
                    label: (widget.config.dashLength ?? 5.0).toStringAsFixed(1),
                    onChanged: (value) =>
                        setState(() => widget.config.dashLength = value),
                  ),
                ),
                Text('${widget.config.dashLength?.toStringAsFixed(1)}px'),
              ],
            ),
            Row(
              children: [
                const Text('Dash Spacing:'),
                Expanded(
                  child: Slider(
                    value: widget.config.dashSpacing ?? 5.0,
                    min: 2.0,
                    max: 20.0,
                    divisions: 36,
                    label:
                        (widget.config.dashSpacing ?? 5.0).toStringAsFixed(1),
                    onChanged: (value) =>
                        setState(() => widget.config.dashSpacing = value),
                  ),
                ),
                Text('${widget.config.dashSpacing?.toStringAsFixed(1)}px'),
              ],
            ),
          ],

          // Line visibility toggles
          CheckboxListTile(
            title: const Text('Show Top Line'),
            value: widget.config.showTop,
            onChanged: (value) =>
                setState(() => widget.config.showTop = value ?? true),
          ),
          CheckboxListTile(
            title: const Text('Show Right Line'),
            value: widget.config.showRight,
            onChanged: (value) =>
                setState(() => widget.config.showRight = value ?? true),
          ),
          CheckboxListTile(
            title: const Text('Show Bottom Line'),
            value: widget.config.showBottom,
            onChanged: (value) =>
                setState(() => widget.config.showBottom = value ?? true),
          ),
          CheckboxListTile(
            title: const Text('Show Left Line'),
            value: widget.config.showLeft,
            onChanged: (value) =>
                setState(() => widget.config.showLeft = value ?? true),
          ),

          const SizedBox(height: 16),

          // Size and position fields
          SizeField(
            initialValue: widget.config.size,
            onChanged: (size) => setState(() => widget.config.size = size),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            enableAngle: true,
            initialValue: widget.config.coordinates,
            onChanged: (coordinates) =>
                setState(() => widget.config.coordinates = coordinates),
          ),
        ],
      ),
    );
  }
}

class DrawnBox extends StatelessWidget {
  final DrawnBoxConfig config;

  const DrawnBox({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: (config.coordinates.angle ?? 0.0) * pi / 180,
      child: CustomPaint(
        painter: _DrawnBoxPainter(
          color: config.color,
          lineWidth: config.lineWidth,
          isDashed: config.isDashed,
          showTop: config.showTop,
          showRight: config.showRight,
          showBottom: config.showBottom,
          showLeft: config.showLeft,
          dashLength: config.dashLength ?? 5.0,
          dashSpacing: config.dashSpacing ?? 5.0,
        ),
      ),
    );
  }
}

class _DrawnBoxPainter extends CustomPainter {
  final Color color;
  final double lineWidth;
  final bool isDashed;
  final bool showTop;
  final bool showRight;
  final bool showBottom;
  final bool showLeft;
  final double dashLength;
  final double dashSpacing;

  _DrawnBoxPainter({
    required this.color,
    required this.lineWidth,
    required this.isDashed,
    required this.showTop,
    required this.showRight,
    required this.showBottom,
    required this.showLeft,
    required this.dashLength,
    required this.dashSpacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke;

    void drawDashedLine(Offset start, Offset end) {
      if (!isDashed) {
        canvas.drawLine(start, end, paint);
        return;
      }

      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final distance = sqrt(dx * dx + dy * dy);

      // Calculate number of complete dash+space segments needed
      final totalLength = dashLength + dashSpacing;
      final count = (distance / totalLength).ceil(); // Changed to ceil
      final adjustedLength =
          distance / count; // Adjust segment length to fit exactly
      final dashLen = (dashLength * adjustedLength) / totalLength;

      for (var i = 0; i < count; i++) {
        final startFraction = i / count;
        final endFraction = (i / count) + (dashLen / distance);

        final dashStart = Offset(
          start.dx + dx * startFraction,
          start.dy + dy * startFraction,
        );
        final dashEnd = Offset(
          start.dx + dx * endFraction,
          start.dy + dy * endFraction,
        );

        canvas.drawLine(dashStart, dashEnd, paint);
      }
    }

    // Draw edges
    if (showTop) {
      drawDashedLine(Offset(0, 0), Offset(size.width, 0));
    }
    if (showRight) {
      drawDashedLine(Offset(size.width, 0), Offset(size.width, size.height));
    }
    if (showBottom) {
      drawDashedLine(Offset(size.width, size.height), Offset(0, size.height));
    }
    if (showLeft) {
      drawDashedLine(Offset(0, size.height), Offset(0, 0));
    }
  }

  @override
  bool shouldRepaint(_DrawnBoxPainter oldDelegate) =>
      color != oldDelegate.color ||
      lineWidth != oldDelegate.lineWidth ||
      isDashed != oldDelegate.isDashed ||
      showTop != oldDelegate.showTop ||
      showRight != oldDelegate.showRight ||
      showBottom != oldDelegate.showBottom ||
      showLeft != oldDelegate.showLeft ||
      dashLength != oldDelegate.dashLength ||
      dashSpacing != oldDelegate.dashSpacing;
}
