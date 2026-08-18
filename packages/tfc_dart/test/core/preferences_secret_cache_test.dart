import 'package:test/test.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/interface.dart';

/// In-memory secure storage that counts every backend access, standing in
/// for the OS keychain so the tests can assert how often it gets hit.
class CountingSecureStorage implements MySecureStorage {
  final Map<String, String> store = {};
  int reads = 0;
  int writes = 0;
  int deletes = 0;

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    reads++;
    return store[key];
  }

  @override
  Future<void> delete({required String key}) async {
    deletes++;
    store.remove(key);
  }
}

/// Storage whose first read throws (transient keychain error) and then
/// recovers.
class ThrowingThenWorkingSecureStorage extends CountingSecureStorage {
  bool _thrown = false;

  @override
  Future<String?> read({required String key}) async {
    if (!_thrown) {
      _thrown = true;
      throw Exception('transient keychain error');
    }
    return super.read(key: key);
  }
}

void main() {
  late CountingSecureStorage storage;
  late Preferences prefs;

  setUp(() {
    // The secret cache is static (process-wide) — clear it so each test
    // starts from a cold cache against its own fresh storage.
    Preferences.clearSecretCache();
    storage = CountingSecureStorage();
    prefs = Preferences(database: null, secureStorage: storage);
  });

  group('Preferences secret cache', () {
    test('repeated reads hit the keychain at most once per key', () async {
      storage.store['secret_key'] = 'hunter2';

      expect(await prefs.getString('secret_key', secret: true), 'hunter2');
      expect(await prefs.getString('secret_key', secret: true), 'hunter2');
      expect(await prefs.getString('secret_key', secret: true), 'hunter2');

      expect(storage.reads, 1);
    });

    test('missing keys are negatively cached', () async {
      expect(await prefs.getString('absent', secret: true), isNull);
      expect(await prefs.getString('absent', secret: true), isNull);

      expect(storage.reads, 1);
    });

    test('overlapping first reads of one key share a single keychain hit',
        () async {
      storage.store['secret_key'] = 'hunter2';

      // Start both reads before either resolves — the startup provider
      // chain does exactly this — and assert they were deduplicated.
      final results = await Future.wait([
        prefs.getString('secret_key', secret: true),
        prefs.getString('secret_key', secret: true),
      ]);

      expect(results, ['hunter2', 'hunter2']);
      expect(storage.reads, 1);
    });

    test('a failed read is not cached — the next read retries the keychain',
        () async {
      final flaky = ThrowingThenWorkingSecureStorage();
      flaky.store['secret_key'] = 'hunter2';
      final p = Preferences(database: null, secureStorage: flaky);

      // First read: transient keychain error. It must propagate — turning
      // it into null would let callers persist default configs over real
      // data — and it must not poison the cache.
      await expectLater(
          p.getString('secret_key', secret: true), throwsException);

      // Second read: the keychain recovered; the value comes through.
      expect(await p.getString('secret_key', secret: true), 'hunter2');
    });

    test('writes go through to storage and populate the cache', () async {
      await prefs.setString('secret_key', 'swordfish', secret: true);

      expect(storage.store['secret_key'], 'swordfish');
      expect(await prefs.getString('secret_key', secret: true), 'swordfish');
      // The read after the write must be served from the cache.
      expect(storage.reads, 0);
    });

    test('a write updates a previously cached value', () async {
      storage.store['secret_key'] = 'old';
      expect(await prefs.getString('secret_key', secret: true), 'old');

      await prefs.setString('secret_key', 'new', secret: true);
      expect(await prefs.getString('secret_key', secret: true), 'new');
      expect(storage.reads, 1); // only the initial cold read
    });

    test('remove deletes from storage and evicts the cache entry', () async {
      storage.store['secret_key'] = 'hunter2';
      expect(await prefs.getString('secret_key', secret: true), 'hunter2');

      await prefs.remove('secret_key', secret: true);
      expect(storage.deletes, 1);
      expect(storage.store.containsKey('secret_key'), isFalse);

      // Evicted: the next read goes back to storage and finds nothing.
      expect(await prefs.getString('secret_key', secret: true), isNull);
      expect(storage.reads, 2);
    });

    test(
        'cache survives Preferences re-creation (per process, not per '
        'instance)', () async {
      storage.store['secret_key'] = 'hunter2';
      expect(await prefs.getString('secret_key', secret: true), 'hunter2');

      // The riverpod provider chain re-creates Preferences on rebuild; the
      // cache must keep the keychain from being re-read by the new instance.
      final prefs2 = Preferences(database: null, secureStorage: storage);
      expect(await prefs2.getString('secret_key', secret: true), 'hunter2');
      expect(storage.reads, 1);
    });

    test('typed secret getters round-trip through the cache', () async {
      await prefs.setBool('b', true, secret: true);
      await prefs.setInt('i', 42, secret: true);
      await prefs.setDouble('d', 2.5, secret: true);
      await prefs.setStringList('l', ['a', 'b'], secret: true);

      expect(await prefs.getBool('b', secret: true), isTrue);
      expect(await prefs.getInt('i', secret: true), 42);
      expect(await prefs.getDouble('d', secret: true), 2.5);
      expect(await prefs.getStringList('l', secret: true), ['a', 'b']);
      expect(storage.reads, 0);
      expect(storage.writes, 4);
    });
  });
}
