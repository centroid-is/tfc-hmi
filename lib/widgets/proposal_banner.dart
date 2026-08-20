import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/navigator_key.dart';
import '../providers/proposal_state.dart';

/// Persistent banner displayed at the top of the app when AI proposals are pending.
///
/// NEVER auto-dismisses -- stays visible until the operator explicitly accepts,
/// rejects, or dismisses every pending proposal.
///
/// Positioned in the main.dart builder Stack (same pattern as ChatOverlay).
class ProposalBanner extends ConsumerStatefulWidget {
  const ProposalBanner({super.key});

  @override
  ConsumerState<ProposalBanner> createState() => _ProposalBannerState();
}

class _ProposalBannerState extends ConsumerState<ProposalBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(proposalStateProvider);
    if (!state.hasPending) return const SizedBox.shrink();

    // Stay visible on the editor page too. The in-editor bar is now purely
    // informational (title + the change list), so hiding here would leave the
    // operator on a page showing a staged edit with no way to accept it.
    final proposals = state.proposals;
    if (proposals.isEmpty) return const SizedBox.shrink();
    final count = proposals.length;

    return Positioned(
      key: const ValueKey('proposal-banner'),
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        elevation: 8,
        child: Container(
          color: Colors.grey.shade900,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SafeArea(
            bottom: false,
            child: count == 1
                ? _buildSingleProposal(proposals.first)
                : _buildMultipleProposals(proposals, count),
          ),
        ),
      ),
    );
  }

  Widget _buildSingleProposal(PendingProposal proposal) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
        const SizedBox(width: 10),
        _ActionChip(proposal.action),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'AI Proposal: ${proposal.title}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _buildViewButton(proposal),
        const SizedBox(width: 4),
        _buildAcceptButton(proposal.id),
        const SizedBox(width: 4),
        _buildRejectButton(proposal.id),
      ],
    );
  }

  Widget _buildMultipleProposals(
      List<PendingProposal> proposals, int count) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The collapsed header is all most operators read before
              // pressing Accept all, so say up front what the batch does:
              // "3 create · 1 delete" reads very differently from "4".
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: '$count AI Proposals',
                    children: [
                      TextSpan(
                        text: '   ${_actionSummary(proposals)}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Accepting twenty-one bindings one row at a time is not review,
              // it is data entry -- the operator has already read the list.
              // Kept beside the count so it is reachable without expanding.
              _buildAcceptAllButton(proposals),
              const SizedBox(width: 4),
              _buildRejectAllButton(proposals),
              const SizedBox(width: 4),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white70,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const Divider(color: Colors.white24, height: 16),
          // Twenty-one rows would push the page off the bottom of the screen.
          // Cap the drawer and scroll inside it instead.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              shrinkWrap: true,
              children: proposals.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const SizedBox(width: 30),
                  _ActionChip(p.action),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${p.editorLabel}: ${p.title}',
                      style: const TextStyle(color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildViewButton(p),
                  const SizedBox(width: 4),
                  _buildAcceptButton(p.id),
                  const SizedBox(width: 4),
                  _buildRejectButton(p.id),
                ],
              ),
            ),
              ).toList(),
            ),
          ),
        ],
      ],
    );
  }

  /// Opens the editor with the whole queue still pending.
  ///
  /// Deliberately NOT acceptProposal() per item: that marks a proposal
  /// accepted in the database and drops it from state without ever applying
  /// the patch to the page, so the edit is silently lost. The apply happens
  /// in the editor, which consumes proposals while they are still pending and
  /// folds a run of asset_update into a single edit -- reviewed once, saved
  /// once, and marked accepted only once that save has persisted.
  Widget _buildAcceptAllButton(List<PendingProposal> proposals) {
    return TextButton.icon(
      onPressed: () {
        // Staged already? Commit it. The editor applied the batch and
        // published its save here; calling it applies and persists, and the
        // proposals are marked accepted as part of that save.
        final commit = ref.read(proposalCommitProvider);
        if (commit != null) {
          commit();
          return;
        }
        // Otherwise open the editor, which stages the whole pending queue
        // and publishes its commit -- then this button accepts.
        final route = proposals.first.editorRoute;
        if (route == null) return;
        try {
          final navKey = ref.read(navigatorKeyProvider);
          final ctx = navKey?.currentContext ?? context;
          Beamer.of(ctx).beamToNamed(route, data: proposals.first.proposalJson);
        } catch (_) {
          // Beamer not available -- ignore
        }
      },
      icon: const Icon(Icons.done_all, size: 16),
      label: Text(ref.watch(proposalCommitProvider) != null
          ? 'Accept all (${proposals.length})'
          : 'Review all (${proposals.length})'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.greenAccent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// Drops the whole queue, reverting the editor if it has staged it.
  ///
  /// Mirrors accept-all: once the editor has applied the batch, rejecting has
  /// to undo those edits as well as mark the rows rejected, or the operator is
  /// left with an unsaved page full of changes and no proposals explaining
  /// them. Without a staged batch there is nothing to revert, so plain
  /// rejectProposal per row is the whole job.
  Widget _buildRejectAllButton(List<PendingProposal> proposals) {
    return TextButton.icon(
      onPressed: () {
        final discard = ref.read(proposalDiscardProvider);
        if (discard != null) {
          discard();
          return;
        }
        final notifier = ref.read(proposalStateProvider.notifier);
        for (final p in proposals) {
          notifier.rejectProposal(p.id);
        }
      },
      icon: const Icon(Icons.close, size: 16),
      label: Text('Reject all (${proposals.length})'),
      style: TextButton.styleFrom(
        foregroundColor: Colors.redAccent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildAcceptButton(int id) {
    return TextButton(
      onPressed: () {
        ref.read(proposalStateProvider.notifier).acceptProposal(id);
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.green,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Accept'),
    );
  }

  Widget _buildRejectButton(int id) {
    return TextButton(
      onPressed: () {
        ref.read(proposalStateProvider.notifier).rejectProposal(id);
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Reject'),
    );
  }

  Widget _buildViewButton(PendingProposal proposal) {
    return TextButton(
      onPressed: () {
        final route = proposal.editorRoute;
        if (route != null) {
          try {
            final navKey = ref.read(navigatorKeyProvider);
            final ctx = navKey?.currentContext ?? context;
            Beamer.of(ctx).beamToNamed(route, data: proposal.proposalJson);
          } catch (_) {
            // Beamer not available -- ignore
          }
        }
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.blue,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('View'),
    );
  }

  /// "2 create · 1 edit · 1 delete", listing only the actions present.
  String _actionSummary(List<PendingProposal> proposals) {
    final counts = <ProposalOp, int>{};
    for (final p in proposals) {
      counts[p.action] = (counts[p.action] ?? 0) + 1;
    }
    return [
      if (counts.containsKey(ProposalOp.create))
        '${counts[ProposalOp.create]} create',
      if (counts.containsKey(ProposalOp.update))
        '${counts[ProposalOp.update]} edit',
      if (counts.containsKey(ProposalOp.delete))
        '${counts[ProposalOp.delete]} delete',
    ].join(' · ');
  }
}

/// Small labelled tag saying what accepting the proposal does: CREATE,
/// EDIT, or DELETE.
///
/// A title like "conveyor.speed" reads identically whether the AI wants to
/// add the mapping or remove it; the operator should not have to open the
/// editor to find out which. Delete gets the same red as Reject on purpose:
/// it is the row where accepting destroys something.
class _ActionChip extends StatelessWidget {
  const _ActionChip(this.action);

  final ProposalOp action;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (action) {
      ProposalOp.create => ('CREATE', Icons.add, Colors.greenAccent),
      ProposalOp.update => ('EDIT', Icons.edit, Colors.lightBlueAccent),
      ProposalOp.delete =>
        ('DELETE', Icons.delete_outline, Colors.redAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(140)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
