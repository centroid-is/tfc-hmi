import 'dart:typed_data';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/tech_doc_index.dart';
import 'package:tfc_mcp_server/src/services/tech_doc_service.dart';
import 'package:tfc_mcp_server/src/tools/tech_doc_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_tech_doc_index.dart';

void main() {
  group('search_tech_docs tool', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockTechDocIndex mockIndex;
    late MockMcpClient client;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      mockIndex = MockTechDocIndex();

      // Populate with sample documents
      await mockIndex.storeDocument(
        name: 'ATV320 Installation Manual',
        pdfBytes: Uint8List(10),
        sections: [
          const ParsedSection(
            title: 'Chapter 1: Safety Precautions',
            content: 'Always disconnect power before servicing the drive.',
            pageStart: 1,
            pageEnd: 5,
            level: 1,
            sortOrder: 0,
            children: [
              ParsedSection(
                title: '1.1 Electrical Safety',
                content:
                    'Ensure all power sources are locked out before working on the drive.',
                pageStart: 2,
                pageEnd: 3,
                level: 2,
                sortOrder: 1,
              ),
            ],
          ),
          const ParsedSection(
            title: 'Chapter 2: Wiring Diagram',
            content:
                'Connect the motor leads to terminals U, V, W. The drive supports both star and delta wiring configurations.',
            pageStart: 6,
            pageEnd: 12,
            level: 1,
            sortOrder: 2,
          ),
        ],
      );

      await mockIndex.storeDocument(
        name: 'Sensor Datasheet XYZ',
        pdfBytes: Uint8List(5),
        sections: [
          const ParsedSection(
            title: 'Specifications',
            content: 'Temperature range: -40 to 85 degrees Celsius.',
            pageStart: 1,
            pageEnd: 2,
            level: 1,
            sortOrder: 0,
          ),
        ],
      );

      final techDocService = TechDocService(mockIndex);

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerTechDocTools(registry, techDocService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('returns matching section titles and page ranges', () async {
      final result = await client.callTool(
        'search_tech_docs',
        {'query': 'wiring'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('ATV320 Installation Manual'));
      expect(text, contains('Wiring Diagram'));
      expect(text, contains('6'));
      expect(text, contains('12'));
    });

    test('returns empty results for no matches', () async {
      final result = await client.callTool(
        'search_tech_docs',
        {'query': 'nonexistent_xyz_abc_123'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('No technical documentation matches'));
    });

    test('respects limit parameter', () async {
      final result = await client.callTool(
        'search_tech_docs',
        {'query': 'a', 'limit': 1},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      // With limit=1, should have at most 1 result entry
      // Count the number of ">" separators (docName > sectionTitle pattern)
      final matches = '>'.allMatches(text).length;
      expect(matches, lessThanOrEqualTo(1));
    });

    test('output follows progressive discovery (metadata only, no full content)',
        () async {
      final result = await client.callTool(
        'search_tech_docs',
        {'query': 'safety'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      // Should contain section title
      expect(text, contains('Safety Precautions'));
      // Should NOT contain full section content text
      expect(
          text,
          isNot(contains(
              'Always disconnect power before servicing the drive.')));
    });

    test('empty index returns helpful message', () async {
      mockIndex.clear();
      final result = await client.callTool(
        'search_tech_docs',
        {'query': 'anything'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('No technical documents uploaded'));
    });
  });

  group('get_tech_doc_section tool', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockTechDocIndex mockIndex;
    late MockMcpClient client;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      mockIndex = MockTechDocIndex();

      await mockIndex.storeDocument(
        name: 'ATV320 Installation Manual',
        pdfBytes: Uint8List(10),
        sections: [
          const ParsedSection(
            title: 'Chapter 1: Safety Precautions',
            content:
                'Always disconnect power before servicing the drive. Follow all local electrical codes.',
            pageStart: 1,
            pageEnd: 5,
            level: 1,
            sortOrder: 0,
          ),
        ],
      );

      final techDocService = TechDocService(mockIndex);

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerTechDocTools(registry, techDocService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('returns full section content for valid section_id', () async {
      final result = await client.callTool(
        'get_tech_doc_section',
        {'section_id': 1},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Safety Precautions'));
      expect(text, contains('Always disconnect power before servicing'));
      expect(text, contains('ATV320 Installation Manual'));
      expect(text, contains('1'));
      expect(text, contains('5'));
    });

    test('returns error for invalid section_id', () async {
      final result = await client.callTool(
        'get_tech_doc_section',
        {'section_id': 9999},
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('No section with ID 9999'));
    });
  });
}
