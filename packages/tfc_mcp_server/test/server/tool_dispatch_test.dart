import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
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

    test(
        '1. Tool call with valid identity creates audit record pending then success',
        () async {
      final env = {'TFC_USER': 'op1'};
      final identity =
          EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
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
        expect(records.first.operatorId, equals('op1'));
        expect(records.first.tool, equals('ping'));
        expect(records.first.status, equals('success'));
      } finally {
        await client.close();
      }
    });

    test(
        '2. Tool call without identity (TFC_USER not set) returns error and creates NO audit record',
        () async {
      final env = <String, String>{};
      final identity =
          EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        final result = await client.callTool('ping', {});

        // Should return an error
        expect(result.isError, isTrue);

        // Error should mention TFC_USER
        final text = (result.content.first as TextContent).text;
        expect(text, contains('TFC_USER'));

        // No audit records should exist
        final records = await db.select(db.auditLog).get();
        expect(records, isEmpty);
      } finally {
        await client.close();
      }
    });

    test(
        '3. Tool call that throws creates audit record with status failed and error message',
        () async {
      final env = {'TFC_USER': 'op1'};
      final identity =
          EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
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
      final env = {'TFC_USER': 'op1'};
      final identity =
          EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
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
      final env = {'TFC_USER': 'op1'};
      final identity =
          EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
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
