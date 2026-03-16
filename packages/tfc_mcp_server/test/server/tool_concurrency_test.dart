import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';

void main() {
  group('ToolRegistry concurrency limiting', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late ToolRegistry registry;
    late MockMcpClient client;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('limits concurrent tool executions to maxConcurrency', () async {
      // Track concurrency inside tool handlers
      var running = 0;
      var maxRunning = 0;
      final completers = List.generate(6, (_) => Completer<void>());

      // Register 6 different tools that each block until their completer fires
      for (var i = 0; i < 6; i++) {
        final idx = i;
        registry.registerTool(
          name: 'slow_tool_$idx',
          description: 'Slow tool $idx',
          handler: (args, extra) async {
            running++;
            if (running > maxRunning) maxRunning = running;
            await completers[idx].future;
            running--;
            return CallToolResult(
              content: [TextContent(text: 'done-$idx')],
            );
          },
        );
      }

      client = await MockMcpClient.connect(mcpServer);

      // Fire all 6 tool calls concurrently
      final futures = <Future<CallToolResult>>[];
      for (var i = 0; i < 6; i++) {
        futures.add(client.callTool('slow_tool_$i', {}));
      }

      // Give time for handlers to start
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // maxRunning should be capped at 3 (the default maxConcurrency)
      expect(maxRunning, lessThanOrEqualTo(3),
          reason: 'At most 3 tool handlers should run concurrently');

      // Complete all
      for (final c in completers) {
        c.complete();
      }
      final results = await Future.wait(futures);

      // All 6 should complete successfully
      for (final result in results) {
        expect(result.isError, isNot(true));
      }
    });
  });
}
