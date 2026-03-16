import 'package:test/test.dart';

import 'mock_alarm_reader.dart';

void main() {
  group('MockAlarmReader', () {
    late MockAlarmReader reader;

    setUp(() {
      reader = MockAlarmReader();
    });

    test('returns configured alarm configs', () {
      reader.addAlarmConfig({
        'uid': 'alarm-001',
        'title': 'Pump Overcurrent',
        'description': 'Motor current exceeds 15A',
        'key': 'pump3.current',
        'rules': '[]',
      });
      reader.addAlarmConfig({
        'uid': 'alarm-002',
        'title': 'Conveyor Overtemp',
        'description': 'Belt temperature above 80C',
        'key': 'conveyor.temp',
        'rules': '[]',
      });

      final configs = reader.alarmConfigs;
      expect(configs, hasLength(2));
      expect(configs[0]['uid'], equals('alarm-001'));
      expect(configs[0]['title'], equals('Pump Overcurrent'));
      expect(configs[1]['uid'], equals('alarm-002'));
      expect(configs[1]['title'], equals('Conveyor Overtemp'));
    });

    test('returns empty list when no configs added', () {
      expect(reader.alarmConfigs, isEmpty);
    });

    test('alarmConfigs returns unmodifiable list', () {
      reader.addAlarmConfig({'uid': 'alarm-001', 'title': 'Test'});
      final configs = reader.alarmConfigs;

      expect(
        () => configs.add({'uid': 'hack'}),
        throwsUnsupportedError,
      );
    });

    test('clear removes all configs', () {
      reader.addAlarmConfig({'uid': 'alarm-001', 'title': 'Test'});
      reader.clear();
      expect(reader.alarmConfigs, isEmpty);
    });
  });
}
