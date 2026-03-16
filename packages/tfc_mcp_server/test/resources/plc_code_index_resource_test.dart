import 'dart:convert';

import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/plc_code_index.dart';
import 'package:tfc_mcp_server/src/server.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_plc_code_index.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('PLC code index resource', () {
    group('with populated PlcCodeIndex', () {
      late ServerDatabase db;
      late MockPlcCodeIndex plcCodeIndex;
      late TfcMcpServer server;
      late MockMcpClient client;

      setUp(() async {
        db = ServerDatabase.inMemory();
        await db.customStatement('SELECT 1');

        plcCodeIndex = MockPlcCodeIndex();
        await plcCodeIndex.indexAsset('plc-1', [
          const ParsedCodeBlock(
            name: 'FB_Pump',
            type: 'FunctionBlock',
            declaration: 'VAR\n  speed : REAL;\nEND_VAR',
            implementation: 'speed := 50.0;',
            fullSource: 'VAR\n  speed : REAL;\nEND_VAR\nspeed := 50.0;',
            filePath: 'POUs/FB_Pump.TcPOU',
            variables: [
              ParsedVariable(name: 'speed', type: 'REAL', section: 'VAR'),
            ],
            children: [],
          ),
          const ParsedCodeBlock(
            name: 'GVL_Main',
            type: 'GVL',
            declaration: 'VAR_GLOBAL\n  temp : REAL;\nEND_VAR',
            implementation: null,
            fullSource: 'VAR_GLOBAL\n  temp : REAL;\nEND_VAR',
            filePath: 'GVLs/GVL_Main.TcGVL',
            variables: [
              ParsedVariable(
                  name: 'temp', type: 'REAL', section: 'VAR_GLOBAL'),
            ],
            children: [],
          ),
        ]);

        final identity = EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        );

        server = TfcMcpServer(
          identity: identity,
          database: db,
          stateReader: MockStateReader(),
          alarmReader: MockAlarmReader(),
          plcCodeIndex: plcCodeIndex,
        );

        client = await MockMcpClient.connect(server.mcpServer);
      });

      tearDown(() async {
        await client.close();
        await db.close();
      });

      test('resource appears in listResources with correct name and URI',
          () async {
        final result = await client.listResources();
        final resource = result.resources.where(
          (r) => r.uri == 'scada://plc/code',
        );
        expect(resource, hasLength(1));
        expect(resource.first.name, equals('PLC Code Index'));
      });

      test('returns per-asset summary with expected fields', () async {
        final result = await client.readResource('scada://plc/code');
        expect(result.contents, hasLength(1));

        final text = (result.contents.first as dynamic).text as String;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['status'], equals('available'));

        final assets = json['assets'] as List;
        expect(assets, hasLength(1));

        final asset = assets.first as Map<String, dynamic>;
        expect(asset['assetKey'], equals('plc-1'));
        expect(asset['blockCount'], greaterThan(0));
        expect(asset['variableCount'], greaterThan(0));
        expect(asset['lastIndexedAt'], isA<String>());
        expect(asset['blockTypeCounts'], isA<Map>());
      });

      test('content type is application/json', () async {
        final result = await client.readResource('scada://plc/code');
        final content = result.contents.first as dynamic;
        expect(content.mimeType, equals('application/json'));
      });
    });

    group('with null PlcCodeIndex (standalone mode)', () {
      late ServerDatabase db;
      late TfcMcpServer server;
      late MockMcpClient client;

      setUp(() async {
        db = ServerDatabase.inMemory();
        await db.customStatement('SELECT 1');

        final identity = EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        );

        server = TfcMcpServer(
          identity: identity,
          database: db,
          stateReader: MockStateReader(),
          alarmReader: MockAlarmReader(),
          // No plcCodeIndex -- null by default
        );

        client = await MockMcpClient.connect(server.mcpServer);
      });

      tearDown(() async {
        await client.close();
        await db.close();
      });

      test('returns no_plc_code_indexed status', () async {
        final result = await client.readResource('scada://plc/code');
        final text = (result.contents.first as dynamic).text as String;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['status'], equals('no_plc_code_indexed'));
        expect(json['message'], contains('No TwinCAT projects'));
      });
    });

    group('with empty PlcCodeIndex', () {
      late ServerDatabase db;
      late MockPlcCodeIndex plcCodeIndex;
      late TfcMcpServer server;
      late MockMcpClient client;

      setUp(() async {
        db = ServerDatabase.inMemory();
        await db.customStatement('SELECT 1');

        // Empty index -- isEmpty returns true
        plcCodeIndex = MockPlcCodeIndex();

        final identity = EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        );

        server = TfcMcpServer(
          identity: identity,
          database: db,
          stateReader: MockStateReader(),
          alarmReader: MockAlarmReader(),
          plcCodeIndex: plcCodeIndex,
        );

        client = await MockMcpClient.connect(server.mcpServer);
      });

      tearDown(() async {
        await client.close();
        await db.close();
      });

      test('returns no_plc_code_indexed status', () async {
        final result = await client.readResource('scada://plc/code');
        final text = (result.contents.first as dynamic).text as String;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['status'], equals('no_plc_code_indexed'));
        expect(json['message'], contains('No TwinCAT projects'));
      });
    });
  });
}
