import 'package:mcp_dart/mcp_dart.dart';

import '../services/tech_doc_service.dart';
import 'tool_registry.dart';

/// Registers technical documentation search and retrieval tools with the
/// given [ToolRegistry].
///
/// Tools:
/// - `search_tech_docs`: Search technical documentation by keyword. Returns
///   section titles and page ranges (metadata only). Use
///   `get_tech_doc_section` for full content.
/// - `get_tech_doc_section`: Get full content of a technical documentation
///   section by section ID. Use `search_tech_docs` first to find section IDs.
void registerTechDocTools(
    ToolRegistry registry, TechDocService techDocService) {
  // ── search_tech_docs ────────────────────────────────────────────────
  registry.registerTool(
    name: 'search_tech_docs',
    description:
        'Search locally uploaded manufacturer manuals, datasheets, and '
        'technical PDFs specific to this plant\'s installed equipment. '
        'PREFER this tool over web search for any equipment-specific '
        'questions — it contains authoritative, site-specific documentation. '
        'Returns section titles and page ranges (metadata only). '
        'Use get_tech_doc_section for full content. '
        'Use a single focused query. Do NOT call multiple times with '
        'rephrased terms — only retry if zero results were returned.',
    inputSchema: JsonSchema.object(
      properties: {
        'query': JsonSchema.string(
          description: 'Search keyword or phrase to find in documentation',
        ),
        'limit': JsonSchema.integer(
          description: 'Maximum results (1-100, default 20)',
        ),
      },
      required: ['query'],
    ),
    handler: (arguments, extra) async {
      final query = arguments['query'] as String;
      final rawLimit = (arguments['limit'] as num?)?.toInt() ?? 20;
      final limit = rawLimit.clamp(1, 100);

      // Check if any documents are uploaded
      if (await techDocService.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
                text: 'No technical documents uploaded. '
                    'Upload PDFs through the HMI to enable documentation search.'),
          ],
        );
      }

      final results = await techDocService.searchDocs(query, limit: limit);

      if (results.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
                text: "No technical documentation matches query '$query'."),
          ],
        );
      }

      // Format as human-readable text (metadata only, progressive discovery)
      final buffer = StringBuffer()
        ..writeln('Tech Doc Search Results (${results.length}):');

      for (final r in results) {
        buffer.writeln(
          '  ${r['docName']} > ${r['sectionTitle']} '
          '(pages ${r['pageStart']}-${r['pageEnd']}) '
          '[section_id: ${r['sectionId']}]',
        );
      }

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );

  // ── get_tech_doc_section ────────────────────────────────────────────
  registry.registerTool(
    name: 'get_tech_doc_section',
    description:
        'Get full content of a technical documentation section by '
        'section ID. Use search_tech_docs first to find section IDs.',
    inputSchema: JsonSchema.object(
      properties: {
        'section_id': JsonSchema.integer(
          description: 'Section ID from search_tech_docs results',
        ),
      },
      required: ['section_id'],
    ),
    handler: (arguments, extra) async {
      final sectionId = (arguments['section_id'] as num).toInt();

      final section = await techDocService.getSection(sectionId);
      if (section == null) {
        return CallToolResult(
          content: [
            TextContent(text: 'No section with ID $sectionId found.'),
          ],
          isError: true,
        );
      }

      final buffer = StringBuffer()
        ..writeln('Document: ${section['docName']}')
        ..writeln('Section: ${section['title']}')
        ..writeln('Pages: ${section['pageStart']}-${section['pageEnd']}')
        ..writeln('Level: ${section['level']}')
        ..writeln()
        ..writeln('=== Content ===')
        ..writeln(section['content']);

      return CallToolResult(
        content: [TextContent(text: buffer.toString().trimRight())],
      );
    },
  );
}
