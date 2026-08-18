import 'package:flutter/material.dart';

abstract final class SolarizedColors {
  static const Color base03 = Color.fromARGB(255, 0, 43, 54);
  static const Color base02 = Color.fromARGB(255, 7, 54, 66);
  static const Color base01 = Color.fromARGB(255, 88, 110, 117);
  static const Color base00 = Color.fromARGB(255, 101, 123, 131);
  static const Color base0 = Color.fromARGB(255, 131, 148, 150);
  static const Color base1 = Color.fromARGB(255, 147, 161, 161);
  static const Color base2 = Color.fromARGB(255, 238, 232, 213);
  static const Color base3 = Color.fromARGB(255, 253, 246, 227);
  static const Color yellow = Color.fromARGB(255, 181, 137, 0);
  static const Color orange = Color.fromARGB(255, 203, 75, 22);
  static const Color red = Color.fromARGB(255, 220, 50, 47);
  static const Color magenta = Color.fromARGB(255, 211, 54, 130);
  static const Color violet = Color.fromARGB(255, 108, 113, 196);
  static const Color blue = Color.fromARGB(255, 38, 139, 210);
  static const Color cyan = Color.fromARGB(255, 42, 161, 152);
  static const Color green = Color.fromARGB(255, 133, 153, 0);
}

/// ISA-101 inspired palette: gray surfaces, muted equipment-state colors,
/// saturated red reserved for faults/alarms.
abstract final class MutedColors {
  static const Color surfaceLight = Color(0xFFECEDEE);
  static const Color containerLight = Color(0xFFDEE1E3);
  static const Color onSurfaceLight = Color(0xFF3C3F41);
  static const Color surfaceDark = Color(0xFF232628);
  static const Color containerDark = Color(0xFF2C3033);
  static const Color onSurfaceDark = Color(0xFFC2C7CB);
  static const Color slate = Color(0xFF4A6572);
  static const Color slateBright = Color(0xFF7FA3B8);
  static const Color gray = Color(0xFF78838B);

  static const Color runningGreen = Color(0xFF7A9B76);
  static const Color manualOchre = Color(0xFFB39B5A);
  static const Color cleanBlue = Color(0xFF6B8CAE);
  static const Color stoppedGray = Color(0xFF9E9E9E);
  static const Color stoppedGrayDark = Color(0xFF6E6E6E);
  static const Color alarmRed = Color(0xFFD32F2F);
  static const Color unknownViolet = Color(0xFF8E7CA6);
  static const Color onState = Color(0xFFF5F5F5);
}

/// Semantic equipment-state colors (conveyors, drives, ...), themed per
/// color scheme so assets don't hardcode `Colors.*`.
@immutable
class HmiStateColors extends ThemeExtension<HmiStateColors> {
  const HmiStateColors({
    required this.auto,
    required this.manual,
    required this.cleaning,
    required this.stopped,
    required this.fault,
    required this.unknown,
    required this.onState,
  });

  /// Running in automatic mode.
  final Color auto;

  /// Running in manual mode.
  final Color manual;

  /// Cleaning mode.
  final Color cleaning;

  /// Stopped / idle.
  final Color stopped;

  /// Faulted / tripped — deliberately the most saturated state color.
  final Color fault;

  /// Unreadable or unrecognized state (misconfiguration, parse error).
  final Color unknown;

  /// Text/glyphs drawn on top of any of the state colors above.
  final Color onState;

  static const solarizedLight = HmiStateColors(
    auto: SolarizedColors.green,
    manual: SolarizedColors.yellow,
    cleaning: SolarizedColors.blue,
    stopped: SolarizedColors.base1,
    fault: SolarizedColors.red,
    unknown: SolarizedColors.magenta,
    onState: SolarizedColors.base3,
  );

  static const solarizedDark = HmiStateColors(
    auto: SolarizedColors.green,
    manual: SolarizedColors.yellow,
    cleaning: SolarizedColors.blue,
    stopped: SolarizedColors.base01,
    fault: SolarizedColors.red,
    unknown: SolarizedColors.magenta,
    onState: SolarizedColors.base3,
  );

  static const mutedLight = HmiStateColors(
    auto: MutedColors.runningGreen,
    manual: MutedColors.manualOchre,
    cleaning: MutedColors.cleanBlue,
    stopped: MutedColors.stoppedGray,
    fault: MutedColors.alarmRed,
    unknown: MutedColors.unknownViolet,
    onState: MutedColors.onState,
  );

  static const mutedDark = HmiStateColors(
    auto: MutedColors.runningGreen,
    manual: MutedColors.manualOchre,
    cleaning: MutedColors.cleanBlue,
    stopped: MutedColors.stoppedGrayDark,
    fault: MutedColors.alarmRed,
    unknown: MutedColors.unknownViolet,
    onState: MutedColors.onState,
  );

