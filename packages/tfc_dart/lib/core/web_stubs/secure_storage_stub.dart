/// Web stub for secure_storage/secure_storage.dart
/// On web, secure storage is not available.

import '../secure_storage/interface.dart';

class SecureStorage implements MySecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('SecureStorage not available on web');
}
