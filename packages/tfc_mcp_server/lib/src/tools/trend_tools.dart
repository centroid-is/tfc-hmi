import 'package:mcp_dart/mcp_dart.dart';

import '../services/trend_service.dart';
import 'tool_registry.dart';

/// Registers trend query MCP tools with the given [ToolRegistry].
///
/// **query_trend_data**: Query time-bucketed trend data (min/avg/max)
/// for a collected key over a time range.
void registerTrendTools(ToolRegistry registry, TrendService trendService) {
  registry.registerTool(
    name: 'query_trend_data',
    description: 'Query time-bucketed trend data (min/avg/max) for a collected '
        'key over a time range. Returns aggregated values, not raw samples.',
    inputSchema: JsonSchema.object(
      properties: {
        'key': JsonSchema.string(
          description: 'Logical key name (e.g., pump3.speed)',
        ),
        'from': JsonSchema.string(
          description: 'Start time (ISO 8601)',
          format: 'date-time',
        ),
        'to': JsonSchema.string(
          description: 'End time (ISO 8601)',
          format: 'date-time',
        ),
      },
      required: ['key', 'from', 'to'],
    ),
    handler: (arguments, extra) async {
      final key = arguments['key'] as String;
      final from = DateTime.parse(arguments['from'] as String);
      final to = DateTime.parse(arguments['to'] as String);

      final result = await trendService.queryTrend(
        key: key,
        from: from,
        to: to,
      );

      if (result.error != null) {
        return CallToolResult(
          content: [TextContent(text: result.error!)],
          isError: true,
        );
      }

      return CallToolResult(
        content: [TextContent(text: result.toText())],
      );
    },
  );
}
