/// Abstract interface for operator identity validation.
///
/// Every MCP tool call must be gated by identity validation.
/// Implementations check the operator's identity on each invocation
/// (not cached) to support token-based auth where identity can expire.
abstract class OperatorIdentity {
  /// The operator's unique identifier.
  ///
  /// Throws [OperatorNotAuthenticatedError] if not authenticated.
  String get operatorId;

  /// Whether the operator is currently authenticated.
  bool get isAuthenticated;

  /// Validates the operator's identity.
  ///
  /// Throws [OperatorNotAuthenticatedError] if validation fails.
  /// Checks identity on every call (not cached) to future-proof
  /// for token-based auth where identity can expire mid-session.
  Future<void> validate();
}

/// Error thrown when an operator is not authenticated.
class OperatorNotAuthenticatedError implements Exception {
  OperatorNotAuthenticatedError(this.message);

  final String message;

  @override
  String toString() => 'OperatorNotAuthenticatedError: $message';
}
