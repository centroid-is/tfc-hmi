import 'dart:convert';

/// Routes proposal types to editor paths.
const proposalRoutes = <String, String>{
  'alarm': '/advanced/alarm-editor',
  'alarm_create': '/advanced/alarm-editor',
  'alarm_update': '/advanced/alarm-editor',
  'key_mapping': '/advanced/key-repository',
  'page': '/advanced/page-editor',
  'asset': '/advanced/page-editor',
  'asset_update': '/advanced/page-editor',
};

/// What accepting a proposal does to its target: bring it into existence,
/// change it, or remove it.
enum ProposalOp { create, update, delete }

int _lastLocalProposalId = 0;

/// Mints an id for a proposal arriving from the MCP server.
///
/// Ids are process-local handles, nothing more: a proposal lives in
/// [ProposalStateNotifier] until the operator decides on it, and is then
/// gone. They used to be `mcp_proposal` row ids; nothing is stored any more,
/// so this counter is the only source.
///
/// A plain counter rather than the clock reading it replaces
/// (`-DateTime.now().microsecondsSinceEpoch`): a batch of proposals is
/// wrapped in one synchronous loop, and two of them landing in the same
/// microsecond would get the same id and the second would be discarded as a
/// duplicate. Negative so that anything still reading `id > 0` as "came from
/// the database" keeps getting false.
int nextLocalProposalId() => --_lastLocalProposalId;

/// A proposal from the MCP server awaiting the operator's decision.
class PendingProposal {
  final int id;
  final String proposalType;
  final String title;
  final String proposalJson;
  final String operatorId;
  final DateTime createdAt;

  const PendingProposal({
    required this.id,
    required this.proposalType,
    required this.title,
    required this.proposalJson,
    required this.operatorId,
    required this.createdAt,
  });

  /// Reads a proposal off the wire, or null if this is not one.
  ///
  /// A proposal is a JSON object carrying `_proposal_type`; the title is
  /// whatever the write tool called the thing it wants to change, which is
  /// `title` for alarms, pages and assets and `key` for key mappings.
  ///
  /// One parser for both ends of the delivery path -- the in-app tool loop
  /// reading its own tool result, and the ingest that stages proposals from
  /// an external MCP client. They stage the same proposal when both are
  /// live, and [ProposalStateNotifier.addProposal] can only tell that if
  /// [proposalJson] is byte-identical on both, so the raw text is kept
  /// exactly as it arrived rather than re-encoded from the decoded map.
  static PendingProposal? tryParse(String proposalJson,
      {String operatorId = 'local'}) {
    if (!proposalJson.contains('_proposal_type')) return null;
    try {
      final decoded = jsonDecode(proposalJson);
      if (decoded is! Map<String, dynamic>) return null;
      if (!decoded.containsKey('_proposal_type')) return null;
      return PendingProposal(
        // A local handle, minted per arrival. The same proposal reaching the
        // notifier twice gets two different ids; addProposal deduplicates on
        // the JSON, which is identical.
        id: nextLocalProposalId(),
        proposalType: decoded['_proposal_type'] as String? ?? 'unknown',
        title: decoded['title'] as String? ??
            decoded['key'] as String? ??
            'Proposal',
        proposalJson: proposalJson,
        operatorId: operatorId,
        createdAt: DateTime.now(),
      );
    } catch (_) {
      // Not valid JSON, or not shaped like a proposal.
      return null;
    }
  }

  String get editorLabel {
    switch (proposalType) {
      case 'alarm':
      case 'alarm_create':
      case 'alarm_update':
        return 'Alarm Editor';
      case 'key_mapping':
        return 'Key Repository';
      case 'page':
        return 'Page Editor';
      case 'asset':
      case 'asset_update':
        return 'Page Editor';
      default:
        return 'Editor';
    }
  }

  String? get editorRoute => proposalRoutes[proposalType];

  /// What accepting this proposal does, read from the `_op` field the
  /// server stamps into the proposal JSON.
  ///
  /// Proposals from a server old enough not to send `_op` fall back to the
  /// type name: only the update types carried the action there
  /// ('asset_update', 'alarm_update'); everything else was a create except
  /// key-mapping deletes, which already marked themselves with `_op: delete`.
  ProposalOp get action {
    String? op;
    try {
      final decoded = jsonDecode(proposalJson);
      if (decoded is Map<String, dynamic>) op = decoded['_op'] as String?;
    } catch (_) {
      // Malformed JSON: fall through to the type-name fallback.
    }
    switch (op) {
      case 'create':
        return ProposalOp.create;
      case 'update':
        return ProposalOp.update;
      case 'delete':
        return ProposalOp.delete;
    }
    if (proposalType.endsWith('_update')) return ProposalOp.update;
    return ProposalOp.create;
  }
}

/// Renders one operator decision as a line of feedback for the AI.
///
/// The text follows `kOperatorDecisionPrefix` in the injected note, so it
/// reads as a sentence: `Accepted the alarm proposal "High temp".` Bulk
/// decisions list up to five titles. Proposal ids are not mentioned: they are
/// process-local handles now, and quoting one at the AI would invite it to
/// ask after a proposal that no longer exists anywhere.
///
/// Lives here rather than in `chat.dart` because it now has two consumers:
/// the in-app conversation, and the `ProposalFeedbackBus` relay that carries
/// the same sentence out to an external MCP client. Both must report the same
/// words -- the operator accepted one thing, not two differently-worded
/// things -- and the relay must not drag in the chat/LLM graph, which is
/// const-guarded out of flag-off builds.
String describeProposalFeedback(
    String action, List<PendingProposal> proposals) {
  final verb = switch (action) {
    'accepted' => 'Accepted',
    'rejected' => 'Rejected',
    'dismissed' => 'Dismissed',
    'viewed' => 'Viewed',
    _ => action,
  };
  final suffix = action == 'viewed' ? ' No decision yet.' : '';

  String typeLabel(String type) => switch (type) {
        'alarm' || 'alarm_create' || 'alarm_update' => 'alarm',
        'key_mapping' => 'key mapping',
        'page' => 'page',
        'asset' => 'asset',
        'asset_update' => 'asset update',
        _ => 'config',
      };

  if (proposals.length == 1) {
    final p = proposals.first;
    return '$verb the ${typeLabel(p.proposalType)} proposal '
        '"${p.title}".$suffix';
  }

  final types = proposals.map((p) => typeLabel(p.proposalType)).toSet();
  final label = types.length == 1 ? '${types.first} proposals' : 'proposals';
  final titles = [
    for (final p in proposals.take(5)) '"${p.title}"',
    if (proposals.length > 5) 'and ${proposals.length - 5} more',
  ].join(', ');
  return '$verb ${proposals.length} $label: $titles.$suffix';
}
