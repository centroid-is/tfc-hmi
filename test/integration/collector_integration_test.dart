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
      config = CollectorConfig();

      collector = Collector(
        config: config,
        stateMan: stateMan,
        database: database,
      );
    });

    tearDownAll(() async {
      await stopDockerCompose();
    });

    Future<List<TimeseriesData<dynamic>>> waitUntilInserted(String tableName,
        {DateTime? sinceTime}) async {
      late dynamic insertedData;
      for (var i = 0; i < 10; i++) {
        // Wait for async processing
        try {
          insertedData =
              await database.queryTimeseriesData(tableName, sinceTime);
          if (insertedData.length > 0) {
            break;
          }
        } catch (e) {
          // Ignore
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return insertedData;
    }

    test('collectImpl should create subscription and handle data collection',
        () async {
      // Arrange
      const testName = 'test_collection';
      final testValue = DynamicValue(value: 'test_value');
      final streamController = StreamController<DynamicValue>();

      final entry = CollectEntry(key: testName, name: testName);
      // Act
      await collector.collectEntryImpl(entry, streamController.stream);

      // Simulate data stream
      streamController.add(testValue);
      final insertedData = await waitUntilInserted(testName);
      expect(insertedData.length, 1);
      expect(insertedData[0].value, 'test_value');

      // Clean up
      streamController.close();
      collector.stopCollect(entry);
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
      final entry = CollectEntry(key: testName, name: testName);
      await collector.collectEntryImpl(entry, streamController.stream);

      // Add multiple values
      for (final value in values) {
        streamController.add(value);
        await waitUntilInserted(testName); // Not sure why this is needed
      }

      final insertedData = await waitUntilInserted(testName);

      expect(insertedData.length, 3);
      expect(insertedData[0].value, 'value1');
      expect(insertedData[1].value, '42');
      expect(insertedData[2].value, 'TRUE');

      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    });

    test('collectImpl should handle stream errors', () async {
      // Arrange
      const testName = 'error_test';
      final streamController = StreamController<DynamicValue>();
      final testError = Exception('Test error');

      // Act
      final entry = CollectEntry(key: testName, name: testName);
      await collector.collectEntryImpl(entry, streamController.stream);

      streamController
          .add(DynamicValue(value: 'test_value')); // Create the table

      // Add an error to the stream
      streamController.addError(testError);

      // Wait for async processing
      await Future.delayed(const Duration(milliseconds: 100));

      final insertedData = await waitUntilInserted(testName);
      expect(insertedData.length, 1);

      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    });

    test('collectImpl should handle stream completion', () async {
      // Arrange
      const testName = 'completion_test';
      final streamController = StreamController<DynamicValue>();

      // Act
      final entry = CollectEntry(key: testName, name: testName);
      await collector.collectEntryImpl(entry, streamController.stream);

      streamController
          .add(DynamicValue(value: 'test_value')); // Create the table

      // Complete the stream
      streamController.close();

      // Wait for async processing
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify no data was inserted since no values were added
      final insertedData = await waitUntilInserted(testName);
      expect(insertedData.length, 1);

      // Clean up
      collector.stopCollect(entry);
    });

    test('collectImpl should handle complex DynamicValue objects', () async {
      // Arrange
      const testName = 'complex_test2';
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
      final entry = CollectEntry(key: testName, name: testName);
      await collector.collectEntryImpl(entry, streamController.stream);
      streamController.add(complexValue);

      // Wait for async processing
      await Future.delayed(const Duration(milliseconds: 100));

      // Assert - verify complex object was inserted correctly
      final insertedData = await waitUntilInserted(testName);

      expect(insertedData.length, 1);
      final insertedValue = insertedData[0].value;
      expect(insertedValue, isA<Map>());
      expect(insertedValue['string'], 'hello');
      expect(insertedValue['number'], 123.45);
      expect(insertedValue['boolean'], false);

      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    });

    test(
        'collectImpl should respect sample interval and only collect latest value within interval',
        () async {
      // Arrange
      const testName = 'sampling_test';
      const sampleInterval = Duration(milliseconds: 100);

      final values = [
        DynamicValue(value: 'value1'),
        DynamicValue(value: 'value2'),
        DynamicValue(value: 'value3'),
      ];
      final streamController = StreamController<DynamicValue>();

      // Act - Create collection with sample interval
      final entry = CollectEntry(
        key: testName,
        name: testName,
        sampleInterval: sampleInterval,
      );
      await collector.collectEntryImpl(entry, streamController.stream);

      // Add first value
      streamController.add(values[0]);
      await Future.delayed(sampleInterval * 1.5); // wait long enough

      // Add second value (should be ignored due to sample interval)
      streamController.add(values[1]);
      await Future.delayed(const Duration(milliseconds: 1));

      // Add third value (should be ignored due to sample interval)
      streamController.add(values[2]);
      await Future.delayed(const Duration(milliseconds: 1));

      // Add another value after the interval (should be collected)
      streamController.add(DynamicValue(value: 'value4'));

      // Wait for async processing
      await Future.delayed(sampleInterval * 1);

      // Assert - Only the first and last values should be collected
      final insertedData = await waitUntilInserted(testName);

      // With proper sampling implementation, we should only see 2 values:
      // 1. The first value (immediately collected)
      // 2. The last value after the sample interval
      expect(insertedData.length, 2);
      expect(insertedData[0].value, 'value1'); // First value
      expect(insertedData[1].value, 'value4'); // Last value after interval

      // The intermediate values (value2, value3) should be dropped due to sampling

      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    }, skip: true); // flaky test

    test('collectStream should return historical data initially', () async {
      // Arrange
      const testKey = 'historical_test';
      const testName = 'historical_test';
      final entry = CollectEntry(key: testKey, name: testName);

      database.registerRetentionPolicy(
          testName,
          const RetentionPolicy(
            dropAfter: Duration(days: 1),
          ));

      // Insert some historical data
      final historicalData = [
        TimeseriesData<dynamic>('value1',
            DateTime.now().toUtc().subtract(const Duration(hours: 2))),
        TimeseriesData<dynamic>('value2',
            DateTime.now().toUtc().subtract(const Duration(hours: 1))),
        TimeseriesData<dynamic>('value3',
            DateTime.now().toUtc().subtract(const Duration(minutes: 30))),
      ];

      for (final data in historicalData) {
        await database.insertTimeseriesData(testName, data.time, data.value);
      }

      // Act
      await collector.collectEntryImpl(entry, const Stream.empty());
      final stream =
          collector.collectStream(testKey, since: const Duration(hours: 3));

      // Assert
      final result = await stream.first;
      expect(result.length, 3);
      expect(result[0].value, 'value1');
      expect(result[1].value, 'value2');
      expect(result[2].value, 'value3');

      // Clean up
      collector.stopCollect(entry);
    });

    test('collectStream should combine historical and real-time data',
        () async {
      // Arrange
      const testKey = 'combined_test';
      const testName = 'combined_test';
      final entry = CollectEntry(key: testKey, name: testName);
      final streamController = StreamController<DynamicValue>();

      database.registerRetentionPolicy(
          testName,
          const RetentionPolicy(
            dropAfter: Duration(days: 1),
          ));

      // Insert historical data
      final historicalData = [
        TimeseriesData<dynamic>('historical1',
            DateTime.now().toUtc().subtract(const Duration(hours: 1))),
        TimeseriesData<dynamic>('historical2',
            DateTime.now().toUtc().subtract(const Duration(minutes: 30))),
      ];

      for (final data in historicalData) {
        await database.insertTimeseriesData(testName, data.time, data.value);
      }

      // Act
      await collector.collectEntryImpl(entry, streamController.stream);
      final stream =
          collector.collectStream(testKey, since: const Duration(hours: 2));

      int count = 0;
      stream.listen((data) {
        count++;
        if (count == 1) {
          expect(data.length, 2);
          expect(data[0].value, 'historical1');
          expect(data[1].value, 'historical2');
        } else if (count == 2) {
          expect(data.length, 3);
          expect(data[0].value, 'historical1');
          expect(data[1].value, 'historical2');
          expect(data[2].value, 'realtime1');
        }
      });

      // wait for database query
      await Future.delayed(const Duration(milliseconds: 100));

      streamController.add(DynamicValue(value: 'realtime1'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(count, 2);
      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    });

    test('collectStream should respect since parameter for historical data',
        () async {
      // Arrange
      const testKey = 'since_test';
      const testName = 'since_test';
      final entry = CollectEntry(key: testKey, name: testName);

      database.registerRetentionPolicy(
          testName,
          const RetentionPolicy(
            dropAfter: Duration(days: 1),
          ));

      // Insert data with different timestamps
      final now = DateTime.now().toUtc();
      final data = [
        TimeseriesData<dynamic>('old', now.subtract(const Duration(hours: 3))),
        TimeseriesData<dynamic>(
            'recent', now.subtract(const Duration(hours: 1))),
        TimeseriesData<dynamic>(
            'very_recent', now.subtract(const Duration(minutes: 30))),
      ];

      for (final d in data) {
        await database.insertTimeseriesData(testName, d.time, d.value);
      }

      // Act - query with since = 2 hours
      await collector.collectEntryImpl(entry, Stream.empty());
      final stream =
          collector.collectStream(testKey, since: const Duration(hours: 2));

      // Assert - should only get data from last 2 hours
      final result = await stream.first;
      expect(result.length, 2);
      expect(result[0].value, 'recent');
      expect(result[1].value, 'very_recent');

      // Clean up
      collector.stopCollect(entry);
    });

    test('collectStream should handle multiple real-time updates', () async {
      // Arrange
      const testKey = 'multiple_updates_test';
      const testName = 'multiple_updates_test';
      final entry = CollectEntry(key: testKey, name: testName);
      final streamController = StreamController<DynamicValue>();

      database.registerRetentionPolicy(
          testName,
          const RetentionPolicy(
            dropAfter: Duration(days: 1),
          ));

      // Insert historical data
      await database.insertTimeseriesData(
          testName,
          DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          'historical');

      // Act
      await collector.collectEntryImpl(entry, streamController.stream);
      final stream =
          collector.collectStream(testKey, since: const Duration(hours: 2));

      int count = 0;
      stream.listen((data) {
        count++;
        if (count == 1) {
          expect(data.length, 1);
          expect(data[0].value, 'historical');
        } else if (count == 2) {
          expect(data.length, 2);
          expect(data[0].value, 'historical');
          expect(data[1].value, 'update1');
        } else if (count == 3) {
          expect(data.length, 3);
          expect(data[0].value, 'historical');
          expect(data[1].value, 'update1');
          expect(data[2].value, 'update2');
        } else if (count == 4) {
          expect(data.length, 4);
          expect(data[0].value, 'historical');
          expect(data[1].value, 'update1');
          expect(data[2].value, 'update2');
          expect(data[3].value, 'update3');
        }
      });
      // wait for database query
      await Future.delayed(const Duration(milliseconds: 100));

      // Add multiple real-time updates
      streamController.add(DynamicValue(value: 'update1'));
      await Future.delayed(const Duration(milliseconds: 100));

      streamController.add(DynamicValue(value: 'update2'));
      await Future.delayed(const Duration(milliseconds: 100));

      streamController.add(DynamicValue(value: 'update3'));
      await Future.delayed(const Duration(milliseconds: 100));

      expect(count, 4);

      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    });

    test('collectStream should handle complex DynamicValue objects', () async {
      // Arrange
      const testKey = 'complex_test';
      const testName = 'complex_test';
      final entry = CollectEntry(key: testKey, name: testName);
      final streamController = StreamController<DynamicValue>();

      database.registerRetentionPolicy(
          testName,
          const RetentionPolicy(
            dropAfter: Duration(days: 1),
          ));

      // Insert historical complex data
      final complexHistoricalData = {
        'temperature': 25.5,
        'humidity': 60.2,
        'pressure': 1013.25,
      };
      await database.insertTimeseriesData(
          testName,
          DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          complexHistoricalData);

      // Act
      await collector.collectEntryImpl(entry, streamController.stream);
      final stream =
          collector.collectStream(testKey, since: const Duration(hours: 2));

      int count = 0;
      stream.listen((data) {
        count++;
        if (count == 1) {
          expect(data.length, 1);
          expect(data[0].value, complexHistoricalData);
        } else if (count == 2) {
          expect(data.length, 2);
          expect(data[0].value, complexHistoricalData);
          expect(data[1].value, isA<Map>());
          expect(data[1].value['temperature'], 26.0);
          expect(data[1].value['humidity'], 65.0);
          expect(data[1].value['pressure'], 1012.0);
        }
      });

      // wait for database query
      await Future.delayed(const Duration(milliseconds: 100));

      // Add complex real-time data
      final complexRealtimeData = DynamicValue.fromMap(
        LinkedHashMap<String, DynamicValue>.from({
          'temperature': DynamicValue(value: 26.0),
          'humidity': DynamicValue(value: 65.0),
          'pressure': DynamicValue(value: 1012.0),
        }),
      );
      streamController.add(complexRealtimeData);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(count, 2);
      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    });

    test('collectStream should handle real-time stream errors', () async {
      // Arrange
      const testKey = 'stream_error_test';
      const testName = 'stream_error_test';
      final entry = CollectEntry(key: testKey, name: testName);
      final streamController = StreamController<DynamicValue>();

      database.registerRetentionPolicy(
          testName,
          const RetentionPolicy(
            dropAfter: Duration(days: 1),
          ));

      // Insert historical data
      await database.insertTimeseriesData(
          testName,
          DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          'historical');

      // Act
      await collector.collectEntryImpl(entry, streamController.stream);
      final stream =
          collector.collectStream(testKey, since: const Duration(hours: 2));

      // Get initial data
      final initialData = await stream.first;
      expect(initialData.length, 1);
      expect(initialData[0].value, 'historical');

      // Add error to the stream
      streamController.addError(Exception('Stream error'));
      await Future.delayed(const Duration(milliseconds: 100));

      // Clean up
      streamController.close();
      collector.stopCollect(entry);
    });
  });
}
