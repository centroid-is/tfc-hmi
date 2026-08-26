/// The startup-URL preference: device-local, defaulting to '/', and cleared
/// (not stored) when reset so a reset station looks like a fresh install.
/// A stray row in the shared database is deleted on sight, because the
/// db→local sync would otherwise overwrite the station's choice every boot.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/preferences.dart';

import 'package:tfc/core/startup_url.dart';

/// Mimics the database-backed `Preferences`, whose `remove()` also erases
/// the key from its local-cache mirror — the same physical store the
/// device-local preferences live in.
class _MirroringPrefs extends InMemoryPreferences {
  final PreferencesApi mirror;
  _MirroringPrefs(this.mirror);

  @override
  Future<void> remove(String key) async {
    await super.remove(key);
    await mirror.remove(key);
  }
}

void main() {
  test('unset reads as the default', () async {
    final prefs = InMemoryPreferences();
    expect(await readStartupUrl(prefs), startupUrlDefault);
  });

  test('a stored URL reads back', () async {
    final prefs = InMemoryPreferences();
    await writeStartupUrl(prefs, '/chiller');
    expect(await readStartupUrl(prefs), '/chiller');
  });

  test('an empty stored string counts as the default', () async {
    final prefs = InMemoryPreferences();
    await prefs.setString(startupUrlPrefsKey, '');
    expect(await readStartupUrl(prefs), startupUrlDefault);
  });

  test('writing the default clears the key', () async {
    final prefs = InMemoryPreferences();
    await writeStartupUrl(prefs, '/chiller');
    await writeStartupUrl(prefs, startupUrlDefault);
    expect(await prefs.containsKey(startupUrlPrefsKey), isFalse);
    expect(await readStartupUrl(prefs), startupUrlDefault);
  });

  group('migrateStartupUrlToDeviceLocal', () {
    test('deletes a stray shared row and keeps the local value', () async {
      final local = InMemoryPreferences();
      final shared = _MirroringPrefs(local);
      await shared.setString(startupUrlPrefsKey, '/from-another-station');
      await local.setString(startupUrlPrefsKey, '/wet-area');

      await migrateStartupUrlToDeviceLocal(shared: shared, local: local);

      expect(await shared.getString(startupUrlPrefsKey), isNull,
          reason: 'the database must never hold a startup URL');
      expect(await readStartupUrl(local), '/wet-area',
          reason: "removing the shared row must not lose this station's choice");
    });

    test('a shared row with nothing local just disappears', () async {
      final local = InMemoryPreferences();
      final shared = _MirroringPrefs(local);
      await shared.setString(startupUrlPrefsKey, '/from-another-station');

      await migrateStartupUrlToDeviceLocal(shared: shared, local: local);

      expect(await shared.getString(startupUrlPrefsKey), isNull);
      expect(await readStartupUrl(local), startupUrlDefault);
    });

    test('no shared row touches nothing', () async {
      final local = InMemoryPreferences();
      final shared = _MirroringPrefs(local);
      await local.setString(startupUrlPrefsKey, '/wet-area');

      await migrateStartupUrlToDeviceLocal(shared: shared, local: local);

      expect(await readStartupUrl(local), '/wet-area');
    });
  });
}
