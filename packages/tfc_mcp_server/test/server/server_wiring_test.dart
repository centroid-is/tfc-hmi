import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/drawing_index.dart';
import 'package:tfc_mcp_server/src/server.dart';
import 'package:tfc_mcp_server/src/tools/tool_toggles.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_drawing_index.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('Server wiring integration', () {
    late ServerDatabase db;
    late MockStateReader stateReader;
    late MockAlarmReader alarmReader;
    late MockDrawingIndex drawingIndex;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      stateReader = MockStateReader();
      stateReader.setValue('pump3.speed', 1750);
      stateReader.setValue('tank1.level', 85.2);

      alarmReader = MockAlarmReader();
      alarmReader.addAlarmConfig({
        'uid': 'alarm-001',
        'key': 'pump3.overtemp',
        'title': 'Pump 3 Overtemp',
        'description': 'Pump 3 exceeded temperature threshold',
        'rules': '{"condition":"temp > 80"}',
      });

      drawingIndex = MockDrawingIndex();
      drawingIndex.addResult(const DrawingSearchResult(
        drawingName: 'Panel-A Main Wiring',
        pageNumber: 3,
        assetKey: 'panel-A',
        componentName: 'relay K3',
      ));
    });

    tearDown(() async {
      await db.close();
    });

    TfcMcpServer createWiredServer({
      Map<String, String>? env,
      bool includeDrawings = true,
      McpToolToggles? toggles,
    }) {
      final identity = EnvOperatorIdentity(
        environmentProvider: () => env ?? {'TFC_USER': 'op1'},
      );
      return TfcMcpServer(
        identity: identity,
        database: db,
        stateReader: stateReader,
        alarmReader: alarmReader,
        drawingIndex: includeDrawings ? drawingIndex : null,
        toggles: toggles ?? McpToolToggles.allEnabled,
      );
    }

    test('1. All 22 expected tools are registered', () async {
      final server = createWiredServer();
      final client = await MockMcpClient.connect(server.mcpServer);
      try {
        final tools = await client.listTools();
        final toolNames = tools.map((t) => t.name).toSet();

        // All 22 expected tools (16 read + 6 write)
        expect(toolNames, containsAll([
          // Read tools
          'ping',
          'list_tags',
          'get_tag_value',
          'list_alarms',
          'get_alarm_detail',
          'query_alarm_history',
          'list_pages',
          'list_assets',
          'get_asset_detail',
          'list_key_mappings',
          'list_alarm_definitions',
          'list_asset_types',
          'search_drawings',
          'get_drawing_page',
          'query_trend_data',
          'diagnose_asset',
          // Write tools
          'create_alarm',
          'update_alarm',
          'create_key_mapping',
          'update_key_mapping',
          'propose_page',
          'propose_asset',
        ]));

        expect(toolNames, hasLength(22));
      } finally {
        await client.close();
      }
    });

    test('2. Calling list_tags with valid identity creates audit record',
        () async {
      final server = createWiredServer();
      final client = await MockMcpClient.connect(server.mcpServer);
      try {
        final result =
            await client.callTool('list_tags', {'filter': 'pump'});

        expect(result.isError, isNot(true));

        // Verify audit record was created
        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        expect(records.first.operatorId, equals('op1'));
        expect(records.first.tool, equals('list_tags'));
        expect(records.first.status, equals('success'));
      } finally {
        await client.close();
      }
    });

    test(
        '3. Progressive discovery: every list tool has a corresponding detail tool',
        () async {
      final server = createWiredServer();
      final client = await MockMcpClient.connect(server.mcpServer);
      try {
        final tools = await client.listTools();
        final toolNames = tools.map((t) => t.name).toSet();

        // Progressive discovery pairs:
        // list_tags -> get_tag_value
        // list_alarms -> get_alarm_detail
        // list_assets -> get_asset_detail
        // list_pages -> get_asset_detail (shared detail tool)
        // search_drawings is a search tool, not a list/detail pair

        final discoveryPairs = {
          'list_tags': 'get_tag_value',
          'list_alarms': 'get_alarm_detail',
          'list_assets': 'get_asset_detail',
          'list_pages': 'get_asset_detail',
        };

        for (final entry in discoveryPairs.entries) {
          expect(toolNames, contains(entry.key),
              reason: 'Missing list tool: ${entry.key}');
          expect(toolNames, contains(entry.value),
              reason:
                  'Missing detail tool: ${entry.value} for ${entry.key}');
        }
      } finally {
        await client.close();
      }
    });

    test('4. Identity gate: no TFC_USER returns error and no audit record',
        () async {
      final server = createWiredServer(env: {});
      final client = await MockMcpClient.connect(server.mcpServer);
      try {
        final result = await client.callTool('list_tags', {});

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text, contains('TFC_USER'));

        // No audit record
        final records = await db.select(db.auditLog).get();
        expect(records, isEmpty);
      } finally {
        await client.close();
      }
    });

    test('5. Drawing tools always registered (DriftDrawingIndex fallback)',
        () async {
      // Even without an explicit DrawingIndex, DriftDrawingIndex is used
      // as the default fallback so drawing tools are always available.
      final server = createWiredServer(includeDrawings: false);
      final client = await MockMcpClient.connect(server.mcpServer);
      try {
        final tools = await client.listTools();
        final toolNames = tools.map((t) => t.name).toSet();

        // All 22 tools are registered (drawing tools always present)
        expect(toolNames, hasLength(22));
        expect(toolNames, contains('search_drawings'));
        expect(toolNames, contains('get_drawing_page'));
      } finally {
        await client.close();
      }
    });
  });
}
