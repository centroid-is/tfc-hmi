import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:mcp_dart/mcp_dart.dart' show McpError;
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/server.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('explain_alarm prompt', () {
    late ServerDatabase db;
    late MockStateReader stateReader;
    late MockAlarmReader alarmReader;
    late TfcMcpServer server;
    late MockMcpClient client;

    final now = DateTime.now().toUtc();
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final twoHoursAgo = now.subtract(const Duration(hours: 2));

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      stateReader = MockStateReader();
      alarmReader = MockAlarmReader();

      // Seed alarm config with 'key' field for prefix correlation
      alarmReader.addAlarmConfig({
        'uid': 'alarm-1',
        'key': 'pump3.overcurrent',
        'title': 'Pump 3 Overcurrent',
        'description': 'Current exceeds 15A threshold',
        'rules': [
          {'type': 'threshold', 'value': 15.0, 'operator': '>'}
        ],
      });

      alarmReader.addAlarmConfig({
        'uid': 'alarm-2',
        'key': 'tank1.overflow',
        'title': 'Tank 1 Overflow',
        'description': 'Level exceeds 100%',
        'rules': [],
      });

      // Seed sibling tags by prefix "pump3"
      stateReader.setValue('pump3.overcurrent', true);
      stateReader.setValue('pump3.speed', 1450.0);
      stateReader.setValue('pump3.temperature', 82.5);
      stateReader.setValue('conveyor.speed', 3.2);

      // Seed alarm definitions in database
      await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
            uid: 'alarm-1',
            title: 'Pump 3 Overcurrent',
            description: 'Current exceeds 15A threshold',
            rules: '[]',
          ));
      await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
            uid: 'alarm-2',
            title: 'Tank 1 Overflow',
            description: 'Level exceeds 100%',
            rules: '[]',
          ));

      // Seed alarm history records
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: true,
              pendingAck: true,
              createdAt: oneHourAgo,
            ),
          );

      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: false,
              pendingAck: false,
              createdAt: twoHoursAgo,
              deactivatedAt: Value(oneHourAgo),
            ),
          );

      final identity = EnvOperatorIdentity(
        environmentProvider: () => {'TFC_USER': 'op1'},
      );

      server = TfcMcpServer(
        identity: identity,
        database: db,
        stateReader: stateReader,
        alarmReader: alarmReader,
      );

      client = await MockMcpClient.connect(server.mcpServer);
    });

    tearDown(() async {
      await client.close();
      await db.close();
    });

    test('explain_alarm appears in listPrompts with description', () async {
      final result = await client.listPrompts();
      final prompt = result.prompts.where(
        (p) => p.name == 'explain_alarm',
      );
      expect(prompt, hasLength(1));
      expect(prompt.first.description, isNotEmpty);
    });

    test('getPrompt with valid alarm_uid returns non-empty messages',
        () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      expect(result.messages, isNotEmpty);
    });

    test('prompt message text contains alarm detail data', () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      expect(text, contains('Pump 3 Overcurrent'));
      expect(text, contains('pump3.overcurrent'));
      expect(text, contains('Current exceeds 15A threshold'));
    });

    test('prompt message text contains correlated tag values by prefix',
        () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      // Should contain sibling tags starting with "pump3"
      expect(text, contains('pump3.speed'));
      expect(text, contains('pump3.temperature'));
      // Should NOT contain tags from other prefixes
      expect(text, isNot(contains('conveyor.speed')));
    });

    test('prompt message text contains causal chain with alarm events',
        () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      // Causal chain section should have alarm history events
      expect(text, contains('Causal Chain'));
      expect(text, contains('Pump 3 Overcurrent'));
    });

    test('prompt message text contains instructions to show source data',
        () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      expect(text, contains('source data'));
      expect(text, contains('possible causes'));
    });

    test('prompt message text contains AI-generated labeling instruction',
        () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      expect(text, contains('AI-generated'));
    });

    test('prompt message text contains What else to check instruction',
        () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      expect(text, contains('What else to check'));
    });

    test('getPrompt with no alarm_uid argument returns MCP error', () async {
      // mcp_dart validates required arguments at the protocol level before
      // calling the callback, so this throws McpError -32602
      expect(
        () => client.getPrompt('explain_alarm'),
        throwsA(isA<McpError>()),
      );
    });

    test(
        'getPrompt with nonexistent alarm_uid returns not-found message',
        () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'nonexistent'},
      );
      final text = _extractText(result);

      expect(text.toLowerCase(), contains('not found'));
    });

    test('prompt message contains Alarm Definition section', () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      expect(text, contains('Alarm Definition'));
    });

    test('prompt output contains Causal Chain section', () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      expect(text, contains('Causal Chain'));
    });

    test('prompt output contains Trend Context section', () async {
      final result = await client.getPrompt(
        'explain_alarm',
        arguments: {'alarm_uid': 'alarm-1'},
      );
      final text = _extractText(result);

      expect(text, contains('Trend Context'));
    });
  });
}

/// Extracts all text content from a [GetPromptResult].
String _extractText(dynamic result) {
  final messages = result.messages as List<dynamic>;
  final buffer = StringBuffer();
  for (final msg in messages) {
    final content = msg.content;
    final text = content.text as String?;
    if (text != null) {
      buffer.writeln(text);
    }
  }
  return buffer.toString();
}
