import 'dart:math' as math;

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:beamer/beamer.dart';

import 'common.dart';
import '../../widgets/baader.dart';
import '../../converter/color_converter.dart';

part 'baader.g.dart';

@JsonSerializable()
class Baader221Config extends BaseAsset {
  @ColorConverter()
  Color color;
  @JsonKey(name: 'stroke_width')
  double strokeWidth;
  @JsonKey(name: 'beam_url')
  String? beamUrl;

  Baader221Config({
    required this.color,
    this.strokeWidth = 2.0,
    this.beamUrl, // Add to constructor
  });

  @override
  Widget build(BuildContext context) {
    final widget = LayoutRotatedBox(
      angle: (coordinates.angle ?? 0.0) * math.pi / 180,
      child: CustomPaint(
        size: size.toSize(MediaQuery.of(context).size),
        painter: Baader221CustomPainter(
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
    if (beamUrl != null) {
      return GestureDetector(
        onTap: () => context.beamToNamed(beamUrl!),
        child: widget,
      );
    }

    return widget;
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
          color: DialogTheme.of(context).backgroundColor ?? Theme.of(context).colorScheme.surface,
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

  static const previewStr = 'Baader221 preview';

  Baader221Config.preview()
      : color = Colors.blue,
        strokeWidth = 0.5,
        beamUrl = null;

  factory Baader221Config.fromJson(Map<String, dynamic> json) =>
      _$Baader221ConfigFromJson(json);
  Map<String, dynamic> toJson() => _$Baader221ConfigToJson(this);
}

class _ConfigContent extends StatefulWidget {
  final Baader221Config config;

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
        SizeField(
          initialValue: widget.config.size,
          onChanged: (size) => widget.config.size = size,
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (coordinates) => widget.config.coordinates = coordinates,
          enableAngle: true,
        ),
        const SizedBox(height: 16),
        ColorPicker(
          pickerColor: widget.config.color,
          onColorChanged: (color) => widget.config.color = color,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Beam URL: '),
            Expanded(
              child: TextFormField(
                initialValue: widget.config.beamUrl ?? '',
                decoration: const InputDecoration(
                  hintText: 'Enter route (e.g., /settings?color=red)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  widget.config.beamUrl = value.isEmpty ? null : value;
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Stroke Width: '),
            Expanded(
              child: TextFormField(
                initialValue: widget.config.strokeWidth.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter stroke width',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final doubleValue = double.tryParse(value);
                  if (doubleValue != null &&
                      doubleValue >= 0.0 &&
                      doubleValue <= 10.0) {
                    widget.config.strokeWidth = doubleValue;
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
