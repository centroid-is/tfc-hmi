/// End-to-end tests: propose_page, propose_asset, and create_key_mapping
/// MCP tool calls → DB proposal → ProposalWatcher detection.
///
/// Mirrors the pattern from proposal_e2e_test.dart but covers page, asset,
/// and key_mapping proposal types which previously had no E2E coverage.
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  // ── propose_page E2E ──────────────────────────────────────────────────

  test('MCP propose_page tool → DB proposal → ProposalWatcher detects',
      () async {
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

    // Call propose_page tool
    final result = await client.callTool(CallToolRequest(
      name: 'propose_page',
      arguments: {
        'title': 'Pump Overview',
        'assets': [
          {
            'asset_type': 'NumberConfig',
            'key': 'pump3.speed',
            'label': 'Pump 3 Speed',
            'x': 0.1,
            'y': 0.05,
          },
          {
            'asset_type': 'LEDConfig',
            'key': 'pump3.pressure',
            'label': 'Pump 3 Pressure',
          },
        ],
      },
    ));

    // Verify the tool returned a proposal
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join();
    final proposal = jsonDecode(text) as Map<String, dynamic>;
    expect(proposal['_proposal_type'], 'page');
    expect(proposal['title'], 'Pump Overview');
    expect(proposal['key'], 'page-pump-overview');
    expect(proposal['assets'], isList);
    expect((proposal['assets'] as List), hasLength(2));

    // Wait for async DB write from ProposalService
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Verify proposal is in the database
    final rows =
        await db.customSelect('SELECT * FROM mcp_proposal').get();
    expect(rows, hasLength(1));
    expect(rows.first.read<String>('proposal_type'), 'page');
    expect(rows.first.read<String>('title'), 'Pump Overview');
    expect(rows.first.read<String>('operator_id'), 'test-operator');
    expect(rows.first.read<String>('status'), 'pending');

    // Verify proposal JSON preserves asset data with asset_name
    final storedJson =
        jsonDecode(rows.first.read<String>('proposal_json')) as Map<String, dynamic>;
    expect(storedJson['assets'], isList);
    expect((storedJson['assets'] as List).first['asset_name'], 'NumberConfig');
    expect((storedJson['assets'] as List).first['key'], 'pump3.speed');

    // Flutter side: ProposalWatcher detects the proposal
    final watcher = ProposalWatcher(db);
    addTearDown(watcher.dispose);

    await Future<void>.delayed(const Duration(seconds: 4));

    expect(watcher.pending, hasLength(1));
    expect(watcher.pending.first.title, 'Pump Overview');
    expect(watcher.pending.first.proposalType, 'page');
    expect(watcher.pending.first.editorRoute, '/advanced/page-editor');

    // Cleanup
    await client.close();
    server.mcpServer.close();
  });

  // ── propose_asset E2E ─────────────────────────────────────────────────

  test('MCP propose_asset tool → DB proposal → ProposalWatcher detects',
      () async {
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

    // Call propose_asset tool
    final result = await client.callTool(CallToolRequest(
      name: 'propose_asset',
      arguments: {
        'title': 'Pump Station',
        'page_key': '/',
        'children': [
          {
            'asset_type': 'NumberConfig',
            'key': 'pump3.speed',
            'title': 'Pump 3',
          },
          {
            'asset_type': 'LEDConfig',
            'key': 'pump4.status',
            'title': 'Pump 4',
          },
        ],
      },
    ));

    // Verify the tool returned a proposal
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join();
    final proposal = jsonDecode(text) as Map<String, dynamic>;
    expect(proposal['_proposal_type'], 'asset');
    expect(proposal['title'], 'Pump Station');
    expect(proposal['key'], 'asset-pump-station');
    expect(proposal['page_key'], '/');
    expect(proposal['children'], isList);
    final children = proposal['children'] as List;
    expect(children, hasLength(2));
    // Each child must have asset_name for AssetRegistry.parse
    expect(children[0]['asset_name'], 'NumberConfig');
    expect(children[0]['key'], 'pump3.speed');
    expect(children[1]['asset_name'], 'LEDConfig');
    expect(children[1]['key'], 'pump4.status');

    // Wait for async DB write
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Verify proposal is in the database
    final rows =
        await db.customSelect('SELECT * FROM mcp_proposal').get();
    expect(rows, hasLength(1));
    expect(rows.first.read<String>('proposal_type'), 'asset');
    expect(rows.first.read<String>('title'), 'Pump Station');
    expect(rows.first.read<String>('operator_id'), 'test-operator');
    expect(rows.first.read<String>('status'), 'pending');

    // Verify proposal JSON preserves children hierarchy with asset_name
    final storedJson =
        jsonDecode(rows.first.read<String>('proposal_json')) as Map<String, dynamic>;
    expect(storedJson['children'], isList);
    expect((storedJson['children'] as List).first['asset_name'], 'NumberConfig');
    expect((storedJson['children'] as List).first['key'], 'pump3.speed');

    // Flutter side: ProposalWatcher detects the proposal
    final watcher = ProposalWatcher(db);
    addTearDown(watcher.dispose);

    await Future<void>.delayed(const Duration(seconds: 4));

    expect(watcher.pending, hasLength(1));
    expect(watcher.pending.first.title, 'Pump Station');
    expect(watcher.pending.first.proposalType, 'asset');
    expect(watcher.pending.first.editorRoute, '/advanced/page-editor');

    // Cleanup
    await client.close();
    server.mcpServer.close();
  });

  // ── create_key_mapping E2E ────────────────────────────────────────────

  test('MCP create_key_mapping tool → DB proposal → ProposalWatcher detects',
      () async {
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

    // Call create_key_mapping tool
    final result = await client.callTool(CallToolRequest(
      name: 'create_key_mapping',
      arguments: {
        'key': 'belt.speed',
        'namespace': 2,
        'identifier': 'Belt.Speed',
      },
    ));

    // Verify the tool returned a proposal
    final text = result.content
        .whereType<TextContent>()
        .map((c) => c.text)
        .join();
    final proposal = jsonDecode(text) as Map<String, dynamic>;
    expect(proposal['_proposal_type'], 'key_mapping');
    expect(proposal['key'], 'belt.speed');
    expect(proposal['opcua_node'], isNotNull);
    expect(proposal['opcua_node']['namespace'], 2);
    expect(proposal['opcua_node']['identifier'], 'Belt.Speed');

    // Wait for async DB write
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Verify proposal is in the database
    final rows =
        await db.customSelect('SELECT * FROM mcp_proposal').get();
    expect(rows, hasLength(1));
    expect(rows.first.read<String>('proposal_type'), 'key_mapping');
    expect(rows.first.read<String>('operator_id'), 'test-operator');
    expect(rows.first.read<String>('status'), 'pending');

    // Verify proposal JSON preserves OPC UA node data
    final storedJson =
        jsonDecode(rows.first.read<String>('proposal_json')) as Map<String, dynamic>;
    expect(storedJson['key'], 'belt.speed');
    expect(storedJson['opcua_node']['namespace'], 2);
    expect(storedJson['opcua_node']['identifier'], 'Belt.Speed');

    // Flutter side: ProposalWatcher detects the proposal
    final watcher = ProposalWatcher(db);
    addTearDown(watcher.dispose);

    await Future<void>.delayed(const Duration(seconds: 4));

    expect(watcher.pending, hasLength(1));
    expect(watcher.pending.first.proposalType, 'key_mapping');
    expect(watcher.pending.first.editorRoute, '/advanced/key-repository');

    // Cleanup
    await client.close();
    server.mcpServer.close();
  });

  // ── Mixed proposal types E2E ──────────────────────────────────────────

  test('All three proposal types coexist in DB and ProposalWatcher', () async {
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

    // 1. Create a page proposal
    await client.callTool(CallToolRequest(
      name: 'propose_page',
      arguments: {
        'title': 'Motor Dashboard',
        'assets': [
          {
            'asset_type': 'TextAssetConfig',
            'key': 'motors-label',
            'label': 'Motors',
          },
        ],
      },
    ));

    // 2. Create an asset proposal
    await client.callTool(CallToolRequest(
      name: 'propose_asset',
      arguments: {
        'title': 'Motor Group',
        'children': [
          {
            'asset_type': 'NumberConfig',
            'key': 'motor1.speed',
            'title': 'Motor 1',
          },
        ],
      },
    ));

    // 3. Create a key mapping proposal
    await client.callTool(CallToolRequest(
      name: 'create_key_mapping',
      arguments: {
        'key': 'motor1.speed',
        'namespace': 3,
        'identifier': 'Motor1.Speed',
      },
    ));

    // Wait for async DB writes
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Verify all three are in the database
    final rows = await db
        .customSelect('SELECT * FROM mcp_proposal ORDER BY id ASC')
        .get();
    expect(rows, hasLength(3));
    expect(rows[0].read<String>('proposal_type'), 'page');
    expect(rows[0].read<String>('title'), 'Motor Dashboard');
    expect(rows[1].read<String>('proposal_type'), 'asset');
    expect(rows[1].read<String>('title'), 'Motor Group');
    expect(rows[2].read<String>('proposal_type'), 'key_mapping');

    // ProposalWatcher picks up all three
    final watcher = ProposalWatcher(db);
    addTearDown(watcher.dispose);

    await Future<void>.delayed(const Duration(seconds: 4));

    expect(watcher.pending, hasLength(3));

    final types = watcher.pending.map((p) => p.proposalType).toList();
    expect(types, contains('page'));
    expect(types, contains('asset'));
    expect(types, contains('key_mapping'));

    // Verify correct editor routes for each type
    final routeMap = {
      for (final p in watcher.pending) p.proposalType: p.editorRoute,
    };
    expect(routeMap['page'], '/advanced/page-editor');
    expect(routeMap['asset'], '/advanced/page-editor');
    expect(routeMap['key_mapping'], '/advanced/key-repository');

    // Cleanup
    await client.close();
    server.mcpServer.close();
  });
}
