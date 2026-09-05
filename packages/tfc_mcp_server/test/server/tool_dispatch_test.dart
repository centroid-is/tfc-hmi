import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/tools/ping_tool.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';

void main() {
  group('Tool dispatch pipeline', () {
    late ServerDatabase db;
    late McpServer mcpServer;

    setUp(() async {
      db = ServerDatabase.inMemory();
      // Ensure tables are created
      await db.customStatement('SELECT 1');
    });

    tearDown(() async {
      await db.close();
    });

    McpServer createMcpServer() {
      return McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
    }

    test('1. Tool call creates audit record pending then success', () async {
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        final result = await client.callTool('ping', {'message': 'test'});

        // Tool should succeed
        expect(result.isError, isNot(true));

        // Check audit record in DB
        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        // This row records that the MCP server ran a tool, not that a
        // person authorized one -- the person's name is on the approval row.
        expect(records.first.operatorId, equals(kMcpAuditOperator));
        expect(records.first.tool, equals('ping'));
        expect(records.first.status, equals('success'));
      } finally {
        await client.close();
      }
    });

    test(
        '3. Tool call that throws creates audit record with status failed and error message',
        () async {
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      // Register a tool that throws
      registry.registerTool(
        name: 'failing_tool',
        description: 'A tool that always fails',
        handler: (args, extra) async {
          throw Exception('test error');
        },
      );

      final client = await MockMcpClient.connect(mcpServer);
      try {
        final result = await client.callTool('failing_tool', {});

        // Should return error
        expect(result.isError, isTrue);

        // Check audit record
        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        expect(records.first.status, equals('failed'));
        expect(records.first.error, contains('test error'));
      } finally {
        await client.close();
      }
    });

    test(
        '4. Audit record contains correct tool name and JSON-encoded arguments',
        () async {
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        await client.callTool('ping', {'message': 'hello'});

        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        expect(records.first.tool, equals('ping'));
        expect(records.first.arguments, contains('hello'));
      } finally {
        await client.close();
      }
    });

    test('7. Ping tool uses domain-oriented design (CORE-03 demonstration)',
        () async {
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        final result = await client.callTool('ping', {'message': 'hello'});

        expect(result.isError, isNot(true));

        // Response should contain the echoed message and server info
        final text = (result.content.first as TextContent).text;
        expect(text, contains('hello'));
        expect(text, contains('tfc-mcp-server'));

        // Verify tool listing uses human-readable names
        final tools = await client.listTools();
        final pingTool = tools.firstWhere((t) => t.name == 'ping');
        expect(pingTool.description, isNotEmpty);
        // Domain-oriented: no OPC UA node IDs in tool name or description
        expect(pingTool.name, isNot(contains('ns=')));
        expect(pingTool.description, isNot(contains('ns=')));
      } finally {
        await client.close();
      }
    });
  });
}
