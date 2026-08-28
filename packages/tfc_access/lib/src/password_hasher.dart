import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// The one PBKDF2 derivation in the repository, and the one iteration hook.
///
/// This used to live in `lib/pages/server_config.dart` as part of
/// `SecureEnvelope`. It is here because a provider must not import a page file,
/// and because password hashing needs the same derivation — having two copies
/// is how the two drift apart.
///
/// ## On the accelerated backend
///
/// `Cryptography.instance` is a process-global. The Flutter app assigns
/// `FlutterCryptography.defaultInstance` to it (see
/// `lib/pages/server_config.dart`), and this pure-Dart code picks that up
/// automatically at runtime. That is why the accelerated backend — which ships
/// as a Flutter plugin — stays on the Flutter side and is deliberately absent
/// from this package's pubspec. Naming it here would break
/// `test/package_purity_test.dart` and the relay's server target for no gain;
/// the string is left unwritten on purpose, since that test reads file text.
abstract final class Pbkdf2Kdf {
  /// Tune per device; higher = slower/stronger. This is the value
  /// `SecureEnvelope` has always used, and every envelope already written
  /// records its own count, so changing it here does not strand them.
  static const int defaultIterations = 200000;

  /// Test hook: production-strength PBKDF2 takes tens of seconds per
  /// derivation in the debug-mode test VM, which turns any test that
  /// encrypts into a minutes-long run. Decrypt reads the iteration count
  /// out of the envelope, so envelopes made with this set still round-trip.
  ///
  /// **This is the only KDF iteration hook in the repository.**
  /// `SecureEnvelope.kdfIterationsForTest` is a forwarding getter/setter onto
  /// this field, not a second store. A second hook is how a suite ends up
  /// running real 200k-iteration derivations somewhere nobody noticed, and the
  /// symptom — "the tests got slow" — never points at the cause.
  @visibleForTesting
  static int? iterationsForTest;

  /// The iteration count to use when a caller does not name one.
  static int get iterations => iterationsForTest ?? defaultIterations;

  /// PBKDF2-HMAC-SHA256 over [passphrase] and [salt].
  ///
  /// [iterations] defaults to [Pbkdf2Kdf.iterations]. Callers decrypting an
  /// existing envelope, or verifying a stored password hash, must pass the
  /// count recorded alongside that ciphertext instead — otherwise raising
  /// [defaultIterations] silently invalidates everything written before it.
  static Future<SecretKey> deriveKey({
    required String passphrase,
    required List<int> salt,
    int? iterations,
    int bits = 256,
  }) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations ?? Pbkdf2Kdf.iterations,
      bits: bits,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt, // salt
    );
  }
}

/// The algorithm tag in the stored [PasswordHash.encode] form.
const String _pbkdf2Sha256Tag = 'pbkdf2-sha256';

/// A derived password hash together with everything needed to re-derive it.
///
/// ## Why the iteration count is a field
///
/// The `AppUser` table (access-control spec §2, quoted as final) has
/// `passwordHash` and `salt` and no iterations column. Rather than add one, the
/// count rides inside `passwordHash` in the PHC-ish form
/// `pbkdf2-sha256$<iterations>$<hash_b64>` — see [encode] / [decode]. The count
/// has to travel with the hash somehow: a later change to
/// [Pbkdf2Kdf.defaultIterations] would otherwise lock every existing user out,
/// and the self-describing form leaves room for a second algorithm later
/// without another migration.
@immutable
class PasswordHash {
  const PasswordHash({
    required this.hashB64,
    required this.saltB64,
    required this.iterations,
  });

  /// Base64 of the derived key bytes.
  final String hashB64;

  /// Base64 of the per-user salt. Stored in `AppUser.salt` raw, not prefixed.
  final String saltB64;

  /// The iteration count this hash was derived with — not necessarily the
  /// current [Pbkdf2Kdf.defaultIterations].
  final int iterations;

  /// The value to write into `AppUser.passwordHash`.
  String encode() => '$_pbkdf2Sha256Tag\$$iterations\$$hashB64';