  /// The theme's state colors, falling back to Solarized when the theme was
  /// built without the extension (bare `MaterialApp` in tests).
  static HmiStateColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<HmiStateColors>() ??
        (theme.brightness == Brightness.dark ? solarizedDark : solarizedLight);
  }

  @override
  HmiStateColors copyWith({
    Color? auto,
    Color? manual,
    Color? cleaning,
    Color? stopped,
    Color? fault,
    Color? unknown,
    Color? onState,
  }) {
    return HmiStateColors(
      auto: auto ?? this.auto,
      manual: manual ?? this.manual,
      cleaning: cleaning ?? this.cleaning,
      stopped: stopped ?? this.stopped,
      fault: fault ?? this.fault,
      unknown: unknown ?? this.unknown,
      onState: onState ?? this.onState,
    );
  }

  @override
  HmiStateColors lerp(HmiStateColors? other, double t) {
    if (other == null) return this;
    return HmiStateColors(
      auto: Color.lerp(auto, other.auto, t)!,
      manual: Color.lerp(manual, other.manual, t)!,
      cleaning: Color.lerp(cleaning, other.cleaning, t)!,
      stopped: Color.lerp(stopped, other.stopped, t)!,
      fault: Color.lerp(fault, other.fault, t)!,
      unknown: Color.lerp(unknown, other.unknown, t)!,
      onState: Color.lerp(onState, other.onState, t)!,
    );
  }
}

/// The color schemes offered in preferences. [solarized] is the historical
/// default; [muted] follows ISA-101's muted, gray-first guidance.
enum AppColorScheme {
  solarized('Solarized'),
  muted('Muted');

  const AppColorScheme(this.displayName);
  final String displayName;
}

ThemeData _themeFromColorScheme(ColorScheme scheme, HmiStateColors states) {
  return ThemeData(
      colorScheme: scheme,
      extensions: [states],
      fontFamily: 'roboto-mono',
      textTheme: const TextTheme(),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: scheme.primary.withAlpha(100),
        selectionHandleColor: scheme.primary,
      ),
      scrollbarTheme: const ScrollbarThemeData(
          thumbVisibility: WidgetStatePropertyAll(true)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      shadowColor: scheme.surfaceBright,
      // The bottom sheet maximum is used for board datetime picker
      bottomSheetTheme:
          BottomSheetThemeData(constraints: BoxConstraints(maxWidth: 1000.0)));
}

(ThemeData, ThemeData) themesForScheme(AppColorScheme scheme) {
  switch (scheme) {
    case AppColorScheme.solarized:
      return solarized();
    case AppColorScheme.muted:
      return muted();
  }
}

(ThemeData, ThemeData) solarized() {
  ColorScheme solarizedDarkColorScheme = const ColorScheme.dark(
    brightness: Brightness.dark,
    primary: SolarizedColors.blue,
    onPrimary: SolarizedColors.base02,
    secondary: SolarizedColors.base01,
    onSecondary: SolarizedColors.base02,
    error: SolarizedColors.red,
    onError: SolarizedColors.base02,
    surface: SolarizedColors.base03,
    onSurface: SolarizedColors.base01,
    tertiary: SolarizedColors.yellow,
    onTertiary: SolarizedColors.base02,
    surfaceContainerLow: SolarizedColors.base02,
    surfaceContainerHighest: SolarizedColors.base02,
  );

  ColorScheme solarizedLightColorScheme = const ColorScheme.light(
    brightness: Brightness.light,
    primary: SolarizedColors.green,
    onPrimary: SolarizedColors.base2,
    secondary: SolarizedColors.base1,
    onSecondary: SolarizedColors.base2,
    error: SolarizedColors.red,
    onError: SolarizedColors.base2,
    surface: SolarizedColors.base3,
    onSurface: SolarizedColors.base00,
    tertiary: SolarizedColors.yellow,
    onTertiary: SolarizedColors.base2,
    surfaceContainerLow: SolarizedColors.base2,
    surfaceContainerHighest: SolarizedColors.base2,
  );

  final solarizedLight = _themeFromColorScheme(
      solarizedLightColorScheme, HmiStateColors.solarizedLight);
  final solarizedDark = _themeFromColorScheme(
      solarizedDarkColorScheme, HmiStateColors.solarizedDark);
  return (solarizedLight, solarizedDark);
}

(ThemeData, ThemeData) muted() {
  ColorScheme isaDarkColorScheme = const ColorScheme.dark(
    brightness: Brightness.dark,
    primary: MutedColors.slateBright,
    onPrimary: MutedColors.surfaceDark,
    secondary: MutedColors.gray,
    onSecondary: MutedColors.surfaceDark,
    error: MutedColors.alarmRed,
    onError: MutedColors.onState,
    surface: MutedColors.surfaceDark,
    onSurface: MutedColors.onSurfaceDark,
    tertiary: MutedColors.manualOchre,
    onTertiary: MutedColors.surfaceDark,
    surfaceContainerLow: MutedColors.containerDark,
    surfaceContainerHighest: MutedColors.containerDark,
  );

  ColorScheme isaLightColorScheme = const ColorScheme.light(
    brightness: Brightness.light,
    primary: MutedColors.slate,
    onPrimary: MutedColors.surfaceLight,
    secondary: MutedColors.gray,
    onSecondary: MutedColors.surfaceLight,
    error: MutedColors.alarmRed,
    onError: MutedColors.onState,
    surface: MutedColors.surfaceLight,
    onSurface: MutedColors.onSurfaceLight,
    tertiary: MutedColors.manualOchre,
    onTertiary: MutedColors.surfaceLight,
    surfaceContainerLow: MutedColors.containerLight,
    surfaceContainerHighest: MutedColors.containerLight,
  );

  final isaLight =
      _themeFromColorScheme(isaLightColorScheme, HmiStateColors.mutedLight);
  final isaDark =
      _themeFromColorScheme(isaDarkColorScheme, HmiStateColors.mutedDark);
  return (isaLight, isaDark);
}
