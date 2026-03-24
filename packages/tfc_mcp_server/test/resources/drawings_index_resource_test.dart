import 'dart:convert';

import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/drawing_index.dart';
import 'package:tfc_mcp_server/src/server.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_drawing_index.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('Drawings index resource', () {
    group('with populated DrawingIndex', () {
      late ServerDatabase db;
      late MockDrawingIndex drawingIndex;
      late TfcMcpServer server;
      late MockMcpClient client;

      setUp(() async {
        db = ServerDatabase.inMemory();
        await db.customStatement('SELECT 1');

        drawingIndex = MockDrawingIndex();
        drawingIndex.addResult(const DrawingSearchResult(
          drawingName: 'Panel-A Main Wiring',
          pageNumber: 3,
          assetKey: 'panel-A',
          componentName: 'relay K3',
        ));
        drawingIndex.addResult(const DrawingSearchResult(
          drawingName: 'Motor Control Center',
          pageNumber: 7,
          assetKey: 'mcc-1',
          componentName: 'motor M1',
        ));

        final identity = EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        );

        server = TfcMcpServer(
          identity: identity,
          database: db,
          stateReader: MockStateReader(),
          alarmReader: MockAlarmReader(),
          drawingIndex: drawingIndex,
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
          (r) => r.uri == 'scada://drawings/index',
        );
        expect(resource, hasLength(1));
        expect(resource.first.name, equals('Electrical Drawings Index'));
      });

      test('readResource returns JSON with drawing entries', () async {
        final result =
            await client.readResource('scada://drawings/index');
        expect(result.contents, hasLength(1));

        final text = (result.contents.first as dynamic).text as String;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['status'], equals('available'));
        expect(json['count'], equals(2));

        final drawings = json['drawings'] as List;
        expect(drawings, hasLength(2));

        final first = drawings.first as Map<String, dynamic>;
        expect(first['drawingName'], equals('Panel-A Main Wiring'));
        expect(first['pageNumber'], equals(3));
        expect(first['assetKey'], equals('panel-A'));
        expect(first['componentName'], equals('relay K3'));
      });
    });

    group('with null DrawingService (standalone mode)', () {
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
          // No drawingIndex -- null by default
        );

        client = await MockMcpClient.connect(server.mcpServer);
      });

      tearDown(() async {
        await client.close();
        await db.close();
      });

      test('readResource returns no_drawings status', () async {
        final result =
            await client.readResource('scada://drawings/index');
        final text = (result.contents.first as dynamic).text as String;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['status'], equals('no_drawings'));
        expect(json['message'], contains('No electrical drawings'));
        expect(json['drawings'], isEmpty);
      });
    });

    group('with empty DrawingIndex', () {
      late ServerDatabase db;
      late MockDrawingIndex drawingIndex;
      late TfcMcpServer server;
      late MockMcpClient client;

      setUp(() async {
        db = ServerDatabase.inMemory();
        await db.customStatement('SELECT 1');

        // Empty index -- isEmpty returns true
        drawingIndex = MockDrawingIndex();

        final identity = EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        );

        server = TfcMcpServer(
          identity: identity,
          database: db,
          stateReader: MockStateReader(),
          alarmReader: MockAlarmReader(),
          drawingIndex: drawingIndex,
        );

        client = await MockMcpClient.connect(server.mcpServer);
      });

      tearDown(() async {
        await client.close();
        await db.close();
      });

      test('readResource returns no_drawings status', () async {
        final result =
            await client.readResource('scada://drawings/index');
        final text = (result.contents.first as dynamic).text as String;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['status'], equals('no_drawings'));
        expect(json['message'], contains('No electrical drawings'));
        expect(json['drawings'], isEmpty);
      });
    });
  });
}
