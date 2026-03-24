import 'package:mcp_dart/mcp_dart.dart';

import '../services/alarm_context_service.dart';

/// Registers the `explain_alarm` MCP prompt on [mcpServer].
///
/// This prompt provides structured context for why a specific alarm fired,
/// using [AlarmContextService] to build a causal chain with correlated tag
/// values, trend data, chronological events, and alarm rule definitions.
/// It instructs the LLM to show source data, list multiple possible causes,
/// and label output as AI-generated.
///
/// **Causal chain:** AlarmContextService correlates alarm history, sibling
/// alarms, tag values, and trend data into a structured [AlarmContext] that
/// enables precise, data-backed AI explanations.
void registerExplainAlarmPrompt(
  McpServer mcpServer,
  AlarmContextService alarmContextService,
) {
  mcpServer.registerPrompt(
    'explain_alarm',
    description:
        'Explain why a specific alarm fired with correlated signals and '
        'source data evidence',
    argsSchema: {
      'alarm_uid': PromptArgumentDefinition(
        description: 'The UID of the alarm to explain',
        required: true,
      ),
    },
    callback: (Map<String, dynamic>? args,
        [RequestHandlerExtra? extra]) async {
      // Validate alarm_uid argument
      final alarmUid = args?['alarm_uid'] as String?;
      if (alarmUid == null || alarmUid.isEmpty) {
        return GetPromptResult(
          description: 'Error: alarm_uid is required',
          messages: [
            PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(
                text: 'Error: alarm_uid argument is required. '
                    'Please provide the UID of the alarm to explain.',
              ),
            ),
          ],
        );
      }

      // Build structured alarm context via AlarmContextService
      final context = await alarmContextService.buildContext(alarmUid);
      if (context == null) {
        return GetPromptResult(
          description: 'Error: alarm not found',
          messages: [
            PromptMessage(
              role: PromptMessageRole.user,
              content: TextContent(
                text: 'Error: Alarm with UID "$alarmUid" was not found. '
                    'Please verify the alarm UID and try again.',
              ),
            ),
          ],
        );
      }

      // Assemble the structured prompt message
      final promptText = '''
You are an industrial SCADA operator assistant. Explain why the following alarm fired based on the source data provided below.

RULES:
1. Label your response as "AI-generated analysis" at the top
2. Always show the source data (tag values, alarm history) alongside your conclusions
3. List at least 2-3 possible causes based on the evidence
4. Never make bare assertions without citing specific data values
5. If data is insufficient, say so explicitly rather than speculating
6. Include a "What else to check" section with suggested investigation steps

${context.toText()}

Based on this data, explain why this alarm fired.''';

      return GetPromptResult(
        description: 'Explain alarm $alarmUid',
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
