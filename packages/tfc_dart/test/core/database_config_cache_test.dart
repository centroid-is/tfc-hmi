import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';

/// Counting in-memory stand-in for the OS keychain.
class CountingSecureStorage implements MySecureStorage {
  final Map<String, String> store = {};
  int reads = 0;

  @override
  Future<void> write({required String key, required String value}) async {
    store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    reads++;
    return store[key];
  }

  @override
  Future<void> delete({required String key}) async {
    store.remove(key);
  }
}

void main() {
  late CountingSecureStorage storage;

  setUp(() {
    storage = CountingSecureStorage();
    SecureStorage.setInstance(storage);
    DatabaseConfig.clearPrefsCache();
  });

  group('DatabaseConfig prefs cache', () {
    test('fromPrefs hits the keychain once, not once per provider rebuild',
        () async {
      // databaseProvider re-runs fromPrefs every 2 s while the database is
      // unreachable — each run must not be a fresh keychain hit for the
      // postgres password.
      await DatabaseConfig.fromPrefs();
      await DatabaseConfig.fromPrefs();
      await DatabaseConfig.fromPrefs();
      expect(storage.reads, 1);
    });

    test('overlapping first reads share a single keychain hit', () async {
      await Future.wait([
        DatabaseConfig.fromPrefs(),
        DatabaseConfig.fromPrefs(),
      ]);
      expect(storage.reads, 1);
    });

    test('toPrefs writes through the cache', () async {
      await DatabaseConfig.fromPrefs();
      final updated = DatabaseConfig(postgres: null, debug: true);
      await updated.toPrefs();

      final roundTripped = await DatabaseConfig.fromPrefs();
      expect(roundTripped.debug, isTrue);
      // Still only the original cold read — the write refreshed the cache.
      expect(storage.reads, 1);
    });
  });
}
