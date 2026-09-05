import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/server.dart';
import 'package:tfc_mcp_server/src/server_instructions.dart';
import 'package:tfc_mcp_server/src/services/proposal_feedback_bus.dart';
import 'package:tfc_mcp_server/src/tools/tool_toggles.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

/// A fresh client on a fresh machine has to be able to learn how to drive
/// this server from the server itself. Two delivery slots carry that:
/// `instructions` at initialize, and the knowledge resource.
///
/// These tests exist because the knowledge resource spent months telling
/// clients the AI "CANNOT modify layouts directly" after propose_asset and
/// update_asset had shipped. Documentation that ships with the code still
/// goes stale unless something checks it.
void main() {
  late ServerDatabase db;
  late ProposalFeedbackBus bus;

  setUp(() async {
    db = ServerDatabase.inMemory();
    await db.customStatement('SELECT 1');
    bus = ProposalFeedbackBus();
  });

  tearDown(() async {
    await bus.close();
    await db.close();
  });

  TfcMcpServer createServer({
    McpToolToggles toggles = McpToolToggles.allEnabled,
    ProposalFeedbackBus? feedbackBus,
  }) {
    return TfcMcpServer(
      database: db,
      stateReader: MockStateReader(),
      alarmReader: MockAlarmReader(),
      toggles: toggles,
      feedbackBus: feedbackBus,
    );
  }

  group('instructions at initialize', () {
    test('the client receives them without asking for anything', () async {
      final client = await MockMcpClient.connect(createServer().mcpServer);
      try {
        expect(client.instructions, isNotNull);
        expect(client.instructions, kTfcServerInstructions);
      } finally {
        await client.close();
      }
    });

    test('they cover the rules a client cannot safely guess', () async {
      final client = await MockMcpClient.connect(createServer().mcpServer);
      try {
        final text = client.instructions!;
        // Every write tool is a proposal, not a write.
        expect(text, contains('PROPOSAL'));
        expect(text, contains('await_proposal_feedback'));
        // The alias that killed 28 sensor mappings when it was omitted.
        expect(text, contains('server_alias'));
        expect(text, contains('st201'));
        expect(text, contains('opcua_node'));
        // Verify before proposing.
        expect(text, contains('shared_preferences.json'));
        // Transport.
        expect(text, contains('127.0.0.1:8765/mcp'));
        expect(text, contains('mcp-session-id'));
        // Concurrency.
        expect(text, contains('concurrency is 3'));
      } finally {
        await client.close();
      }
    });

    test('every tool named in the instructions is actually registered',
        () async {
      final server = createServer(feedbackBus: bus);
      final client = await MockMcpClient.connect(server.mcpServer);
      try {
        final registered = (await client.listTools()).map((t) => t.name).toSet();
        final text = client.instructions!;
        // The tools the instructions tell a client to reach for. Naming one
        // that does not exist sends a fresh client hunting for a phantom.
        // browse_nodes is left out: it only registers when a live PLC
        // session supplies a NodeBrowser, which this fixture does not.
        const named = [
          'create_alarm',
          'update_alarm',
          'delete_alarm',
          'create_key_mapping',
          'update_key_mapping',
          'delete_key_mapping',
          'propose_page',
          'propose_asset',
          'update_asset',
          'get_tag_value',
          'list_pages',
          'list_assets',
          'list_asset_types',
          'get_asset_detail',
          'list_key_mappings',
          'list_alarm_definitions',
          'await_proposal_feedback',
          'get_proposal_feedback',
        ];
        for (final name in named) {
          expect(text, contains(name),
              reason: 'the instructions should mention $name');
          expect(registered, contains(name),
              reason: '$name is named in the instructions but not registered');
        }
      } finally {
        await client.close();
      }
    });
  });

  group('knowledge resource', () {
    test('no longer claims the AI cannot modify pages or alarms', () async {
      final client = await MockMcpClient.connect(createServer().mcpServer);
      try {
        final result = await client.readResource('scada://source/knowledge');
        final text = (result.contents.first as dynamic).text as String;

        expect(text, isNot(contains('CANNOT modify layouts')));
        expect(text, isNot(contains('CANNOT acknowledge, silence, or modify')));
        expect(text, contains('propose_asset'));
        expect(text, contains('server_alias'));
        expect(text, contains('await_proposal_feedback'));
      } finally {
        await client.close();
      }
    });
  });

  group('feedback tool registration', () {
    test('registered when a bus is supplied', () async {
      final client =
          await MockMcpClient.connect(createServer(feedbackBus: bus).mcpServer);
      try {
        final names = (await client.listTools()).map((t) => t.name).toSet();
        expect(names, contains('await_proposal_feedback'));
        expect(names, contains('get_proposal_feedback'));
      } finally {
        await client.close();
      }
    });

    test('absent without one -- a standalone server has no operator', () async {
      final client = await MockMcpClient.connect(createServer().mcpServer);
      try {
        final names = (await client.listTools()).map((t) => t.name).toSet();
        expect(names, isNot(contains('await_proposal_feedback')));
        expect(names, isNot(contains('get_proposal_feedback')));
      } finally {
        await client.close();
      }
    });

    test('absent when the proposal tool group is turned off', () async {
      const noProposals = McpToolToggles(proposalsEnabled: false);
      final client = await MockMcpClient.connect(
          createServer(toggles: noProposals, feedbackBus: bus).mcpServer);
      try {
        final names = (await client.listTools()).map((t) => t.name).toSet();
        expect(names, isNot(contains('await_proposal_feedback')),
            reason: 'no proposals means nothing to give feedback on');
      } finally {
        await client.close();
      }
    });
  });

  group('capabilities', () {
    test('logging is advertised, so server-sent notifications are legitimate',
        () async {
      final client = await MockMcpClient.connect(createServer().mcpServer);
      try {
        expect(client.serverCapabilities?.logging, isNotNull);
      } finally {
        await client.close();
      }
    });
  });
}
