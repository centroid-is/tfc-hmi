@Tags(['docker'])
library;

import 'package:test/test.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'docker_compose.dart';

void main() {
  final testDb = TestDb(
    composeFile: 'docker-compose.alarm.yml',
    containerName: 'test-db-alarm',
    port: 5444,
  );

  late Database database;
  late Preferences prefs;
  late StateMan stateMan;

  AlarmConfig makeAlarmConfig(String uid,
      {String? key, String title = 'Test alarm'}) {
    return AlarmConfig(
      uid: uid,
      key: key,
      title: title,
      description: 'Description for $uid',
      rules: [
        AlarmRule(
          level: AlarmLevel.error,
          expression: ExpressionConfig(
            value: Expression(formula: 'A == true'),
          ),
          acknowledgeRequired: false,
        ),
      ],
    );
  }

  AlarmActive makeActive(Alarm alarm, AlarmConfig config) {
    return AlarmActive(
      alarm: alarm,
      notification: AlarmNotification(
        uid: config.uid,
        active: true,
        expression: 'A == true',
        rule: config.rules.first,
        timestamp: DateTime.now(),
      ),
    );
  }

  setUpAll(() async {
    await testDb.start();
    await testDb.waitForReady();
    database = await testDb.connect();
    expect(await database.db.isOpen, true);
  });

  setUp(() async {
    // Clean tables before each test
    await database.db.customStatement('DELETE FROM alarm_history');
    await database.db.customStatement('DELETE FROM alarm');

    prefs = await Preferences.create(db: database);
    stateMan = await StateMan.create(
      config: StateManConfig(opcua: []),
      keyMappings: KeyMappings(nodes: {}),
      useIsolate: false,
      alias: 'test-alarm-db',
    );
  });

  tearDown(() async {
    await stateMan.close();
  });

  tearDownAll(() async {
    await database.close();
    await testDb.stop();
  });

  group('Alarm DB sync', () {
    test('addAlarm inserts row into alarm table', () async {
      final alarmMan =
          await AlarmMan.create(prefs, stateMan, historyToDb: true);
      final config = makeAlarmConfig('test-1');

      alarmMan.addAlarm(config);
      await Future.delayed(const Duration(milliseconds: 100));

      final rows = await database.db.select(database.db.alarm).get();
      expect(rows, hasLength(1));
      expect(rows.first.uid, 'test-1');
      expect(rows.first.title, 'Test alarm');
    });

    test('removeAlarm deletes row from alarm table', () async {
      final alarmMan =
          await AlarmMan.create(prefs, stateMan, historyToDb: true);
      final config = makeAlarmConfig('test-2');

      alarmMan.addAlarm(config);
      await Future.delayed(const Duration(milliseconds: 100));

      var rows = await database.db.select(database.db.alarm).get();
      expect(rows, hasLength(1));

      alarmMan.removeAlarm(config);
      await Future.delayed(const Duration(milliseconds: 100));

      rows = await database.db.select(database.db.alarm).get();
      expect(rows, isEmpty);
    });

    test('updateAlarm updates row in alarm table', () async {
      final alarmMan =
          await AlarmMan.create(prefs, stateMan, historyToDb: true);
      final config = makeAlarmConfig('test-3', title: 'Original');

      alarmMan.addAlarm(config);
      await Future.delayed(const Duration(milliseconds: 100));

      final updated = AlarmConfig(
        uid: 'test-3',
        title: 'Updated',
        description: config.description,
        rules: config.rules,
      );
      alarmMan.updateAlarm(updated);
      await Future.delayed(const Duration(milliseconds: 100));

      final rows = await database.db.select(database.db.alarm).get();
      expect(rows, hasLength(1));
      expect(rows.first.title, 'Updated');
    });

    test('removeAlarmsWhere deletes matching rows', () async {
      final alarmMan =
          await AlarmMan.create(prefs, stateMan, historyToDb: true);
      alarmMan.addAlarm(makeAlarmConfig('keep-1'));
      alarmMan.addAlarm(makeAlarmConfig('remove-1'));
      alarmMan.addAlarm(makeAlarmConfig('remove-2'));
      await Future.delayed(const Duration(milliseconds: 100));

      var rows = await database.db.select(database.db.alarm).get();
      expect(rows, hasLength(3));

      alarmMan.removeAlarmsWhere((a) => a.uid.startsWith('remove'));
      await Future.delayed(const Duration(milliseconds: 100));

      rows = await database.db.select(database.db.alarm).get();
      expect(rows, hasLength(1));
      expect(rows.first.uid, 'keep-1');
    });

    test('alarm history insert succeeds when alarm row exists', () async {
      final alarmMan =
          await AlarmMan.create(prefs, stateMan, historyToDb: true);
      final config = makeAlarmConfig('hist-1');

      alarmMan.addAlarm(config);
      await Future.delayed(const Duration(milliseconds: 100));

      // Trigger alarm active → ack to push history via _removeActiveAlarm
      final alarm = alarmMan.alarms.firstWhere((a) => a.config.uid == 'hist-1');
      final active = makeActive(alarm, config);

      alarmMan.addExternalAlarm(active);
      await Future.delayed(const Duration(milliseconds: 100));

      alarmMan.ackAlarm(active);
      await Future.delayed(const Duration(milliseconds: 100));

      final historyRows =
          await database.db.select(database.db.alarmHistory).get();
      expect(historyRows, hasLength(1));
      expect(historyRows.first.alarmUid, 'hist-1');
    });

    test('alarm history insert fails without alarm row (FK violation)',
        () async {
      final alarmMan =
          await AlarmMan.create(prefs, stateMan, historyToDb: true);

      // Use addEphemeralAlarm — no DB row created
      final config = makeAlarmConfig('orphan-1');
      alarmMan.addEphemeralAlarm(config);

      final alarm =
          alarmMan.alarms.firstWhere((a) => a.config.uid == 'orphan-1');
      final active = makeActive(alarm, config);

      alarmMan.addExternalAlarm(active);
      await Future.delayed(const Duration(milliseconds: 100));

      alarmMan.ackAlarm(active);
      await Future.delayed(const Duration(milliseconds: 100));

      // FK violation — no history row
      final historyRows =
          await database.db.select(database.db.alarmHistory).get();
      expect(historyRows, isEmpty);
    });
  });
}
