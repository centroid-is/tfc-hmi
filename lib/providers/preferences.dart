import '../preferences/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod/riverpod.dart';
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'preferences.g.dart';

@Riverpod(keepAlive: true)
Future<Preferences> preferences(Ref ref) async {
  final prefs = SharedPreferencesAsync();

  // Try to load config from shared preferences
  var configJson = await prefs.getString('preferences_config');
  PreferencesConfig config;
  if (configJson == null) {
    // If not found, create default config
    config = PreferencesConfig(
        postgres: null); // Or provide a default Endpoint if needed
    configJson = jsonEncode(config.toJson());
    await prefs.setString('preferences_config', configJson);
  } else {
    config = PreferencesConfig.fromJson(jsonDecode(configJson));
  }

  // Create Preferences instance
  return await Preferences.create(config: config);
}
