import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/alarm_service.dart';
import '../services/tag_service.dart';

/// Registers the `shift_handover` prompt on [mcpServer].
///
/// This prompt generates a structured shift handover summary covering alarms,
/// acknowledgements, and anomalies over a configurable time window. It
/// pre-fetches alarm history, active alarms, and current tag values, then
/// assembles instructions for the LLM to produce a data-backed summary.
///
/// Accepts an optional `hours` argument (default 8, clamped to 1-72).
/// Invalid values fall back to the 8-hour default.
///
/// The prompt mandates automation bias mitigations:
/// - AI-generated labeling at the top of the response
/// - Source alarm records shown alongside the summary
/// - A "Verify" section for incoming operator physical checks
void registerShiftHandoverPrompt(
  McpServer mcpServer,
  AlarmService alarmService,
  TagService tagService,
) {
  mcpServer.registerPrompt(
    'shift_handover',
    description:
        'Generate a structured shift handover summary covering alarms, '
        'acknowledgements, and anomalies over a configurable time period',
    argsSchema: {
      'hours': PromptArgumentDefinition(
        description:
            'Time window in hours (default: 8, typical shift lengths: 8 or 12)',
        required: false,
      ),
    },
    callback: (args, extra) async {
      // Parse hours from args, default 8, clamp to 1-72
      var hours = 8;
      if (args != null && args.containsKey('hours')) {
        final parsed = int.tryParse(args['hours'].toString());
        if (parsed != null) {
          hours = parsed.clamp(1, 72);
        }
      }

      final now = DateTime.now().toUtc();
      final after = now.subtract(Duration(hours: hours));

      // Fetch data from services
      final alarmHistory =
          await alarmService.queryHistory(after: after, limit: 500);
      final activeAlarms = await alarmService.listActiveAlarms(limit: 100);
      final tagValues = tagService.listTags(limit: 50);

      // Compute summary statistics
      final totalFired = alarmHistory.length;
      final acknowledgedCount = alarmHistory
          .where((a) => a.containsKey('acknowledgedAt'))
          .length;
      final activeCount = activeAlarms.length;
      final uniqueAlarmUids = alarmHistory
          .map((a) => a['alarmUid'] as String?)
          .where((uid) => uid != null)
          .toSet()
          .length;

      final encoder = const JsonEncoder.withIndent('  ');

      final promptText = '''
You are an industrial SCADA operator assistant preparing a shift handover summary.
Summarize the operational events from the last $hours hours for the incoming operator.

RULES:
1. Label your response as "AI-generated shift handover summary" at the top
2. Show the source alarm records in a table alongside your summary
3. Organize into sections: "Alarms Fired", "Acknowledgements", "Currently Active", "Anomalies & Notes"
4. Flag any alarm that fired multiple times (recurring pattern)
5. If data is sparse, say "quiet shift" rather than inventing issues
6. Include a "Verify" section listing items the incoming operator should physically check

## Time Window
Last $hours hours (from ${after.toIso8601String()} to ${now.toIso8601String()})

## Summary Statistics
- Total alarms fired: $totalFired
- Acknowledged: $acknowledgedCount
- Currently active: $activeCount
- Unique alarm sources: $uniqueAlarmUids

## Alarm History (Last $hours Hours)
${encoder.convert(alarmHistory)}

## Currently Active Alarms
${encoder.convert(activeAlarms)}

## Current System State (Tag Values)
${encoder.convert(tagValues)}

Provide a structured shift handover summary based on this data.''';

      return GetPromptResult(
        description:
            'Shift handover summary for the last $hours hours',
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(text: promptText),
          ),
        ],
      );
    },
  );
}
