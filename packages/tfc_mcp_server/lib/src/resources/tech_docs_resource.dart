import 'package:mcp_dart/mcp_dart.dart';

import '../services/tech_doc_service.dart';

/// Registers the `scada://source/tech_docs` resource on [mcpServer].
///
/// This resource returns a human-readable catalog of all uploaded technical
/// documents with their section counts, page counts, and upload dates.
/// When no documents are available (either because [techDocService] is null
/// or the index is empty), it returns a helpful status message.
///
/// The catalog is intended for LLM grounding -- the AI can tell the operator
/// which technical documents are available for reference.
void registerTechDocsResource(
  McpServer mcpServer,
  TechDocService? techDocService,
) {
  mcpServer.registerResource(
    'Knowledge Base',
    'scada://source/tech_docs',
    (
      description:
          'Catalog of uploaded technical documentation with section structure',
      mimeType: 'text/plain',
    ),
    (Uri uri, RequestHandlerExtra extra) async {
      if (techDocService == null || await techDocService.isEmpty) {
        return ReadResourceResult(
          contents: [
            TextResourceContents(
              uri: uri.toString(),
              mimeType: 'text/plain',
              text: 'No technical documents uploaded.\n'
                  'Upload PDFs through the HMI to enable documentation search.',
            ),
          ],
        );
      }

      final summaries = await techDocService.getSummary();

      final buffer = StringBuffer()
        ..writeln('Knowledge Base (${summaries.length} documents):')
        ..writeln();

      for (final doc in summaries) {
        buffer.writeln(
          '  ${doc['name']} '
          '(${doc['pageCount']} pages, ${doc['sectionCount']} sections) '
          '-- uploaded ${doc['uploadedAt']}',
        );
      }

      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'text/plain',
            text: buffer.toString().trimRight(),
          ),
        ],
      );
    },
  );
}
