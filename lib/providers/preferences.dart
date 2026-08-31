import 'package:shared_preferences/shared_preferences.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/preferences.dart';
import '../core/startup_url.dart';
import 'database.dart';

part 'preferences.g.dart';

@Riverpod(keepAlive: true)
Future<Preferences> preferences(Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  final localCache = SharedPreferencesWrapper(SharedPreferencesAsync());

  final prefs = await Preferences.create(db: db, localCache: localCache);
  // A startup_url row in the shared database would overwrite every station's
  // local choice on each sync; delete it the moment it is seen. Runs on
  // every (re)connect because this provider is rebuilt then — idempotent.
  await migrateStartupUrlToDeviceLocal(shared: prefs, local: localCache);
  return prefs;
}

/// Device-local preferences that never touch the shared database.
///
/// Use this for per-station settings (e.g. the MCP server config) that
/// must not be shared between HMI instances pointed at the same Postgres.
final localPreferencesProvider = Provider<PreferencesApi>(
  (ref) => SharedPreferencesWrapper(SharedPreferencesAsync()),
);
