import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'proposal.dart';

export 'proposal.dart'
    show PendingProposal, ProposalOp, nextLocalProposalId, proposalRoutes;

/// Prefix marking operator-decision notes in the chat conversation.
///
/// Notes carry the user role so every LLM provider keeps them in
/// chronological order (Claude hoists system-role messages into the system
/// parameter), and the prefix lets [MessageBubble] hide them -- they are
/// feedback for the AI, not something the operator needs shown back.
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
/// Lives outside [proposalStateProvider] so the chat lifecycle can subscribe
/// once, independently of the notifier's own lifetime.
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

/// Holds the proposals the operator has not decided on yet.
///
/// Nothing here is persisted. A proposal exists from the moment a write tool
/// hands it to the UI until the operator accepts, rejects or dismisses it.
/// Accepting is what makes it durable, and that write belongs to the editor.
class ProposalStateNotifier extends StateNotifier<ProposalState> {
  ProposalStateNotifier({StreamController<ProposalFeedback>? feedback})
      : _feedback = feedback,
        super(const ProposalState());

  final StreamController<ProposalFeedback>? _feedback;

  /// Proposals already reported as viewed, so re-opening an editor does not
  /// spam the AI with repeat notes.
  final _viewedIds = <int>{};

  /// Add a proposal if it is not already present.
  ///
  /// Deduplicates by both id and proposal JSON content. The JSON check is the
  /// one that does the work: an in-app tool call surfaces the same proposal
  /// twice, once from the server's proposal callback and once from the tool
  /// result, and those two carry different locally-minted ids but identical
  /// JSON -- the write tool returns the encoding of the very map the callback
  /// was handed.
  void addProposal(PendingProposal proposal) {
    if (state.proposals.any((p) =>
        p.id == proposal.id || p.proposalJson == proposal.proposalJson)) {
      return;
    }
    state = ProposalState(
      proposals: [...state.proposals, proposal],
    );
  }

  /// Accept a proposal: report the decision and drop it from state.
  ///
  /// The `async` suspends nothing now that there is no write to wait for, so
  /// the removal lands in the caller's own microtask. That is what closes the
  /// "yellow boxes came back" race: a batch accept fired these without
  /// awaiting the database round trip inside, and the editor's listener
  /// re-staged whatever had not been removed yet. The [Future] stays because
  /// every editor call site awaits it.
  Future<void> acceptProposal(int id) async {
    _emitFeedback('accepted', id);
    _removeFromState(id);
  }

  /// Reject a proposal: report the decision and drop it from state.
  Future<void> rejectProposal(int id) async {
    _emitFeedback('rejected', id);
    _removeFromState(id);
  }

  /// Dismiss a proposal: report the decision and drop it from state.
  Future<void> dismissProposal(int id) async {
    _emitFeedback('dismissed', id);
    _removeFromState(id);
  }

  /// Record that the operator opened a proposal in its editor.
  ///
  /// Keeps the proposal pending -- a look is not a decision. Reported to the
  /// AI once per proposal.
  Future<void> viewProposal(int id) async {
    if (!state.proposals.any((p) => p.id == id)) return;
    if (!_viewedIds.add(id)) return;
    _emitFeedback('viewed', id);
  }

  /// Accept all proposals of a given type.
  ///
  /// Returns the accepted proposals so the caller can route them to editors.
  /// Removes exactly the ids it reported on, so a proposal that arrives in
  /// the meantime stays pending rather than being silently swallowed.
  Future<List<PendingProposal>> acceptAllOfType(String type) async {
    final matching =
        state.proposals.where((p) => p.proposalType == type).toList();
    final matchingIds = matching.map((p) => p.id).toSet();
    _emitFeedbackAll('accepted', matching);
    state = ProposalState(
      proposals:
          state.proposals.where((p) => !matchingIds.contains(p.id)).toList(),
    );
    return matching;
  }

  /// Reject all proposals of a given type. See [acceptAllOfType].
  Future<void> rejectAllOfType(String type) async {
    final matching =
        state.proposals.where((p) => p.proposalType == type).toList();
    final matchingIds = matching.map((p) => p.id).toSet();
    _emitFeedbackAll('rejected', matching);
    state = ProposalState(
      proposals:
          state.proposals.where((p) => !matchingIds.contains(p.id)).toList(),
    );
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
/// Tracks all pending proposals across types (alarm, page, asset,
/// key_mapping). Fed by `ChatNotifier`, which is where the MCP server's
/// proposal callback lands. Deliberately depends on nothing else: it used to
/// watch the database connection, so a reconnect rebuilt the notifier and
/// dropped every proposal the operator had not yet acted on.
final proposalStateProvider =
    StateNotifierProvider<ProposalStateNotifier, ProposalState>((ref) {
  return ProposalStateNotifier(feedback: ref.watch(proposalFeedbackProvider));
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

/// How the banner hands a proposal to an editor that is already on screen.
///
/// The banner's View and "Review all" beam to the proposal's editor route.
/// That works from anywhere else in the app, but not from the editor itself:
/// beaming to the route you are already on rebuilds the route's *builder*
/// and not the page it built. Flutter's page-based routes only re-run
/// `buildPage` on `changedExternalState`, and a settings change routes
/// through `changedInternalState` instead -- so the freshly built
/// `PageEditor(proposalData: ...)` is thrown away, the mounted one never sees
/// the new proposal, and `didUpdateWidget` never runs.
///
/// So the mounted editor publishes a way in. While it is up, the banner calls
/// this instead of beaming; with nothing published, the beam is still the
/// right answer because the editor has to be built in the first place.
class ProposalReviewEntry {
  const ProposalReviewEntry({required this.route, required this.enter});

  /// The editor route this entry serves, e.g. `/advanced/page-editor`.
  ///
  /// Checked against [PendingProposal.editorRoute] before use: an alarm
  /// proposal must not be handed to the page editor just because the page
  /// editor happens to be the screen in front of the operator.
  final String route;

  /// Routes the open editor to the proposal and stages it, the same thing a
  /// cold open does through `initState`.
  final void Function(String proposalJson) enter;
}

/// The editor currently on screen, if it is one that can take a proposal.
///
/// Null whenever no such editor is mounted. See [ProposalReviewEntry].
final proposalReviewProvider =
    StateProvider<ProposalReviewEntry?>((ref) => null);
