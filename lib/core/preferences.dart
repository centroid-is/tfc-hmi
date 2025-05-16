import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:json_annotation/json_annotation.dart';

part 'preferences.g.dart';

class PreferencesException implements Exception {
  final String message;
  PreferencesException(this.message);
}

class EndpointConverter
    implements JsonConverter<Endpoint, Map<String, dynamic>> {
  const EndpointConverter();

  @override
  Endpoint fromJson(Map<String, dynamic> json) {
    return Endpoint(
      host: json['host'] as String,
      port: json['port'] as int,
      database: json['database'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
      isUnixSocket: json['isUnixSocket'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson(Endpoint endpoint) => {
        'host': endpoint.host,
        'port': endpoint.port,
        'database': endpoint.database,
        'username': endpoint.username,
        'password': endpoint.password,
        'isUnixSocket': endpoint.isUnixSocket,
      };
}

class SslModeConverter implements JsonConverter<SslMode, String> {
  const SslModeConverter();

  @override
  SslMode fromJson(String json) {
    return SslMode.values.firstWhere(
      (mode) => mode.name == json,
      orElse: () => SslMode.disable,
    );
  }

  @override
  String toJson(SslMode mode) => mode.name;
}

@JsonSerializable()
class PreferencesConfig {
  @EndpointConverter()
  Endpoint? postgres;
  @SslModeConverter()
  SslMode? sslMode;

  PreferencesConfig({this.postgres, this.sslMode});

  factory PreferencesConfig.fromJson(Map<String, dynamic> json) =>
      _$PreferencesConfigFromJson(json);
  Map<String, dynamic> toJson() => _$PreferencesConfigToJson(this);
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

  /// Stream of preferences that have changed.
  ///
  /// The stream will emit the key of the preference that has changed.
  Stream<String> get onPreferencesChanged;
}

class Preferences implements PreferencesApi {
  final PreferencesConfig config;
  final Connection? connection;
  final SharedPreferencesAsync sharedPreferences = SharedPreferencesAsync();
  final StreamController<String> _onPreferencesChanged =
      StreamController<String>.broadcast();

  Preferences({required this.config, required this.connection});

  static Future<void> ensureTable(Connection connection) async {
    await connection.execute('''
      CREATE TABLE IF NOT EXISTS flutter_preferences (
        key TEXT PRIMARY KEY,
        value TEXT,
        type TEXT NOT NULL
      )
    ''');
  }

  static Future<Preferences> create({required PreferencesConfig config}) async {
    try {
      if (config.postgres == null) {
        return Preferences(config: config, connection: null);
      }
      final connection = await Connection.open(
        config.postgres!,
        settings: ConnectionSettings(sslMode: config.sslMode),
      ).onError((error, stackTrace) {
        throw PreferencesException(
          'Connection to Postgres failed: $error\n $stackTrace',
        );
      });
      await ensureTable(connection);
      final prefs = Preferences(config: config, connection: connection);
      await prefs.loadFromPostgres();
      return prefs;
    } on PreferencesException catch (e) {
      stderr.writeln(e.message);
      return Preferences(config: config, connection: null);
    }
  }

  bool get dbConnected => connection != null && connection!.isOpen;

  Future<void> _upsertToPostgres(String key, Object? value, String type) async {
    if (!dbConnected) return;
    final valStr = value is List<String> ? value.join(',') : value?.toString();
    await connection!.execute(
      Sql.named(
        'INSERT INTO flutter_preferences (key, value, type) VALUES (@key, @value, @type) '
        'ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, type = EXCLUDED.type',
      ),
      parameters: {'key': key, 'value': valStr, 'type': type},
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
  Future<bool?> getBool(String key) async {
    return await sharedPreferences.getBool(key);
  }

  @override
  Future<int?> getInt(String key) async {
    return await sharedPreferences.getInt(key);
  }

  @override
  Future<double?> getDouble(String key) async {
    return await sharedPreferences.getDouble(key);
  }

  @override
  Future<String?> getString(String key) async {
    return await sharedPreferences.getString(key);
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    return await sharedPreferences.getStringList(key);
  }

  @override
  Future<bool> containsKey(String key) async {
    return await sharedPreferences.containsKey(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await sharedPreferences.setBool(key, value);
    await _upsertToPostgres(key, value, 'bool');
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setInt(String key, int value) async {
    await sharedPreferences.setInt(key, value);
    await _upsertToPostgres(key, value, 'int');
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setDouble(String key, double value) async {
    await sharedPreferences.setDouble(key, value);
    await _upsertToPostgres(key, value, 'double');
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    await sharedPreferences.setString(key, value);
    await _upsertToPostgres(key, value, 'String');
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    await sharedPreferences.setStringList(key, value);
    await _upsertToPostgres(key, value, 'List<String>');
    _onPreferencesChanged.add(key);
  }

  @override
  Future<void> remove(String key) {
    sharedPreferences.remove(key);
    // TODO: remove from postgres
    _onPreferencesChanged.add(key);
    return Future.value();
  }

  @override
  Future<void> clear({Set<String>? allowList}) {
    return sharedPreferences.clear(allowList: allowList);
  }

  @override
  Stream<String> get onPreferencesChanged => _onPreferencesChanged.stream;

  /// Loads all preferences from Postgres into shared preferences.
  Future<void> loadFromPostgres() async {
    if (!dbConnected) return;
    final result = await connection!.execute(
      'SELECT key, value, type FROM flutter_preferences',
    );
    for (final row in result) {
      final key = row[0] as String;
      final value = row[1] as String?;
      final type = row[2] as String;
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
