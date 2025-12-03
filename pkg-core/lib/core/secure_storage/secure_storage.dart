import 'dart:io';

import 'interface.dart';
import 'linux.dart';
import 'other.dart';

export 'interface.dart';

class SecureStorage {
  static MySecureStorage getInstance() {
    if (Platform.isLinux) {
      return LinuxSecureStorage();
    }
    return OtherSecureStorage();
  }
}
