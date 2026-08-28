import 'package:meta/meta.dart';

/// A person who has signed in: a username, exactly one role name, and
/// something to show them in the app bar.
///
/// Carries **no password-specific fields** on purpose. This is the type an
/// OIDC implementation would populate from claims without touching a single
/// caller, which is one of the three things spec §3 asks for to keep SSO cheap
/// later. Adding a hash, a salt or a token here is what would make that
/// expensive.
///
/// One role, not many. Multi-role brings union semantics and an "effective
/// permissions" inspector, and is not worth it at this size.
@immutable
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.username,
    required this.roleName,
    String? displayName,
  }) : _displayName = displayName;

  /// The `AppUser` primary key.
  final String username;

  /// The name of the role this user holds — matched against `AppRole.name`,
  /// never against an id.
  final String roleName;

  final String? _displayName;

  /// What to show the operator. Falls back to [username] when nothing better
  /// is known, so the app bar never renders an empty elevation badge.
  String get displayName =>
      (_displayName == null || _displayName.isEmpty) ? username : _displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthenticatedUser &&
          other.username == username &&
          other.roleName == roleName &&
          other.displayName == displayName;

  @override
  int get hashCode => Object.hash(username, roleName, displayName);

  @override
  String toString() => 'AuthenticatedUser($username as $roleName)';
}
