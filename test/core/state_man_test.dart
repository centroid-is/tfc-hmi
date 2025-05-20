import 'dart:async';

import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:tfc/core/state_man.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyCollectorManager', () {
    late KeyCollectorManager manager;
    late StreamController<DynamicValue> mockStreamController;

    setUp(() {
      mockStreamController = StreamController<DynamicValue>.broadcast();
      manager = KeyCollectorManager(
        monitorFn: (key) async => mockStreamController.stream,
      );
    });

    tearDown(() {
      manager.close();
      mockStreamController.close();
    });

    test('should start collection and emit values', () async {
      const key = 'testKey';
      const size = 3;

      await manager.collect(key, size);
      final stream = manager.collectStream(key);

      // Add some values
      mockStreamController.add(DynamicValue(value: 1, typeId: NodeId.int16));
      mockStreamController.add(DynamicValue(value: 2, typeId: NodeId.int16));
      mockStreamController.add(DynamicValue(value: 3, typeId: NodeId.int16));

      // Verify the buffer size is maintained
      final values = await stream.firstWhere((list) => list.length == size);
      expect(values.length, equals(size));
      expect(values[0].value.asInt, equals(1));
      expect(values[1].value.asInt, equals(2));
      expect(values[2].value.asInt, equals(3));
    });

    test('should throw when accessing non-existent collection', () {
      expect(
        () => manager.collectStream('nonExistentKey'),
        throwsA(isA<StateManException>()),
      );
    });

    test('should handle multiple collections simultaneously', () async {
      const key1 = 'key1';
      const key2 = 'key2';
      const size = 2;

      await manager.collect(key1, size);
      await manager.collect(key2, size);

      mockStreamController.add(DynamicValue(value: 1, typeId: NodeId.int16));

      final values1 = await manager.collectStream(key1).first;
      final values2 = await manager.collectStream(key2).first;

      expect(values1.length, equals(1));
      expect(values2.length, equals(1));
    });

    test('should stop collection and clean up resources', () async {
      const key = 'testKey';
      const size = 2;

      await manager.collect(key, size);
      manager.stopCollect(key);

      expect(
        () => manager.collectStream(key),
        throwsA(isA<StateManException>()),
      );
    });

    test('should handle stream errors gracefully', () async {
      // const key = 'testKey';
      // const size = 2;

      // await manager.collect(key, size);
      // final stream = manager.collectStream(key);

      // mockStreamController.addError('Test error');

      // expect(
      //   stream.firstWhere((_) => false),
      //   throwsA('Test error'),
      // );
    }, skip: 'TODO: fix this test');

    test('should maintain buffer size when adding more values than capacity',
        () async {
      const key = 'testKey';
      const size = 2;

      await manager.collect(key, size);
      final stream = manager.collectStream(key);

      // Add more values than buffer size
      mockStreamController.add(DynamicValue(value: 1, typeId: NodeId.int16));
      mockStreamController.add(DynamicValue(value: 2, typeId: NodeId.int16));
      mockStreamController.add(DynamicValue(value: 3, typeId: NodeId.int16));

      final values = await stream.firstWhere((list) =>
          list.length == size &&
          list[0].value.asInt == 2 &&
          list[1].value.asInt == 3);
      expect(values.length, equals(size),
          reason: 'Buffer size should be maintained');
      expect(values[0].value.asInt, equals(2),
          reason: 'First value should be 2');
      expect(values[1].value.asInt, equals(3),
          reason: 'Second value should be 3');
    });

    test('should handle multiple subscribers to the same collection', () async {
      const key = 'testKey';
      const size = 2;

      await manager.collect(key, size);
      final stream1 = manager.collectStream(key);
      final stream2 = manager.collectStream(key);

      mockStreamController.add(DynamicValue(value: 1, typeId: NodeId.int16));

      final values1 = await stream1.first;
      final values2 = await stream2.first;

      expect(values1.length, equals(1));
      expect(values2.length, equals(1));
    });

    test('should handle collection restart', () async {
      const key = 'testKey';
      const size = 2;

      await manager.collect(key, size);
      manager.stopCollect(key);
      await manager.collect(key, size);

      mockStreamController.add(DynamicValue(value: 1, typeId: NodeId.int16));

      final values = await manager.collectStream(key).first;
      expect(values.length, equals(1));
    });

    test('should copy dynamic value when received', () async {
      const key = 'testKey';
      const size = 3;

      await manager.collect(key, size);
      final stream = manager.collectStream(key);

      // Add more values than buffer size
      var value = DynamicValue(value: 1, typeId: NodeId.int16);
      mockStreamController.add(value);
      await Future.delayed(const Duration(milliseconds: 1));
      value.value = 2;
      mockStreamController.add(value);
      await Future.delayed(const Duration(milliseconds: 1));
      value.value = 3;
      mockStreamController.add(value);

      final values = await stream.firstWhere((list) => list.length == size);
      expect(values.length, equals(size),
          reason: 'Buffer size should be maintained');
      expect(values[0].value.asInt, equals(1),
          reason: 'First value should be 1');
      expect(values[1].value.asInt, equals(2),
          reason: 'Second value should be 2');
      expect(values[2].value.asInt, equals(3),
          reason: 'Third value should be 3');
    });
  });
}
