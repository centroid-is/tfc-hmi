import 'dart:io';

import 'interface.dart';
import 'linux.dart';

export 'interface.dart';

class SecureStorage {
  static MySecureStorage? _instance;

  static void setInstance(MySecureStorage instance) {
    _instance = instance;
  }

  static MySecureStorage getInstance() {
    if (_instance != null) {
      return _instance!;
    }
    if (Platform.isLinux) {
      return LinuxSecureStorage();
    }
    throw Exception('SecureStorage instance not set for this platform');
  }
}
