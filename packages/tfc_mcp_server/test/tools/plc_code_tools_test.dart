import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/services/plc_code_service.dart';
import 'package:tfc_mcp_server/src/tools/plc_code_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_plc_code_index.dart';

/// Stub [KeyMappingLookup] that returns canned results for test keys.
class _StubKeyMappingLookup implements KeyMappingLookup {
  final List<Map<String, dynamic>> _mappings;

  _StubKeyMappingLookup([List<Map<String, dynamic>>? mappings])
      : _mappings = mappings ?? [];

  @override
  Future<List<Map<String, dynamic>>> listKeyMappings({
    String? filter,
    int limit = 50,
  }) async {
    if (filter == null) return _mappings;
    return _mappings
        .where((m) =>
            (m['key'] as String?)?.contains(filter) == true ||
            (m['title'] as String?)?.contains(filter) == true)
        .take(limit)
        .toList();
  }
}

void main() {
  group('search_plc_code tool', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockPlcCodeIndex mockIndex;
    late MockMcpClient client;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      mockIndex = MockPlcCodeIndex();

      // Populate test data: a function block with variables
      await mockIndex.indexAsset('plc-1', [
        const ParsedCodeBlock(
          name: 'FB_Pump',
          type: 'FunctionBlock',
          declaration: 'VAR\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR',
          implementation: 'pump3_speed := 50.0;\nIF pump3_running THEN\n  // pump logic\nEND_IF;',
          fullSource:
              'VAR\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR\npump3_speed := 50.0;\nIF pump3_running THEN\n  // pump logic\nEND_IF;',
          filePath: 'POUs/FB_Pump.TcPOU',
          variables: [
            ParsedVariable(
                name: 'pump3_speed', type: 'REAL', section: 'VAR'),
            ParsedVariable(
                name: 'pump3_running', type: 'BOOL', section: 'VAR'),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  global_temp : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  global_temp : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
                name: 'global_temp', type: 'REAL', section: 'VAR_GLOBAL'),
          ],
          children: [],
        ),
      ]);

      // Key mapping lookup with OPC UA identifier for pump3.speed
      // The identifier maps to FB_Pump.pump3_speed which exists in indexed data
      final keyMappings = _StubKeyMappingLookup([
        {
          'key': 'pump3.speed',
          'title': 'Pump 3 Speed',
          'identifier': 'ns=4;s=FB_Pump.pump3_speed',
        },
      ]);

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      final plcCodeService = PlcCodeService(mockIndex, keyMappings);
      registerPlcCodeTools(registry, plcCodeService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('text mode search returns metadata-only results', () async {
      final result = await client.callTool(
        'search_plc_code',
        {'query': 'pump', 'mode': 'text'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('PLC Code Search Results'));
      expect(text, contains('FB_Pump'));
      expect(text, contains('FunctionBlock'));
      expect(text, contains('plc-1'));
      // Should NOT contain full source code
      expect(text, isNot(contains('pump3_speed := 50.0')));
    });

    test('key mode search uses searchByKey for OPC UA correlation', () async {
      final result = await client.callTool(
        'search_plc_code',
        {'query': 'pump3.speed', 'mode': 'key'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('PLC Code Search Results'));
      // searchByKey should resolve pump3.speed -> GVL_Main.pump3_speed
    });

    test('variable mode searches PLC variable names directly', () async {
      final result = await client.callTool(
        'search_plc_code',
        {'query': 'pump3_speed', 'mode': 'variable'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('PLC Code Search Results'));
      expect(text, contains('pump3_speed'));
      expect(text, contains('REAL'));
    });

    test('default mode is text when mode not provided', () async {
      final result = await client.callTool(
        'search_plc_code',
        {'query': 'pump'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      // Text mode searches fullSource -- FB_Pump matches 'pump'
      expect(text, contains('FB_Pump'));
    });

    test('limit parameter clamped to 1-100 range', () async {
      // limit=0 should be clamped to 1
      final result0 = await client.callTool(
        'search_plc_code',
        {'query': 'pump', 'limit': 0},
      );
      expect(result0.isError, isNot(true));

      // limit=200 should be clamped to 100
      final result200 = await client.callTool(
        'search_plc_code',
        {'query': 'pump', 'limit': 200},
      );
      expect(result200.isError, isNot(true));
    });

    test('empty index returns "No PLC code matches" message', () async {
      mockIndex.clear();
      final result = await client.callTool(
        'search_plc_code',
        {'query': 'anything'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('No PLC code matches'));
    });

    test('no matches returns "No PLC code matches" message', () async {
      final result = await client.callTool(
        'search_plc_code',
        {'query': 'nonexistent_xyz_abc'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('No PLC code matches'));
    });

    test('asset_filter parameter passed through to service', () async {
      // Add data to a second asset
      await mockIndex.indexAsset('plc-2', [
        const ParsedCodeBlock(
          name: 'FB_Motor',
          type: 'FunctionBlock',
          declaration: 'VAR\n  motor_speed : REAL;\nEND_VAR',
          implementation: 'motor_speed := 100.0;',
          fullSource:
              'VAR\n  motor_speed : REAL;\nEND_VAR\nmotor_speed := 100.0;',
          filePath: 'POUs/FB_Motor.TcPOU',
          variables: [
            ParsedVariable(
                name: 'motor_speed', type: 'REAL', section: 'VAR'),
          ],
          children: [],
        ),
      ]);

      // Search with asset_filter should only return plc-1 results
      final result = await client.callTool(
        'search_plc_code',
        {'query': 'speed', 'mode': 'variable', 'asset_filter': 'plc-1'},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('pump3_speed'));
      expect(text, isNot(contains('motor_speed')));
    });
  });

  group('get_plc_code_block tool', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockPlcCodeIndex mockIndex;
    late MockMcpClient client;

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      mockIndex = MockPlcCodeIndex();

      await mockIndex.indexAsset('plc-1', [
        const ParsedCodeBlock(
          name: 'FB_Pump',
          type: 'FunctionBlock',
          declaration: 'VAR\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR',
          implementation: 'pump3_speed := 50.0;\nIF pump3_running THEN\n  // pump logic\nEND_IF;',
          fullSource:
              'VAR\n  pump3_speed : REAL;\n  pump3_running : BOOL;\nEND_VAR\npump3_speed := 50.0;\nIF pump3_running THEN\n  // pump logic\nEND_IF;',
          filePath: 'POUs/FB_Pump.TcPOU',
          variables: [
            ParsedVariable(
                name: 'pump3_speed', type: 'REAL', section: 'VAR'),
            ParsedVariable(
                name: 'pump3_running', type: 'BOOL', section: 'VAR'),
          ],
          children: [],
        ),
        const ParsedCodeBlock(
          name: 'GVL_Main',
          type: 'GVL',
          declaration: 'VAR_GLOBAL\n  global_temp : REAL;\nEND_VAR',
          implementation: null,
          fullSource: 'VAR_GLOBAL\n  global_temp : REAL;\nEND_VAR',
          filePath: 'GVLs/GVL_Main.TcGVL',
          variables: [
            ParsedVariable(
                name: 'global_temp', type: 'REAL', section: 'VAR_GLOBAL'),
          ],
          children: [],
        ),
      ]);

      final keyMappings = _StubKeyMappingLookup();

      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);

      mcpServer = McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      final plcCodeService = PlcCodeService(mockIndex, keyMappings);
      registerPlcCodeTools(registry, plcCodeService);

      client = await MockMcpClient.connect(mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('returns full code block with declaration, implementation, and variables',
        () async {
      // Block ID 1 is the first indexed block (FB_Pump)
      final result = await client.callTool(
        'get_plc_code_block',
        {'block_id': 1},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Block: FB_Pump (FunctionBlock)'));
      expect(text, contains('Asset: plc-1'));
      expect(text, contains('File: POUs/FB_Pump.TcPOU'));
      expect(text, contains('=== Declaration ==='));
      expect(text, contains('pump3_speed : REAL'));
      expect(text, contains('=== Implementation ==='));
      expect(text, contains('pump3_speed := 50.0'));
      expect(text, contains('=== Variables'));
      expect(text, contains('pump3_running'));
    });

    test('variables listed with name, type, section, qualifiedName', () async {
      final result = await client.callTool(
        'get_plc_code_block',
        {'block_id': 1},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('VAR'));
      expect(text, contains('pump3_speed'));
      expect(text, contains('REAL'));
      expect(text, contains('FB_Pump.pump3_speed'));
    });

    test('returns isError for unknown block_id', () async {
      final result = await client.callTool(
        'get_plc_code_block',
        {'block_id': 9999},
      );

      expect(result.isError, isTrue);
      final text = (result.content.first as TextContent).text;
      expect(text, contains('No PLC code block with ID 9999'));
    });

    test('GVL block shows "N/A" for implementation', () async {
      // Block ID 2 is GVL_Main
      final result = await client.callTool(
        'get_plc_code_block',
        {'block_id': 2},
      );

      expect(result.isError, isNot(true));
      final text = (result.content.first as TextContent).text;
      expect(text, contains('Block: GVL_Main (GVL)'));
      expect(text, contains('N/A (declaration-only block)'));
    });
  });
}
