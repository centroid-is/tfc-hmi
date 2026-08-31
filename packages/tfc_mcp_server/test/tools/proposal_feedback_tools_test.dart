import 'dart:async';
import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/services/proposal_feedback_bus.dart';
import 'package:tfc_mcp_server/src/tools/proposal_feedback_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/test_database.dart';

/// End to end over a real MCP client: the operator clicks a button and an
/// external client learns what was clicked, in words.
void main() {
  late ServerDatabase db;
  late McpServer mcpServer;
  late MockMcpClient client;
  late ProposalFeedbackBus bus;

  setUp(() async {
    db = createTestDatabase();
    await db.customStatement('SELECT 1');

    mcpServer = McpServer(
      const Implementation(name: 'test-server', version: '0.1.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );

    final registry = ToolRegistry(
      mcpServer: mcpServer,
      auditLogService: AuditLogService(db),
    );

    bus = ProposalFeedbackBus();
    registerProposalFeedbackTools(registry, bus);

    client = await MockMcpClient.connect(mcpServer);
  });

  tearDown(() async {
    await client.close();
    await bus.close();
    await db.close();
  });

  Map<String, dynamic> decode(CallToolResult result) {
    expect(result.isError, isNot(true), reason: 'tool returned an error');
    final text = (result.content.first as TextContent).text;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// The decision a batch accept in the page editor produces.
  void publishAssetBatch() {
    bus.publish(
      action: 'accepted',
      summary: 'Accepted 2 asset update proposals: '
          '"CVS02.CN01.PX01.Fault: server_alias -> st201", '
          '"Line 1: keys -> SPB01.Recipe, SPB02.Recipe, SPB03.Recipe".',
      proposals: [
        {
          'title': 'CVS02.CN01.PX01.Fault: server_alias -> st201',
          'type': 'asset_update',
          'op': 'update',
        },
        {
          'title': 'Line 1: keys -> SPB01.Recipe, SPB02.Recipe, SPB03.Recipe',
          'type': 'asset_update',
          'op': 'update',
        },
      ],
    );
  }

  group('both tools are registered', () {
    test('they show up in tools/list', () async {
      final names = (await client.listTools()).map((t) => t.name).toSet();
      expect(names, containsAll(
          ['await_proposal_feedback', 'get_proposal_feedback']));
    });
  });

  group('get_proposal_feedback', () {
    test('returns nothing, promptly, when nobody has decided anything',
        () async {
      final payload = decode(await client.callTool('get_proposal_feedback', {})
          .timeout(const Duration(seconds: 2)));

      expect(payload['decisions'], isEmpty);
      expect(payload['last_seq'], 0);
      expect(payload['truncated'], isFalse);
      expect(payload['timed_out'], isFalse);
    });

    test('carries the banner text the operator actually saw', () async {
      publishAssetBatch();

      final payload = decode(await client.callTool('get_proposal_feedback', {}));

      final decisions = payload['decisions'] as List<dynamic>;
      expect(decisions, hasLength(1));
      final decision = decisions.single as Map<String, dynamic>;

      expect(decision['action'], 'accepted');
      expect(decision['count'], 2);
      // This is the requirement: the payload has to read like a sentence a
      // person could act on, naming what was accepted.
      expect(
        decision['summary'],
        'Accepted 2 asset update proposals: '
            '"CVS02.CN01.PX01.Fault: server_alias -> st201", '
            '"Line 1: keys -> SPB01.Recipe, SPB02.Recipe, SPB03.Recipe".',
      );

      final proposals = decision['proposals'] as List<dynamic>;
      expect(proposals, hasLength(2));
      expect((proposals.first as Map)['title'],
          'CVS02.CN01.PX01.Fault: server_alias -> st201');
      expect((proposals.first as Map)['type'], 'asset_update');
      expect((proposals.first as Map)['op'], 'update');

      expect(payload['last_seq'], 1);
    });

    test('since replays nothing already delivered', () async {
      publishAssetBatch();
      final first = decode(await client.callTool('get_proposal_feedback', {}));
      final cursor = first['last_seq'] as int;

      final second = decode(await client
          .callTool('get_proposal_feedback', {'since': cursor}));
      expect(second['decisions'], isEmpty);
      expect(second['last_seq'], cursor);

      bus.publish(action: 'rejected', summary: 'Rejected the alarm proposal.');
      final third = decode(await client
          .callTool('get_proposal_feedback', {'since': cursor}));
      expect((third['decisions'] as List<dynamic>).single,
          containsPair('action', 'rejected'));
    });

  });

  group('await_proposal_feedback', () {
    test('returns the moment the operator decides', () async {
      final pending = client.callTool(
          'await_proposal_feedback', {'timeout_seconds': 30});

      // The call is parked in the server; nothing has been decided yet.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      publishAssetBatch();

      final payload = decode(await pending.timeout(const Duration(seconds: 3)));
      expect(payload['timed_out'], isFalse);
      expect((payload['decisions'] as List<dynamic>).single,
          containsPair('action', 'accepted'));
    });

    test('returns timed_out rather than an error when nothing happens',
        () async {
      final payload = decode(await client
          .callTool('await_proposal_feedback', {'timeout_seconds': 1})
          .timeout(const Duration(seconds: 5)));

      expect(payload['timed_out'], isTrue);
      expect(payload['decisions'], isEmpty);
      // The cursor still comes back so the caller can re-arm unchanged.
      expect(payload['last_seq'], 0);
    });

    test('a timeout below the floor is clamped rather than rejected',
        () async {
      final payload = decode(await client
          .callTool('await_proposal_feedback', {'timeout_seconds': 0})
          .timeout(const Duration(seconds: 5)));
      expect(payload['timed_out'], isTrue);
    });

    test('returns the backlog immediately when it already has one', () async {
      publishAssetBatch();
      final payload = decode(await client
          .callTool('await_proposal_feedback', {'timeout_seconds': 30})
          .timeout(const Duration(seconds: 2)));
      expect(payload['timed_out'], isFalse);
      expect((payload['decisions'] as List<dynamic>), hasLength(1));
    });
  });
}
