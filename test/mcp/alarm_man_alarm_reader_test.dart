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
}
