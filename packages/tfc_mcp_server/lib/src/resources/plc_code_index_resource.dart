import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/plc_code_service.dart';

/// Registers the `scada://plc/code` resource on [mcpServer].
///
/// This resource returns a JSON summary of all indexed PLC code per asset,
/// including block counts, variable counts, last upload date, and block type
/// breakdown. When no PLC code is available (either because [plcCodeService]
/// is null or the index is empty), it returns a meaningful status message.
///
/// The summary is intended for LLM grounding -- the AI can tell the operator
/// which assets have PLC code available for inspection.
void registerPlcCodeIndexResource(
  McpServer mcpServer,
  PlcCodeService? plcCodeService,
) {
  mcpServer.registerResource(
    'PLC Code Index',
    'scada://plc/code',
    (
      description:
          'Per-asset summary of indexed PLC code blocks and variables.',
      mimeType: 'application/json',
    ),
    (Uri uri, RequestHandlerExtra extra) async {
      final encoder = const JsonEncoder.withIndent('  ');

      if (plcCodeService == null || !plcCodeService.hasCode) {
        final empty = {
          'status': 'no_plc_code_indexed',
          'message':
              'No TwinCAT projects have been uploaded and indexed.',
        };

        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              mimeType: 'application/json',
              text: encoder.convert(empty),
            ),
          ],
        );
      }

      final summaries = await plcCodeService.getIndexSummary();

      final assets = summaries
          .map((s) => {
                'assetKey': s.assetKey,
                'blockCount': s.blockCount,
                'variableCount': s.variableCount,
                'lastIndexedAt': s.lastIndexedAt.toIso8601String(),
                'blockTypeCounts': s.blockTypeCounts,
              })
          .toList();

      final catalog = {
        'status': 'available',
        'assetCount': assets.length,
        'assets': assets,
      };

      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'application/json',
            text: encoder.convert(catalog),
          ),
        ],
      );
    },
  );
}
