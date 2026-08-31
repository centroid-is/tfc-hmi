import 'package:logger/logger.dart';
import 'package:meta/meta.dart';
import 'package:tfc_access/tfc_access.dart';

import 'access_repository.dart';

/// Authenticates against `app_user` with whichever derivation the stored row
/// names.
///
/// New rows are Argon2id. A `pbkdf2-sha256` row is verified forever, at the
/// count recorded in the row: existing users must not be locked out by the
/// change of algorithm.
///
/// The only [AuthProvider] this milestone ships. A second implementation —
/// OIDC, one day — goes behind the same interface without touching a caller,
/// which is the whole reason the interface exists.
///
/// ## null versus throw
///
/// **Null means the credentials were not recognised. A throw means
/// infrastructure failed.** Nothing in here wraps the body in a try/catch that
/// turns a dropped connection into a null, and nothing should be added that
/// does. The caller (plan 01-07) writes an audit row with `allowed: false` for
/// a null; if an outage arrived as a null too, a five-minute network blip would
/// land in the trail as twenty failed login attempts, and a trail that reports
/// events that did not happen is a trail nobody trusts afterwards. The
/// distinction cannot be recovered further up, so it has to be honoured here.
///
/// ## The honest framing
///
/// This is an operational guardrail against accident, not an access control.
/// Anyone holding the station's Postgres credential can rewrite `app_user`
/// directly. What it buys is that a shoulder-surfed screen or a shared
/// workstation does not hand over somebody else's role.
class LocalAuthProvider implements AuthProvider {
  LocalAuthProvider(this.repository, {Logger? logger})
      : _logger = logger ?? Logger();

  final AccessRepository repository;
  final Logger _logger;

  /// A well-formed hash and salt to derive against when the user does not
  /// exist, so the absent-user path costs the same work as the wrong-password
  /// path.
  ///
  /// Fixed values, and deliberately not derived from any real password: nothing
  /// verifies against them, they exist to be burned. Base64 of 32 and 16 zero
  /// bytes respectively — the shapes [PasswordHasher.verify] expects, so it
  /// reaches the derivation rather than bailing out early on a decode failure.
  static const String _dummyHashB64 =
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  static const String _dummySaltB64 = 'AAAAAAAAAAAAAAAAAAAAAA==';

  /// How many dummy derivations have run.
  ///
  /// A test hook, and the only way to assert the enumeration-resistance path
  /// was taken: the honest alternative is wall-clock timing, which is far too
  /// flaky to put in a suite.
  @visibleForTesting
  static int dummyDerivations = 0;

  @override
  Future<AuthenticatedUser?> authenticate(
      String username, String password) async {
    final name = username.trim();
    // Nothing to hide on this branch: an empty username is not a username
    // somebody might or might not have, so short-circuiting it leaks nothing
    // and saves a pointless derivation.
    if (name.isEmpty || password.isEmpty) return null;

    final row = await repository.user(name);

    if (row == null) {
      // Username-enumeration resistance: derive anyway, so "no such user" and
      // "wrong password" cost the same. Be honest about the weight of this —
      // it is cheap and correct, but the whole scheme is a guardrail, and an
      // attacker who can time an HMI login form can also run `psql`. It is
      // here because leaving it out would be a gratuitous difference, not
      // because it defends against a threat this deployment actually faces.
      //
      // Built at the *current* Argon2id parameters, because that is what a
      // real row costs. The residual, stated rather than absorbed: a user who
      // is still on a `pbkdf2-sha256` row costs a different amount than this
      // dummy, so the timing distinguishes "not yet migrated" from "does not
      // exist" until that row is rewritten on its owner's next login. It does
      // not distinguish existence for anyone already migrated, and it
      // self-heals as the rows turn over.
      dummyDerivations++;
      final params = Argon2idKdf.params;
      await PasswordHasher.verify(
        password: password,
        stored: PasswordHash.argon2id(
          hashB64: _dummyHashB64,
          saltB64: _dummySaltB64,
          memoryKib: params.memoryKib,
          iterations: params.iterations,
          parallelism: params.parallelism,
        ),
      );
      return null;
    }

    final stored = decodeStoredHash(row.passwordHash, saltB64: row.salt);
    if (stored == null) {
      // A hash column mangled by hand. Not a credential failure in spirit, but
      // it is one in effect, and it must not take the login screen down with a
      // FormatException.
      _logger.w(
        'The stored password hash for "$name" could not be decoded — the row '
        'has been edited outside the app. Treating the login as failed.',
      );
      return null;
    }

    final ok = await PasswordHasher.verify(
      password: password,
      stored: stored,
    );
    if (!ok) return null;

    final role = await repository.role(row.roleName);
    if (role == null) {
      // A role deleted out from under a user. Returning an AuthenticatedUser
      // here would sign somebody in against an undefined group set, which
      // resolves to "nothing" or "everything" depending on who reads it next —
      // both wrong, and neither visible to the person at the panel.
      _logger.w(
        'User "$name" holds the role "${row.roleName}", which no longer exists '
        'in app_role. Refusing the login rather than signing in against an '
        'undefined group set.',
      );
      return null;
    }

    await repository.touchLastLogin(row.username, DateTime.now().toUtc());

    return AuthenticatedUser(
      username: row.username,
      roleName: row.roleName,
    );
  }
}
