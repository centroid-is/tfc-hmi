import 'dart:io';

import '../database.dart' show DatabaseConfig;
import '../preferences.dart' show Preferences;
import 'interface.dart';
import 'linux.dart';

export 'interface.dart';

class SecureStorage {
  static MySecureStorage? _instance;

  static void setInstance(MySecureStorage instance) {
    _instance = instance;
    // Swapping the backing store invalidates everything cached from the
    // old one. Production sets the instance once at startup (no-op); tests
    // swap in fresh fakes per test and must not see a previous test's
    // secrets served from the process-wide caches.
    Preferences.clearSecretCache();
    DatabaseConfig.clearPrefsCache();
  }

  static MySecureStorage getInstance() {
    if (_instance != null) {
      return _instance!;
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return AwsSecureStorage();
    }
    throw Exception('SecureStorage instance not set for this platform');
  }
}
