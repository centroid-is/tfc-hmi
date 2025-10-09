import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Variable;

import 'database.dart';
import 'secure_storage/secure_storage.dart';

class PreferencesException implements Exception {
  final String message;
  PreferencesException(this.message);
}

abstract class PreferencesApi {
  /// Returns all keys on the the platform that match provided [parameters].
  ///
  /// If no restrictions are provided, fetches all keys stored on the platform.
  ///
  /// Ignores any keys whose values are types which are incompatible with shared_preferences.
  Future<Set<String>> getKeys({Set<String>? allowList});

  /// Returns all keys and values on the the platform that match provided [parameters].
  ///
  /// If no restrictions are provided, fetches all entries stored on the platform.
  ///
  /// Ignores any entries of types which are incompatible with shared_preferences.
  Future<Map<String, Object?>> getAll({Set<String>? allowList});

  /// Reads a value from the platform, throwing a [TypeError] if the value is
  /// not a bool.
  Future<bool?> getBool(String key);

  /// Reads a value from the platform, throwing a [TypeError] if the value is
  /// not an int.
  Future<int?> getInt(String key);

  /// Reads a value from the platform, throwing a [TypeError] if the value is
  /// not a double.
  Future<double?> getDouble(String key);

  /// Reads a value from the platform, throwing a [TypeError] if the value is
  /// not a String.
  Future<String?> getString(String key);

  /// Reads a list of string values from the platform, throwing a [TypeError]
  /// if the value not a List<String>.
  Future<List<String>?> getStringList(String key);

  /// Returns true if the the platform contains the given [key].
  Future<bool> containsKey(String key);

  /// Saves a boolean [value] to the platform.
  Future<void> setBool(String key, bool value);

  /// Saves an integer [value] to the platform.
  Future<void> setInt(String key, int value);

  /// Saves a double [value] to the platform.
  ///
  /// On platforms that do not support storing doubles,
  /// the value will be stored as a float.
  Future<void> setDouble(String key, double value);

  /// Saves a string [value] to the platform.
  ///
  /// Some platforms have special values that cannot be stored, please refer to
  /// the README for more information.
  Future<void> setString(String key, String value);

  /// Saves a list of strings [value] to the platform.
  Future<void> setStringList(String key, List<String> value);

  /// Removes an entry from the platform.
  Future<void> remove(String key);

  /// Clears all preferences from the platform.
  ///
  /// If no [parameters] are provided, and [SharedPreferencesAsync] has no filter,
  /// all preferences will be removed. This may include values not set by this instance,
  /// such as those stored by native code or by other packages using
  /// shared_preferences internally, which may cause unintended side effects.
  ///
  /// It is highly recommended that an [allowList] be provided to this call.
  Future<void> clear({Set<String>? allowList});
}

class KeyCache {
  Set<String> keys = {};
  DateTime lastUpdated = DateTime.now().subtract(const Duration(days: 100));
  Future<void>? cacheUpdate;
}

class Preferences implements PreferencesApi {
  final Database? database;
  final KeyCache keyCache = KeyCache();
  final SharedPreferencesAsync sharedPreferences = SharedPreferencesAsync();
  final MySecureStorage secureStorage;
  final StreamController<String> _onPreferencesChanged =
      StreamController<String>.broadcast();

  Preferences({required this.database, required this.secureStorage});

  static Future<Preferences> create({required Database? db}) async {
    final secureStorage = SecureStorage.getInstance();
    try {
      if (db == null) {
        return Preferences(database: null, secureStorage: secureStorage);
      }
      final prefs = Preferences(database: db, secureStorage: secureStorage);
      await prefs.loadFromPostgres();
      return prefs;
    } on PreferencesException catch (e) {
      stderr.writeln(e.message);
      return Preferences(database: db, secureStorage: secureStorage);
    }
  }

  Future<void> _upsertToPostgres(String key, Object? value, String type) async {
    final valStr = value is List<String> ? value.join(',') : value?.toString();
    if (database == null) {
      throw Exception('Database is not configured or connected');
    }
    final db = database!.db;
    // TODO: track changes, like have a timestamp and then we can revert to the previous value if we want
    // then we can do a insert with primary key as timestamp
    // and use drift instead of custom insert
    await db.customInsert(
      r'''INSERT INTO flutter_preferences (key, value, type) VALUES ($1, $2, $3) 
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, type = EXCLUDED.type''',
      variables: [
        Variable.withString(key),
        Variable.withString(valStr ?? ''),
        Variable.withString(type),
      ],
    );
  }

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async {
    return await sharedPreferences.getKeys(allowList: allowList);
  }

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async {
    return await sharedPreferences.getAll(allowList: allowList);
  }

  @override
  Future<bool?> getBool(String key, {bool secret = false}) async {
    if (secret) {
      final value = await secureStorage.read(key: key);
      return value == null ? null : value == 'true';
    } else {
      return await sharedPreferences.getBool(key);
    }
  }

  @override
  Future<int?> getInt(String key, {bool secret = false}) async {
    if (secret) {
      final value = await secureStorage.read(key: key);
      return value == null ? null : int.parse(value);
    } else {
      return await sharedPreferences.getInt(key);
    }
  }

