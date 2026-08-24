/// The startup-URL preference: device-local, defaulting to '/', and cleared
/// (not stored) when reset so a reset station looks like a fresh install.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/preferences.dart';

import 'package:tfc/core/startup_url.dart';

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
}
