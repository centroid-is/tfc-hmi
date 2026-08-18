import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/secure_storage/macos.dart';
import 'package:tfc_dart/core/secure_storage/interface.dart';

/// In-memory secure storage whose keychain calls can be made to fail the way
/// flutter_secure_storage does on a sandboxed build without the
/// keychain-access-groups entitlement: PlatformException(-34018).
class FakeStorage implements MySecureStorage {
  FakeStorage({this.throwOnAccess = false});

  /// When true every call throws, mimicking a build without entitlements.
  bool throwOnAccess;

  /// When true only [write] throws (partial-failure shape).
  bool throwOnWrite = false;

  /// When true only [delete] throws (partial-failure shape).
  bool throwOnDelete = false;

  final Map<String, String> store = {};
  int reads = 0;
  int writes = 0;
  int deletes = 0;

  void _maybeThrow() {
    if (throwOnAccess) {
      throw PlatformException(
          code: '-34018', message: "A required entitlement isn't present");
    }
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    _maybeThrow();
    if (throwOnWrite) {
      throw PlatformException(
          code: '-34018', message: "A required entitlement isn't present");
    }
    store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    reads++;
    _maybeThrow();
    return store[key];
  }

  @override
  Future<void> delete({required String key}) async {
    deletes++;
    _maybeThrow();
    if (throwOnDelete) {
      throw PlatformException(
          code: '-34018', message: "A required entitlement isn't present");
    }
    store.remove(key);
  }
}

void main() {
  late FakeStorage newStorage;
  late FakeStorage legacy;
  late MacOsMigratingSecureStorage storage;

  setUp(() {
    newStorage = FakeStorage();
    legacy = FakeStorage();
    storage = MacOsMigratingSecureStorage(
        newStorage: newStorage, legacyStorage: legacy);
  });

  group('MacOsMigratingSecureStorage migration', () {
    test('reads present in the new storage never touch legacy', () async {
      newStorage.store['k'] = 'new-value';
      expect(await storage.read(key: 'k'), 'new-value');
      expect(legacy.reads, 0);
    });

    test('read miss falls back to legacy and copies the value over', () async {
      legacy.store['k'] = 'legacy-value';

      expect(await storage.read(key: 'k'), 'legacy-value');
      // Migrated: the value now lives in the new storage too...
      expect(newStorage.store['k'], 'legacy-value');

      // ...so the next read is served without consulting legacy again.
      expect(await storage.read(key: 'k'), 'legacy-value');
      expect(legacy.reads, 1);

      // Copy-forward completes the migration for this key: the legacy
      // entry is removed so it cannot go stale or duplicate the secret.
      expect(legacy.store.containsKey('k'), isFalse);
      expect(legacy.deletes, 1);
    });

    test('read of a key absent everywhere returns null', () async {
      expect(await storage.read(key: 'nope'), isNull);
    });

    test('writes go to the new storage only', () async {
      await storage.write(key: 'k', value: 'v');
      expect(newStorage.store['k'], 'v');
      expect(legacy.writes, 0);
    });

    test('delete removes both copies so legacy cannot resurrect the key',
        () async {
      newStorage.store['k'] = 'v';
      legacy.store['k'] = 'old-v';

      await storage.delete(key: 'k');
      expect(newStorage.store.containsKey('k'), isFalse);
      expect(legacy.store.containsKey('k'), isFalse);
      expect(await storage.read(key: 'k'), isNull);
    });
  });

  group('MacOsMigratingSecureStorage without keychain entitlements', () {
    // Mimics PlatformException(-34018) from every new-storage call.
    setUp(() => newStorage.throwOnAccess = true);

    test('read is served from legacy instead of throwing', () async {
      legacy.store['k'] = 'legacy-value';
      expect(await storage.read(key: 'k'), 'legacy-value');
    });

    test('read of an absent key returns null instead of throwing', () async {
      expect(await storage.read(key: 'k'), isNull);
    });

    test('write lands in legacy instead of throwing', () async {
      await storage.write(key: 'k', value: 'v');
      expect(legacy.store['k'], 'v');
      expect(newStorage.store.containsKey('k'), isFalse);

      // And the round trip works.
      expect(await storage.read(key: 'k'), 'v');
    });

    test('delete still removes the legacy copy instead of throwing', () async {
      legacy.store['k'] = 'v';
      await storage.delete(key: 'k');
      expect(legacy.store.containsKey('k'), isFalse);
    });

    test(
        'migration read still returns the legacy value when the copy-over '
        'write fails', () async {
      // New storage read succeeds but returns null; only the copy-over
      // write fails. The caller must still get the legacy value instead of
      // null (which would silently regenerate default configs).
      final flaky = FakeStorage()..throwOnWrite = true;
      final s =
          MacOsMigratingSecureStorage(newStorage: flaky, legacyStorage: legacy);
      legacy.store['k'] = 'legacy-value';

      expect(await s.read(key: 'k'), 'legacy-value');
      expect(flaky.writes, 1); // the copy-over was attempted...
      expect(flaky.store.containsKey('k'), isFalse); // ...and failed
      // The legacy entry stays: it is still the only copy of the value.
      expect(legacy.store['k'], 'legacy-value');
    });
  });

  group('MacOsMigratingSecureStorage error semantics', () {
    // A storage error must never read as "key absent": callers like
    // StateManConfig.fromPrefs persist a default config over a null read,
    // which would overwrite real data.

    test('read miss with an erroring legacy storage is treated as absent',
        () async {
      // A broken amplify store means the pre-migration app could not read
      // this machine's secrets either — there is no working configuration
      // to protect, and a fresh install must not break over a store it
      // never wrote to. (Errors from the *operative* storage still
      // propagate — see the tests below.)
      legacy.throwOnAccess = true;
      expect(await storage.read(key: 'k'), isNull);
    });

    test('read throws when both storages error', () async {
      newStorage.throwOnAccess = true;
      legacy.throwOnAccess = true;
      expect(storage.read(key: 'k'), throwsA(isA<PlatformException>()));
    });

    test('write throws when both storages error', () async {
      newStorage.throwOnAccess = true;
      legacy.throwOnAccess = true;
      expect(storage.write(key: 'k', value: 'v'),
          throwsA(isA<PlatformException>()));
    });

    test(
        'delete throws when the new storage refuses the delete but still '
        'serves reads — a swallowed error would resurrect the value', () async {
      newStorage.store['k'] = 'v';
      newStorage.throwOnDelete = true;
      await expectLater(
          storage.delete(key: 'k'), throwsA(isA<PlatformException>()));
      // The legacy copy was still cleaned up on the way through.
      expect(legacy.store.containsKey('k'), isFalse);
    });

    test('delete swallows legacy failure', () async {
      legacy.throwOnAccess = true;
      newStorage.store['k'] = 'v';
      await storage.delete(key: 'k');
      expect(newStorage.store.containsKey('k'), isFalse);
    });
  });
}
