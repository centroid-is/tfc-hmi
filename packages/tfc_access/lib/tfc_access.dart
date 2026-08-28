/// The fixed access vocabulary shared by the HMI and, later, the relay.
///
/// Groups, roles, the authenticated user, the authentication interface and the
/// audit contract — enums, strings and interfaces, nothing more. This library
/// is pure Dart and must stay that way; see the README for the one-way
/// dependency rule and `test/package_purity_test.dart` for its enforcement.
library;

export 'src/access_group.dart';
export 'src/access_role.dart';
export 'src/auth_provider.dart';
export 'src/authenticated_user.dart';
