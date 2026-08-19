import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

part 'theme.g.dart';

@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  static const String _key = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final String? themeName = prefs.getString(_key);
    return _themeStringToMode(themeName);
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = AsyncData(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  static ThemeMode _themeStringToMode(String? themeName) {
    switch (themeName) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

@riverpod
class ColorSchemeNotifier extends _$ColorSchemeNotifier {
  static const String _key = 'color_scheme';

  @override
  Future<AppColorScheme> build() async {
    final prefs = await SharedPreferences.getInstance();
    final String? name = prefs.getString(_key);
    return AppColorScheme.values.asNameMap()[name] ?? AppColorScheme.solarized;
  }

  Future<void> setScheme(AppColorScheme scheme) async {
    state = AsyncData(scheme);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, scheme.name);
  }
}
