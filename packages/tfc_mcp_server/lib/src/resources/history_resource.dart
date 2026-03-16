import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/alarm_service.dart';

/// Registers the `scada://history/recent` resource on [mcpServer].
///
/// This resource returns a JSON snapshot of recent operational history
/// including currently active alarms and alarm history from the last 4 hours.
/// Data is assembled from [alarmService] methods.
///
/// The response includes:
/// - `active_alarms`: currently active alarms (active=true, deactivatedAt=null)
/// - `recent_history`: alarm history records from the last 4 hours
/// - `time_window`: description of the query window ("last 4 hours")
/// - `generated_at`: ISO 8601 timestamp of when the snapshot was generated
void registerHistoryResource(
  McpServer mcpServer,
  AlarmService alarmService,
) {
  mcpServer.registerResource(
    'Operational History',
    'scada://history/recent',
    (
      description:
          'Recent alarms and operational events from the last 4 hours',
      mimeType: 'application/json',
    ),
    (Uri uri, RequestHandlerExtra extra) async {
      final activeAlarms = await alarmService.listActiveAlarms(limit: 100);
      final recentHistory = await alarmService.queryHistory(
        after: DateTime.now().toUtc().subtract(const Duration(hours: 4)),
        limit: 200,
      );

      final history = {
        'active_alarms': activeAlarms,
        'recent_history': recentHistory,
        'time_window': 'last 4 hours',
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final encoder = const JsonEncoder.withIndent('  ');

      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'application/json',
            text: encoder.convert(history),
          ),
        ],
      );
    },
  );
}
