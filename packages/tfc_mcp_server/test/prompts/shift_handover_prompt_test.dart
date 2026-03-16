import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/server.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('shift_handover prompt', () {
    late ServerDatabase db;
    late MockStateReader stateReader;
    late MockAlarmReader alarmReader;
    late TfcMcpServer server;
    late MockMcpClient client;

    final now = DateTime.now().toUtc();
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    final threeHoursAgo = now.subtract(const Duration(hours: 3));
    final sixHoursAgo = now.subtract(const Duration(hours: 6));
    final tenHoursAgo = now.subtract(const Duration(hours: 10));

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      stateReader = MockStateReader();
      stateReader.setValue('pump3.speed', 1450);
      stateReader.setValue('tank1.level', 82.5);
      stateReader.setValue('conveyor.running', true);

      alarmReader = MockAlarmReader();

      // Seed alarm definitions (FK integrity)
      await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
            uid: 'alarm-1',
            title: 'Pump 3 Overcurrent',
            description: 'Current exceeds 15A threshold',
            rules: '[]',
          ));
      await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
            uid: 'alarm-2',
            title: 'Tank 1 High Level',
            description: 'Level exceeds 95% capacity',
            rules: '[]',
          ));
      await db.into(db.serverAlarm).insert(ServerAlarmCompanion.insert(
            uid: 'alarm-3',
            title: 'Conveyor Jam',
            description: 'Conveyor belt stalled',
            rules: '[]',
          ));

      // Active alarm (within 8 hours, not acknowledged)
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: true,
              pendingAck: true,
              createdAt: twoHoursAgo,
            ),
          );

      // Recent history (within 8 hours, acknowledged and deactivated)
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-2',
              alarmTitle: 'Tank 1 High Level',
              alarmDescription: 'Level exceeds 95% capacity',
              alarmLevel: 'warning',
              active: false,
              pendingAck: false,
              createdAt: threeHoursAgo,
              deactivatedAt: Value(twoHoursAgo),
              acknowledgedAt: Value(threeHoursAgo.add(const Duration(minutes: 5))),
            ),
          );

      // Recent history (within 8 hours, within 6 hours -- for 12-hour tests too)
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-3',
              alarmTitle: 'Conveyor Jam',
              alarmDescription: 'Conveyor belt stalled',
              alarmLevel: 'info',
              active: false,
              pendingAck: false,
              createdAt: sixHoursAgo,
              deactivatedAt: Value(sixHoursAgo.add(const Duration(minutes: 10))),
            ),
          );

      // Old history (outside 8-hour window, inside 12-hour window)
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: false,
              pendingAck: false,
              createdAt: tenHoursAgo,
              deactivatedAt:
                  Value(tenHoursAgo.add(const Duration(minutes: 30))),
              acknowledgedAt:
                  Value(tenHoursAgo.add(const Duration(minutes: 15))),
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

    test('shift_handover appears in listPrompts with description', () async {
      final result = await client.listPrompts();
      final prompt = result.prompts.where((p) => p.name == 'shift_handover');
      expect(prompt, hasLength(1));
      expect(prompt.first.description, isNotNull);
      expect(prompt.first.description, contains('shift handover'));
    });

    test('getPrompt with no arguments uses 8-hour default window', () async {
      final result = await client.getPrompt('shift_handover');
      expect(result.messages, isNotEmpty);
      final text = (result.messages.first.content as dynamic).text as String;
      expect(text, contains('8 hours'));
    });

    test('getPrompt with hours=12 uses 12-hour window', () async {
      final result = await client.getPrompt(
        'shift_handover',
        arguments: {'hours': '12'},
      );
      expect(result.messages, isNotEmpty);
      final text = (result.messages.first.content as dynamic).text as String;
      expect(text, contains('12 hours'));
    });

    test('prompt message contains alarm history data from the time window',
        () async {
      final result = await client.getPrompt('shift_handover');
      final text = (result.messages.first.content as dynamic).text as String;
      // Should contain alarm titles from last 8 hours
      expect(text, contains('Pump 3 Overcurrent'));
      expect(text, contains('Tank 1 High Level'));
      expect(text, contains('Conveyor Jam'));
    });

    test('prompt message contains currently active alarms', () async {
      final result = await client.getPrompt('shift_handover');
      final text = (result.messages.first.content as dynamic).text as String;
      // Active alarms section should reference the active alarm
      expect(text, contains('Currently Active Alarms'));
      expect(text, contains('Pump 3 Overcurrent'));
    });

    test('prompt message contains current tag value snapshot', () async {
      final result = await client.getPrompt('shift_handover');
      final text = (result.messages.first.content as dynamic).text as String;
      expect(text, contains('pump3.speed'));
      expect(text, contains('1450'));
      expect(text, contains('tank1.level'));
      expect(text, contains('82.5'));
    });

    test(
        'prompt message contains instructions for structured summary sections',
        () async {
      final result = await client.getPrompt('shift_handover');
      final text = (result.messages.first.content as dynamic).text as String;
      expect(text, contains('Alarms Fired'));
      expect(text, contains('Acknowledgements'));
      expect(text, contains('Currently Active'));
      expect(text, contains('Anomalies'));
    });

    test('prompt message contains AI-generated labeling instruction',
        () async {
      final result = await client.getPrompt('shift_handover');
      final text = (result.messages.first.content as dynamic).text as String;
      expect(text, contains('AI-generated'));
    });

    test('prompt message contains source data display instructions', () async {
      final result = await client.getPrompt('shift_handover');
      final text = (result.messages.first.content as dynamic).text as String;
      expect(text, contains('source'));
      expect(text, contains('Verify'));
    });

    test('prompt message contains summary statistics', () async {
      final result = await client.getPrompt('shift_handover');
      final text = (result.messages.first.content as dynamic).text as String;
      expect(text, contains('Summary Statistics'));
      expect(text, contains('Total alarms fired'));
      expect(text, contains('Acknowledged'));
      expect(text, contains('Currently active'));
      expect(text, contains('Unique alarm sources'));
    });

    test('invalid hours value falls back to 8-hour default', () async {
      final result = await client.getPrompt(
        'shift_handover',
        arguments: {'hours': 'abc'},
      );
      expect(result.messages, isNotEmpty);
      final text = (result.messages.first.content as dynamic).text as String;
      // Should fall back to 8 hours, not crash
      expect(text, contains('8 hours'));
    });
  });
}
