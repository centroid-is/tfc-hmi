import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/services/trend_service.dart';
import 'package:tfc_mcp_server/src/tools/trend_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

void main() {
  group('Trend tools integration', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockMcpClient client;

    setUp(() async {
      db = createTestDatabase();
      await db.customStatement('SELECT 1');

      final trendService = TrendService(db, isPostgres: false);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerTrendTools(registry, trendService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('query_trend_data appears in listTools', () async {
      final tools = await client.listTools();
      final trendTool = tools.where((t) => t.name == 'query_trend_data');
      expect(trendTool, hasLength(1));
      expect(trendTool.first.description, isNotEmpty);
    });

    test('query_trend_data tool has correct input schema', () async {
      final tools = await client.listTools();
      final trendTool =
          tools.firstWhere((t) => t.name == 'query_trend_data');
      final schema = trendTool.inputSchema;
      // Verify the schema is an object with required key/from/to
      final jsonObj = schema as JsonObject;
      expect(jsonObj.required, isNotNull);
      expect(jsonObj.required, containsAll(['key', 'from', 'to']));
    });

    test('calling with non-existent table returns error content', () async {
      final result = await client.callTool('query_trend_data', {
        'key': 'pump3.speed',
        'from': '2026-01-01T12:00:00Z',
        'to': '2026-01-01T13:00:00Z',
      });

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('pump3.speed'));
      expect(text, contains('No trend data table'));
    });

    test('calling with existing table but no data returns text content',
        () async {
      // Create a timeseries table
      await db.customStatement(
        'CREATE TABLE "pump3.speed" (time TEXT NOT NULL, value REAL)',
      );

      final result = await client.callTool('query_trend_data', {
        'key': 'pump3.speed',
        'from': '2026-01-01T12:00:00Z',
        'to': '2026-01-01T13:00:00Z',
      });

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('No data'));
    });

    test('calling with existing table and data returns bucket text', () async {
      // Create and populate a timeseries table
      await db.customStatement(
        'CREATE TABLE "pump3.speed" (time TEXT NOT NULL, value REAL)',
      );
      await db.customStatement(
        "INSERT INTO \"pump3.speed\" VALUES ('2026-01-01T12:05:00.000Z', 1.5)",
      );
      await db.customStatement(
        "INSERT INTO \"pump3.speed\" VALUES ('2026-01-01T12:10:00.000Z', 2.0)",
      );
      await db.customStatement(
        "INSERT INTO \"pump3.speed\" VALUES ('2026-01-01T12:15:00.000Z', 1.8)",
      );

      final result = await client.callTool('query_trend_data', {
        'key': 'pump3.speed',
        'from': '2026-01-01T12:00:00Z',
        'to': '2026-01-01T13:00:00Z',
      });

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('pump3.speed'));
      expect(text, contains('min='));
      expect(text, contains('avg='));
      expect(text, contains('max='));
      expect(text, contains('samples='));
    });
  });
}
