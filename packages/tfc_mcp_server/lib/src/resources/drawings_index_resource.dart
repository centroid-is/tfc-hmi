import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/drawing_service.dart';

/// Registers the `scada://drawings/index` resource on [mcpServer].
///
/// This resource returns a JSON catalog of all indexed electrical drawings
/// with their asset mappings. When no drawings are available (either because
/// [drawingService] is null in standalone mode or the index is empty), it
/// returns a meaningful status message instead of an error.
///
/// The catalog is intended for LLM grounding -- the AI can offer to show
/// specific drawings when they are relevant to an operator's question.
void registerDrawingsIndexResource(
  McpServer mcpServer,
  DrawingService? drawingService,
) {
  mcpServer.registerResource(
    'Electrical Drawings Index',
    'scada://drawings/index',
    (
      description:
          'Catalog of available electrical drawings mapped to assets '
          'with searchable component metadata',
      mimeType: 'application/json',
    ),
    (Uri uri, RequestHandlerExtra extra) async {
      final encoder = const JsonEncoder.withIndent('  ');

      if (drawingService == null || !(await drawingService.hasDrawings)) {
        final empty = {
          'status': 'no_drawings',
          'message':
              'No electrical drawings have been indexed. Drawing upload '
              'and indexing is available through the HMI page editor.',
          'drawings': <Map<String, dynamic>>[],
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

      // Empty query returns all indexed entries
      final drawings =
          await drawingService.searchDrawings(query: '', limit: 500);

      final catalog = {
        'status': 'available',
        'count': drawings.length,
        'drawings': drawings,
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
