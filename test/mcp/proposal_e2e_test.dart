/// End-to-end test: MCP tool call → DB proposal → ProposalWatcher detection.
///
/// Verifies the full chain from server-side ProposalService writing to the
/// database through to the Flutter-side ProposalWatcher picking it up.
/// Uses AppDatabase (which has the mcp_proposal table) as both the
/// MCP server's database and the Flutter app's database — just like
/// in-process mode.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/safety/risk_gate.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart';

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

  test('MCP create_alarm tool → DB proposal → ProposalWatcher detects',
      () async {
    // 1. Create a real TfcMcpServer with AppDatabase (like in-process mode)
    final env = {'TFC_USER': 'test-operator'};
    final identity = EnvOperatorIdentity(environmentProvider: () => env);

    final server = TfcMcpServer(
      identity: identity,
      database: db,
      stateReader: _EmptyStateReader(),
      alarmReader: _EmptyAlarmReader(),
      toggles: const McpToolToggles(proposalsEnabled: true),
    );

    // 2. Connect a mock client
    final client = await _connectClient(server.mcpServer);

    // 3. Call create_alarm tool
    final result = await client.callTool(CallToolRequest(
      name: 'create_alarm',
      arguments: {
        'title': 'Pump Overcurrent',
        'key': 'pump3.overcurrent',
        'description': 'Motor current exceeded safe threshold',
        'rules': [
          {
            'level': 'warning',
            'formula': 'pump3.current > 15',
            'acknowledge_required': false,
          },
          {
            'level': 'error',
            'formula': 'pump3.current > 20',
            'acknowledge_required': true,
          },
        ],
      },
    ));

    // 4. Verify the tool returned a proposal
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join();
    final proposal = jsonDecode(text) as Map<String, dynamic>;
    expect(proposal['_proposal_type'], 'alarm');
    expect(proposal['title'], 'Pump Overcurrent');

    // 5. Wait for async DB write from ProposalService
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // 6. Verify proposal is in the database
    final rows =
        await db.customSelect('SELECT * FROM mcp_proposal').get();
    expect(rows, hasLength(1));
    expect(rows.first.read<String>('proposal_type'), 'alarm');
    expect(rows.first.read<String>('title'), 'Pump Overcurrent');
    expect(rows.first.read<String>('operator_id'), 'test-operator');
    expect(rows.first.read<String>('status'), 'pending');

    // 7. Flutter side: ProposalWatcher detects the proposal
    final watcher = ProposalWatcher(db);
    addTearDown(watcher.dispose);

    await Future<void>.delayed(const Duration(seconds: 4));

    expect(watcher.pending, hasLength(1));
    expect(watcher.pending.first.title, 'Pump Overcurrent');
    expect(watcher.pending.first.proposalType, 'alarm');
    expect(watcher.pending.first.editorRoute, '/advanced/alarm-editor');

    // 8. Cleanup
    await client.close();
    server.mcpServer.close();
  });
}
