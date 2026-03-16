/// Thrown when an operator declines or cancels a proposal elicitation.
///
/// This exception triggers [AuditStatus.declined] in the audit trail
/// (via [AuditLogService.executeWithAudit]) and a non-error response
/// to the MCP client (via [ToolRegistry] middleware).
class ProposalDeclinedException implements Exception {
  ProposalDeclinedException(this.message);

  /// Human-readable message describing the decline/cancel reason.
  final String message;

  @override
  String toString() => message;
}
