import 'dart:math' as math;

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'common.dart';
import '../../widgets/baader.dart';
import '../../converter/color_converter.dart';

part 'baader.g.dart';

@JsonSerializable()
class Baader221Config extends BaseAsset {
  @ColorConverter()
  Color color;

  Baader221Config({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutRotatedBox(
      angle: (coordinates.angle ?? 0.0) * math.pi / 180,
      child: CustomPaint(
        size: size.toSize(MediaQuery.of(context).size),
        painter: Baader221CustomPainter(
          color: color,
        ),
      ),
    );
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

  static const previewStr = 'Baader221 preview';

  Baader221Config.preview() : color = Colors.blue;

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
      ],
    );
  }
}
