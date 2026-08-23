import 'package:test/test.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/interface.dart';

/// A local cache that records every write.
///
/// The real one is `shared_preferences`. On Windows its `_setValue` re-encodes
/// the whole preference map and rewrites the entire file with
/// `writeAsStringSync` **per call** — measured at 35.5 ms for four keys
/// against a 754,707-byte file on a Mac NVMe, on the UI isolate, on every
/// startup and every database reconnect. Plant hardware is slower. So what
/// this test cares about is not the resulting values but the number of writes.
class _RecordingPrefs implements PreferencesApi {
  final Map<String, Object> _store = {};
  final List<String> writes = [];
  int getAllCalls = 0;

  _RecordingPrefs([Map<String, Object>? initial]) {
    if (initial != null) _store.addAll(initial);
  }

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      _store.keys.toSet();

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async {
    getAllCalls++;
    return Map.of(_store);
  }

  @override
  Future<bool?> getBool(String key) async => _store[key] as bool?;
  @override
  Future<int?> getInt(String key) async => _store[key] as int?;
  @override
  Future<double?> getDouble(String key) async => _store[key] as double?;
  @override
  Future<String?> getString(String key) async => _store[key] as String?;
  @override
  Future<List<String>?> getStringList(String key) async =>
      _store[key] as List<String>?;
  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  /// Puts a value on "disk" without counting as a write.
  ///
  /// Stands in for the divergence the sync exists to close: `loadFromPostgres`
  /// fills the *memory* cache only, so after it the two can differ. Going
  /// through [setString] and friends would write both sides and leave nothing
  /// to sync.
  void seed(String key, Object value) => _store[key] = value;

  void evict(String key) => _store.remove(key);

  void _write(String key, Object value) {
    writes.add(key);
    _store[key] = value;
  }

  @override
  Future<void> setBool(String key, bool value) async => _write(key, value);
  @override
  Future<void> setInt(String key, int value) async => _write(key, value);
  @override
  Future<void> setDouble(String key, double value) async => _write(key, value);
  @override
  Future<void> setString(String key, String value) async => _write(key, value);
  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _write(key, value);

  @override
  Future<void> remove(String key) async {
    writes.add(key);
    _store.remove(key);
  }

  @override
  Future<void> clear({Set<String>? allowList}) async => _store.clear();
}

class _NoSecrets implements MySecureStorage {
  @override
  Future<void> delete({required String key}) async {}
  @override
  Future<String?> read({required String key}) async => null;
  @override
  Future<void> write({required String key, required String value}) async {}
}

Preferences _prefsWith(PreferencesApi localCache) => Preferences(
      database: null,
      secureStorage: _NoSecrets(),
      localCache: localCache,
    );

void main() {
  setUp(Preferences.clearSecretCache);

  group('syncToLocalCache', () {
    test('writes nothing when every value already matches', () async {
      // The normal restart: Postgres hands back exactly what the last session
      // already wrote to disk. Nothing has changed, so nothing should be
      // rewritten.
      final cache = _RecordingPrefs({
        'a_string': 'hello',
        'an_int': 7,
        'a_double': 1.5,
        'a_bool': true,
        'a_list': <String>['x', 'y'],
      });
      final prefs = _prefsWith(cache);
      await prefs.setString('a_string', 'hello');
      await prefs.setInt('an_int', 7);
      await prefs.setDouble('a_double', 1.5);
      await prefs.setBool('a_bool', true);
      await prefs.setStringList('a_list', ['x', 'y']);
      cache.writes.clear();

      await prefs.syncToLocalCache();

      expect(cache.writes, isEmpty);
    });

    test('writes only the keys whose value actually changed', () async {
      final cache = _RecordingPrefs();
      final prefs = _prefsWith(cache);
      await prefs.setString('unchanged', 'same');
      await prefs.setString('changed', 'new');
      await prefs.setStringList('changed_list', ['a', 'b']);
      // Another station edited these two since this one last synced.
      cache.seed('changed', 'old');
      cache.seed('changed_list', <String>['a']);
      cache.writes.clear();

      await prefs.syncToLocalCache();

      expect(cache.writes..sort(), ['changed', 'changed_list']);
      expect(await cache.getString('changed'), 'new');
      expect(await cache.getStringList('changed_list'), ['a', 'b']);
      expect(await cache.getString('unchanged'), 'same');
    });

    test('writes keys the local cache has never seen', () async {
      final cache = _RecordingPrefs();
      final prefs = _prefsWith(cache);
      await prefs.setString('brand_new', 'v');
      cache.evict('brand_new');
      cache.writes.clear();

      await prefs.syncToLocalCache();

      expect(cache.writes, ['brand_new']);
      expect(await cache.getString('brand_new'), 'v');
    });

    test('a type change counts as a change', () async {
      // '7' and 7 are different values even though they stringify the same.
      final cache = _RecordingPrefs();
      final prefs = _prefsWith(cache);
      await prefs.setInt('k', 7);
      cache.seed('k', '7');
      cache.writes.clear();

      await prefs.syncToLocalCache();

      expect(cache.writes, ['k']);
      expect(await cache.getInt('k'), 7);
    });

    test('reads the local cache once, not once per key', () async {
      final cache = _RecordingPrefs({for (var i = 0; i < 20; i++) 'k$i': i});
      final prefs = _prefsWith(cache);
      for (var i = 0; i < 20; i++) {
        await prefs.setInt('k$i', i);
      }
      cache.getAllCalls = 0;

      await prefs.syncToLocalCache();

      expect(cache.getAllCalls, 1);
    });

    test('leaves device-local keys the database does not know about alone',
        () async {
      // localPreferencesProvider stores per-station settings in the *same*
      // SharedPreferences store. The sync is additive on purpose: pruning
      // keys that Postgres has never heard of would wipe them.
      final cache = _RecordingPrefs({
        'device_only': 'keep me',
        'shared': 'v',
      });
      final prefs = _prefsWith(cache);
      await prefs.setString('shared', 'v');
      cache.writes.clear();

      await prefs.syncToLocalCache();

      expect(cache.writes, isEmpty);
      expect(await cache.getString('device_only'), 'keep me');
    });
  });
}
