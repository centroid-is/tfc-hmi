import 'package:json_annotation/json_annotation.dart';
import 'dart:ui' show Color, Size;
import 'package:flutter/material.dart';
import 'common.dart';

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
    final containerSize = MediaQuery.of(context).size;
    final actualSize = size.toSize(containerSize);

    final button = Container(
      width: actualSize.width,
      height: actualSize.height,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            inwardColor,
            outwardColor,
          ],
          stops: const [0.0, 1.0],
        ),
        border: Border.all(
          color: outwardColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            // Handle tap event
          },
        ),
      ),
    );

    return buildWithText(button, key, textPos);
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

class CircleButton extends StatelessWidget {
  final CircleButtonConfig config;

  const CircleButton(this.config);

  @override
  Widget build(BuildContext context) {
    final containerSize = MediaQuery.of(context).size;
    final actualSize = config.size.toSize(containerSize);

    final button = Container(
      width: actualSize.width,
      height: actualSize.height,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            config.inwardColor,
            config.outwardColor,
          ],
          stops: const [0.0, 1.0],
        ),
        border: Border.all(
          color: config.outwardColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            // Handle tap event
          },
        ),
      ),
    );

    return buildWithText(button, config.key, config.textPos);
  }
}