  @override
  Future<double?> getDouble(String key, {bool secret = false}) async {
    if (secret) {
      final value = await secureStorage.read(key: key);
      return value == null ? null : double.parse(value);
    } else {
      return await sharedPreferences.getDouble(key);
    }
  }

  @override
  Future<String?> getString(String key, {bool secret = false}) async {
    if (secret) {
      return await secureStorage.read(key: key);
    } else {
      return await sharedPreferences.getString(key);
    }
  }

  @override
  Future<List<String>?> getStringList(String key, {bool secret = false}) async {
    if (secret) {
      final value = await secureStorage.read(key: key);
      return value?.split(',');
    } else {
      return await sharedPreferences.getStringList(key);
    }
  }

  @override
  Future<bool> containsKey(String key, {bool secret = false}) async {
    if (secret) {
      throw UnimplementedError(
          'containsKey is not implemented for secret storage');
    } else {
      return await sharedPreferences.containsKey(key);
    }
  }

  @override
  Future<void> setBool(String key, bool value,
      {bool saveToDb = true, bool secret = false}) async {
    if (secret) {
      await secureStorage.write(key: key, value: value.toString());
    } else {
      await sharedPreferences.setBool(key, value);
    }
    if (saveToDb) {
      await _upsertToPostgres(key, value, 'bool');
    }
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setInt(String key, int value,
      {bool saveToDb = true, bool secret = false}) async {
    if (secret) {
      await secureStorage.write(key: key, value: value.toString());
    } else {
      await sharedPreferences.setInt(key, value);
    }
    if (saveToDb) {
      await _upsertToPostgres(key, value, 'int');
    }
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setDouble(String key, double value,
      {bool saveToDb = true, bool secret = false}) async {
    if (secret) {
      await secureStorage.write(key: key, value: value.toString());
    } else {
      await sharedPreferences.setDouble(key, value);
    }
    if (saveToDb) {
      await _upsertToPostgres(key, value, 'double');
    }
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setString(String key, String value,
      {bool saveToDb = true, bool secret = false}) async {
    if (secret) {
      await secureStorage.write(key: key, value: value);
    } else {
      await sharedPreferences.setString(key, value);
    }
    if (saveToDb) {
      await _upsertToPostgres(key, value, 'String');
    }
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setStringList(String key, List<String> value,
      {bool saveToDb = true, bool secret = false}) async {
    if (secret) {
      await secureStorage.write(key: key, value: value.join(','));
    } else {
      await sharedPreferences.setStringList(key, value);
    }
    if (saveToDb) {
      await _upsertToPostgres(key, value, 'List<String>');
    }
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> remove(String key, {bool secret = false}) {
    if (secret) {
      secureStorage.delete(key: key);
    } else {
      sharedPreferences.remove(key);
    }
    // TODO: remove from postgres
    _onPreferencesChanged.add(key);
    return Future.value();
  }

  @override
  Future<void> clear({Set<String>? allowList}) {
    return sharedPreferences.clear(allowList: allowList);
  }

  Stream<String> get onPreferencesChanged => _onPreferencesChanged.stream;

  Future<bool> isKeyInDatabase(String key) async {
    if (keyCache.lastUpdated
        .isBefore(DateTime.now().subtract(const Duration(minutes: 10)))) {
      if (keyCache.cacheUpdate != null) {
        await keyCache.cacheUpdate!;
      } else {
        // Start the update
        keyCache.cacheUpdate = _updateCache();
        await keyCache.cacheUpdate!;
        keyCache.cacheUpdate = null;
      }
    }
    return keyCache.keys.contains(key);
  }

  Future<void> _updateCache() async {
    if (database == null) {
      return;
    }
    final db = database!.db;
    final select = db.selectOnly(db.flutterPreferences)
      ..addColumns([db.flutterPreferences.key]);
    final result = await select.get();
    keyCache.keys = result
        .map((e) => e.read(db.flutterPreferences.key))
        .whereType<String>()
        .toSet();
    keyCache.lastUpdated = DateTime.now();
  }

  /// Loads all preferences from Postgres into shared preferences.
  Future<void> loadFromPostgres() async {
    final db = database!.db;
    final result = await db.select(db.flutterPreferences).get();
    for (final row in result) {
      final key = row.key;
      final value = row.value;
      final type = row.type;
      switch (type) {
        case 'bool':
          if (value != null) {
            await sharedPreferences.setBool(key, value == 'true');
          }
          break;
        case 'int':
          if (value != null) {
            await sharedPreferences.setInt(key, int.parse(value));
          }
          break;
        case 'double':
          if (value != null) {
            await sharedPreferences.setDouble(key, double.parse(value));
          }
          break;
        case 'String':
          if (value != null) {
            await sharedPreferences.setString(key, value);
          }
          break;
        case 'List<String>':
          if (value != null) {
            await sharedPreferences.setStringList(key, value.split(','));
          }
          break;
        default:
          throw Exception('Unsupported type: $type');
      }
    }
  }
}

/// A wrapper around SharedPreferencesAsync that implements PreferencesApi
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
