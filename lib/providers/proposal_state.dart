import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/mcp_database.dart';

import 'proposal_watcher.dart';
import 'database.dart' show databaseProvider;

export 'proposal_watcher.dart' show PendingProposal, ProposalOp;

/// Prefix marking operator-decision notes in the chat conversation.
///
/// Notes carry the user role so every LLM provider keeps them in
/// chronological order (Claude hoists system-role messages into the system
/// parameter), and the prefix lets [MessageBubble] render them as a system
/// note instead of an operator speech bubble.
const kOperatorDecisionPrefix = '[Operator decision]';

/// An operator decision on AI proposals, relayed back to the AI.
///
/// Emitted by [ProposalStateNotifier] whenever the operator accepts,
/// rejects, dismisses, or opens a proposal -- from any surface (banner
/// buttons, batch cards, editor commit/discard). The chat layer turns these
/// into operator-decision notes in the conversation so the AI learns what
/// happened to its proposals.
class ProposalFeedback {
  /// One of `accepted`, `rejected`, `dismissed`, `viewed`.
  final String action;

  /// The proposals the action applied to. Bulk actions arrive as one event.
  final List<PendingProposal> proposals;

  const ProposalFeedback({required this.action, required this.proposals});
}

/// Broadcast channel for [ProposalFeedback] events.
///
/// Lives outside [proposalStateProvider] so listeners (the chat lifecycle)
/// survive a notifier rebuild when the database connection changes.
final proposalFeedbackProvider =
    Provider<StreamController<ProposalFeedback>>((ref) {
  final controller = StreamController<ProposalFeedback>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});

/// Immutable snapshot of all pending proposals across types.
class ProposalState {
  final List<PendingProposal> proposals;

  const ProposalState({this.proposals = const []});

  int get pendingCount => proposals.length;

  bool get hasPending => proposals.isNotEmpty;

  /// Filter proposals by type (alarm, page, asset, key_mapping).
  List<PendingProposal> ofType(String type) =>
      proposals.where((p) => p.proposalType == type).toList();
}

/// Manages proposal lifecycle with DB write-through for status changes.
class ProposalStateNotifier extends StateNotifier<ProposalState> {
  ProposalStateNotifier(this._db, {StreamController<ProposalFeedback>? feedback})
      : _feedback = feedback,
        super(const ProposalState());

  final McpDatabase? _db;
  final StreamController<ProposalFeedback>? _feedback;

  /// Proposals already reported as viewed, so re-opening an editor does not
  /// spam the AI with repeat notes.
  final _viewedIds = <int>{};

  /// Add a proposal if it is not already present.
  ///
  /// Deduplicates by both ID and proposal JSON content, so inline proposals
  /// surfaced immediately from tool results don't create duplicates when the
  /// DB-sourced proposal arrives via [ProposalWatcher].
  void addProposal(PendingProposal proposal) {
    if (state.proposals.any((p) =>
        p.id == proposal.id || p.proposalJson == proposal.proposalJson)) {
      return;
    }
    state = ProposalState(
      proposals: [...state.proposals, proposal],
    );
  }

  /// Accept a proposal: update DB status to 'accepted' and remove from state.
  Future<void> acceptProposal(int id) async {
    await _updateStatus(id, 'accepted');
    _emitFeedback('accepted', id);
    _removeFromState(id);
  }

  /// Reject a proposal: update DB status to 'rejected' and remove from state.
  Future<void> rejectProposal(int id) async {
    await _updateStatus(id, 'rejected');
    _emitFeedback('rejected', id);
    _removeFromState(id);
  }

  /// Dismiss a proposal: update DB status to 'dismissed' and remove from state.
  Future<void> dismissProposal(int id) async {
    await _updateStatus(id, 'dismissed');
    _emitFeedback('dismissed', id);
    _removeFromState(id);
  }

  /// Record that the operator opened a proposal in its editor.
  ///
  /// Writes status 'viewed' but keeps the proposal pending in state -- a look
  /// is not a decision. Reported to the AI once per proposal.
  Future<void> viewProposal(int id) async {
    if (!state.proposals.any((p) => p.id == id)) return;
    if (!_viewedIds.add(id)) return;
    await _updateStatus(id, 'viewed');
    _emitFeedback('viewed', id);
  }

