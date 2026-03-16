import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/server.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('Knowledge resource', () {
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
        (r) => r.uri == 'scada://source/knowledge',
      );
      expect(resource, hasLength(1));
      expect(resource.first.name, equals('Application Knowledge'));
    });

    test('readResource returns text describing StateMan, AlarmMan, Collector, PageManager',
        () async {
      final result =
          await client.readResource('scada://source/knowledge');
      expect(result.contents, hasLength(1));

      final text = (result.contents.first as dynamic).text as String;
      expect(text, contains('StateMan'));
      expect(text, contains('AlarmMan'));
      expect(text, contains('Collector'));
      expect(text, contains('PageManager'));
    });

    test('knowledge text describes key mappings and OPC UA', () async {
      final result =
          await client.readResource('scada://source/knowledge');
      final text = (result.contents.first as dynamic).text as String;

      expect(text, contains('Key Mappings'));
      expect(text, contains('OPC UA'));
    });

    test('knowledge text describes alarm rules and boolean expressions',
        () async {
      final result =
          await client.readResource('scada://source/knowledge');
      final text = (result.contents.first as dynamic).text as String;

      expect(text, contains('Alarm Definitions'));
      expect(text, contains('boolean expressions'));
    });

    test('knowledge text describes data access boundaries (CANNOT)',
        () async {
      final result =
          await client.readResource('scada://source/knowledge');
      final text = (result.contents.first as dynamic).text as String;

      expect(text, contains('CANNOT'));
      expect(text, contains('What the AI CAN do'));
      expect(text, contains('What the AI CANNOT do'));
    });

    test('knowledge text describes pages and assets', () async {
      final result =
          await client.readResource('scada://source/knowledge');
      final text = (result.contents.first as dynamic).text as String;

      expect(text, contains('Pages and Assets'));
    });

    test('knowledge text describes proposals', () async {
      final result =
          await client.readResource('scada://source/knowledge');
      final text = (result.contents.first as dynamic).text as String;

      expect(text, contains('Proposals'));
      expect(text, contains('editor'));
    });

    test('all 4 Phase 3 resources visible in listResources', () async {
      final result = await client.listResources();
      final uris =
          result.resources.map((r) => r.uri).toSet();

      expect(uris, contains('scada://config/snapshot'));
      expect(uris, contains('scada://history/recent'));
      expect(uris, contains('scada://drawings/index'));
      expect(uris, contains('scada://source/knowledge'));
    });
  });
}
