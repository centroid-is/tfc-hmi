import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/mcp/alarm_man_alarm_reader.dart';

/// Test data for alarm configurations.
///
/// AlarmManAlarmReader works with AlarmConfig objects from tfc_dart.
/// Since AlarmMan is tightly coupled to StateMan (FFI), we test the
/// adapter by constructing it with known AlarmConfig fixtures directly.

// We need to import AlarmConfig/AlarmRule for test fixtures.
import 'package:tfc_dart/core/alarm.dart'
    show AlarmConfig, AlarmRule, AlarmLevel;
import 'package:tfc_dart/core/boolean_expression.dart'
    show ExpressionConfig, Expression;

void main() {
  group('AlarmManAlarmReader', () {
    test('alarmConfigs returns list of maps with correct keys', () {
      final configs = [
        AlarmConfig(
          uid: 'alarm-001',
          key: 'pump1.pressure',
          title: 'High Pressure',
          description: 'Pump 1 pressure exceeds threshold',
          rules: [
            AlarmRule(
              level: AlarmLevel.warning,
              expression: ExpressionConfig(
                value: Expression(formula: 'pump1.pressure > 100'),
              ),
              acknowledgeRequired: false,
            ),
          ],
        ),
      ];

      final reader = AlarmManAlarmReader.fromConfigs(configs);
      final result = reader.alarmConfigs;

      expect(result, hasLength(1));
      expect(result[0]['uid'], 'alarm-001');
      expect(result[0]['key'], 'pump1.pressure');
      expect(result[0]['title'], 'High Pressure');
      expect(result[0]['description'], 'Pump 1 pressure exceeds threshold');
      expect(result[0]['rules'], isList);
      expect(result[0]['rules'], hasLength(1));
    });

    test('alarmConfigs correctly converts AlarmRule.toJson() for rules', () {
      final configs = [
        AlarmConfig(
          uid: 'alarm-002',
          key: 'motor.temp',
          title: 'Motor Overheating',
          description: 'Motor temperature too high',
          rules: [
            AlarmRule(
              level: AlarmLevel.error,
              expression: ExpressionConfig(
                value: Expression(formula: 'motor.temp > 85'),
              ),
              acknowledgeRequired: true,
            ),
            AlarmRule(
              level: AlarmLevel.warning,
              expression: ExpressionConfig(
                value: Expression(formula: 'motor.temp > 70'),
              ),
              acknowledgeRequired: false,
            ),
          ],
        ),
      ];

      final reader = AlarmManAlarmReader.fromConfigs(configs);
      final result = reader.alarmConfigs;

      expect(result[0]['rules'], hasLength(2));
      // Each rule should be a Map from toJson()
      final rule0 = result[0]['rules'][0] as Map<String, dynamic>;
      expect(rule0['level'], 'error');
      expect(rule0['acknowledgeRequired'], true);
    });

    test('alarmConfigs returns empty list when no alarms configured', () {
      final reader = AlarmManAlarmReader.fromConfigs([]);
      expect(reader.alarmConfigs, isEmpty);
    });

    test('alarmConfigs handles alarm with null key', () {
      final configs = [
        AlarmConfig(
          uid: 'alarm-003',
          key: null,
          title: 'System Alert',
          description: 'General system alert',
          rules: [],
        ),
      ];

      final reader = AlarmManAlarmReader.fromConfigs(configs);
      final result = reader.alarmConfigs;

      expect(result[0]['key'], isNull);
      expect(result[0]['uid'], 'alarm-003');
    });

    test('alarmConfigs handles multiple alarms', () {
      final configs = [
        AlarmConfig(
          uid: 'a1',
          key: 'k1',
          title: 'Alarm 1',
          description: 'Desc 1',
          rules: [],
        ),
        AlarmConfig(
          uid: 'a2',
          key: 'k2',
          title: 'Alarm 2',
          description: 'Desc 2',
          rules: [],
        ),
        AlarmConfig(
          uid: 'a3',
          key: 'k3',
          title: 'Alarm 3',
          description: 'Desc 3',
          rules: [],
        ),
      ];

      final reader = AlarmManAlarmReader.fromConfigs(configs);
      expect(reader.alarmConfigs, hasLength(3));
    });
  });

  group('AlarmManAlarmReader.live', () {
    /// One alarm, in [group].
    AlarmConfig alarmIn(List<String> group, {String uid = 'alarm-1'}) =>
        AlarmConfig(
          uid: uid,
          key: 'multivac.film',
          title: 'Film reel empty',
          description: 'The upper film reel ran out',
          rules: const [],
          group: group,
          bindToGroup: false,
        );

    test('picks up a regroup that replaced the whole alarm list', () {
      // What an accepted alarm edit does: AlarmMan.updateAlarm mutates
      // config.alarms, then the editor calls invalidate(alarmManProvider),
      // which builds a NEW AlarmMan around a NEW list read back from
      // preferences. A reader that captured the list -- or the AlarmMan --
      // at construction is pinned to the orphan and answers every later MCP
      // read from it. In the field that showed up as get_alarm_tree
      // reporting 6 alarms under "Line 1" where the saved config had 31.
      var live = <AlarmConfig>[alarmIn(const [])];
      final reader = AlarmManAlarmReader.live(() => live);

      expect(reader.alarmConfigs.single['group'], isEmpty);

      // The invalidate: a different list object, holding the edit.
      live = <AlarmConfig>[
        alarmIn(const ['Line 1', 'Multivac'])
      ];

      expect(reader.alarmConfigs.single['group'], ['Line 1', 'Multivac'],
          reason: 'the reader must resolve the alarm list on every read, '
              'not capture it at construction');
    });

    test('sees an alarm added to the replacement list', () {
      var live = <AlarmConfig>[
        alarmIn(const ['Line 1'])
      ];
      final reader = AlarmManAlarmReader.live(() => live);
      expect(reader.alarmConfigs, hasLength(1));

      live = <AlarmConfig>[
        alarmIn(const ['Line 1']),
        alarmIn(const ['Line 1'], uid: 'alarm-2'),
      ];
      expect(reader.alarmConfigs, hasLength(2));
    });

    test('keeps answering from the last list while the source is null', () {
      // alarmManProvider is briefly unreadable after an invalidate, and a
      // rebuild window must not be reported as "no alarms are configured".
      List<AlarmConfig>? live = <AlarmConfig>[
        alarmIn(const ['Line 1'])
      ];
      final reader = AlarmManAlarmReader.live(() => live);
      expect(reader.alarmConfigs, hasLength(1));

      live = null;
      expect(reader.alarmConfigs.single['group'], ['Line 1']);

      live = <AlarmConfig>[
        alarmIn(const ['Line 2'])
      ];
      expect(reader.alarmConfigs.single['group'], ['Line 2']);
    });

    test('an empty live list is an empty answer, not a stale one', () {
      // Distinct from the null above: the operator deleted their last alarm.
      List<AlarmConfig>? live = <AlarmConfig>[
        alarmIn(const ['Line 1'])
      ];
      final reader = AlarmManAlarmReader.live(() => live);
      expect(reader.alarmConfigs, hasLength(1));

      live = <AlarmConfig>[];
      expect(reader.alarmConfigs, isEmpty);
    });
  });
}