  /// Parse a value read out of `AppUser.passwordHash`.
  ///
  /// [saltB64] comes from the row's separate `salt` column.
  ///
  /// A value with no `$` in it is a legacy bare-base64 hash written before this
  /// encoding existed; it is taken to have been made at the ambient default,
  /// [Pbkdf2Kdf.iterations].
  ///
  /// Throws [FormatException] on a prefixed value that is malformed or names an
  /// algorithm this package does not implement. Callers on the login path
  /// should prefer [tryDecode] — a row mangled in `psql` should fail a login,
  /// not crash the app.
  static PasswordHash decode(String stored, {required String saltB64}) {
    if (!stored.contains(r'$')) {
      return PasswordHash(
        hashB64: stored,
        saltB64: saltB64,
        iterations: Pbkdf2Kdf.iterations,
      );
    }
    final parts = stored.split(r'$');
    if (parts.length != 3) {
      throw FormatException('malformed password hash', stored);
    }
    if (parts[0] != _pbkdf2Sha256Tag) {
      throw FormatException(
        'unsupported password hash algorithm "${parts[0]}"',
        stored,
      );
    }
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) {
      throw FormatException('bad iteration count "${parts[1]}"', stored);
    }
    return PasswordHash(
      hashB64: parts[2],
      saltB64: saltB64,
      iterations: iterations,
    );
  }

  /// [decode], returning null instead of throwing.
  static PasswordHash? tryDecode(String stored, {required String saltB64}) {
    try {
      return decode(stored, saltB64: saltB64);
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PasswordHash &&
      other.hashB64 == hashB64 &&
      other.saltB64 == saltB64 &&
      other.iterations == iterations;

  @override
  int get hashCode => Object.hash(hashB64, saltB64, iterations);

  /// Deliberately does not print [hashB64]. A hash in a log line is not a
  /// password, but it is not something to scatter through the trail either.
  @override
  String toString() =>
      'PasswordHash($_pbkdf2Sha256Tag, iterations: $iterations)';
}

/// Password hashing for the local auth provider.
///
/// The honest framing, repeated from the package README: this is an operational
/// guardrail against accident, not an access control. Anyone holding the
/// station's Postgres password can rewrite `app_user` directly. What this buys
/// is that a shoulder-surfed screen, a shared workstation or a mistyped
/// username does not hand over somebody else's role.
abstract final class PasswordHasher {
  static final Random _rng = Random.secure();

  /// Bytes of salt per user. 16 is what `SecureEnvelope` uses and is ample for
  /// uniqueness; the point of the salt is that two users who pick the same
  /// password do not get the same hash.
  static const int saltBytes = 16;

  static List<int> _rand(int n) =>
      List<int>.generate(n, (_) => _rng.nextInt(256));

  /// Hash [password] with a fresh random salt at the current iteration count.
  static Future<PasswordHash> hash(String password) async {
    // Read once: the count that goes into the record must be the count that
    // was actually used, even if the hook is changed mid-run.
    final iterations = Pbkdf2Kdf.iterations;
    final salt = _rand(saltBytes);
    final key = await Pbkdf2Kdf.deriveKey(
      passphrase: password,
      salt: salt,
      iterations: iterations,
    );
    return PasswordHash(
      hashB64: base64Encode(await key.extractBytes()),
      saltB64: base64Encode(salt),
      iterations: iterations,
    );
  }

  /// Re-derive with the stored salt and iteration count and compare.
  ///
  /// Returns false for a wrong password, and also for a row that cannot be
  /// decoded at all — a hash or salt mangled by hand in `psql` must fail a
  /// login, not take the app down with a [FormatException] on the login screen.
  static Future<bool> verify({
    required String password,
    required String hashB64,
    required String saltB64,
    required int iterations,
  }) async {
    try {
      if (iterations < 1) return false;
      final expected = base64Decode(hashB64);
      final salt = base64Decode(saltB64);
      if (expected.isEmpty || salt.isEmpty) return false;
      final key = await Pbkdf2Kdf.deriveKey(
        passphrase: password,
        salt: salt,
        iterations: iterations,
        bits: 256,
      );
      return constantTimeEquals(await key.extractBytes(), expected);
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// Compare two byte lists without returning early on the first mismatch.
  ///
  /// Defence in depth on a guardrail, not a security boundary: the whole scheme
  /// is bypassed by anyone with `psql`, and a remote attacker cannot time this
  /// through an HMI login form anyway. But a timing-leaky compare is free to
  /// avoid, and writing the obvious `==` here is the kind of thing that gets
  /// copied into somewhere it does matter.
  ///
  /// The length check does return early. Lengths are not secret — the hash is
  /// always 32 bytes — and there is nothing to compare against otherwise.
  @visibleForTesting
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
