import 'access_group.dart';
import 'authenticated_user.dart';

/// The single seam behind which authentication lives.
///
/// One interface, so a second implementation — OIDC, one day — can be added
/// without touching a caller. `LocalAuthProvider` (plan 01-03) is the only
/// implementation this milestone ships.
abstract class AuthProvider {
  /// Resolve [username] and [password] to a user, or null.
  ///
  /// **Null means the credentials were not recognised.** Throwing means
  /// infrastructure failed — the database was unreachable, the connection
  /// dropped mid-query.
  ///
  /// The distinction is load-bearing, not stylistic: the caller writes an
  /// audit row with `allowed: false` for a null, and must not record a
  /// database outage as somebody's failed login attempt. A trail that reports
  /// twenty failed logins during a five-minute network blip is a trail nobody
  /// trusts afterwards.
  Future<AuthenticatedUser?> authenticate(String username, String password);
}

/// Raised when a write is refused because the current role lacks the group it
/// requires.
///
/// Vocabulary only in this phase — Phase 1 gates nothing, so nothing throws
/// this yet. The guards in Phase 3 (`AccessGate`, `GuardedStateMan`,
/// `GuardedPreferences`) are what will.
class AccessDenied implements Exception {
  const AccessDenied(this.itemKey, this.required);

  /// The tag, preference key or route that was refused.
  final String itemKey;

  /// The group the caller would have needed.
  final AccessGroup required;

  @override
  String toString() =>
      'AccessDenied: "$itemKey" requires the ${required.name} group.';
}
