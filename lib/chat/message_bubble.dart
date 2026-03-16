import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../drawings/drawing_action.dart';
import '../drawings/drawing_overlay.dart';
import '../llm/llm_models.dart';
import '../providers/proposal_state.dart';
import 'proposal_action.dart';
import 'tool_trace_widget.dart';

/// Renders a single chat message with role-specific styling.
///
/// - User messages: right-aligned with primary color background
/// - Assistant messages: left-aligned with surface color
/// - Tool result messages: left-aligned, indented, monospace
/// - Assistant messages with tool calls show [ToolTraceWidget]
/// - Messages containing proposal JSON show [ProposalAction]
/// - Messages containing drawing action JSON show "Open Drawing" button
class MessageBubble extends ConsumerWidget {
  /// The chat message to render.
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (message.role) {
      case ChatRole.user:
        return _buildUserBubble(context);
      case ChatRole.assistant:
        return _buildAssistantBubble(context, ref);
      case ChatRole.tool:
        return _buildToolResultBubble(context, ref);
      case ChatRole.system:
        return const SizedBox.shrink(); // System messages not displayed
    }
  }

  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        // Wrap in TextSelectionTheme so the selection highlight contrasts
        // against the primary-color bubble background.  The global theme
        // uses semi-transparent primary which is invisible on a primary bg.
        child: TextSelectionTheme(
          data: TextSelectionThemeData(
            selectionColor: Colors.white.withAlpha(90),
          ),
          child: SelectableText(
            message.content,
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(BuildContext context, WidgetRef ref) {
    final hasToolCalls = message.toolCalls.isNotEmpty;
    final proposalJson = _extractProposalJson(message.content);
    final drawingActionJson = _extractDrawingActionJson(message.content);

    // Check if this message has a pending proposal via proposalStateProvider
    final proposalState = ref.watch(proposalStateProvider);
    final hasPendingProposal = proposalJson != null &&
        proposalState.proposals.any((p) => p.proposalJson == proposalJson);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          // Amber border for bubbles containing pending proposals
          border: hasPendingProposal
              ? Border.all(color: Colors.amber, width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasToolCalls)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ToolTraceWidget(toolCalls: message.toolCalls),
              ),
            if (message.content.isNotEmpty)
              SelectableText(
                message.content,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            if (drawingActionJson != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildDrawingActionButton(context, ref, drawingActionJson),
              ),
            if (proposalJson != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ProposalAction(proposalJson: proposalJson),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolResultBubble(BuildContext context, WidgetRef ref) {
    final proposalJson = _extractProposalJson(message.content);
    final drawingActionJson = _extractDrawingActionJson(message.content);

    // When the tool result is a proposal, show a clean proposal card
    // instead of dumping raw JSON — operators don't need to see the JSON.
    if (proposalJson != null) {
      return _buildProposalToolResult(context, ref, proposalJson);
    }

    // When the tool result is a drawing action, show the drawing button
    // without the raw JSON clutter.
    if (drawingActionJson != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
          child: _buildDrawingActionButton(context, ref, drawingActionJson),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.build,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                message.content,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a prominent proposal card for tool results that contain a proposal.
  ///
  /// Instead of showing raw JSON (which is meaningless to operators), this
  /// renders a clean card with the proposal title, type, and a prominent
  /// "Open in Editor" button via [ProposalAction].
  Widget _buildProposalToolResult(
      BuildContext context, WidgetRef ref, String proposalJson) {
    // Parse the proposal to extract a human-readable summary
    String? title;
    String? proposalType;
    try {
      final parsed = jsonDecode(proposalJson) as Map<String, dynamic>;
      title = parsed['title'] as String? ?? parsed['key'] as String?;
      proposalType = parsed['_proposal_type'] as String?;
    } catch (_) {}

    final typeLabel = _proposalTypeLabel(proposalType);

    // Check if this proposal is still pending — amber border for pending,
    // subtle outline for processed (accepted/rejected/dismissed).
    final proposalState = ref.watch(proposalStateProvider);
    final isPending =
        proposalState.proposals.any((p) => p.proposalJson == proposalJson);
    final borderColor = isPending
        ? Colors.amber
        : Theme.of(context).colorScheme.outlineVariant;
    final borderWidth = isPending ? 1.5 : 0.5;
    final iconColor = isPending ? Colors.amber : Colors.grey;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$typeLabel Proposal${title != null ? ': $title' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProposalAction(proposalJson: proposalJson),
          ],
        ),
      ),
    );
  }

  /// Maps a proposal type string to a human-readable label.
  static String _proposalTypeLabel(String? type) {
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

  /// Builds the "Open Drawing" button for a _drawing_action response.
  Widget _buildDrawingActionButton(
      BuildContext context, WidgetRef ref, String json) {
    final parsed = jsonDecode(json) as Map<String, dynamic>;
    final name =
        parsed[DrawingAction.drawingName] as String? ?? 'Drawing';
    final page = parsed[DrawingAction.pageNumber] as int? ?? 1;
    final path = parsed[DrawingAction.filePath] as String?;
    final highlight = parsed[DrawingAction.highlightText] as String?;

    return ElevatedButton.icon(
      onPressed: path == null
          ? null
          : () {
              ref.read(activeDrawingTitleProvider.notifier).state = name;
              ref.read(activeDrawingBytesProvider.notifier).state = null;
              ref.read(activeDrawingPathProvider.notifier).state = path;
              ref.read(activeDrawingPageProvider.notifier).state = page;
              ref.read(activeDrawingHighlightProvider.notifier).state =
                  highlight;
              ref.read(drawingVisibleProvider.notifier).state = true;
            },
      icon: const Icon(Icons.electrical_services, size: 16),
      label: Text('Open $name (page $page)'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }

  /// Extracts drawing action JSON from message content using [DrawingAction] constants.
  String? _extractDrawingActionJson(String content) {
    if (!content.contains(DrawingAction.marker)) return null;
    // Try the entire content as JSON
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> &&
          DrawingAction.tryParse(decoded) != null) {
        return content;
      }
    } catch (_) {}
    // Try embedded JSON in code blocks
    final jsonPattern =
        RegExp(r'```(?:json)?\s*(\{[^`]*\})\s*```', dotAll: true);
    final match = jsonPattern.firstMatch(content);
    if (match != null) {
      final candidate = match.group(1)!;
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic> &&
            DrawingAction.tryParse(decoded) != null) {
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Extracts proposal JSON from message content if it contains _proposal_type.
  String? _extractProposalJson(String content) {
    if (!content.contains('_proposal_type')) return null;
    // Try to find a JSON block within the content
    try {
      // Check if the entire content is JSON
      final decoded = jsonDecode(content);
      if (decoded is Map && decoded.containsKey('_proposal_type')) {
        return content;
      }
    } catch (_) {
      // Not pure JSON; try to find embedded JSON
    }
    // Try to extract JSON from markdown code blocks
    final jsonPattern =
        RegExp(r'```(?:json)?\s*(\{[^`]*\})\s*```', dotAll: true);
    final match = jsonPattern.firstMatch(content);
    if (match != null) {
      final candidate = match.group(1)!;
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map && decoded.containsKey('_proposal_type')) {
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }
}
