import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/tools/ping_tool.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';

void main() {
  group('Identity gate integration', () {
    late ServerDatabase db;

    setUp(() async {
      db = ServerDatabase.inMemory();
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

    test('5. Identity is validated per-call, not cached at startup', () async {
      // Start with a valid identity
      final env = <String, String>{'TFC_USER': 'op1'};
      final identity =
          EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      final mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        // First call with valid identity should succeed
        final result1 = await client.callTool('ping', {});
        expect(result1.isError, isNot(true));

        // Remove identity mid-session
        env.remove('TFC_USER');

        // Second call should fail because identity is validated per-call
        final result2 = await client.callTool('ping', {});
        expect(result2.isError, isTrue);
      } finally {
        await client.close();
      }
    });

    test('6. Error response for missing identity includes helpful message',
        () async {
      final env = <String, String>{};
      final identity =
          EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      final mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      registerPingTool(registry);

      final client = await MockMcpClient.connect(mcpServer);
      try {
        final result = await client.callTool('ping', {});

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;

        // Should contain the env var name
        expect(text, contains('TFC_USER'));
        // Should contain setup instructions
        expect(text, contains('Set TFC_USER'));
      } finally {
        await client.close();
      }
    });
  });
}
