import 'package:flutter/widgets.dart'
    show BuildContext, Color, immutable, visibleForTesting;

import 'package:json_annotation/json_annotation.dart';

import '../theme.dart' show HmiColorRole, SolarizedColors;

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
  ///
  /// The values mirror the Solarized-light palette, which is what
  /// `HmiStateColors.of` and [HmiColorRole.resolve] fall back to when no
  /// theme extension is in play — so a degraded color lands in the same
  /// family as the properly-resolved one instead of a raw Material hue.
  /// `test/page_creator/assets/asset_parse_robustness_test.dart` fails if
  /// [HmiColorRole] grows an entry that is missing here.
  @visibleForTesting
  static const Map<String, Color> roleFallbacks = {
    'green': SolarizedColors.green,
    'yellow': SolarizedColors.yellow,
    'blue': SolarizedColors.blue,
    'grey': SolarizedColors.base1,
    'red': SolarizedColors.red,
    'violet': SolarizedColors.magenta,
    // Scheme roles: the solarized *light* ColorScheme's values.
    'primary': SolarizedColors.green,
    'secondary': SolarizedColors.base1,
    'tertiary': SolarizedColors.yellow,
    'error': SolarizedColors.red,
    'surface': SolarizedColors.base3,
    'onSurface': SolarizedColors.base00,
  };

  /// One channel of a stored color, as a 0..1 double.
  ///
  /// Deliberately type-testing rather than casting: a hand-edited config (the
  /// 2026-08-26 recovery was manual JSON surgery) can carry a string or a
  /// bool where a number belongs, and `as num?` would throw on it — the one
  /// thing this converter must never do.
  static double _channel(Map<String, dynamic> json, String key,
      [double fallback = 0.5]) {
    final value = json[key];
    if (value is num && value.isFinite) return value.toDouble().clamp(0.0, 1.0);
    return fallback;
  }

  @override
  Color fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    if (role is String) {
      return roleFallbacks[role] ?? roleFallbacks['grey']!;
    }
    // Missing or malformed channels default instead of throwing, for the same
    // reason as the role fallback above: a bad stored color must render
    // wrong, not blank the HMI.
    return Color.fromRGBO(
      (_channel(json, 'red') * 255).toInt(),
      (_channel(json, 'green') * 255).toInt(),
      (_channel(json, 'blue') * 255).toInt(),
      _channel(json, 'alpha', 1.0),
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
    // "No color" is the natural degraded answer here, so anything that is not
    // a usable literal triple — absent, role-format, or a hand-edited string
    // where a number belongs — reads as null. Like [ColorConverter], this
    // must never throw: it is reached from the same page-config parse.
    if (json == null ||
        json['red'] is! num ||
        json['green'] is! num ||
        json['blue'] is! num) {
      return null;
    }
    return const ColorConverter().fromJson(json);
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
