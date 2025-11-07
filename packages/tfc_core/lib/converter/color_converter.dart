import 'dart:ui' show Color;

import 'package:json_annotation/json_annotation.dart';

class ColorConverter implements JsonConverter<Color, Map<String, dynamic>> {
  const ColorConverter();

  @override
  Color fromJson(Map<String, dynamic> json) {
    return Color.fromRGBO(
      (json['red']! * 255).toInt(),
      (json['green']! * 255).toInt(),
      (json['blue']! * 255).toInt(),
      json['alpha'] ?? 1.0,
    );
  }

  @override
  Map<String, double> toJson(Color color) => {
        'red': color.r,
        'green': color.g,
        'blue': color.b,
        'alpha': color.a,
      };
}

class OptionalColorConverter
    implements JsonConverter<Color?, Map<String, dynamic>?> {
  const OptionalColorConverter();

  @override
  Color? fromJson(Map<String, dynamic>? json) {
    if (json == null ||
        json['red'] == null ||
        json['green'] == null ||
        json['blue'] == null) {
      return null;
    }
    return Color.fromRGBO(
      (json['red']! * 255).toInt(),
      (json['green']! * 255).toInt(),
      (json['blue']! * 255).toInt(),
      json['alpha'] ?? 1.0,
    );
  }

  @override
  Map<String, double>? toJson(Color? color) {
    if (color == null) {
      return null;
    }
    return {
      'red': color.r,
      'green': color.g,
      'blue': color.b,
      'alpha': color.a,
    };
  }
}
