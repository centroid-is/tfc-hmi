import 'package:flutter/widgets.dart' show BuildContext, Color, immutable;

import 'package:json_annotation/json_annotation.dart';

import '../theme.dart' show HmiColorRole;

/// A persistable color that is either a reference into the active color
/// scheme ([HmiColorRole]) or a literal RGBA value.
///
/// Role-backed values serialize as `{"role": "auto"}` and re-resolve through
/// the theme on every build, so they track scheme switches; literals
/// serialize as the classic `{"red": ..., "green": ..., ...}` map and never
/// change. Old page configs therefore load unchanged as literals.
@immutable
class AssetColor {
  final Color? _literal;
  final HmiColorRole? role;

  const AssetColor.literal(Color literal)
      : _literal = literal,
        role = null;
  const AssetColor.role(HmiColorRole this.role) : _literal = null;

  static const auto = AssetColor.role(HmiColorRole.auto);
  static const stopped = AssetColor.role(HmiColorRole.stopped);
  static const primary = AssetColor.role(HmiColorRole.primary);
  static const secondary = AssetColor.role(HmiColorRole.secondary);

  bool get isRole => role != null;

  /// The literal value, if this is not a role reference.
  Color? get literal => _literal;

  Color resolve(BuildContext context) =>
      role?.resolve(context) ?? _literal!;

  @override
  bool operator ==(Object other) =>
      other is AssetColor && other.role == role && other._literal == _literal;

  @override
  int get hashCode => Object.hash(role, _literal);

  @override
  String toString() =>
      role != null ? 'AssetColor.role(${role!.name})' : 'AssetColor($_literal)';
}

/// JSON for [AssetColor]: `{"role": "<name>"}` or the [ColorConverter] map.
class AssetColorConverter
    implements JsonConverter<AssetColor, Map<String, dynamic>> {
  const AssetColorConverter();

  @override
  AssetColor fromJson(Map<String, dynamic> json) {
    final roleName = json['role'];
    if (roleName is String) {
      // An unknown role (config written by a newer build) must not take the
      // page down — degrade to the most neutral state color.
      return AssetColor.role(
          HmiColorRole.values.asNameMap()[roleName] ?? HmiColorRole.stopped);
    }
    return AssetColor.literal(const ColorConverter().fromJson(json));
  }

  @override
  Map<String, dynamic> toJson(AssetColor color) {
    if (color.role != null) return {'role': color.role!.name};
    return const ColorConverter().toJson(color.literal!);
  }
}

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
