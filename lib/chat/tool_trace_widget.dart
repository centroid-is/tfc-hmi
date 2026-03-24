import 'dart:convert';

import 'package:flutter/material.dart';

import '../llm/llm_models.dart';
import '../providers/chat.dart';

/// A collapsible tool invocation trace widget.
///
/// Shows which tools were called with their arguments and execution status.
/// Displayed within assistant message bubbles that contain tool calls.
class ToolTraceWidget extends StatefulWidget {
  /// The tool calls to display.
  final List<ToolCall> toolCalls;

  /// Optional progress indicators (used during active execution).
  final List<ToolProgress>? progress;

  const ToolTraceWidget({
    super.key,
    required this.toolCalls,
    this.progress,
  });

  @override
  State<ToolTraceWidget> createState() => _ToolTraceWidgetState();
}

class _ToolTraceWidgetState extends State<ToolTraceWidget> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    // Expanded during active execution, collapsed otherwise
    _isExpanded = widget.progress != null &&
        widget.progress!.any((p) => p.status == 'Running...');
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.toolCalls.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.build,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'Tools used ($count)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Column(
              children: widget.toolCalls.asMap().entries.map((entry) {
                final index = entry.key;
                final tc = entry.value;
                final progressItem = (widget.progress != null &&
                        index < widget.progress!.length)
                    ? widget.progress![index]
                    : null;

                return _buildToolEntry(context, tc, progressItem);
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildToolEntry(
      BuildContext context, ToolCall toolCall, ToolProgress? progress) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildStatusIcon(progress),
              const SizedBox(width: 6),
              Text(
                toolCall.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    progress.status,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          if (toolCall.arguments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                _formatArguments(toolCall.arguments),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(ToolProgress? progress) {
    if (progress == null) {
      return const Icon(Icons.check_circle, size: 14, color: Colors.green);
    }

    switch (progress.status) {
      case 'Running...':
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'Done':
        return const Icon(Icons.check_circle, size: 14, color: Colors.green);
      case 'Error':
        return const Icon(Icons.error, size: 14, color: Colors.red);
      default:
        return const Icon(Icons.circle, size: 14, color: Colors.grey);
    }
  }

  String _formatArguments(Map<String, dynamic> args) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(args);
    } catch (_) {
      return args.toString();
    }
  }
}
