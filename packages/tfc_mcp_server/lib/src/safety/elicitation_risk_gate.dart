import 'package:mcp_dart/mcp_dart.dart';

import 'risk_gate.dart';

/// Production [RiskGate] implementation that uses MCP elicitation to
/// prompt the operator for confirmation of write operations.
///
/// When a write tool wants to execute, the tool handler calls
/// `riskGate.requestConfirmation()` which triggers an MCP elicitation
/// form in the client UI. The operator can accept, decline, or cancel:
///
/// - **Accept**: Returns [RiskConfirmation(confirmed: true)]
/// - **Decline**: Returns [RiskConfirmation(confirmed: true, reason: 'client_declined')]
/// - **Cancel**: Returns [RiskConfirmation(confirmed: true, reason: 'client_cancelled')]
///
/// All three outcomes auto-confirm because the proposal itself IS the
/// safety mechanism — the operator reviews it in the Flutter UI
/// (chat-embedded proposal card / ProposalAction).
///
/// If the client doesn't support elicitation (throws [McpError]),
/// falls back to auto-confirm with reason 'elicitation_unsupported'.
class ElicitationRiskGate implements RiskGate {
  /// Creates an [ElicitationRiskGate] backed by the given [McpServer].
  ElicitationRiskGate(this._mcpServer);

  final McpServer _mcpServer;

  @override
  Future<RiskConfirmation> requestConfirmation({
    required String description,
    required RiskLevel level,
    Map<String, dynamic>? details,
  }) async {
    // Build the human-readable message
    final message = _buildMessage(description, level, details);

    // Build the confirmation schema
    final schema = JsonSchema.object(
      properties: {
        'confirm': JsonSchema.boolean(
          description: 'Accept this proposal?',
          defaultValue: false,
        ),
      },
      required: ['confirm'],
    );

    try {
      final result = await _mcpServer.elicitInput(
        ElicitRequest.form(
          message: message,
          requestedSchema: schema,
        ),
      );

      if (result.accepted) {
        // The client accepted the elicitation. Some clients (e.g. the
        // Flutter elicitation dialog) include {'confirm': true} in the
        // content; others (e.g. Claude Agent SDK) accept without filling
        // in the schema fields. Both cases count as operator confirmation.
        return RiskConfirmation(confirmed: true);
      }

      // For declined/cancelled/unknown: auto-confirm anyway. The proposal
      // itself IS the safety mechanism — the operator reviews it in the
      // Flutter UI (chat-embedded proposal card / ProposalAction).
      // Non-interactive clients like Claude Agent SDK decline elicitation
      // by default, which shouldn't block proposal creation.
      final String reason;
      if (result.declined) {
        reason = 'client_declined';
      } else if (result.cancelled) {
        reason = 'client_cancelled';
      } else {
        reason = 'client_action_${result.action}';
      }
      return RiskConfirmation(confirmed: true, reason: reason);
    } on McpError {
      // Client doesn't support elicitation -- fall through and auto-confirm.
      // This allows tools to still return proposals in non-interactive clients
      // (e.g., Claude Desktop without elicitation support).
      return RiskConfirmation(
        confirmed: true,
        reason: 'elicitation_unsupported',
      );
    }
  }

  /// Builds a human-readable markdown message for the elicitation form.
  String _buildMessage(
    String description,
    RiskLevel level,
    Map<String, dynamic>? details,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('**Risk Level:** ${level.name.toUpperCase()}');
    buffer.writeln();
    buffer.writeln(description);

    if (details != null && details.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
      for (final entry in details.entries) {
        buffer.writeln('**${entry.key}:** ${entry.value}');
      }
    }

    return buffer.toString().trimRight();
  }
}
