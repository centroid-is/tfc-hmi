import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Shows an elicitation dialog for an MCP elicitation request.
///
/// The dialog displays the request message (which may contain markdown-style
/// formatting from [ElicitationRiskGate]) and presents Confirm/Deny buttons.
///
/// Returns the [ElicitResult] via the provided [completer]:
/// - **Confirm**: `action: 'accept', content: {'confirm': true}`
/// - **Deny**: `action: 'decline'`
/// - **Dismiss** (tap outside): `action: 'cancel'`
void showElicitationDialog({
  required BuildContext context,
  required ElicitRequest request,
  required Completer<ElicitResult> completer,
}) {
  showDialog<ElicitResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (dialogContext) {
      return _ElicitationDialogContent(
        request: request,
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          if (!completer.isCompleted) {
            completer.complete(const ElicitResult(
              action: 'accept',
              content: {'confirm': true},
            ));
          }
        },
        onDeny: () {
          Navigator.of(dialogContext).pop();
          if (!completer.isCompleted) {
            completer.complete(const ElicitResult(action: 'decline'));
          }
        },
      );
    },
  ).then((_) {
    // If dialog was dismissed without pressing a button (barrier tap),
    // complete with cancel.
    if (!completer.isCompleted) {
      completer.complete(const ElicitResult(action: 'cancel'));
    }
  });
}

/// Internal dialog content widget.
class _ElicitationDialogContent extends StatelessWidget {
  final ElicitRequest request;
  final VoidCallback onConfirm;
  final VoidCallback onDeny;

  const _ElicitationDialogContent({
    required this.request,
    required this.onConfirm,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parseMessage(request.message);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Row(
        children: [
          Icon(
            Icons.help_outline,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text('Confirm Action'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 400),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Risk level badge
              if (parsed.riskLevel != null) ...[
                _buildRiskBadge(context, parsed.riskLevel!),
                const SizedBox(height: 12),
              ],
              // Description
              if (parsed.description.isNotEmpty) ...[
                Text(
                  parsed.description,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
              ],
              // Detail fields
              if (parsed.details.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: 8),
                ...parsed.details.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(
                            '${entry.key}:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('elicitation-deny'),
          onPressed: onDeny,
          child: const Text('Deny'),
        ),
        FilledButton(
          key: const ValueKey<String>('elicitation-confirm'),
          onPressed: onConfirm,
          child: const Text('Confirm'),
        ),
      ],
    );
  }

  Widget _buildRiskBadge(BuildContext context, String level) {
    final theme = Theme.of(context);
    final color = _riskColor(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Risk: ${level.toUpperCase()}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _riskColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      case 'medium':
        return Colors.amber.shade700;
      case 'low':
        return Colors.green.shade700;
      default:
        return Colors.grey;
    }
  }
}

/// Parsed representation of an elicitation message.
class _ParsedMessage {
  final String? riskLevel;
  final String description;
  final Map<String, String> details;

  const _ParsedMessage({
    this.riskLevel,
    required this.description,
    required this.details,
  });
}

/// Parses the markdown-style message from [ElicitationRiskGate._buildMessage].
///
/// Expected format:
/// ```
/// **Risk Level:** HIGH
///
/// Create alarm "Pump Overcurrent"
///
/// ---
///
/// **title:** Pump Overcurrent
/// **description:** Current exceeds threshold
/// **rules:** warning: pump.current > 15
/// ```
_ParsedMessage _parseMessage(String message) {
  String? riskLevel;
  final details = <String, String>{};
  final descriptionLines = <String>[];
  bool inDetails = false;

  for (final line in message.split('\n')) {
    final trimmed = line.trim();

    // Skip empty lines and separators
    if (trimmed.isEmpty) continue;
    if (trimmed == '---') {
      inDetails = true;
      continue;
    }

    // Parse **Risk Level:** VALUE
    final riskMatch = RegExp(r'\*\*Risk Level:\*\*\s*(.+)').firstMatch(trimmed);
    if (riskMatch != null) {
      riskLevel = riskMatch.group(1)?.trim();
      continue;
    }

    // Parse **key:** value (detail fields after ---)
    if (inDetails) {
      final detailMatch = RegExp(r'\*\*(.+?):\*\*\s*(.+)').firstMatch(trimmed);
      if (detailMatch != null) {
        details[detailMatch.group(1)!] = detailMatch.group(2)!;
        continue;
      }
    }

    // Everything else is description
    descriptionLines.add(trimmed);
  }

  return _ParsedMessage(
    riskLevel: riskLevel,
    description: descriptionLines.join('\n'),
    details: details,
  );
}
