import 'interface.dart';
import 'linux.dart';

export 'interface.dart';

class SecureStorage {
  static MySecureStorage getInstance() {
    // Pure Dart package - Linux only
    return LinuxSecureStorage();
  }
}
