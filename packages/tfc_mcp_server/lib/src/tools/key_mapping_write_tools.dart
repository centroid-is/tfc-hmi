import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../safety/risk_gate.dart';
import '../services/config_service.dart';
import '../services/proposal_service.dart';
import 'tool_registry.dart';

/// Registers key mapping write tools on the given [registry].
///
/// These tools generate OPC UA key mapping proposals for the key repository
/// editor. Neither tool writes to the database -- they return proposal JSON
/// that the Flutter UI routes to the appropriate editor.
///
/// Tools registered:
/// - `create_key_mapping`: Build a new key mapping proposal
/// - `update_key_mapping`: Look up existing mapping and propose changes
void registerKeyMappingWriteTools(
  ToolRegistry registry, {
  required ConfigService configService,
  required RiskGate riskGate,
  required ProposalService proposalService,
}) {
  // ── create_key_mapping ──────────────────────────────────────────────

  registry.registerTool(
    name: 'create_key_mapping',
    description:
        'Create a new OPC UA key mapping proposal. Returns proposal JSON '
        'for the key repository editor -- does not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'Logical key name e.g. belt.speed',
        ),
        'namespace': JsonSchema.integer(
          description: 'OPC UA namespace index',
        ),
        'identifier': JsonSchema.string(
          description: 'OPC UA node identifier e.g. Belt.Speed',
        ),
      },
      required: ['key', 'namespace', 'identifier'],
    ),
    handler: (args, extra) async {
      final key = args['key'] as String;
      final namespace = args['namespace'] as int;
      final identifier = args['identifier'] as String;

      // Build proposal JSON matching key_mappings preference structure
      final proposal = <String, dynamic>{
        'key': key,
        'opcua_node': {
          'namespace': namespace,
          'identifier': identifier,
        },
      };

      // Format a human-readable diff for elicitation
      final diffMessage = proposalService.formatCreateDiff(
        'Key Mapping',
        key,
        {
          'key': key,
          'namespace': namespace,
          'identifier': identifier,
        },
      );

      // Elicit operator confirmation -- throws ProposalDeclinedException
      // on decline/cancel, which propagates up to ToolRegistry middleware.
      await riskGate.requestConfirmation(
        description: diffMessage,
        level: RiskLevel.medium,
      );

      // Wrap with _proposal_type for Phase 5 routing
      final wrapped = proposalService.wrapProposal('key_mapping', proposal);

      return CallToolResult(
        content: [TextContent(text: jsonEncode(wrapped))],
      );
    },
  );

  // ── update_key_mapping ──────────────────────────────────────────────

  registry.registerTool(
    name: 'update_key_mapping',
    description:
        'Update an existing OPC UA key mapping. Looks up the current mapping '
        'and returns a proposal with the changes -- does not write to the '
        'database.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'The key name to update (must already exist)',
        ),
        'namespace': JsonSchema.integer(
          description: 'New OPC UA namespace index (optional)',
        ),
        'identifier': JsonSchema.string(
          description: 'New OPC UA node identifier (optional)',
        ),
      },
      required: ['key'],
    ),
    handler: (args, extra) async {
      final key = args['key'] as String;
      final newNamespace = args['namespace'] as int?;
      final newIdentifier = args['identifier'] as String?;

      // Look up existing mapping
      final mappings = await configService.listKeyMappings(filter: key);
      final existing = mappings.where((m) => m['key'] == key).firstOrNull;

      if (existing == null) {
        return CallToolResult(
          content: [
            TextContent(text: 'No key mapping found for: $key'),
          ],
          isError: true,
        );
      }

      final oldNamespace = existing['namespace'] as int;
      final oldIdentifier = existing['identifier'] as String;

      // Merge updated fields
      final updatedNamespace = newNamespace ?? oldNamespace;
      final updatedIdentifier = newIdentifier ?? oldIdentifier;

      // Compute changes map for diff (only changed fields)
      final changes = <String, String>{};
      if (updatedNamespace != oldNamespace) {
        changes['namespace'] = '$oldNamespace -> $updatedNamespace';
      }
      if (updatedIdentifier != oldIdentifier) {
        changes['identifier'] = '$oldIdentifier -> $updatedIdentifier';
      }

      // Format before/after diff for elicitation
      final diffMessage = proposalService.formatUpdateDiff(
        'Key Mapping',
        key,
        changes,
      );

      // Elicit operator confirmation -- throws ProposalDeclinedException
      // on decline/cancel, which propagates up to ToolRegistry middleware.
      await riskGate.requestConfirmation(
        description: diffMessage,
        level: RiskLevel.medium,
      );

      // Build updated proposal
      final proposal = <String, dynamic>{
        'key': key,
        'opcua_node': {
          'namespace': updatedNamespace,
          'identifier': updatedIdentifier,
        },
      };

      final wrapped = proposalService.wrapProposal('key_mapping', proposal);

      return CallToolResult(
        content: [TextContent(text: jsonEncode(wrapped))],
      );
    },
  );
}
