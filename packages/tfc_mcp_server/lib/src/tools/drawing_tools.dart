import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../services/drawing_service.dart';
import 'tool_registry.dart';

/// Registers drawing tools with the given [ToolRegistry].
///
/// Tools:
/// - `search_drawings`: Search electrical drawings by component name or
///   subsystem. Returns metadata only (drawing name, page number, asset,
///   component) -- use the drawing viewer to see the actual drawing.
/// - `get_drawing_page`: Navigate to a specific page in a drawing PDF.
///   Returns a `_drawing_action` JSON object with navigation metadata
///   that the Flutter chat UI consumes to open the drawing overlay.
void registerDrawingTools(
    ToolRegistry registry, DrawingService drawingService) {
  registry.registerTool(
    name: 'search_drawings',
    description: 'Search electrical drawings by component name or subsystem. '
        'Returns metadata only (drawing name, page number, asset, component) '
        '-- use the drawing viewer to see the actual drawing.',
    inputSchema: JsonSchema.object(
      properties: {
        'query': JsonSchema.string(
          description: 'Component name or subsystem to search for '
              '(e.g. "relay K3", "motor")',
        ),
        'asset_filter': JsonSchema.string(
          description:
              'Optional asset key to filter results (e.g. "panel-A")',
        ),
        'limit': JsonSchema.integer(
          description: 'Maximum number of results to return (1-100)',
        ),
      },
      required: ['query'],
    ),
    handler: (arguments, extra) async {
      final query = arguments['query'] as String;
      final assetFilter = arguments['asset_filter'] as String?;
      final limit = (arguments['limit'] as num?)?.toInt() ?? 20;

      // Clamp limit to valid range
      final clampedLimit = limit.clamp(1, 100);

      // Check if index has any drawings at all
      if (!(await drawingService.hasDrawings)) {
        return CallToolResult(
          content: [TextContent(text: 'No electrical drawings indexed.')],
        );
      }

      final results = await drawingService.searchDrawings(
        query: query,
        assetFilter: assetFilter,
        limit: clampedLimit,
      );

      if (results.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(text: "No drawings match query '$query'."),
          ],
        );
      }

      final buffer = StringBuffer()
        ..writeln('Drawing Search Results (${results.length}):');

      for (final r in results) {
        buffer.writeln(
          '  ${r['componentName']} on ${r['drawingName']}, '
          'page ${r['pageNumber']} (asset: ${r['assetKey']})',
        );
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );

  registry.registerTool(
    name: 'get_drawing_page',
    description:
        'Navigate to a specific page in an electrical drawing PDF. Returns '
        'navigation metadata (not PDF bytes) that the HMI drawing viewer uses '
        'to display the page. Use search_drawings first to find the drawing '
        'name and page number.',
    inputSchema: JsonSchema.object(
      properties: {
        'drawing_name': JsonSchema.string(
          description: 'Exact drawing name as returned by search_drawings',
        ),
        'page_number': JsonSchema.integer(
          description: '1-based page number within the drawing',
        ),
        'highlight': JsonSchema.string(
          description:
              'Optional text to highlight on the target page (e.g. component name)',
        ),
      },
      required: ['drawing_name', 'page_number'],
    ),
    handler: (arguments, extra) async {
      final drawingName = arguments['drawing_name'] as String;
      final pageNumber = (arguments['page_number'] as num).toInt();
      final highlight = arguments['highlight'] as String?;

      // Look up drawing by name
      final summaries = await drawingService.getDrawingSummary();
      final match = summaries.where((s) => s.drawingName == drawingName);

      if (match.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
                text: "Drawing '$drawingName' not found. "
                    'Use search_drawings to find available drawing names.'),
          ],
          isError: true,
        );
      }

      final drawing = match.first;

      // Validate page range
      if (pageNumber < 1 || pageNumber > drawing.pageCount) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'Page $pageNumber is out of range for '
                    "'$drawingName' (1-${drawing.pageCount})."),
          ],
          isError: true,
        );
      }

      // Build _drawing_action JSON response.
      // Field names must match lib/drawings/drawing_action.dart DrawingAction constants:
      //   DrawingAction.marker = '_drawing_action'
      //   DrawingAction.drawingName = 'drawingName'
      //   DrawingAction.filePath = 'filePath'
      //   DrawingAction.pageNumber = 'pageNumber'
      //   DrawingAction.highlightText = 'highlightText'
      final actionJson = <String, dynamic>{
        '_drawing_action': true,
        'drawingName': drawing.drawingName,
        'filePath': drawing.filePath,
        'pageNumber': pageNumber,
      };

      if (highlight != null && highlight.isNotEmpty) {
        actionJson['highlightText'] = highlight;
      }

      return CallToolResult(
        content: [TextContent(text: jsonEncode(actionJson))],
      );
    },
  );
}
