import 'package:test/test.dart';

import 'mock_state_reader.dart';

void main() {
  group('MockStateReader', () {
    late MockStateReader reader;

    setUp(() {
      reader = MockStateReader();
    });

    test('setValue/getValue round-trips correctly', () {
      reader.setValue('pump3.speed', 1450);
      reader.setValue('conveyor.temp', 72.5);
      reader.setValue('motor.running', true);

      expect(reader.getValue('pump3.speed'), equals(1450));
      expect(reader.getValue('conveyor.temp'), equals(72.5));
      expect(reader.getValue('motor.running'), isTrue);
    });

    test('getValue returns null for missing keys', () {
      expect(reader.getValue('nonexistent'), isNull);
    });

    test('keys returns all set keys', () {
      reader.setValue('pump3.speed', 1450);
      reader.setValue('conveyor.temp', 72.5);
      reader.setValue('motor.running', true);

      expect(reader.keys, unorderedEquals(['pump3.speed', 'conveyor.temp', 'motor.running']));
    });

    test('currentValues returns unmodifiable map', () {
      reader.setValue('a', 1);
      reader.setValue('b', 2);

      final values = reader.currentValues;
      expect(values, hasLength(2));
      expect(values['a'], equals(1));
      expect(values['b'], equals(2));

      // Should be unmodifiable
      expect(
        () => values['c'] = 3,
        throwsUnsupportedError,
      );
    });

    test('clear removes all values', () {
      reader.setValue('a', 1);
      reader.setValue('b', 2);
      reader.clear();

      expect(reader.keys, isEmpty);
      expect(reader.currentValues, isEmpty);
      expect(reader.getValue('a'), isNull);
    });
  });
}
