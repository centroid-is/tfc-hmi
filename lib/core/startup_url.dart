import 'package:tfc_dart/core/preferences.dart';

/// SharedPreferences key holding the URL the app opens on at startup. Local
/// to the machine on purpose — stations sharing one database front different
/// equipment, so each picks its own startup page (in the page editor's Pages
/// dialog) without dragging the others along.
const String startupUrlPrefsKey = 'startup_url';

/// Where the app starts when no startup URL has been chosen.
const String startupUrlDefault = '/';

/// Reads the persisted startup URL; absent or empty counts as
/// [startupUrlDefault].
Future<String> readStartupUrl(PreferencesApi prefs) async {
  final stored = await prefs.getString(startupUrlPrefsKey);
  if (stored == null || stored.isEmpty) return startupUrlDefault;
  return stored;
}

/// Persists the startup URL. The default clears the key instead of storing
/// it, so a reset station is indistinguishable from a fresh install.
Future<void> writeStartupUrl(PreferencesApi prefs, String url) async {
  if (url == startupUrlDefault) {
    await prefs.remove(startupUrlPrefsKey);
  } else {
    await prefs.setString(startupUrlPrefsKey, url);
  }
}
