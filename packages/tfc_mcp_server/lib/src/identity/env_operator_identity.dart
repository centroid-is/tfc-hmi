import 'dart:io' show Platform;

import 'operator_identity.dart';

/// Reads operator identity from the TFC_USER environment variable.
///
/// Accepts an optional [environmentProvider] for testability.
/// Production code uses the default which reads [Platform.environment].
///
/// Identity is validated on every access (not cached) to future-proof
/// for token-based auth where identity can expire mid-session.
class EnvOperatorIdentity implements OperatorIdentity {
  EnvOperatorIdentity({
    Map<String, String> Function()? environmentProvider,
  }) : _environmentProvider = environmentProvider ?? _defaultEnvProvider;

  final Map<String, String> Function() _environmentProvider;

  static const String _envKey = 'TFC_USER';

  static const String _errorMessage =
      'TFC_USER environment variable not set. '
      'Set TFC_USER to your operator ID to use MCP features.';

  static Map<String, String> _defaultEnvProvider() => Platform.environment;

  @override
  String get operatorId {
    final env = _environmentProvider();
    final user = env[_envKey];
    if (user == null || user.isEmpty) {
      throw OperatorNotAuthenticatedError(_errorMessage);
    }
    return user;
  }

  @override
  bool get isAuthenticated {
    final env = _environmentProvider();
    final user = env[_envKey];
    return user != null && user.isNotEmpty;
  }

  @override
  Future<void> validate() async {
    // Access operatorId to trigger validation check.
    // Throws OperatorNotAuthenticatedError if TFC_USER is not set.
    operatorId;
  }
}
