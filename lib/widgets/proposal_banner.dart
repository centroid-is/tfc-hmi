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

  /// Returns the current Beamer route path, or null if unavailable.
  String? _currentRoutePath() {
    try {
      final navKey = ref.read(navigatorKeyProvider);
      final ctx = navKey?.currentContext;
      if (ctx == null) return null;
      return Beamer.of(ctx)
          .currentBeamLocation
          .state
          .routeInformation
          .uri
          .path;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(proposalStateProvider);
    if (!state.hasPending) return const SizedBox.shrink();

    // Hide proposals whose editor page is currently visible (the amber
    // in-editor banner handles those).
    final currentPath = _currentRoutePath();
    final proposals = currentPath != null
        ? state.proposals
            .where((p) =>
                p.editorRoute == null || !currentPath.contains(p.editorRoute!))
            .toList()
        : state.proposals;
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
              Text(
                '$count AI Proposals',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white70,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const Divider(color: Colors.white24, height: 16),
          ...proposals.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const SizedBox(width: 30),
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
          ),
        ],
      ],
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
}
