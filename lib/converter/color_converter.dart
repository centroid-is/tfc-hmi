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

  static const green = AssetColor.role(HmiColorRole.green);
  static const grey = AssetColor.role(HmiColorRole.grey);
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
          HmiColorRole.values.asNameMap()[roleName] ?? HmiColorRole.grey);
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

  /// Last-resort literals for role-format maps reaching this converter.
  ///
  /// Role colors properly resolve through the theme via [AssetColorConverter];
  /// this map only exists because stored configs can carry `{"role": ...}` in
  /// fields declared with the plain [ColorConverter] (a proposal or a newer
  /// build wrote them). 2026-08-26: one such color made `fromJson` throw,
  /// which took out the entire page-config parse and blanked every screen on
  /// a plant HMI. A color is never allowed to do that again — resolve to a
  /// fixed literal approximation instead.
  static const Map<String, Color> _roleFallbacks = {
    'green': Color(0xFF4CAF50),
    'yellow': Color(0xFFFDD835),
    'blue': Color(0xFF2196F3),
    'grey': Color(0xFF9E9E9E),
    'red': Color(0xFFF44336),
    'violet': Color(0xFF9C27B0),
    'primary': Color(0xFF607D8B),
    'secondary': Color(0xFF78909C),
    'tertiary': Color(0xFF90A4AE),
    'error': Color(0xFFF44336),
    'surface': Color(0xFFFAFAFA),
    'onSurface': Color(0xFF212121),
  };

  @override
  Color fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    if (role is String) {
      return _roleFallbacks[role] ?? _roleFallbacks['grey']!;
    }
    // Missing channels default instead of throwing, for the same reason as
    // the role fallback above: a malformed stored color must render wrong,
    // not blank the HMI.
    double channel(String key, [double fallback = 0.5]) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return Color.fromRGBO(
      (channel('red') * 255).toInt(),
      (channel('green') * 255).toInt(),
      (channel('blue') * 255).toInt(),
      channel('alpha', 1.0),
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
