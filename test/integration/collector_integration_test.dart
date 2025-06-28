import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/core/collector.dart';
import 'package:tfc/core/state_man.dart';
import 'package:tfc/core/database.dart';

import 'docker_compose.dart';

void main() {
  group('Collector Integration', () {
    late Collector collector;
    late CollectorConfig config;
    late StateMan stateMan;
    late Database database;

    setUpAll(() async {
      stateMan = await StateMan.create(
          config: StateManConfig(opcua: []),
          keyMappings: KeyMappings(nodes: {}));
      await stopDockerCompose();
      await startDockerCompose();
      await waitForDatabaseReady();
      database = await connectToDatabase();
    });

    setUp(() {
      // Create a basic config for testing
      config = CollectorConfig(tables: [
        CollectTable(
          name: 'test_table',
          entries: [
            CollectEntry(key: 'test_key', name: 'Test Key'),
            CollectEntry(key: 'test_key2', name: 'Test Key 2'),
          ],
        ),
      ]);

      collector = Collector(
        config: config,
        stateMan: stateMan,
        database: database,
      );
    });

    tearDownAll(() async {
      await stopDockerCompose();
    });

    Future<List<List<dynamic>>> waitUntilInserted(String tableName,
        {DateTime? sinceTime}) async {
      late dynamic insertedData;
      for (var i = 0; i < 10; i++) {
        // Wait for async processing
        await Future.delayed(const Duration(milliseconds: 100));
        try {
          insertedData =
              await database.queryTimeseriesData(tableName, sinceTime);
          if (insertedData.length > 0) {
            break;
          }
        } catch (e) {
          // Ignore
        }
      }
      return insertedData;
    }

    test('should initialize with empty key mappings', () {
      expect(collector.config.tables.length, 1);
      expect(collector.subscriptions, isEmpty);
    });

    test('collectImpl should create subscription and handle data collection',
        () async {
      // Arrange
      const testName = 'test_collection';
      final testValue = DynamicValue(value: 'test_value');
      final streamController = StreamController<DynamicValue>();

      // Act
      await collector.collectEntryImpl(
          CollectEntry(key: testName, name: testName), streamController.stream);

      // Verify subscription was created
      expect(collector.subscriptions.containsKey(testName), isTrue);
      expect(collector.subscriptions[testName], isNotNull);

      // Simulate data stream
      streamController.add(testValue);
      final insertedData = await waitUntilInserted(testName);
      expect(insertedData.length, 1);
      expect(insertedData[0][1],
          'test_value'); // The value should be stored as JSON

      // Clean up
      streamController.close();
      collector.stopCollect(testName);
    });

    test('collectImpl fail if value type is not same', () async {
      // Arrange
      const testName = 'multi_test';
      final values = [
        DynamicValue(value: 'value1'),
        DynamicValue(value: 42),
        DynamicValue(value: true),
      ];
      final streamController = StreamController<DynamicValue>();

      // Act
      await collector.collectEntryImpl(
          CollectEntry(key: testName, name: testName), streamController.stream);

      // Add multiple values
      for (final value in values) {
        streamController.add(value);
        await waitUntilInserted(testName); // Not sure why this is needed
      }

      final insertedData = await waitUntilInserted(testName);

      expect(insertedData.length, 3);
      expect(insertedData[0][1], 'value1');
      expect(insertedData[1][1], '42');
      expect(insertedData[2][1], 'TRUE');

      // Clean up
      streamController.close();
      collector.stopCollect(testName);
    });

    test('collectImpl should handle stream errors', () async {
      // Arrange
      const testName = 'error_test';
      final streamController = StreamController<DynamicValue>();
      final testError = Exception('Test error');

      // Act
      await collector.collectEntryImpl(
          CollectEntry(key: testName, name: testName), streamController.stream);

      streamController
          .add(DynamicValue(value: 'test_value')); // Create the table

      // Add an error to the stream
      streamController.addError(testError);

      // Wait for async processing
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert - error should be logged but not crash
      expect(collector.subscriptions.containsKey(testName), isTrue);

      final insertedData = await waitUntilInserted(testName);
      expect(insertedData.length, 1);

      // Clean up
      streamController.close();
      collector.stopCollect(testName);
    });

    test('collectImpl should handle stream completion', () async {
      // Arrange
      const testName = 'completion_test';
      final streamController = StreamController<DynamicValue>();

      // Act
      await collector.collectEntryImpl(
          CollectEntry(key: testName, name: testName), streamController.stream);

      streamController
          .add(DynamicValue(value: 'test_value')); // Create the table

      // Complete the stream
      streamController.close();

      // Wait for async processing
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert - subscription should still exist but be done
      expect(collector.subscriptions.containsKey(testName), isTrue);

      // Verify no data was inserted since no values were added
      final insertedData = await waitUntilInserted(testName);
      expect(insertedData.length, 1);

      // Clean up
      collector.stopCollect(testName);
    });

    test('collectImpl should handle complex DynamicValue objects', () async {
      // Arrange
      const testName = 'complex_test';
      final complexValue = DynamicValue.fromMap(
        LinkedHashMap<String, DynamicValue>.from(
          {
            'string': DynamicValue(value: 'hello'),
            'number': DynamicValue(value: 123.45),
            'boolean': DynamicValue(value: false),
          },
        ),
      );
      final streamController = StreamController<DynamicValue>();

      // Act
      await collector.collectEntryImpl(
          CollectEntry(key: testName, name: testName), streamController.stream);
      streamController.add(complexValue);

      // Wait for async processing
      await Future.delayed(Duration(milliseconds: 100));

      // Assert - verify complex object was inserted correctly
      final sinceTime = DateTime.now().toUtc().subtract(Duration(minutes: 1));
      final insertedData =
          await database.queryTimeseriesData(testName, sinceTime);

      expect(insertedData.length, 1);
      final insertedValue = insertedData[0][1];
      expect(insertedValue, isA<Map>());
      expect(insertedValue['string'], 'hello');
      expect(insertedValue['number'], 123.45);
      expect(insertedValue['boolean'], false);

      // Clean up
      streamController.close();
      collector.stopCollect(testName);
    });

    test('collectImpl should store subscription in subscriptions map',
        () async {
      // Arrange
      const testName = 'subscription_test';
      final streamController = StreamController<DynamicValue>();

      // Act
      await collector.collectEntryImpl(
          CollectEntry(key: testName, name: testName), streamController.stream);

      // Assert
      expect(collector.subscriptions.containsKey(testName), isTrue);
      expect(collector.subscriptions[testName],
          isA<StreamSubscription<DynamicValue>>());

      // Clean up
      streamController.close();
      collector.stopCollect(testName);
    });
  });
}
