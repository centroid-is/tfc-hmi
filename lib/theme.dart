import 'package:flutter/material.dart';

class SolarizedColors {
  final Color base03 = const Color.fromARGB(255, 0, 43, 54);
  final Color base02 = const Color.fromARGB(255, 7, 54, 66);
  final Color base01 = const Color.fromARGB(255, 88, 110, 117);
  final Color base00 = const Color.fromARGB(255, 101, 123, 131);
  final Color base0 = const Color.fromARGB(255, 131, 148, 150);
  final Color base1 = const Color.fromARGB(255, 147, 161, 161);
  final Color base2 = const Color.fromARGB(255, 238, 232, 213);
  final Color base3 = const Color.fromARGB(255, 253, 246, 227);
  final Color yellow = const Color.fromARGB(255, 181, 137, 0);
  final Color orange = const Color.fromARGB(255, 203, 75, 22);
  final Color red = const Color.fromARGB(255, 220, 50, 47);
  final Color magenta = const Color.fromARGB(255, 211, 54, 130);
  final Color violet = const Color.fromARGB(255, 108, 113, 196);
  final Color blue = const Color.fromARGB(255, 38, 139, 210);
  final Color cyan = const Color.fromARGB(255, 42, 161, 152);
  final Color green = const Color.fromARGB(255, 133, 153, 0);
}

(ThemeData, ThemeData) solarized() {
  ColorScheme solarizedDarkColorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: SolarizedColors().base03,
      onPrimary: SolarizedColors().green,
      secondary: SolarizedColors().base03,
      onSecondary: SolarizedColors().base01,
      error: SolarizedColors().base03,
      onError: SolarizedColors().red,
      surface: SolarizedColors().base02,
      onSurface: SolarizedColors().base0,
      tertiary: SolarizedColors().base03,
      onTertiary: SolarizedColors().yellow);
  TextStyle solarizedDarkBaseStyle = const TextStyle(fontFamily: 'roboto-mono');

// Not currently used, default text themes are to my liking.
// each size can be customized here if desired
  TextTheme solarizedTextTheme = TextTheme();

// Customize inputdecorations
  InputDecorationTheme solarizedDarkInputDecorationsTheme =
      InputDecorationTheme(
    focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: solarizedDarkColorScheme.onPrimary)),
    errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: solarizedDarkColorScheme.onError)),
    focusColor: solarizedDarkColorScheme.onPrimary,
    labelStyle: TextStyle(color: solarizedDarkColorScheme.onSecondary),
    floatingLabelStyle: TextStyle(color: solarizedDarkColorScheme.onPrimary),
    enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: solarizedDarkColorScheme.onSecondary)),
  );

  ElevatedButtonThemeData solarizedDarkElevatedButton = ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStatePropertyAll<Color>(SolarizedColors().green),
    ),
  );
  final solarizedDark = ThemeData(
      fontFamily: 'roboto-mono',
      colorScheme: solarizedDarkColorScheme,
      textTheme: solarizedTextTheme,
      canvasColor: solarizedDarkColorScheme.surface,
      scaffoldBackgroundColor: solarizedDarkColorScheme.surface,
      highlightColor: Colors.transparent,
      focusColor: solarizedDarkColorScheme.onPrimary,
      appBarTheme:
          AppBarTheme(backgroundColor: solarizedDarkColorScheme.primary)
      // inputDecorationTheme: solarizedDarkInputDecorationsTheme,
      // elevatedButtonTheme: solarizedDarkElevatedButton);
      );
  ColorScheme solarizedLightColorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: SolarizedColors().base3,
      onPrimary: SolarizedColors().green,
      secondary: SolarizedColors().base3,
      onSecondary: SolarizedColors().base1,
      error: SolarizedColors().base3,
      onError: SolarizedColors().red,
      surface: SolarizedColors().base3,
      onSurface: SolarizedColors().base00,
      tertiary: SolarizedColors().base3,
      onTertiary: SolarizedColors().yellow);
  final solarizedLight = ThemeData(
    fontFamily: 'roboto-mono',
    colorScheme: solarizedLightColorScheme,
    textTheme: solarizedTextTheme,
    canvasColor: solarizedLightColorScheme.surface,
    scaffoldBackgroundColor: solarizedLightColorScheme.surface,
    highlightColor: Colors.transparent,
    focusColor: solarizedLightColorScheme.onPrimary,
    // inputDecorationTheme: solarizedDarkInputDecorationsTheme,
    // elevatedButtonTheme: solarizedDarkElevatedButton);
  );
  return (solarizedLight, solarizedDark);
}

class ThemeNotifier with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  void setTheme(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}
