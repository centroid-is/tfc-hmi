import 'dart:convert';

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/navigator_key.dart';
import '../providers/proposal_state.dart';
import '../providers/proposal_watcher.dart';

/// Displays a summary card when multiple proposals of the same type are
/// pending, with "Accept All" and "Reject All" batch actions.
///
/// This widget watches [proposalStateProvider] and groups proposals by type.
/// For each type with 2+ pending proposals, it shows a summary bar with
/// the count and batch action buttons.
///
/// When "Accept All" is tapped, proposals are accepted in batch and the
/// first one is opened in the editor. The remaining proposals are accepted
/// but not navigated to — the user can open them individually from the
/// editor's proposal queue.
class BatchProposalSummary extends ConsumerWidget {
  const BatchProposalSummary({super.key});

  /// Returns a [BuildContext] that is a descendant of the app Navigator.
  BuildContext _navContext(WidgetRef ref, BuildContext fallback) {
    final key = ref.read(navigatorKeyProvider);
    return key?.currentContext ?? fallback;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposalState = ref.watch(proposalStateProvider);

    if (!proposalState.hasPending) return const SizedBox.shrink();

    // Group proposals by type
    final grouped = <String, List<PendingProposal>>{};
    for (final p in proposalState.proposals) {
      (grouped[p.proposalType] ??= []).add(p);
    }

    // Only show summary for types with 2+ proposals
    final batchTypes =
        grouped.entries.where((e) => e.value.length >= 2).toList();

    if (batchTypes.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in batchTypes)
          _buildBatchCard(context, ref, entry.key, entry.value),
      ],
    );
  }

  Widget _buildBatchCard(
    BuildContext context,
    WidgetRef ref,
    String type,
    List<PendingProposal> proposals,
  ) {
    final typeLabel = _typeLabel(type);
    final count = proposals.length;

    return Container(
      key: ValueKey<String>('batch-proposal-$type'),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb, size: 18, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count $typeLabel proposals pending',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          TextButton(
            key: ValueKey<String>('batch-reject-all-$type'),
            onPressed: () async {
              await ref
                  .read(proposalStateProvider.notifier)
                  .rejectAllOfType(type);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Reject All',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            key: ValueKey<String>('batch-accept-all-$type'),
            onPressed: () async {
              final accepted = await ref
                  .read(proposalStateProvider.notifier)
                  .acceptAllOfType(type);

              if (accepted.isEmpty) return;

              // Navigate to the editor with the first proposal
              final route = accepted.first.editorRoute;
              if (route != null && context.mounted) {
                try {
                  Beamer.of(_navContext(ref, context)).beamToNamed(
                    route,
                    data: accepted.first.proposalJson,
                  );
                } catch (_) {
                  // Beamer not available — best effort.
                }
              }
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text('Accept All ($count)'),
          ),
        ],
      ),
    );
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'alarm':
      case 'alarm_create':
      case 'alarm_update':
        return 'Alarm';
      case 'key_mapping':
        return 'Key Mapping';
      case 'page':
        return 'Page';
      case 'asset':
        return 'Asset';
      default:
        return 'Config';
    }
  }
}
