import 'package:mcp_dart/mcp_dart.dart';

import '../services/plc_code_service.dart';
import 'tool_registry.dart';

/// Registers PLC code search and retrieval tools with the given [ToolRegistry].
///
/// Tools:
/// - `search_plc_code`: Search PLC code index by HMI key name, PLC variable
///   name, or free-text. Returns metadata only -- use `get_plc_code_block`
///   for full source code.
/// - `get_plc_code_block`: Get full PLC code block with declaration,
///   implementation, and variables by block ID.
void registerPlcCodeTools(
    ToolRegistry registry, PlcCodeService plcCodeService) {
  // ── search_plc_code ──────────────────────────────────────────────────
  registry.registerTool(
    name: 'search_plc_code',
    description:
        'Search PLC code index by HMI key name (correlates via OPC UA '
        'identifier), PLC variable name, or free-text within code body and '
        'comments. Returns metadata only -- use get_plc_code_block for '
        'full code. Do NOT use if you already have the PLC variable path '
        'from a key mapping — use mode=variable with the exact path instead '
        'of re-discovering it.',
    inputSchema: JsonSchema.object(
      properties: {
        'query': JsonSchema.string(
          description:
              'Search term: HMI key name (mode=key), PLC variable name '
              '(mode=variable), or text to find in code (mode=text)',
        ),
        'mode': JsonSchema.string(
          description:
              'Search mode: "key" (HMI key correlation), "variable" '
              '(PLC var name), "text" (free-text in code). Default: text',
        ),
        'asset_filter': JsonSchema.string(
          description: 'Optional Beckhoff asset key to filter results',
        ),
        'limit': JsonSchema.integer(
          description: 'Maximum results (1-100, default 20)',
        ),
      },
      required: ['query'],
    ),
    handler: (arguments, extra) async {
      final query = arguments['query'] as String;
      final mode = (arguments['mode'] as String?) ?? 'text';
      final assetFilter = arguments['asset_filter'] as String?;
      final rawLimit = (arguments['limit'] as num?)?.toInt() ?? 20;
      final limit = rawLimit.clamp(1, 100);

      // Dispatch to appropriate search method (search() calls
      // _ensureInitialized() internally, so no synchronous hasCode gate).
      final results = mode == 'key'
          ? await plcCodeService.searchByKey(query, limit: limit)
          : await plcCodeService.search(
              query,
              mode: mode,
              assetFilter: assetFilter,
              limit: limit,
            );

      if (results.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(text: "No PLC code matches query '$query'."),
          ],
        );
      }

      // Format results as human-readable text (metadata only)
      final buffer = StringBuffer()
        ..writeln('PLC Code Search Results (${results.length}):');

      for (final r in results) {
        if (r.variableName != null) {
          buffer.writeln(
            '  ${r.variableName} : ${r.variableType} in '
            '${r.blockName} (${r.blockType}) [asset: ${r.assetKey}]',
          );
          if (r.declarationLine != null) {
            buffer.writeln('    > ${r.declarationLine}');
          }
        } else {
          buffer.writeln(
            '  ${r.blockName} (${r.blockType}) [asset: ${r.assetKey}]',
          );
        }
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );

  // ── get_plc_code_block ───────────────────────────────────────────────
  registry.registerTool(
    name: 'get_plc_code_block',
    description:
        'Get full PLC code block with declaration, implementation, and '
        'variables. Use search_plc_code first to find block IDs.',
    inputSchema: JsonSchema.object(
      properties: {
        'block_id': JsonSchema.integer(
          description: 'Block ID from search_plc_code results',
        ),
      },
      required: ['block_id'],
    ),
    handler: (arguments, extra) async {
      final blockId = (arguments['block_id'] as num).toInt();

      final block = await plcCodeService.getBlock(blockId);
      if (block == null) {
        return CallToolResult(
          content: [
            TextContent(text: 'No PLC code block with ID $blockId found.'),
          ],
          isError: true,
        );
      }

      final buffer = StringBuffer()
        ..writeln('Block: ${block.blockName} (${block.blockType})')
        ..writeln('Asset: ${block.assetKey}')
        ..writeln('File: ${block.filePath}')
        ..writeln('Indexed: ${block.indexedAt.toIso8601String()}')
        ..writeln()
        ..writeln('=== Declaration ===')
        ..writeln(block.declaration)
        ..writeln()
        ..writeln('=== Implementation ===')
        ..writeln(block.implementation ?? 'N/A (declaration-only block)')
        ..writeln()
        ..writeln('=== Variables (${block.variables.length}) ===');

      for (final v in block.variables) {
        buffer.writeln(
          '  ${v.section}: ${v.variableName} : ${v.variableType} '
          '[${v.qualifiedName}]',
        );
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}
