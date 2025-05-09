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

  ThemeData themeFromColorScheme(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      fontFamily: 'roboto-mono',
      textTheme: const TextTheme(),
      scrollbarTheme: const ScrollbarThemeData(
          thumbVisibility: WidgetStatePropertyAll(true)),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      shadowColor: scheme.surfaceBright,
    );
  }

  final solarizedLight = themeFromColorScheme(solarizedLightColorScheme);
  final solarizedDark = themeFromColorScheme(solarizedDarkColorScheme);
  return (solarizedLight, solarizedDark);
}
