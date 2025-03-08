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
  @SizeConverter()
  @JsonKey(name: 'size')
  final Size size;

  @override
  Widget build(BuildContext context) {
    return CircleButton(this).build(context);
  }

  CircleButtonConfig({
    required this.key,
    required this.outwardColor,
    required this.inwardColor,
    required this.textPos,
    required this.size,
  });

  factory CircleButtonConfig.fromJson(Map<String, dynamic> json) =>
      _$CircleButtonConfigFromJson(json);
  Map<String, dynamic> toJson() => _$CircleButtonConfigToJson(this);
}

class CircleButton extends StatelessWidget {
  final CircleButtonConfig config;

  const CircleButton(this.config);

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
