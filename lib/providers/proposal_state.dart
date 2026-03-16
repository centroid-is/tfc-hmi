import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/mcp_database.dart';

import 'proposal_watcher.dart';
import 'database.dart' show databaseProvider;

export 'proposal_watcher.dart' show PendingProposal;

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
  ProposalStateNotifier(this._db) : super(const ProposalState());

  final McpDatabase? _db;

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
    _removeFromState(id);
  }

  /// Reject a proposal: update DB status to 'rejected' and remove from state.
  Future<void> rejectProposal(int id) async {
    await _updateStatus(id, 'rejected');
    _removeFromState(id);
  }

  /// Dismiss a proposal: update DB status to 'dismissed' and remove from state.
  Future<void> dismissProposal(int id) async {
    await _updateStatus(id, 'dismissed');
    _removeFromState(id);
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
}

/// Universal proposal state provider.
///
/// Tracks all pending proposals across types (alarm, page, asset, key_mapping).
/// Feeds from [proposalWatcherProvider] and writes status changes back to DB.
final proposalStateProvider =
    StateNotifierProvider<ProposalStateNotifier, ProposalState>((ref) {
  final dbAsync = ref.watch(databaseProvider);
  final db = dbAsync.valueOrNull?.db;
  final notifier = ProposalStateNotifier(db);

  // Listen to ProposalWatcher and feed new proposals into universal state.
  ref.listen<ProposalWatcher?>(proposalWatcherProvider, (prev, next) {
    if (next == null) return;
    for (final p in next.pending) {
      notifier.addProposal(p);
    }
  });

  return notifier;
});
