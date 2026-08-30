/// The fixed access vocabulary shared by the HMI and, later, the relay.
///
/// Groups, roles, the authenticated user, the authentication interface, the
/// audit contract, the session and its listener-gated inactivity countdown,
/// and the single PBKDF2 derivation the HMI uses for both password hashing and
/// config-export envelopes. This library
/// is pure Dart and must stay that way; see the README for the one-way
/// dependency rule and `test/package_purity_test.dart` for its enforcement.
library;

export 'src/access_group.dart';
export 'src/access_policy.dart';
export 'src/access_role.dart';
export 'src/access_session.dart';
export 'src/access_template.dart';
export 'src/audit.dart';
export 'src/auth_provider.dart';
export 'src/authenticated_user.dart';
export 'src/inactivity_monitor.dart';
export 'src/password_hasher.dart';
