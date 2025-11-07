import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Simple file-based preferences implementation for pure Dart.
/// Replaces SharedPreferencesAsync for headless/server usage.
class FilePreferences {
  final File _file;
  Map<String, Object?> _cache = {};
  bool _loaded = false;

  FilePreferences._(this._file);

  /// Creates a FilePreferences instance.
  /// By default stores preferences in ~/.config/tfc/preferences.json
  /// or /etc/tfc/preferences.json if running as root/system service.
  static Future<FilePreferences> getInstance({String? path}) async {
    final file = File(path ?? _defaultPath());
    final prefs = FilePreferences._(file);
    await prefs._load();
    return prefs;
  }

  static String _defaultPath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return '$home/.config/tfc/preferences.json';
    }
    // Fallback for system services
    return '/etc/tfc/preferences.json';
  }

  Future<void> _load() async {
    if (_loaded) return;

    try {
      if (await _file.exists()) {
        final contents = await _file.readAsString();
        _cache = json.decode(contents) as Map<String, Object?>;
      } else {
        // Create directory if it doesn't exist
        await _file.parent.create(recursive: true);
        _cache = {};
      }
      _loaded = true;
    } catch (e) {
      stderr.writeln('Failed to load preferences from ${_file.path}: $e');
      _cache = {};
      _loaded = true;
    }
  }

  Future<void> _save() async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(json.encode(_cache));
    } catch (e) {
      stderr.writeln('Failed to save preferences to ${_file.path}: $e');
    }
  }

  Future<Set<String>> getKeys({Set<String>? allowList}) async {
    await _load();
    if (allowList == null) {
      return _cache.keys.toSet();
    }
    return _cache.keys.where((key) => allowList.contains(key)).toSet();
  }

  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async {
    await _load();
    if (allowList == null) {
      return Map.from(_cache);
    }
    return Map.fromEntries(
      _cache.entries.where((e) => allowList.contains(e.key)),
    );
  }

  Future<bool?> getBool(String key) async {
    await _load();
    final value = _cache[key];
    return value is bool ? value : null;
  }

  Future<int?> getInt(String key) async {
    await _load();
    final value = _cache[key];
    return value is int ? value : null;
  }

  Future<double?> getDouble(String key) async {
    await _load();
    final value = _cache[key];
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  Future<String?> getString(String key) async {
    await _load();
    final value = _cache[key];
    return value is String ? value : null;
  }

  Future<List<String>?> getStringList(String key) async {
    await _load();
    final value = _cache[key];
    if (value is List) {
      return value.cast<String>();
    }
    return null;
  }

  Future<bool> containsKey(String key) async {
    await _load();
    return _cache.containsKey(key);
  }

  Future<void> setBool(String key, bool value) async {
    await _load();
    _cache[key] = value;
    await _save();
  }

  Future<void> setInt(String key, int value) async {
    await _load();
    _cache[key] = value;
    await _save();
  }

  Future<void> setDouble(String key, double value) async {
    await _load();
    _cache[key] = value;
    await _save();
  }

  Future<void> setString(String key, String value) async {
    await _load();
    _cache[key] = value;
    await _save();
  }

  Future<void> setStringList(String key, List<String> value) async {
    await _load();
    _cache[key] = value;
    await _save();
  }

  Future<void> remove(String key) async {
    await _load();
    _cache.remove(key);
    await _save();
  }

  Future<void> clear({Set<String>? allowList}) async {
    await _load();
    if (allowList == null) {
      _cache.clear();
    } else {
      _cache.removeWhere((key, _) => allowList.contains(key));
    }
    await _save();
  }
}
