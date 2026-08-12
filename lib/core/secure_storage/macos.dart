import 'package:tfc_dart/core/secure_storage/linux.dart' show AwsSecureStorage;
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';

import 'other.dart';

/// macOS secure storage: the CentroidX-branded [OtherSecureStorage] with a
/// one-time migration from the legacy Amplify-based storage.
///
/// Historically macOS fell through to [AwsSecureStorage]
/// (amplify_secure_storage_dart), which stores keychain items under the
/// service name `com.amplify.awsCognitoAuthPlugin` — so macOS keychain
/// prompts showed an Amazon/Amplify identity instead of CentroidX. New
/// reads/writes now go through [OtherSecureStorage] (flutter_secure_storage
/// with accountName "CentroidX"), but existing installs still hold their
/// secrets under the old amplify service name. Without migration those
/// reads would come back null and the app would silently regenerate default
/// configs, losing the user's server/database setup.
///
/// Migration strategy: on a read miss in the new storage, fall back to the
/// legacy storage and, if the value exists there, copy it into the new
/// storage so subsequent reads never touch the legacy entry again. The
/// legacy entry is left in place (harmless, and safer if the user rolls
/// back to an older build); deletes remove the key from both storages so a
/// deleted secret cannot be resurrected by the fallback read.
class MacOsMigratingSecureStorage implements MySecureStorage {
  final OtherSecureStorage _storage = OtherSecureStorage();

  /// Legacy amplify-backed storage, created lazily: most reads hit the new
  /// storage and never need it.
  AwsSecureStorage? _legacyInstance;
  AwsSecureStorage get _legacy => _legacyInstance ??= AwsSecureStorage();

  @override
  Future<String?> read({required String key}) async {
    final value = await _storage.read(key: key);
    if (value != null) {
      return value;
    }
    // One-time migration: check the old amplify-branded keychain entry.
    try {
      final legacyValue = await _legacy.read(key: key);
      if (legacyValue != null) {
        await _storage.write(key: key, value: legacyValue);
      }
      return legacyValue;
    } catch (_) {
      // If the legacy storage is unreadable (e.g. keychain access denied),
      // behave as if the key simply does not exist.
      return null;
    }
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
    // Also delete the legacy copy, otherwise the migration fallback in
    // [read] would bring a deleted secret back from the dead.
    try {
      await _legacy.delete(key: key);
    } catch (_) {
      // Best effort: the legacy entry may not exist or be inaccessible.
    }
  }
}
