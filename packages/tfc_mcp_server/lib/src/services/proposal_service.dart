/// Callback type for proposal notifications.
///
/// Invoked synchronously by [ProposalService.wrapProposal] with the wrapped
/// proposal map (with `_proposal_type` set). This is the whole transport: the
/// MCP server is hosted inside the Flutter app, so the tool handler and the
/// banner that shows its result are objects in the same isolate.
typedef ProposalCallback = void Function(Map<String, dynamic> wrapped);

/// Shared proposal diff formatting and tagging for write tools.
///
/// Every write tool produces a "proposal" (a preview of what the AI wants
/// to create or modify) that is presented to the operator for confirmation.
/// This service provides consistent markdown formatting for those proposals
/// and hands the wrapped result to the UI through [ProposalCallback].
///
/// Nothing about a proposal is persisted. Proposals used to be inserted into
/// `mcp_proposal` so that a three-second poll on the Flutter side could read
/// them back out again -- a database round trip to move a map between two
/// objects in one isolate. That poll bound its parameters with `?` where
/// Postgres needs `$1`, inside a bare `catch (_)`, so it never read a single
/// row in production; 1018 rows accumulated, all still `pending`. Delivery
/// has always in fact come from the callback below. The table is left in
/// place (dropping it needs a migration) but is no longer read or written.
class ProposalService {
  ProposalService({ProposalCallback? onProposal}) : _onProposal = onProposal;

  final ProposalCallback? _onProposal;

  /// Formats a markdown diff for a "create" proposal.
  ///
  /// Produces a human-readable table showing the fields and values
  /// of the object to be created.
  String formatCreateDiff(
    String type,
    String title,
    Map<String, dynamic> fields,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('## Proposal: Create $type');
    buffer.writeln();
    buffer.writeln('**$title**');
    buffer.writeln();
    buffer.writeln('| Field | Value |');
    buffer.writeln('|-------|-------|');
    for (final entry in fields.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
    return buffer.toString().trimRight();
  }

  /// Formats a markdown diff for an "update" proposal.
  ///
  /// Produces a human-readable before/after table showing what fields
  /// will change.
  ///
  /// The [changes] map keys are field names and values are strings
  /// in the format "before -> after".
  String formatUpdateDiff(
    String type,
    String title,
    Map<String, String> changes,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('## Proposal: Update $type');
    buffer.writeln();
    buffer.writeln('**$title**');
    buffer.writeln();
    buffer.writeln('| Field | Before | After |');
    buffer.writeln('|-------|--------|-------|');
    for (final entry in changes.entries) {
      final parts = entry.value.split(' -> ');
      final before = parts.isNotEmpty ? parts[0] : '';
      final after = parts.length > 1 ? parts[1] : '';
      buffer.writeln('| ${entry.key} | $before | $after |');
    }
    return buffer.toString().trimRight();
  }

  /// Adds a `_proposal_type` field to [proposal] for Phase 5 routing, and
  /// hands the wrapped map to the in-process listener.
  ///
  /// The `_proposal_type` field allows the Flutter UI to identify what
  /// kind of proposal this is (e.g., 'alarm', 'page') and route to the
  /// appropriate editor.
  ///
  /// [op] says what accepting the proposal does to its target: 'create',
  /// 'update', or 'delete'. The type alone cannot carry this -- 'alarm' and
  /// 'key_mapping' are used for both creates and updates -- so it is stamped
  /// into the JSON as `_op` for the notification banner to label each row.
  ///
  /// The returned map is the same object the callback receives, and write
  /// tools return its JSON encoding as the tool result. Both copies are
  /// therefore byte-identical, which is what lets the UI deduplicate a
  /// proposal that arrives once through the callback and once through the
  /// tool result of an in-app tool call.
  ///
  /// Still returns a [Future] although nothing here awaits: every write tool
  /// awaits this call, and the future completes without suspending, so the
  /// callback runs before the tool handler continues.
  Future<Map<String, dynamic>> wrapProposal(
    String type,
    Map<String, dynamic> proposal, {
    String op = 'create',
  }) async {
    final wrapped = {
      ...proposal,
      '_proposal_type': type,
      '_op': op,
    };

    _onProposal?.call(wrapped);

    return wrapped;
  }
}
