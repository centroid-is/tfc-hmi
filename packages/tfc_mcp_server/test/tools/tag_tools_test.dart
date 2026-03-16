import 'package:mcp_dart/mcp_dart.dart';
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/services/tag_service.dart';
import 'package:tfc_mcp_server/src/tools/tag_tools.dart';
import 'package:tfc_mcp_server/src/tools/tool_registry.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('Tag tools (via MockMcpClient)', () {
    late ServerDatabase db;
    late McpServer mcpServer;
    late MockStateReader stateReader;

    setUp(() async {
      db = ServerDatabase.inMemory();
      // Ensure tables are created
      await db.customStatement('SELECT 1');

      stateReader = MockStateReader();
      stateReader.setValue('pump3.speed', 1450);
      stateReader.setValue('pump3.current', 12.5);
      stateReader.setValue('conveyor.speed', 800);
      stateReader.setValue('conveyor.current', 5.2);
      stateReader.setValue('mixer.temp', 85);
    });

    tearDown(() async {
      await db.close();
    });

    McpServer createMcpServer() {
      return McpServer(
        const Implementation(name: 'test-server', version: '0.1.0'),
        options: McpServerOptions(
          capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        ),
      );
    }

    Future<MockMcpClient> createClientWithTagTools() async {
      final env = {'TFC_USER': 'op1'};
      final identity = EnvOperatorIdentity(environmentProvider: () => env);
      final auditService = AuditLogService(db);
      mcpServer = createMcpServer();

      final registry = ToolRegistry(
        mcpServer: mcpServer,
        identity: identity,
        auditLogService: auditService,
      );

      final tagService = TagService(stateReader);
      registerTagTools(registry, tagService);

      return MockMcpClient.connect(mcpServer);
    }

    test('list_tags with no args returns formatted tag list', () async {
      final client = await createClientWithTagTools();
      try {
        final result = await client.callTool('list_tags', {});

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, contains('Tags (5 results)'));
        expect(text, contains('pump3.speed'));
        expect(text, contains('1450'));
      } finally {
        await client.close();
      }
    });

    test('list_tags with filter returns only matching tags', () async {
      final client = await createClientWithTagTools();
      try {
        final result = await client.callTool('list_tags', {'filter': 'pump'});

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, contains('Tags (2 results)'));
        expect(text, contains('pump3.speed'));
        expect(text, contains('pump3.current'));
        expect(text, isNot(contains('conveyor')));
      } finally {
        await client.close();
      }
    });

    test('list_tags with limit returns at most limit results', () async {
      final client = await createClientWithTagTools();
      try {
        final result = await client.callTool('list_tags', {'limit': 1});

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, contains('Tags (1 results)'));
      } finally {
        await client.close();
      }
    });

    test('get_tag_value with known key returns value text', () async {
      final client = await createClientWithTagTools();
      try {
        final result =
            await client.callTool('get_tag_value', {'key': 'pump3.speed'});

        expect(result.isError, isNot(true));
        final text = (result.content.first as TextContent).text;
        expect(text, contains('pump3.speed'));
        expect(text, contains('1450'));
      } finally {
        await client.close();
      }
    });

    test('get_tag_value with unknown key returns isError', () async {
      final client = await createClientWithTagTools();
      try {
        final result =
            await client.callTool('get_tag_value', {'key': 'unknown'});

        expect(result.isError, isTrue);
        final text = (result.content.first as TextContent).text;
        expect(text, contains('unknown'));
      } finally {
        await client.close();
      }
    });

    test('both tools create audit records', () async {
      final client = await createClientWithTagTools();
      try {
        await client.callTool('list_tags', {});
        await client.callTool('get_tag_value', {'key': 'pump3.speed'});

        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(2));
        final tools = records.map((r) => r.tool).toList();
        expect(tools, contains('list_tags'));
        expect(tools, contains('get_tag_value'));
        // Both should be success
        for (final record in records) {
          expect(record.operatorId, equals('op1'));
          expect(record.status, equals('success'));
        }
      } finally {
        await client.close();
      }
    });
  });
}
