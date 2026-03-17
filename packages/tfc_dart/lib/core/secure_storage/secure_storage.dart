import 'dart:io' if (dart.library.js_interop) '../web_stubs/io_stub.dart';

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
    if (Platform.isLinux || Platform.isMacOS) {
      return AwsSecureStorage();
    }
    throw Exception('SecureStorage instance not set for this platform');
  }
}
