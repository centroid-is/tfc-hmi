import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'interface.dart';

class OtherSecureStorage implements MySecureStorage {
  final _storage = FlutterSecureStorage();

  @override
  Future<void> write({required String key, required String value}) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
  }

  @override
  Future<String?> read({required String key}) async {
    return await _storage.read(key: key);
  }
}
