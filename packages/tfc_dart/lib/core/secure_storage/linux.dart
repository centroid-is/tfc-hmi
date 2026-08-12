import 'dart:async';

// elinux does not support flutter_secure_storage
// so we use amplify_secure_storage_dart
// todo I would like to just use dbus secrets api, instead of amplify_secure_storage_dart

import 'package:amplify_secure_storage_dart/amplify_secure_storage_dart.dart';

import 'interface.dart';

class AwsSecureStorage implements MySecureStorage {
  // NOTE: no namespace is configured, so amplify_secure_storage_dart falls
  // back to its default of 'com.amplify.<scope>', i.e. the stored service
  // name is "com.amplify.awsCognitoAuthPlugin". That is ugly branding, but
  // every deployed Linux/eLinux install has its secrets stored under that
  // name — changing it would orphan those secrets (configs would silently
  // reset to defaults). Do not change it without a migration path.
  final _storage = AmplifySecureStorageDart.factoryFrom(
      macOSOptions: MacOSSecureStorageOptions(
    useDataProtection: false, // todo
    accessible: KeychainAttributeAccessible.accessibleAfterFirstUnlock,
    /*
dart compile exe bin/main.dart -o build/myapp

entitlements.plist

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>keychain-access-groups</key>
  <array>
    <string>YOUR_TEAM_ID.is.centroid.tfc-hmi</string>
  </array>
</dict>
</plist>

codesign -s - --force --entitlements entitlements.plist build/myapp
          */
  ))(
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
