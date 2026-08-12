import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:tfc_dart/core/secure_storage/secure_storage.dart';

class OtherSecureStorage implements MySecureStorage {
  final _storage = FlutterSecureStorage(
    // useDataProtectionKeyChain MUST stay false on macOS: the
    // data-protection keychain (kSecUseDataProtectionKeychain) requires
    // provisioned code signing (a real Apple Development identity with an
    // application-identifier), and every keychain call fails with
    // errSecMissingEntitlement (-34018) on ad-hoc/unprovisioned builds —
    // which is what dev-machine and release builds are. The file-based
    // login keychain works without provisioning (this is also why the
    // amplify storage sets useDataProtection: false). Windows ignores
    // mOptions entirely, so this is macOS-only in effect.
    mOptions: MacOsOptions(
      accountName: 'CentroidX',
      useDataProtectionKeyChain: false,
    ),
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
