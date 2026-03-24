import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/config_service.dart';
import 'tool_registry.dart';

/// Registers configuration query tools with the given [ToolRegistry].
///
/// These tools enable the AI copilot to read system configuration using
/// progressive discovery:
///   Level 1: list_pages / list_assets (summaries)
///   Level 2: get_asset_detail (full page config)
///   Supporting: list_key_mappings, list_alarm_definitions
///
/// All tools enforce a limit parameter to prevent context window overflow.
void registerConfigTools(ToolRegistry registry, ConfigService configService) {
  // -- list_pages --
  registry.registerTool(
    name: 'list_pages',
    description:
        'List configured HMI pages with their keys and titles. '
        'Use get_asset_detail for full page configuration. '
        'Do NOT use if you already have the page key — call '
        'get_asset_detail directly.',
    inputSchema: JsonSchema.object(
      properties: {
        'limit': JsonSchema.integer(
          description: 'Maximum number of pages to return (default: 50)',
        ),
      },
    ),
    handler: (arguments, extra) async {
      final limit = arguments['limit'] as int? ?? 50;
      final pages = await configService.listPages(limit: limit);

      if (pages.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No pages configured.')],
        );
      }

      final buffer = StringBuffer('Pages (${pages.length}):\n');
      for (final page in pages) {
        buffer.writeln('  ${page['key']}: ${page['title']}');
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );

  // -- list_assets --
  registry.registerTool(
    name: 'list_assets',
    description:
        'List configured assets (HMI pages) with their keys and titles. '
        'Use get_asset_detail for full asset configuration. '
        'Do NOT use if you already have the asset key — call '
        'get_asset_detail directly.',
    inputSchema: JsonSchema.object(
      properties: {
        'limit': JsonSchema.integer(
          description: 'Maximum number of assets to return (default: 50)',
        ),
      },
    ),
    handler: (arguments, extra) async {
      final limit = arguments['limit'] as int? ?? 50;
      final assets = await configService.listAssets(limit: limit);

      if (assets.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No assets configured.')],
        );
      }

      final buffer = StringBuffer('Assets (${assets.length}):\n');
      for (final asset in assets) {
        buffer.writeln('  ${asset['key']}: ${asset['title']}');
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );

  // -- get_asset_detail --
  registry.registerTool(
    name: 'get_asset_detail',
    description:
        'Get full configuration for a specific HMI page/asset, including '
        'widgets and key bindings. Call directly when you have the page key. '
        'Only use list_pages or list_assets if you need to discover page keys. '
        'Do NOT call if the asset context was already provided in the '
        'conversation.',
    inputSchema: JsonSchema.object(
      properties: {
        'page_key': JsonSchema.string(
          description: 'The page key to retrieve (from list_pages)',
        ),
      },
      required: ['page_key'],
    ),
    handler: (arguments, extra) async {
      final pageKey = arguments['page_key'] as String;
      final detail = await configService.getAssetDetail(pageKey);

      if (detail == null) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'Page not found: "$pageKey". '
                  'Use list_pages to see available page keys.',
            ),
          ],
          isError: true,
        );
      }

      final jsonOutput = const JsonEncoder.withIndent('  ').convert(detail);
      return CallToolResult(
        content: [
          TextContent(
            text: 'Page "$pageKey" configuration:\n$jsonOutput',
          ),
        ],
      );
    },
  );

  // -- list_key_mappings --
  registry.registerTool(
    name: 'list_key_mappings',
    description:
        'List key-to-protocol-node mappings showing which data points are '
        'connected to OPC UA, Modbus, or M2400 nodes. '
        'Supports fuzzy text filter.',
    inputSchema: JsonSchema.object(
      properties: {
        'filter': JsonSchema.string(
          description: 'Optional fuzzy filter on key names',
        ),
        'limit': JsonSchema.integer(
          description: 'Maximum number of mappings to return (default: 50)',
        ),
      },
    ),
    handler: (arguments, extra) async {
      final filter = arguments['filter'] as String?;
      final limit = arguments['limit'] as int? ?? 50;
      final mappings = await configService.listKeyMappings(
        filter: filter,
        limit: limit,
      );

      if (mappings.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No key mappings configured.')],
        );
      }

      final buffer = StringBuffer('Key Mappings (${mappings.length}):\n');
      for (final m in mappings) {
        final protocol = m['protocol'] as String? ?? 'opcua';
        switch (protocol) {
          case 'modbus':
            buffer.writeln(
                '  ${m['key']} -> modbus ${m['register_type']}@${m['address']} '
                '(${m['data_type']}, group: ${m['poll_group']})');
          case 'm2400':
            final field = m['field'] != null ? ', field: ${m['field']}' : '';
            buffer.writeln(
                '  ${m['key']} -> m2400 ${m['record_type']}$field');
          default: // opcua
            buffer.writeln(
                '  ${m['key']} -> ${m['namespace']}:${m['identifier']}');
        }
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );

  // -- list_alarm_definitions --
  registry.registerTool(
    name: 'list_alarm_definitions',
    description:
        'List configured alarm definitions with their IDs, titles, and '
        'descriptions. Supports fuzzy text filter. '
        'Do NOT use if you already have the alarm UID — call '
        'get_alarm_detail directly instead.',
    inputSchema: JsonSchema.object(
      properties: {
        'filter': JsonSchema.string(
          description: 'Optional fuzzy filter on alarm title or description',
        ),
        'limit': JsonSchema.integer(
          description:
              'Maximum number of alarm definitions to return (default: 50)',
        ),
      },
    ),
    handler: (arguments, extra) async {
      final filter = arguments['filter'] as String?;
      final limit = arguments['limit'] as int? ?? 50;
      final alarms = await configService.listAlarmDefinitions(
        filter: filter,
        limit: limit,
      );

      if (alarms.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'No alarm definitions configured.')],
        );
      }

      final buffer =
          StringBuffer('Alarm Definitions (${alarms.length}):\n');
      for (final a in alarms) {
        buffer.writeln('  [${a['uid']}] ${a['title']} - ${a['description']}');
      }
      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}
