import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/drawing_index.dart';
import 'package:tfc_mcp_server/src/services/drawing_service.dart';
import 'package:tfc_mcp_server/src/tools/drawing_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_drawing_index.dart';
import '../helpers/mock_mcp_client.dart';

void main() {
  group('search_drawings tool', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockDrawingIndex mockIndex;
    late MockMcpClient client;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      mockIndex = MockDrawingIndex();

      // Populate test data
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-A Main Wiring',
        pageNumber: 5,
        assetKey: 'panel-A',
        componentName: 'relay K3',
      ));
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-B Motor Control',
        pageNumber: 2,
        assetKey: 'panel-B',
        componentName: 'motor M1',
      ));
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-A Aux Wiring',
        pageNumber: 8,
        assetKey: 'panel-A',
        componentName: 'relay K7',
      ));

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

      final drawingService = DrawingService(mockIndex);
      registerDrawingTools(registry, drawingService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('returns formatted results for matching query', () async {
      final result = await client.callTool(
        'search_drawings',
        {'query': 'relay'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Drawing Search Results (2)'));
      expect(text, contains('relay K3'));
      expect(text, contains('Panel-A Main Wiring'));
      expect(text, contains('page 5'));
      expect(text, contains('relay K7'));
      expect(text, contains('Panel-A Aux Wiring'));
      expect(text, contains('page 8'));
    });

    test('returns filtered results with asset_filter', () async {
      final result = await client.callTool(
        'search_drawings',
        {'query': 'relay', 'asset_filter': 'panel-A'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Drawing Search Results (2)'));
      expect(text, contains('relay K3'));
      expect(text, contains('relay K7'));
      // Should not contain motor from panel-B
      expect(text, isNot(contains('motor M1')));
    });

    test('returns "No drawings match" when index has data but no match',
        () async {
      final result = await client.callTool(
        'search_drawings',
        {'query': 'nonexistent'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains("No drawings match query 'nonexistent'"));
    });

    test('returns "No electrical drawings indexed." when index is empty',
        () async {
      mockIndex.clear();
      final result = await client.callTool(
        'search_drawings',
        {'query': 'anything'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, equals('No electrical drawings indexed.'));
    });

    test('enforces limit parameter', () async {
      // Add more relay results
      mockIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-D Relay Bank',
        pageNumber: 1,
        assetKey: 'panel-D',
        componentName: 'relay K10',
      ));

      final result = await client.callTool(
        'search_drawings',
        {'query': 'relay', 'limit': 2},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Drawing Search Results (2)'));
    });
  });

  group('get_drawing_page tool', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockDrawingIndex mockIndex;
    late MockMcpClient client;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      mockIndex = MockDrawingIndex();

      // Store drawing data via storeDrawing so getDrawingSummary returns it
      await mockIndex.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'relay K3\nmotor M1'),
          const DrawingPageText(pageNumber: 2, fullText: 'contactor Q1'),
          const DrawingPageText(pageNumber: 3, fullText: 'breaker CB5'),
        ],
      );
      await mockIndex.storeDrawing(
        assetKey: 'panel-B',
        drawingName: 'Panel-B Motor Control',
        filePath: '/drawings/panel-b.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'VFD drive 1\nmotor starter'),
        ],
      );

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

      final drawingService = DrawingService(mockIndex);
      registerDrawingTools(registry, drawingService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('returns _drawing_action JSON with filePath, pageNumber, drawingName',
        () async {
      final result = await client.callTool(
        'get_drawing_page',
        {'drawing_name': 'Panel-A Main Wiring', 'page_number': 2},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      final json = jsonDecode(text) as Map<String, dynamic>;

      expect(json['_drawing_action'], isTrue);
      expect(json['drawingName'], equals('Panel-A Main Wiring'));
      expect(json['filePath'], equals('/drawings/panel-a.pdf'));
      expect(json['pageNumber'], equals(2));
    });

    test('includes highlightText when highlight parameter provided', () async {
      final result = await client.callTool(
        'get_drawing_page',
        {
          'drawing_name': 'Panel-A Main Wiring',
          'page_number': 1,
          'highlight': 'relay K3',
        },
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      final json = jsonDecode(text) as Map<String, dynamic>;

      expect(json['_drawing_action'], isTrue);
      expect(json['highlightText'], equals('relay K3'));
    });

    test('returns error for unknown drawing name', () async {
      final result = await client.callTool(
        'get_drawing_page',
        {'drawing_name': 'Nonexistent Drawing', 'page_number': 1},
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Nonexistent Drawing'));
      expect(text, contains('not found'));
    });

    test('returns error for page out of range', () async {
      final result = await client.callTool(
        'get_drawing_page',
        {'drawing_name': 'Panel-A Main Wiring', 'page_number': 10},
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('out of range'));
    });

    test('search_drawings still works (no regression)', () async {
      final result = await client.callTool(
        'search_drawings',
        {'query': 'relay'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('relay K3'));
    });

    test('response JSON uses DrawingAction constant field names', () async {
      final result = await client.callTool(
        'get_drawing_page',
        {
          'drawing_name': 'Panel-A Main Wiring',
          'page_number': 1,
          'highlight': 'relay K3',
        },
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      final json = jsonDecode(text) as Map<String, dynamic>;

      // Field names must match lib/drawings/drawing_action.dart DrawingAction constants
      // DrawingAction.marker = '_drawing_action'
      expect(json.containsKey('_drawing_action'), isTrue);
      // DrawingAction.drawingName = 'drawingName'
      expect(json.containsKey('drawingName'), isTrue);
      // DrawingAction.filePath = 'filePath'
      expect(json.containsKey('filePath'), isTrue);
      // DrawingAction.pageNumber = 'pageNumber'
      expect(json.containsKey('pageNumber'), isTrue);
      // DrawingAction.highlightText = 'highlightText'
      expect(json.containsKey('highlightText'), isTrue);
    });
  });
}
