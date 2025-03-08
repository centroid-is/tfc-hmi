import 'package:json_annotation/json_annotation.dart';
import 'dart:ui' show Color, Size;
import 'package:flutter/material.dart';
part 'common.g.dart';

@JsonSerializable()
class ColorConverter implements JsonConverter<Color, Map<String, double>> {
  const ColorConverter();

  @override
  Color fromJson(Map<String, double> json) {
    return Color.fromRGBO(
      (json['red']! * 255).toInt(),
      (json['green']! * 255).toInt(),
      (json['blue']! * 255).toInt(),
      1.0,
    );
  }

  @override
  Map<String, double> toJson(Color color) => {
        'red': color.r,
        'green': color.g,
        'blue': color.b,
      };
}

@JsonSerializable()
class SizeConverter implements JsonConverter<Size, Map<String, double>> {
  const SizeConverter();

  @override
  Size fromJson(Map<String, double> json) {
    return Size(
      json['width'] ?? 0.0,
      json['height'] ?? 0.0,
    );
  }

  @override
  Map<String, double> toJson(Size size) => {
        'width': size.width,
        'height': size.height,
      };
}

@JsonEnum()
enum TextPos {
  above,
  below,
  left,
  right,
}

@JsonSerializable()
class Coordinates {
  final double x; // 0.0 to 1.0
  final double y; // 0.0 to 1.0
  final double? angle;

  Coordinates({
    required this.x,
    required this.y,
    this.angle,
  });

  factory Coordinates.fromJson(Map<String, dynamic> json) =>
      _$CoordinatesFromJson(json);
  Map<String, dynamic> toJson() => _$CoordinatesToJson(this);
}

extension SizeFromJson on Size {
  static Size fromJson(Map<String, dynamic> json) =>
      Size(json['width'] as double, json['height'] as double);

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
      };
}

abstract class Asset {
  String get assetName;
  Coordinates get coordinates;
  set coordinates(Coordinates coordinates);
  Widget build(BuildContext context);
  Map<String, dynamic> toJson();
}

@JsonSerializable(createFactory: false, explicitToJson: true)
abstract class BaseAsset implements Asset {
  @override
  String get assetName => variant;
  @JsonKey(name: 'asset_name')
  late final String variant;

  BaseAsset() {
    variant = runtimeType.toString();
  }

  @JsonKey(name: 'coordinates')
  Coordinates _coordinates = Coordinates(x: 0.0, y: 0.0);

  @override
  Coordinates get coordinates => _coordinates;

  @override
  set coordinates(Coordinates coordinates) {
    _coordinates = coordinates;
  }

  Map<String, dynamic> toJson();
}
