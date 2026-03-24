import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/services/alarm_service.dart';
import '../helpers/mock_alarm_reader.dart';
import '../helpers/test_database.dart';

void main() {
  group('AlarmService', () {
    late ServerDatabase db;
    late MockAlarmReader alarmReader;
    late AlarmService service;

    // Timestamps for test data (spread across a time range).
    final now = DateTime.utc(2026, 3, 6, 12, 0, 0);
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    final threeHoursAgo = now.subtract(const Duration(hours: 3));
    final fourHoursAgo = now.subtract(const Duration(hours: 4));

    setUp(() async {
      db = createTestDatabase();
      // Ensure tables are created.
      await db.customStatement('SELECT 1');

      alarmReader = MockAlarmReader();

      // Add alarm configs to MockAlarmReader.
      alarmReader.addAlarmConfig({
        'uid': 'alarm-1',
        'key': 'pump3.overcurrent',
        'title': 'Pump 3 Overcurrent',
        'description': 'Current exceeds 15A threshold',
        'rules': '[]',
      });
      alarmReader.addAlarmConfig({
        'uid': 'alarm-2',
        'key': 'tank1.highlevel',
        'title': 'Tank 1 High Level',
        'description': 'Level exceeds 95% capacity',
        'rules': '[]',
      });
      alarmReader.addAlarmConfig({
        'uid': 'alarm-3',
        'key': 'valve5.stuck',
        'title': 'Valve 5 Stuck',
        'description': 'Valve position not responding',
        'rules': '[]',
      });

      // Insert alarm configs into serverAlarm table (FK integrity).
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
            title: 'Valve 5 Stuck',
            description: 'Valve position not responding',
            rules: '[]',
          ));

      // Insert alarm history records:
      // Active alarms (active=true, deactivatedAt=null).
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
              alarmUid: 'alarm-2',
              alarmTitle: 'Tank 1 High Level',
              alarmDescription: 'Level exceeds 95% capacity',
              alarmLevel: 'warning',
              active: true,
              pendingAck: false,
              createdAt: twoHoursAgo,
            ),
          );
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-3',
              alarmTitle: 'Valve 5 Stuck',
              alarmDescription: 'Valve position not responding',
              alarmLevel: 'info',
              active: true,
              pendingAck: false,
              createdAt: threeHoursAgo,
            ),
          );

      // Inactive alarm (deactivated).
      await db.into(db.serverAlarmHistory).insert(
            ServerAlarmHistoryCompanion.insert(
              alarmUid: 'alarm-1',
              alarmTitle: 'Pump 3 Overcurrent',
              alarmDescription: 'Current exceeds 15A threshold',
              alarmLevel: 'critical',
              active: false,
              pendingAck: false,
              createdAt: fourHoursAgo,
              deactivatedAt: Value(threeHoursAgo),
            ),
          );

      service = AlarmService(alarmReader: alarmReader, db: db);
    });

    tearDown(() async {
      await db.close();
    });

    group('listActiveAlarms', () {
      test('returns active alarms with level, title, description, timestamp',
          () async {
        final alarms = await service.listActiveAlarms();

        expect(alarms, hasLength(3));

        // Most recent first (ordered by createdAt DESC).
        final first = alarms.first;
        expect(first['alarmLevel'], equals('critical'));
        expect(first['alarmTitle'], equals('Pump 3 Overcurrent'));
        expect(first['alarmDescription'],
            equals('Current exceeds 15A threshold'));
        expect(first['createdAt'], isNotNull);
      });

      test('enforces limit parameter', () async {
        final alarms = await service.listActiveAlarms(limit: 2);

        expect(alarms, hasLength(2));
      });

      test('returns empty list when no active alarms', () async {
        // Deactivate all active alarms.
        await (db.update(db.serverAlarmHistory)
              ..where((t) => t.active.equals(true)))
            .write(ServerAlarmHistoryCompanion(
          active: const Value(false),
          deactivatedAt: Value(now),
        ));

        final alarms = await service.listActiveAlarms();
        expect(alarms, isEmpty);
      });
    });

    group('getAlarmDetail', () {
      test('returns alarm config matching uid', () {
        final detail = service.getAlarmDetail('alarm-1');

        expect(detail, isNotNull);
        expect(detail!['uid'], equals('alarm-1'));
        expect(detail['key'], equals('pump3.overcurrent'));
        expect(detail['title'], equals('Pump 3 Overcurrent'));
        expect(
            detail['description'], equals('Current exceeds 15A threshold'));
      });

      test('returns null for nonexistent uid', () {
        final detail = service.getAlarmDetail('nonexistent');

        expect(detail, isNull);
      });
    });

    group('queryHistory', () {
      test('filters by time range (after/before)', () async {
        // Query history between threeHoursAgo and oneHourAgo.
        final results = await service.queryHistory(
          after: threeHoursAgo,
          before: oneHourAgo,
        );

        // Should include records at threeHoursAgo, twoHoursAgo, and
        // oneHourAgo (3 records), but NOT fourHoursAgo (1 record).
        expect(results, hasLength(3));
      });

      test('filters by alarm uid', () async {
        final results = await service.queryHistory(alarmUid: 'alarm-1');

        // alarm-1 has 2 history records (one active, one inactive).
        expect(results, hasLength(2));
        for (final r in results) {
          expect(r['alarmUid'], equals('alarm-1'));
        }
      });

      test('returns most recent history up to limit with no filters',
          () async {
        final results = await service.queryHistory();

        // All 4 records returned (default limit 100).
        expect(results, hasLength(4));
      });

      test('enforces limit parameter', () async {
        final results = await service.queryHistory(limit: 3);

        expect(results, hasLength(3));
      });

      test('results ordered by createdAt descending (most recent first)',
          () async {
        final results = await service.queryHistory();

        expect(results.length, greaterThanOrEqualTo(2));
        for (var i = 0; i < results.length - 1; i++) {
          final current = DateTime.parse(results[i]['createdAt'] as String);
          final next = DateTime.parse(results[i + 1]['createdAt'] as String);
          expect(current.isAfter(next) || current.isAtSameMomentAs(next),
              isTrue,
              reason:
                  'Result at index $i ($current) should be >= result at index ${i + 1} ($next)');
        }
      });
    });
  });
}
