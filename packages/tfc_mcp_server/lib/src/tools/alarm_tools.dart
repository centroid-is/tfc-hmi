import 'package:mcp_dart/mcp_dart.dart';

import '../services/alarm_service.dart';
import 'tool_registry.dart';

/// Registers alarm MCP tools with the given [ToolRegistry].
///
/// Three tools implementing progressive discovery:
/// - **list_alarms** (Level 1): Overview of active alarms
/// - **get_alarm_detail** (Level 2): Full config for a specific alarm
/// - **query_alarm_history** (Level 3): Historical records with filtering
void registerAlarmTools(ToolRegistry registry, AlarmService alarmService) {
  _registerListAlarms(registry, alarmService);
  _registerGetAlarmDetail(registry, alarmService);
  _registerQueryAlarmHistory(registry, alarmService);
}

void _registerListAlarms(ToolRegistry registry, AlarmService alarmService) {
  registry.registerTool(
    name: 'list_alarms',
    description: 'List currently active alarms with severity, '
        'title, description, and activation time. '
        'Do NOT use if you already have the alarm UID — call '
        'get_alarm_detail directly instead.',
    inputSchema: JsonSchema.object(
      properties: {
        'limit': JsonSchema.integer(
          description: 'Maximum number of alarms to return (1-200, default 50)',
          minimum: 1,
          maximum: 200,
          defaultValue: 50,
        ),
      },
    ),
    handler: (arguments, extra) async {
      final limit = (arguments['limit'] as num?)?.toInt() ?? 50;
      final alarms = await alarmService.listActiveAlarms(limit: limit);

      if (alarms.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No active alarms.')],
        );
      }

      final buffer = StringBuffer();
      for (final alarm in alarms) {
        buffer.writeln(
            '[${alarm['alarmLevel']}] ${alarm['alarmTitle']}');
        buffer.writeln('  ${alarm['alarmDescription']}');
        buffer.writeln('  Since: ${alarm['createdAt']}');
        buffer.writeln();
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}

void _registerGetAlarmDetail(
    ToolRegistry registry, AlarmService alarmService) {
  registry.registerTool(
    name: 'get_alarm_detail',
    description: 'Get full alarm configuration including key mapping, '
        'description, and rules for a specific alarm. '
        'Call directly when you have the alarm UID — do NOT call '
        'list_alarms first.',
    inputSchema: JsonSchema.object(
      properties: {
        'uid': JsonSchema.string(
          description: 'The unique identifier of the alarm',
        ),
      },
      required: ['uid'],
    ),
    handler: (arguments, extra) async {
      final uid = arguments['uid'] as String;
      final detail = alarmService.getAlarmDetail(uid);

      if (detail == null) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'No alarm found with UID: $uid'),
          ],
          isError: true,
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Alarm: ${detail['title']}');
      buffer.writeln('UID: ${detail['uid']}');
      if (detail['key'] != null) {
        buffer.writeln('Key: ${detail['key']}');
      }
      buffer.writeln('Description: ${detail['description']}');
      buffer.writeln('Rules: ${detail['rules']}');

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}

void _registerQueryAlarmHistory(
    ToolRegistry registry, AlarmService alarmService) {
  registry.registerTool(
    name: 'query_alarm_history',
    description: 'Search alarm history by time range and/or alarm UID. '
        'Returns historical alarm activations and deactivations.',
    inputSchema: JsonSchema.object(
      properties: {
        'after': JsonSchema.string(
          description: 'Start of time range (ISO 8601 format)',
          format: 'date-time',
        ),
        'before': JsonSchema.string(
          description: 'End of time range (ISO 8601 format)',
          format: 'date-time',
        ),
        'alarm_uid': JsonSchema.string(
          description: 'Filter by specific alarm UID',
        ),
        'limit': JsonSchema.integer(
          description:
              'Maximum number of records to return (1-500, default 100)',
          minimum: 1,
          maximum: 500,
          defaultValue: 100,
        ),
      },
    ),
    handler: (arguments, extra) async {
      final afterStr = arguments['after'] as String?;
      final beforeStr = arguments['before'] as String?;
      final alarmUid = arguments['alarm_uid'] as String?;
      final limit = (arguments['limit'] as num?)?.toInt() ?? 100;

      final after = afterStr != null ? DateTime.parse(afterStr) : null;
      final before = beforeStr != null ? DateTime.parse(beforeStr) : null;

      final results = await alarmService.queryHistory(
        after: after,
        before: before,
        alarmUid: alarmUid,
        limit: limit,
      );

      if (results.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No alarm history found.')],
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Alarm History (${results.length} records):');
      buffer.writeln();
      for (final record in results) {
        final status = record['active'] == true ? 'ACTIVE' : 'RESOLVED';
        buffer.writeln(
            '[$status] [${record['alarmLevel']}] ${record['alarmTitle']}');
        buffer.writeln('  ${record['alarmDescription']}');
        buffer.writeln('  Activated: ${record['createdAt']}');
        if (record['deactivatedAt'] != null) {
          buffer.writeln('  Resolved: ${record['deactivatedAt']}');
        }
        buffer.writeln();
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}
