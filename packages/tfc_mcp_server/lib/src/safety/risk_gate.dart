/// Risk levels for tiered confirmation of write operations.
enum RiskLevel { low, medium, high, critical }

/// Result of a risk confirmation request.
class RiskConfirmation {
  RiskConfirmation({required this.confirmed, this.reason});

  /// Whether the operation was confirmed.
  final bool confirmed;

  /// Optional reason for the decision (especially useful for declines).
  final String? reason;
}

/// Abstract interface for tiered confirmation of risky operations.
///
/// In Phase 1 (read-only tools), [NoOpRiskGate] is used which always
/// confirms. In Phase 4 (write tools), an elicitation-based implementation
/// will prompt the operator for confirmation via MCP elicitation.
abstract class RiskGate {
  /// Requests confirmation for an operation at the given [level].
  Future<RiskConfirmation> requestConfirmation({
    required String description,
    required RiskLevel level,
    Map<String, dynamic>? details,
  });
}

/// A no-op risk gate that always confirms.
///
/// Used during Phase 1 testing and for read-only operations that
/// don't require operator confirmation.
class NoOpRiskGate implements RiskGate {
  @override
  Future<RiskConfirmation> requestConfirmation({
    required String description,
    required RiskLevel level,
    Map<String, dynamic>? details,
  }) async {
    return RiskConfirmation(confirmed: true);
  }
}
