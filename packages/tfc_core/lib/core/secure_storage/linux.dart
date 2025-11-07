import 'dart:async';

// elinux does not support flutter_secure_storage
// so we use amplify_secure_storage_dart
// todo I would like to just use dbus secrets api, instead of amplify_secure_storage_dart

import 'package:amplify_secure_storage_dart/amplify_secure_storage_dart.dart';

import 'interface.dart';

class LinuxSecureStorage implements MySecureStorage {
  final _storage = AmplifySecureStorageDart.factoryFrom()(
    AmplifySecureStorageScope
        .awsCognitoAuthPlugin, // dont know if this makes sense
  );

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
