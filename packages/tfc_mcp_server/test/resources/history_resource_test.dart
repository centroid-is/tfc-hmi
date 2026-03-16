import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/identity/env_operator_identity.dart';
import 'package:tfc_mcp_server/src/server.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/mock_mcp_client.dart';
import '../helpers/mock_state_reader.dart';

void main() {
  group('History resource', () {
    late ServerDatabase db;
    late MockStateReader stateReader;
    late MockAlarmReader alarmReader;
    late TfcMcpServer server;
    late MockMcpClient client;

    final now = DateTime.now().toUtc();
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    final threeHoursAgo = now.subtract(const Duration(hours: 3));
    final sixHoursAgo = now.subtract(const Duration(hours: 6));

    setUp(() async {
      db = ServerDatabase.inMemory();
      await db.customStatement('SELECT 1');

      stateReader = MockStateReader();
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

      // Active alarm (within 4 hours)
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

      // Recent history (within 4 hours)
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
            ),
          );

      // Old history (outside 4-hour window)
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: false,
              pendingAck: false,
              createdAt: sixHoursAgo,
              deactivatedAt: Value(sixHoursAgo.add(const Duration(minutes: 30))),
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

    test('resource appears in listResources with correct name and URI',
        () async {
      final result = await client.listResources();
      final historyResource = result.resources.where(
        (r) => r.uri == 'scada://history/recent',
      );
      expect(historyResource, hasLength(1));
      expect(historyResource.first.name, equals('Operational History'));
    });

    test(
        'readResource returns JSON with active_alarms and recent_history keys',
        () async {
      final result = await client.readResource('scada://history/recent');
      expect(result.contents, hasLength(1));

      final text = (result.contents.first as dynamic).text as String;
      final json = jsonDecode(text) as Map<String, dynamic>;

      expect(json, containsPair('active_alarms', isA<List<dynamic>>()));
      expect(json, containsPair('recent_history', isA<List<dynamic>>()));
      expect(json, containsPair('time_window', 'last 4 hours'));
      expect(json, containsPair('generated_at', isA<String>()));
    });

    test('recent_history contains alarms from last 4 hours only', () async {
      final result = await client.readResource('scada://history/recent');
      final text = (result.contents.first as dynamic).text as String;
      final json = jsonDecode(text) as Map<String, dynamic>;

      final recentHistory = json['recent_history'] as List;
      // Should contain the 2 recent records (2h and 3h ago), not the 6h old one
      expect(recentHistory, hasLength(2));

      // Verify the old record (6 hours ago) is not included
      for (final entry in recentHistory) {
        final record = entry as Map<String, dynamic>;
        final createdAt = DateTime.parse(record['createdAt'] as String);
        expect(
          createdAt.isAfter(now.subtract(const Duration(hours: 4, minutes: 1))),
          isTrue,
          reason: 'Record at $createdAt should be within 4-hour window',
        );
      }
    });

    test('active_alarms contains only active alarms', () async {
      final result = await client.readResource('scada://history/recent');
      final text = (result.contents.first as dynamic).text as String;
      final json = jsonDecode(text) as Map<String, dynamic>;

      final activeAlarms = json['active_alarms'] as List;
      // Only 1 active alarm
      expect(activeAlarms, hasLength(1));
      final activeAlarm = activeAlarms.first as Map<String, dynamic>;
      expect(activeAlarm['alarmTitle'], equals('Pump 3 Overcurrent'));
    });

    test('empty alarm history returns valid JSON with empty arrays', () async {
      // Create a fresh empty database
      final emptyDb = ServerDatabase.inMemory();
      await emptyDb.customStatement('SELECT 1');

      final emptyIdentity = EnvOperatorIdentity(
        environmentProvider: () => {'TFC_USER': 'op1'},
      );
      final emptyServer = TfcMcpServer(
        identity: emptyIdentity,
        database: emptyDb,
        stateReader: MockStateReader(),
        alarmReader: MockAlarmReader(),
      );

      final emptyClient =
          await MockMcpClient.connect(emptyServer.mcpServer);
      try {
        final result =
            await emptyClient.readResource('scada://history/recent');
        final text = (result.contents.first as dynamic).text as String;
        final json = jsonDecode(text) as Map<String, dynamic>;

        expect(json['active_alarms'], isEmpty);
        expect(json['recent_history'], isEmpty);
        expect(json['time_window'], equals('last 4 hours'));
        expect(json['generated_at'], isNotNull);
      } finally {
        await emptyClient.close();
        await emptyDb.close();
      }
    });
  });
}
