import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/interfaces/tech_doc_index.dart';
import 'package:tfc_mcp_server/src/server.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';
import '../helpers/mock_tech_doc_index.dart';

void main() {
  group('scada://source/tech_docs resource', () {
    group('with populated TechDocIndex', () {
      late ServerDatabase db;
      late MockTechDocIndex techDocIndex;
      late TfcMcpServer server;
      late MockMcpClient client;

      setUp(() async {
        db = ServerDatabase.inMemory();
        await db.customStatement('SELECT 1');

        techDocIndex = MockTechDocIndex();

        // Populate with 2 sample documents
        await techDocIndex.storeDocument(
          name: 'ATV320 Installation Manual',
          pdfBytes: Uint8List(100),
          sections: [
            const ParsedSection(
              title: 'Chapter 1: Safety',
              content: 'Safety content here.',
              pageStart: 1,
              pageEnd: 10,
              level: 1,
              sortOrder: 0,
            ),
            const ParsedSection(
              title: 'Chapter 2: Wiring',
              content: 'Wiring content here.',
              pageStart: 11,
              pageEnd: 20,
              level: 1,
              sortOrder: 1,
            ),
          ],
        );

        await techDocIndex.storeDocument(
          name: 'PT100 Sensor Datasheet',
          pdfBytes: Uint8List(50),
          sections: [
            const ParsedSection(
              title: 'Specifications',
              content: 'Temperature range specifications.',
              pageStart: 1,
              pageEnd: 3,
              level: 1,
              sortOrder: 0,
            ),
          ],
        );

        final identity = EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        );

        server = TfcMcpServer(
          identity: identity,
          database: db,
          stateReader: MockStateReader(),
          alarmReader: MockAlarmReader(),
          techDocIndex: techDocIndex,
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
          (r) => r.uri == 'scada://source/tech_docs',
        );
        expect(resource, hasLength(1));
        expect(resource.first.name, equals('Knowledge Base'));
      });

      test('returns catalog with doc names, section counts, and page counts',
          () async {
        final result =
            await client.readResource('scada://source/tech_docs');
        expect(result.contents, hasLength(1));

        final text = (result.contents.first as dynamic).text as String;
        expect(text, contains('ATV320 Installation Manual'));
        expect(text, contains('PT100 Sensor Datasheet'));
        // Should contain section counts
        expect(text, contains('2')); // ATV320 has 2 sections
        expect(text, contains('1')); // PT100 has 1 section
      });

      test('content type is text/plain', () async {
        final result =
            await client.readResource('scada://source/tech_docs');
        final content = result.contents.first as dynamic;
        expect(content.mimeType, equals('text/plain'));
      });
    });

    group('with empty TechDocIndex', () {
      late ServerDatabase db;
      late MockTechDocIndex techDocIndex;
      late TfcMcpServer server;
      late MockMcpClient client;

      setUp(() async {
        db = ServerDatabase.inMemory();
        await db.customStatement('SELECT 1');

        techDocIndex = MockTechDocIndex();
        // Empty -- no documents stored

        final identity = EnvOperatorIdentity(
          environmentProvider: () => {'TFC_USER': 'op1'},
        );

        server = TfcMcpServer(
          identity: identity,
          database: db,
          stateReader: MockStateReader(),
          alarmReader: MockAlarmReader(),
          techDocIndex: techDocIndex,
        );

        client = await MockMcpClient.connect(server.mcpServer);
      });

      tearDown(() async {
        await client.close();
        await db.close();
      });

      test('returns "No technical documents uploaded" message', () async {
        final result =
            await client.readResource('scada://source/tech_docs');
        final text = (result.contents.first as dynamic).text as String;
        expect(text, contains('No technical documents uploaded'));
      });
    });

    group('with null TechDocIndex (standalone mode)', () {
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
          // No techDocIndex -- null by default
        );

        client = await MockMcpClient.connect(server.mcpServer);
      });

      tearDown(() async {
        await client.close();
        await db.close();
      });

      test('returns "No technical documents uploaded" message', () async {
        final result =
            await client.readResource('scada://source/tech_docs');
        final text = (result.contents.first as dynamic).text as String;
        expect(text, contains('No technical documents uploaded'));
      });
    });
  });
}
