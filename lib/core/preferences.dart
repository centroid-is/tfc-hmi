// Todo move local storage to file or sqlite, for now use shared preferences

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tfc_core/core/preferences.dart';

// / A wrapper around SharedPreferencesAsync that implements PreferencesApi
class SharedPreferencesWrapper implements PreferencesApi {
  final SharedPreferencesAsync _prefs;

  SharedPreferencesWrapper(this._prefs);

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) {
    return _prefs.getKeys(allowList: allowList);
  }

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) {
    return _prefs.getAll(allowList: allowList);
  }

  @override
  Future<bool?> getBool(String key) {
    return _prefs.getBool(key);
  }

  @override
  Future<int?> getInt(String key) {
    return _prefs.getInt(key);
  }

  @override
  Future<double?> getDouble(String key) {
    return _prefs.getDouble(key);
  }

  @override
  Future<String?> getString(String key) {
    return _prefs.getString(key);
  }

  @override
  Future<List<String>?> getStringList(String key) {
    return _prefs.getStringList(key);
  }

  @override
  Future<bool> containsKey(String key) {
    return _prefs.containsKey(key);
  }

  @override
  Future<void> setBool(String key, bool value) {
    return _prefs.setBool(key, value);
  }

  @override
  Future<void> setInt(String key, int value) {
    return _prefs.setInt(key, value);
  }

  @override
  Future<void> setDouble(String key, double value) {
    return _prefs.setDouble(key, value);
  }

  @override
  Future<void> setString(String key, String value) {
    return _prefs.setString(key, value);
  }

  @override
  Future<void> setStringList(String key, List<String> value) {
    return _prefs.setStringList(key, value);
  }

  @override
  Future<void> remove(String key) {
    return _prefs.remove(key);
  }

  @override
  Future<void> clear({Set<String>? allowList}) {
    return _prefs.clear(allowList: allowList);
  }
}
