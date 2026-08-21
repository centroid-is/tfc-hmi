import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/proposal_service.dart';
import 'tool_registry.dart';

/// Registers the proposal feedback tool on the given [registry].
///
/// Write tools are fire-and-forget from the AI's point of view: they hand a
/// proposal to the operator and return. This tool closes the loop -- after
/// proposing, the AI can ask what the operator did with it.
///
/// Tools registered:
/// - `get_proposal_status`: Look up operator decisions on proposals
void registerProposalStatusTools(
  ToolRegistry registry,
  ProposalService proposalService,
) {
  registry.registerTool(
    name: 'get_proposal_status',
    description:
        'Check what the operator did with proposals you created. Write tools '
        'return a `_proposal_id`; pass those ids here, or omit `ids` to list '
        'the most recent proposals. Statuses: `pending`/`notified` = awaiting '
        'operator review, `viewed` = opened in an editor but not yet decided, '
        '`accepted` = applied and saved, `rejected`/`dismissed` = declined.',
    inputSchema: JsonSchema.object(
      properties: {
        'ids': JsonSchema.array(
          description:
              'Proposal ids (`_proposal_id` from write tool results) to look '
              'up. Omit to list recent proposals instead.',
          items: JsonSchema.integer(),
        ),
        'limit': JsonSchema.integer(
          description:
              'Maximum rows when listing recent proposals (default 20, max '
              '100). Ignored when `ids` is given.',
        ),
      },
    ),
    handler: (args, extra) async {
      final rawIds = args['ids'] as List<dynamic>?;
      final ids = rawIds?.map((e) => (e as num).toInt()).toList();
      final limit = (args['limit'] as num?)?.toInt() ?? 20;

      final statuses =
          await proposalService.getProposalStatuses(ids: ids, limit: limit);

      return CallToolResult(
        content: [TextContent(text: jsonEncode({'proposals': statuses}))],
      );
    },
  );
}
