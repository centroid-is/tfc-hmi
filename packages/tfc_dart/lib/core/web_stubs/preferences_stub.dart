/// Web stub for preferences.dart
/// On web, preferences use SharedPreferences (no Postgres/SecureStorage).

import 'dart:async';

class PreferencesException implements Exception {
  final String message;
  PreferencesException(this.message);
}

abstract class PreferencesApi {
  Future<Set<String>> getKeys({Set<String>? allowList});
  Future<Map<String, Object?>> getAll({Set<String>? allowList});
  Future<bool?> getBool(String key);
  Future<int?> getInt(String key);
  Future<double?> getDouble(String key);
  Future<String?> getString(String key);
  Future<List<String>?> getStringList(String key);
  Future<bool> containsKey(String key);
  Future<void> setBool(String key, bool value);
  Future<void> setInt(String key, int value);
  Future<void> setDouble(String key, double value);
  Future<void> setString(String key, String value);
  Future<void> setStringList(String key, List<String> value);
  Future<void> remove(String key);
  Future<void> clear({Set<String>? allowList});
}

class KeyCache {
  Set<String> keys = {};
  DateTime lastUpdated = DateTime.now().subtract(const Duration(days: 100));
  Future<void>? cacheUpdate;
}

class InMemoryPreferences implements PreferencesApi {
  final Map<String, Object> _cache = {};

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async {
    if (allowList == null) return _cache.keys.toSet();
    return _cache.keys.where((k) => allowList.contains(k)).toSet();
  }

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async {
    if (allowList == null) return Map.from(_cache);
    return Map.fromEntries(
        _cache.entries.where((e) => allowList.contains(e.key)));
  }

  @override
  Future<bool?> getBool(String key) async => _cache[key] as bool?;
  @override
  Future<int?> getInt(String key) async => _cache[key] as int?;
  @override
  Future<double?> getDouble(String key) async => _cache[key] as double?;
  @override
  Future<String?> getString(String key) async => _cache[key] as String?;
  @override
  Future<List<String>?> getStringList(String key) async =>
      _cache[key] as List<String>?;
  @override
  Future<bool> containsKey(String key) async => _cache.containsKey(key);
  @override
  Future<void> setBool(String key, bool value) async => _cache[key] = value;
  @override
  Future<void> setInt(String key, int value) async => _cache[key] = value;
  @override
  Future<void> setDouble(String key, double value) async => _cache[key] = value;
  @override
  Future<void> setString(String key, String value) async => _cache[key] = value;
  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _cache[key] = value;
  @override
  Future<void> remove(String key) async => _cache.remove(key);
  @override
  Future<void> clear({Set<String>? allowList}) async {
    if (allowList == null) {
      _cache.clear();
    } else {
      _cache.removeWhere((k, _) => allowList.contains(k));
    }
  }
}

class Preferences implements PreferencesApi {
  final dynamic database;
  final KeyCache keyCache = KeyCache();
  final InMemoryPreferences _memoryCache = InMemoryPreferences();
  final dynamic secureStorage;
  final PreferencesApi? localCache;
  final StreamController<String> _onPreferencesChanged =
      StreamController<String>.broadcast();

  Preferences(
      {required this.database,
      required this.secureStorage,
      this.localCache});

  static Future<Preferences> create(
      {required dynamic db, PreferencesApi? localCache}) async {
    throw UnsupportedError('Preferences.create not available on web');
  }

  Stream<String> get onPreferencesChanged => _onPreferencesChanged.stream;

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) =>
      _memoryCache.getKeys(allowList: allowList);
  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) =>
      _memoryCache.getAll(allowList: allowList);
  @override
  Future<bool?> getBool(String key) => _memoryCache.getBool(key);
  @override
  Future<int?> getInt(String key) => _memoryCache.getInt(key);
  @override
  Future<double?> getDouble(String key) => _memoryCache.getDouble(key);
  @override
  Future<String?> getString(String key) => _memoryCache.getString(key);
  @override
  Future<List<String>?> getStringList(String key) =>
      _memoryCache.getStringList(key);
  @override
  Future<bool> containsKey(String key) => _memoryCache.containsKey(key);
  @override
  Future<void> setBool(String key, bool value) =>
      _memoryCache.setBool(key, value);
  @override
  Future<void> setInt(String key, int value) =>
      _memoryCache.setInt(key, value);
  @override
  Future<void> setDouble(String key, double value) =>
      _memoryCache.setDouble(key, value);
  @override
  Future<void> setString(String key, String value) =>
      _memoryCache.setString(key, value);
  @override
  Future<void> setStringList(String key, List<String> value) =>
      _memoryCache.setStringList(key, value);
  @override
  Future<void> remove(String key) => _memoryCache.remove(key);
  @override
  Future<void> clear({Set<String>? allowList}) =>
      _memoryCache.clear(allowList: allowList);

  Future<bool> isKeyInDatabase(String key) async => false;
  Future<void> loadFromPostgres() async {}
}
