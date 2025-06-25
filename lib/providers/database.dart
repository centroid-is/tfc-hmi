import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../core/database.dart';

part 'database.g.dart';

Future<DatabaseConfig> readDatabaseConfig() async {
  final prefs = SharedPreferencesAsync();
  var configJson = await prefs.getString(Database.configLocation);
  DatabaseConfig config;
  if (configJson == null) {
    // If not found, create default config
    config = DatabaseConfig(
        postgres: null); // Or provide a default Endpoint if needed
    configJson = jsonEncode(config.toJson());
    await prefs.setString(Database.configLocation, configJson);
  } else {
    config = DatabaseConfig.fromJson(jsonDecode(configJson));
  }
  return config;
}

@Riverpod(keepAlive: true)
Future<Database?> database(Ref ref) async {
  final config = await readDatabaseConfig();
  if (config.postgres == null) {
    return null;
  }
  final db = Database(config);
  try {
    await db.connect();
    return db;
  } catch (error, stackTrace) {
    Logger().e('Connection to Postgres failed: $error\n $stackTrace');
    return null;
  }
}
