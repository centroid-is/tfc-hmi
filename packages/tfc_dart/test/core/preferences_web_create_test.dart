// Test A: Verify that the web stub Preferences.create() returns a working
// instance instead of throwing UnsupportedError.
//
// Imports the web stub directly (not via conditional import) so this test
// exercises the web code path on any platform.
import 'package:test/test.dart';
import 'package:tfc_dart/core/web_stubs/preferences_stub.dart';

void main() {
  group('Web Preferences.create()', () {
    test('returns a working Preferences instance', () async {
      final prefs = await Preferences.create(db: null);
      expect(prefs, isA<Preferences>());
    });

    test('setString / getString roundtrips work', () async {
      final prefs = await Preferences.create(db: null);
      await prefs.setString('test_key', 'test_value');
      final value = await prefs.getString('test_key');
      expect(value, 'test_value');
    });

    test('setBool / getBool roundtrips work', () async {
      final prefs = await Preferences.create(db: null);
      await prefs.setBool('flag', true);
      expect(await prefs.getBool('flag'), isTrue);
    });

    test('onPreferencesChanged stream exists', () async {
      final prefs = await Preferences.create(db: null);
      expect(prefs.onPreferencesChanged, isA<Stream<String>>());
    });

    test('accepts a localCache parameter', () async {
      final localCache = InMemoryPreferences();
      await localCache.setString('cached_key', 'cached_value');

      final prefs =
          await Preferences.create(db: null, localCache: localCache);
      expect(prefs, isA<Preferences>());
    });
  });
}