  /// Accept all proposals of a given type.
  ///
  /// Updates each proposal's DB status to 'accepted' and removes them from
  /// state. Returns the list of accepted proposals so the caller can route
  /// them to editors.
  ///
  /// Note: only proposals present in state at the time of the call are
  /// processed. The final state removal filters by type, so a proposal of
  /// the same type added concurrently (via [addProposal] during an await
  /// gap) will also be removed from local state — but since Dart is single-
  /// threaded, this only happens if an external event (e.g. watcher
  /// listener) fires between DB updates. The watcher will re-surface any
  /// truly pending proposals on its next poll cycle.
  Future<List<PendingProposal>> acceptAllOfType(String type) async {
    final matching = state.proposals.where((p) => p.proposalType == type).toList();
    final matchingIds = matching.map((p) => p.id).toSet();
    for (final p in matching) {
      await _updateStatus(p.id, 'accepted');
    }
    _emitFeedbackAll('accepted', matching);
    // Remove only the proposals we actually updated, not any that arrived
    // concurrently with the same type.
    state = ProposalState(
      proposals: state.proposals.where((p) => !matchingIds.contains(p.id)).toList(),
    );
    return matching;
  }

  /// Reject all proposals of a given type.
  ///
  /// Updates each proposal's DB status to 'rejected' and removes them from
  /// state. See [acceptAllOfType] for concurrency notes.
  Future<void> rejectAllOfType(String type) async {
    final matching = state.proposals.where((p) => p.proposalType == type).toList();
    final matchingIds = matching.map((p) => p.id).toSet();
    for (final p in matching) {
      await _updateStatus(p.id, 'rejected');
    }
    _emitFeedbackAll('rejected', matching);
    state = ProposalState(
      proposals: state.proposals.where((p) => !matchingIds.contains(p.id)).toList(),
    );
  }

  Future<void> _updateStatus(int id, String status) async {
    if (_db == null) return;
    try {
      await _db.customUpdate(
        'UPDATE mcp_proposal SET status = ? WHERE id = ?',
        variables: [
          Variable.withString(status),
          Variable.withInt(id),
        ],
        updates: {},
      );
    } catch (_) {
      // Best-effort DB update; don't block UI on transient errors.
    }
  }

  void _removeFromState(int id) {
    state = ProposalState(
      proposals: state.proposals.where((p) => p.id != id).toList(),
    );
  }

  /// Emits feedback for a single proposal still present in state.
  ///
  /// A decision on an id that is no longer in state (already consumed by a
  /// concurrent path) carries no title or type to report, so it is skipped.
  void _emitFeedback(String action, int id) {
    final matches = state.proposals.where((p) => p.id == id);
    if (matches.isEmpty) return;
    _emitFeedbackAll(action, [matches.first]);
  }

  void _emitFeedbackAll(String action, List<PendingProposal> proposals) {
    final feedback = _feedback;
    if (feedback == null || feedback.isClosed || proposals.isEmpty) return;
    feedback.add(ProposalFeedback(action: action, proposals: proposals));
  }
}

/// Universal proposal state provider.
///
/// Tracks all pending proposals across types (alarm, page, asset, key_mapping).
/// Feeds from [proposalWatcherProvider] and writes status changes back to DB.
final proposalStateProvider =
    StateNotifierProvider<ProposalStateNotifier, ProposalState>((ref) {
  final dbAsync = ref.watch(databaseProvider);
  final db = dbAsync.valueOrNull?.db;
  final notifier =
      ProposalStateNotifier(db, feedback: ref.watch(proposalFeedbackProvider));

  // Listen to ProposalWatcher and feed new proposals into universal state.
  ref.listen<ProposalWatcher?>(proposalWatcherProvider, (prev, next) {
    if (next == null) return;
    for (final p in next.pending) {
      notifier.addProposal(p);
    }
  });

  return notifier;
});


/// How the banner commits a staged proposal.
///
/// Applying a proposal and saving it belongs to the page editor -- it owns the
/// page data and the undo snapshot. The operator's accept/reject controls
/// belong in one place, the notification banner, rather than being duplicated
/// on an in-editor bar where one copy applied and the other silently did not.
/// The editor publishes its commit here while it is showing a staged
/// proposal; the banner calls it. Null when nothing is staged.
final proposalCommitProvider =
    StateProvider<Future<void> Function()?>((ref) => null);

/// How the banner discards a staged proposal.
///
/// Counterpart to [proposalCommitProvider]: reverting the staged edit needs
/// the editor's pre-proposal snapshot, which only the editor holds.
final proposalDiscardProvider =
    StateProvider<Future<void> Function()?>((ref) => null);
