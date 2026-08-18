import 'package:flutter/services.dart' show PlatformException;
import 'package:logger/logger.dart';

import 'package:tfc_dart/core/secure_storage/linux.dart' show AwsSecureStorage;
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';

import 'other.dart';

final _logger = Logger();

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
/// storage and delete the legacy entry. Deleting completes the migration
/// for that key: all future writes go to the new storage only, so a
/// lingering legacy entry would be a frozen pre-migration snapshot — a
/// rollback to an older build would silently load a stale config, and the
/// secret would live in the keychain twice indefinitely. Deletes remove
/// the key from both storages so a deleted secret cannot be resurrected by
/// the fallback read.
///
/// A legacy-storage error during the fallback read is tolerated (logged,
/// treated as absent): amplify errors mean the pre-migration app could not
/// read its secrets on this machine either, so there is no working
/// configuration to lose — and a fresh install must not depend on a
/// storage backend it will never write to.
///
/// Entitlement fallback: keychain calls through flutter_secure_storage can
/// throw PlatformException(-34018, "A required entitlement isn't present")
/// on builds without the required entitlements/provisioning (see the
/// comment in other.dart). A misconfigured/dev build must not break the
/// whole config-load path, so any [PlatformException] from the new storage
/// makes the operation fall through to the legacy amplify storage (which
/// does not need them), with a once-per-process warning per operation.
///
/// Error semantics: a storage error is never converted into "key absent".
/// Callers like StateManConfig.fromPrefs persist a default config when a
/// read returns null, so returning null on error would overwrite real data.
/// [read] returns null only when a storage affirmatively reports the key
/// absent; if the storage(s) consulted error out, the error propagates.
class MacOsMigratingSecureStorage implements MySecureStorage {
  /// [newStorage]/[legacyStorage] exist for tests; production uses the
  /// defaults ([OtherSecureStorage] / lazily-created [AwsSecureStorage]).
  MacOsMigratingSecureStorage({
    MySecureStorage? newStorage,
    MySecureStorage? legacyStorage,
  })  : _storage = newStorage ?? OtherSecureStorage(),
        _injectedLegacy = legacyStorage;

  final MySecureStorage _storage;

  final MySecureStorage? _injectedLegacy;

  /// Legacy amplify-backed storage, created lazily: most reads hit the new
  /// storage and never need it.
  MySecureStorage? _legacyInstance;
  MySecureStorage get _legacy =>
      _injectedLegacy ?? (_legacyInstance ??= AwsSecureStorage());

  /// Warn about missing keychain entitlements only once per process *per
  /// operation* — the fallback fires on every keychain call, so per-call
  /// logging would flood the log, but a read warning must not suppress the
  /// first warning that writes are landing in the legacy store.
  static final Set<String> _warnedMissingEntitlements = {};
  static void _warnMissingEntitlements(String operation, Object error) {
    if (!_warnedMissingEntitlements.add(operation)) return;
    _logger.w('CentroidX keychain $operation failed — this build is probably '
        'missing the keychain-access-groups entitlement (sandboxed dev '
        'build?). Falling back to the legacy amplify secure storage. '
        'Error: $error');
  }

  @override
  Future<String?> read({required String key}) async {
    String? value;
    try {
      value = await _storage.read(key: key);
    } on PlatformException catch (e) {
      // New storage unusable (missing entitlements): the legacy storage is
      // the operative store, serve the read from there. If it errors too,
      // let that propagate — with both storages broken, "null" would be a
      // lie that makes callers persist default configs over real data.
      _warnMissingEntitlements('read', e);
      return await _legacy.read(key: key);
    }
    if (value != null) {
      return value;
    }
    // One-time migration: the new storage affirmatively reported the key
    // absent, so check the old amplify-branded keychain entry. A legacy
    // error is tolerated (see class doc): a broken amplify store means the
    // pre-migration app could not read this machine's secrets either, and
    // a fresh install must not break over a store it never wrote to.
    String? legacyValue;
    try {
      legacyValue = await _legacy.read(key: key);
    } catch (e) {
      _logger.w('Legacy (amplify) secure storage read for "$key" failed during '
          'migration fallback — treating as absent. If this machine had '
          'pre-migration secrets they are unreadable (they were equally '
          'unreadable to the pre-migration app). Error: $e');
      return null;
    }
    if (legacyValue != null) {
      try {
        await _storage.write(key: key, value: legacyValue);
        // Copy-forward verified — remove the legacy entry so it cannot go
        // stale (writes only go to the new storage from now on) and the
        // secret does not live in the keychain twice.
        try {
          await _legacy.delete(key: key);
        } catch (_) {
          // Best effort: the new-storage copy is already authoritative.
        }
      } on PlatformException catch (e) {
        // Couldn't copy into the new storage (missing entitlements); the
        // legacy value is still the answer and stays where it is.
        _warnMissingEntitlements('migration write', e);
      }
    }
    return legacyValue;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      // No keychain entitlements: keep the app working by persisting to
      // the legacy amplify storage instead.
      _warnMissingEntitlements('write', e);
      await _legacy.write(key: key, value: value);
    }
  }

  @override
  Future<void> delete({required String key}) async {
    Object? undeleted;
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (e) {
      _warnMissingEntitlements('delete', e);
      // Distinguish "storage wholly unusable, legacy is the operative
      // store" (fallback mode — swallowing is correct) from "delete alone
      // was denied but the value is still readable" — there a swallowed
      // error means the next read resurrects data the caller was told was
      // deleted, so it must surface.
      try {
        if (await _storage.read(key: key) != null) {
          undeleted = e;
        }
      } on PlatformException catch (_) {
        // Reads fail too: the new storage is not operative, nothing to
        // resurrect from it.
      }
    }
    // Also delete the legacy copy, otherwise the migration fallback in
    // [read] would bring a deleted secret back from the dead.
    try {
      await _legacy.delete(key: key);
    } catch (_) {
      // Best effort: the legacy entry may not exist or be inaccessible.
    }
    if (undeleted != null) {
      // ignore: only_throw_errors -- rethrowing the original exception.
      throw undeleted;
    }
  }
}
