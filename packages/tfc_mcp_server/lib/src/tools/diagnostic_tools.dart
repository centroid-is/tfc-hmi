import 'package:mcp_dart/mcp_dart.dart';

import '../services/diagnostic_service.dart';
import 'tool_registry.dart';

/// Registers the composite `diagnose_asset` tool with the given [ToolRegistry].
///
/// This tool gathers ALL diagnostic data for an asset in a single call,
/// querying multiple data sources in parallel and assembling a structured
/// text report. It replaces the need to call 6+ individual tools
/// sequentially (get_tag_value, query_alarm_history, search_drawings,
/// search_plc_code, search_tech_docs, query_trend_data).
///
/// The individual tools remain available for focused follow-up queries.
void registerDiagnosticTools(
  ToolRegistry registry,
  DiagnosticService diagnosticService,
) {
  registry.registerTool(
    name: 'diagnose_asset',
    description: 'Gather ALL diagnostic data for an asset in a single call. '
        'Returns live tag values, active alarms, alarm history, key mappings, '
        'electrical drawings, PLC code references, technical documentation, '
        'and trend data in one structured report. '
        'Use this instead of calling get_tag_value, query_alarm_history, '
        'search_drawings, search_plc_code, search_tech_docs, and '
        'query_trend_data separately. Individual tools are still available '
        'for focused follow-up queries.',
    inputSchema: JsonSchema.object(
      properties: {
        'asset_key': JsonSchema.string(
          description: 'The asset key to diagnose (e.g., "pump3", '
              '"conveyor1", "tank2"). This is the logical key prefix '
              'used to match tags, alarms, drawings, and code.',
        ),
        'hours': JsonSchema.integer(
          description: 'How many hours of history to include for alarm history '
              'and trend data (default: 4, max: 72)',
          minimum: 1,
          maximum: 72,
          defaultValue: 4,
        ),
      },
      required: ['asset_key'],
    ),
    handler: (arguments, extra) async {
      final assetKey = arguments['asset_key'] as String;
      final hours = (arguments['hours'] as num?)?.toInt() ?? 4;

      // Clamp hours to valid range.
      final clampedHours = hours.clamp(1, 72);

      final report = await diagnosticService.diagnoseAsset(
        assetKey: assetKey,
        hoursHistory: clampedHours,
      );

      return CallToolResult(
        content: [TextContent(text: report)],
      );
    },
  );
}
