import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/services/proposal_feedback_bus.dart';
import 'package:tfc_mcp_server/src/tools/proposal_feedback_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';

/// The load-bearing risk in the whole feature.
///
/// [ToolRegistry] holds a concurrency slot for a handler's entire duration,
/// and there are only three. `await_proposal_feedback` parks for up to 110
/// seconds by design, so three of them registered as ordinary metered tools
/// would take every slot and freeze the server -- get_tag_value, list_alarms,
/// everything -- for as long as the operator did not click anything. Which is
/// most of the time.
///
/// `metered: false` is what prevents that, and this test is what proves it.
void main() {
  late ServerDatabase db;
  late McpServer mcpServer;
  late MockMcpClient client;
  late ProposalFeedbackBus bus;
  late ToolRegistry registry;

  setUp(() async {
    db = ServerDatabase.inMemory();
    await db.customStatement('SELECT 1');

    mcpServer = McpServer(
      const Implementation(name: 'test-server', version: '0.1.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );

    registry = ToolRegistry(
      mcpServer: mcpServer,
      identity: EnvOperatorIdentity(
        environmentProvider: () => {'TFC_USER': 'op1'},
      ),
      auditLogService: AuditLogService(db),
    );

    bus = ProposalFeedbackBus();
    registerProposalFeedbackTools(registry, bus);
  });

  tearDown(() async {
    await client.close();
    await bus.close();
    await db.close();
  });

  test('three parked long polls do not block an ordinary metered tool',
      () async {
    // A stand-in for any normal tool: get_tag_value, list_alarms, whatever.
    registry.registerTool(
      name: 'ordinary_tool',
      description: 'A normal metered tool',
      handler: (args, extra) async =>
          CallToolResult(content: [TextContent(text: 'ok')]),
    );

    client = await MockMcpClient.connect(mcpServer);

    // Occupy every concurrency slot three times over, if the semaphore
    // applied. Each of these will park for the full 110 seconds unless the
    // operator decides something -- which nothing in this test does until the
    // assertion has already been made.
    final parked = [
      for (var i = 0; i < 3; i++)
        client.callTool('await_proposal_feedback', {'timeout_seconds': 110}),
    ];

    // Let all three reach the bus and park.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(bus.waiterCount, 3,
        reason: 'all three long polls should be parked in the bus');

    // The whole point: this must come straight back, not queue behind them.
    final result = await client
        .callTool('ordinary_tool', {})
        .timeout(const Duration(seconds: 3),
            onTimeout: () => fail('a metered tool was starved by long polls'));
    expect((result.content.first as TextContent).text, 'ok');

    // And two more, to be sure the slots really were never taken.
    for (var i = 0; i < 2; i++) {
      await client
          .callTool('ordinary_tool', {})
          .timeout(const Duration(seconds: 3));
    }

    // Release the parked calls so the test does not sit for 110 seconds.
    bus.publish(action: 'accepted', summary: 'Accepted something.');
    final results = await Future.wait(parked)
        .timeout(const Duration(seconds: 5));
    for (final r in results) {
      final payload =
          jsonDecode((r.content.first as TextContent).text) as Map<String, dynamic>;
      expect(payload['timed_out'], isFalse);
      expect((payload['decisions'] as List<dynamic>), hasLength(1));
    }
  });

  test('metered tools still queue at three among themselves', () async {
    // The bypass must be opt-in, not a hole in the semaphore for everyone.
    var running = 0;
    var maxRunning = 0;
    final gates = List.generate(6, (_) => Completer<void>());

    for (var i = 0; i < 6; i++) {
      final idx = i;
      registry.registerTool(
        name: 'slow_tool_$idx',
        description: 'Slow tool $idx',
        handler: (args, extra) async {
          running++;
          if (running > maxRunning) maxRunning = running;
          await gates[idx].future;
          running--;
          return CallToolResult(content: [TextContent(text: 'done')]);
        },
      );
    }

    client = await MockMcpClient.connect(mcpServer);

    final calls = [
      for (var i = 0; i < 6; i++) client.callTool('slow_tool_$i', {}),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(maxRunning, lessThanOrEqualTo(3));

    for (final g in gates) {
      g.complete();
    }
    await Future.wait(calls).timeout(const Duration(seconds: 5));
  });

  test('an unmetered tool is still identity-gated', () async {
    // Skipping the semaphore and the audit trail must not skip auth: the
    // identity check lives outside both, and has to stay there.
    final unauthenticatedServer = McpServer(
      const Implementation(name: 'test-server', version: '0.1.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );
    registerProposalFeedbackTools(
      ToolRegistry(
        mcpServer: unauthenticatedServer,
        identity: EnvOperatorIdentity(environmentProvider: () => {}),
        auditLogService: AuditLogService(db),
      ),
      bus,
    );

    client = await MockMcpClient.connect(unauthenticatedServer);
    final result = await client
        .callTool('get_proposal_feedback', {})
        .timeout(const Duration(seconds: 3));

    expect(result.isError, isTrue);
    expect((result.content.first as TextContent).text,
        contains('TFC_USER'));
  });
}
