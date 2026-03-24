/// End-to-end test: Multiple MCP create_alarm calls → multiple DB proposals.
///
/// Verifies that when the LLM calls create_alarm 10 times (e.g., "create an
/// alarm for all 10 motors"), each call produces a separate proposal in the
/// database and each is independently trackable via ProposalWatcher and
/// ProposalStateNotifier.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart';

import 'package:tfc/providers/proposal_state.dart';
import 'package:tfc/providers/proposal_watcher.dart';

/// Mock client that connects in-process to an MCP server.
Future<McpClient> _connectClient(McpServer server) async {
  final clientToServer = StreamController<List<int>>();
  final serverToClient = StreamController<List<int>>();

  final serverTransport = IOStreamTransport(
    stream: clientToServer.stream,
    sink: serverToClient.sink,
  );
  final clientTransport = IOStreamTransport(
    stream: serverToClient.stream,
    sink: clientToServer.sink,
  );

  await server.connect(serverTransport);

  final client = McpClient(
    const Implementation(name: 'test-client', version: '0.1.0'),
    options: McpClientOptions(
      capabilities: ClientCapabilities(
        sampling: ClientCapabilitiesSampling(),
      ),
    ),
  );
  await client.connect(clientTransport);
  return client;
}

/// No-op reader stubs.
class _EmptyStateReader implements StateReader {
  @override
  Map<String, dynamic> get currentValues => {};
  @override
  dynamic getValue(String key) => null;
  @override
  List<String> get keys => [];
}

class _EmptyAlarmReader implements AlarmReader {
  @override
  List<Map<String, dynamic>> get alarmConfigs => [];
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemoryForTest();
  });

  tearDown(() async {
    await db.close();
  });

  test('10 create_alarm calls produce 10 separate proposals in DB', () async {
    final env = {'TFC_USER': 'test-operator'};
    final identity = EnvOperatorIdentity(environmentProvider: () => env);

    final server = TfcMcpServer(
      identity: identity,
      database: db,
      stateReader: _EmptyStateReader(),
      alarmReader: _EmptyAlarmReader(),
      toggles: const McpToolToggles(proposalsEnabled: true),
    );

    final client = await _connectClient(server.mcpServer);

    // Call create_alarm 10 times (simulating "create alarm for all 10 motors")
    final proposals = <Map<String, dynamic>>[];
    for (var i = 1; i <= 10; i++) {
      final result = await client.callTool(CallToolRequest(
        name: 'create_alarm',
        arguments: {
          'title': 'Motor $i Fault',
          'key': 'motor$i.fault',
          'description': 'Motor $i fault alarm',
          'rules': [
            {
              'level': 'error',
              'formula': 'motor$i.fault > 0',
            },
          ],
        },
      ));

      final text = result.content
          .whereType<TextContent>()
          .map((c) => c.text)
          .join();
      final proposal = jsonDecode(text) as Map<String, dynamic>;
      proposals.add(proposal);
    }

    // Verify all 10 proposals are unique
    expect(proposals, hasLength(10));
    final uids = proposals.map((p) => p['uid'] as String).toSet();
    expect(uids, hasLength(10), reason: 'All UIDs should be unique');

    // Verify all have correct type
    for (final p in proposals) {
      expect(p['_proposal_type'], 'alarm');
    }

    // Wait for async DB writes
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Verify all 10 are in the database
    final rows =
        await db.customSelect('SELECT * FROM mcp_proposal ORDER BY id ASC').get();
    expect(rows, hasLength(10));

    for (var i = 0; i < 10; i++) {
      expect(rows[i].read<String>('proposal_type'), 'alarm');
      expect(rows[i].read<String>('title'), 'Motor ${i + 1} Fault');
      expect(rows[i].read<String>('status'), 'pending');
      expect(rows[i].read<String>('operator_id'), 'test-operator');
    }

    // Cleanup
    await client.close();
    server.mcpServer.close();
  });

  test('ProposalStateNotifier tracks 10 proposals and batch-accepts them',
      () async {
    final notifier = ProposalStateNotifier(db);

    // Insert 10 proposals and add to notifier
    for (var i = 1; i <= 10; i++) {
      await db.customInsert(
        'INSERT INTO mcp_proposal '
        '(proposal_type, title, proposal_json, operator_id, status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString('alarm'),
          Variable.withString('Motor $i Fault'),
          Variable.withString(
              '{"_proposal_type":"alarm","uid":"motor-$i","title":"Motor $i Fault"}'),
          Variable.withString('test-operator'),
          Variable.withString('pending'),
          Variable.withString(DateTime.now().toIso8601String()),
        ],
      );
    }

    final rows = await db
        .customSelect('SELECT id, title, proposal_json FROM mcp_proposal ORDER BY id ASC')
        .get();
    for (final row in rows) {
      notifier.addProposal(PendingProposal(
        id: row.read<int>('id'),
        proposalType: 'alarm',
        title: row.read<String>('title'),
        proposalJson: row.read<String>('proposal_json'),
        operatorId: 'test-operator',
        createdAt: DateTime.now(),
      ));
    }

    expect(notifier.state.pendingCount, 10);
    expect(notifier.state.ofType('alarm'), hasLength(10));

    // Batch accept all
    final accepted = await notifier.acceptAllOfType('alarm');
    expect(accepted, hasLength(10));
    expect(notifier.state.pendingCount, 0);

    // Verify DB
    final dbRows = await db
        .customSelect(
            "SELECT status FROM mcp_proposal WHERE status = 'accepted'")
        .get();
    expect(dbRows, hasLength(10));
  });

  test('Inline proposals from tool results are deduped with DB proposals',
      () async {
    final notifier = ProposalStateNotifier(db);

    // Simulate ChatNotifier._surfaceProposalFromToolResult adding inline proposals
    // (negative IDs, as the real code does)
    for (var i = 1; i <= 5; i++) {
      notifier.addProposal(PendingProposal(
        id: -i,
        proposalType: 'alarm',
        title: 'Motor $i Fault',
        proposalJson:
            '{"_proposal_type":"alarm","uid":"motor-$i","title":"Motor $i Fault"}',
        operatorId: 'local',
        createdAt: DateTime.now(),
      ));
    }

    expect(notifier.state.pendingCount, 5);

    // Now simulate DB-sourced proposals arriving with positive IDs but same JSON
    for (var i = 1; i <= 5; i++) {
      notifier.addProposal(PendingProposal(
        id: i * 100, // positive DB IDs
        proposalType: 'alarm',
        title: 'Motor $i Fault',
        proposalJson:
            '{"_proposal_type":"alarm","uid":"motor-$i","title":"Motor $i Fault"}',
        operatorId: 'test-operator',
        createdAt: DateTime.now(),
      ));
    }

    // Deduplication by proposalJson should keep count at 5
    expect(notifier.state.pendingCount, 5);
  });
}
