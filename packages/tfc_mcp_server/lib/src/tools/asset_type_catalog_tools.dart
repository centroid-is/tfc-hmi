import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/asset_type_catalog.dart';
import 'tool_registry.dart';

/// Registers the `list_asset_types` MCP tool.
///
/// This tool returns the catalog of all available HMI asset types so the LLM
/// knows what widget types exist when creating page or asset proposals.
///
/// Supports optional `category` filter and `detail` flag:
///   - `category` (string): filter by category name (exact match)
///   - `detail` (bool): if true, returns full JSON with properties;
///     if false (default), returns a compact text summary
void registerAssetTypeCatalogTools(ToolRegistry registry) {
  registry.registerTool(
    name: 'list_asset_types',
    description:
        'List all available HMI asset/widget types that can be placed on '
        'pages. Returns type names, categories, descriptions, and '
        'configurable properties. Use this to discover what assets exist '
        'before creating page or asset proposals.',
    inputSchema: JsonSchema.object(
      properties: {
        'category': JsonSchema.string(
          description:
              'Optional category filter (exact match). Known categories: '
              '${AssetTypeCatalog.categories.join(", ")}',
        ),
        'detail': JsonSchema.boolean(
          description:
              'If true, returns full JSON with properties. '
              'If false (default), returns a compact text summary.',
        ),
      },
    ),
    handler: (arguments, extra) async {
      final category = arguments['category'] as String?;
      final detail = arguments['detail'] as bool? ?? false;

      final types = category != null
          ? AssetTypeCatalog.byCategory(category)
          : AssetTypeCatalog.all;

      if (types.isEmpty) {
        final msg = category != null
            ? 'No asset types found in category "$category". '
                'Available categories: ${AssetTypeCatalog.categories.join(", ")}'
            : 'No asset types available.';
        return CallToolResult(
          content: [TextContent(text: msg)],
        );
      }

      if (detail) {
        // Full JSON output with all properties
        final json = types.map((t) => t.toJson()).toList();
        return CallToolResult(
          content: [
            TextContent(
                text: const JsonEncoder.withIndent('  ').convert(json)),
          ],
        );
      }

      // Compact text summary grouped by category
      final grouped = <String, List<AssetTypeInfo>>{};
      for (final t in types) {
        grouped.putIfAbsent(t.category, () => []).add(t);
      }

      final buffer = StringBuffer('Asset Types (${types.length}):\n');
      final sortedCategories = grouped.keys.toList()..sort();
      for (final cat in sortedCategories) {
        buffer.writeln('\n[$cat]');
        for (final t in grouped[cat]!) {
          buffer.writeln(
              '  ${t.assetName} (${t.displayName}): ${t.description}');
        }
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}
