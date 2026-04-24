import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/dynamic_value.dart' show DynamicValue;

import 'package:tfc/mcp/state_man_state_reader.dart';

/// Minimal mock for testing StateManStateReader logic.
///
/// Since StateMan is tightly coupled to OPC UA FFI, we cannot easily
/// instantiate it in unit tests. Instead, we test StateManStateReader
/// via its public interface by constructing it with controllable streams
/// using the test-only constructor.
void main() {
  group('StateManStateReader', () {
    test('keys returns all provided keys', () {
      final reader = StateManStateReader.forTest(
        keys: ['tag1', 'tag2', 'tag3'],
        streams: {},
      );

      expect(reader.keys, unorderedEquals(['tag1', 'tag2', 'tag3']));
    });

    test('getValue returns null for unsubscribed key', () {
      final reader = StateManStateReader.forTest(
        keys: ['tag1'],
        streams: {},
      );

      expect(reader.getValue('tag1'), isNull);
      expect(reader.getValue('nonexistent'), isNull);
    });

    test('getValue returns cached value after stream emits', () async {
      final controller = StreamController<DynamicValue>.broadcast();
      final reader = StateManStateReader.forTest(
        keys: ['temp'],
        streams: {'temp': controller.stream},
      );

      await reader.init();

      // Emit a value
      controller.add(DynamicValue(value: 42));
      // Allow async propagation
      await Future.delayed(Duration.zero);

      expect(reader.getValue('temp'), equals(42));

      await controller.close();
      reader.dispose();
    });

    test('getValue returns updated value when stream emits new data', () async {
      final controller = StreamController<DynamicValue>.broadcast();
      final reader = StateManStateReader.forTest(
        keys: ['pressure'],
        streams: {'pressure': controller.stream},
      );

      await reader.init();

      controller.add(DynamicValue(value: 100.5));
      await Future.delayed(Duration.zero);
      expect(reader.getValue('pressure'), equals(100.5));

      controller.add(DynamicValue(value: 200.0));
      await Future.delayed(Duration.zero);
      expect(reader.getValue('pressure'), equals(200.0));

      await controller.close();
      reader.dispose();
    });

    test('currentValues returns map of all cached pairs', () async {
      final ctrl1 = StreamController<DynamicValue>.broadcast();
      final ctrl2 = StreamController<DynamicValue>.broadcast();
      final reader = StateManStateReader.forTest(
        keys: ['a', 'b'],
        streams: {'a': ctrl1.stream, 'b': ctrl2.stream},
      );

      await reader.init();

      ctrl1.add(DynamicValue(value: 'hello'));
      ctrl2.add(DynamicValue(value: true));
      await Future.delayed(Duration.zero);

      final values = reader.currentValues;
      expect(values, {'a': 'hello', 'b': true});
      // Should be unmodifiable
      expect(() => values['c'] = 1, throwsUnsupportedError);

      await ctrl1.close();
      await ctrl2.close();
      reader.dispose();
    });

    test('handles DynamicValue with string value', () async {
      final controller = StreamController<DynamicValue>.broadcast();
      final reader = StateManStateReader.forTest(
        keys: ['status'],
        streams: {'status': controller.stream},
      );

      await reader.init();

      controller.add(DynamicValue(value: 'running'));
      await Future.delayed(Duration.zero);

      expect(reader.getValue('status'), equals('running'));

      await controller.close();
      reader.dispose();
    });

    test('handles DynamicValue with boolean value', () async {
      final controller = StreamController<DynamicValue>.broadcast();
      final reader = StateManStateReader.forTest(
        keys: ['flag'],
        streams: {'flag': controller.stream},
      );

      await reader.init();

      controller.add(DynamicValue(value: false));
      await Future.delayed(Duration.zero);

      expect(reader.getValue('flag'), equals(false));

      await controller.close();
      reader.dispose();
    });

    test('dispose cancels all subscriptions', () async {
      final controller = StreamController<DynamicValue>.broadcast();
      final reader = StateManStateReader.forTest(
        keys: ['tag'],
        streams: {'tag': controller.stream},
      );

      await reader.init();
      expect(controller.hasListener, isTrue);

      reader.dispose();
      expect(controller.hasListener, isFalse);
    });
  });
}
