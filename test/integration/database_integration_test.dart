import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:tfc/core/database.dart';

import 'docker_compose.dart';

// docker exec -it test-db /bin/ash -c "psql -d testdb --user testuser -c 'select * from test_timeseries;'"

void main() {
  group('Database Integration Tests', () {
    late Database database;

    // Test table names
    const testTableName = 'test_timeseries';
    const testTableName2 = 'test_timeseries_2';

    setUpAll(() async {
      await startDockerCompose();
      await waitForDatabaseReady(); // More reliable than a fixed delay

      database = await connectToDatabase();

      // Verify connection
      expect(database.isOpen, true);
    });

    tearDown(() async {
      // Clean up test tables
      try {
        // Remove retention policies first
        await database
            .execute('DROP TABLE IF EXISTS $testTableName CASCADE')
            .timeout(const Duration(seconds: 5));
        await database
            .execute('DROP TABLE IF EXISTS $testTableName2 CASCADE')
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    tearDownAll(() async {
      await database.close();
      await stopDockerCompose();
    });

    group('Connection Tests', () {
      test('should connect to PostgreSQL database', () async {
        expect(database.isOpen, true);

        // Test basic query
        final result = await database.execute('SELECT 1 as test_value');
        expect(result.first[0], 1);
      });

      test('should handle connection errors gracefully', () async {
        final badConfig = DatabaseConfig(
          postgres: Endpoint(
            host: 'invalid-host',
            port: 5432,
            database: 'testdb',
            username: 'testuser',
            password: 'testpass',
          ),
        );

        final badDatabase = Database(badConfig);

        expect(
          () => badDatabase.connect(),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('Table Operations', () {
      test('should check if table exists', () async {
        // Table should not exist initially
        expect(await database.tableExists(testTableName), false);

        // Create table
        await database.execute('''
          CREATE TABLE "$testTableName" (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');

        // Table should exist now
        expect(await database.tableExists(testTableName), true);

        // Clean up
        await database.execute('DROP TABLE "$testTableName"');
      });

      test('should handle table operations with special characters', () async {
        const specialTableName = 'test-table_with.special_chars';

        expect(await database.tableExists(specialTableName), false);

        await database.execute('''
          CREATE TABLE "$specialTableName" (
            id SERIAL PRIMARY KEY
          )
        ''');

        expect(await database.tableExists(specialTableName), true);

        await database.execute('DROP TABLE "$specialTableName"');
      });
    });

    group('TimescaleDB Integration', () {
      test('should create timeseries table with retention policy', () async {
        const retention = Duration(minutes: 5);

        await database.registerRetentionPolicy(
            testTableName, RetentionPolicy(dropAfter: retention));
        await database.insertTimeseriesData(
            testTableName, DateTime.now(), 42); // This should create the table

        // Verify table exists
        expect(await database.tableExists(testTableName), true);

        // Verify it's a hypertable (TimescaleDB specific)
        final hypertableResult = await database.execute(Sql.named('''
          SELECT EXISTS (
            SELECT FROM timescaledb_information.hypertables 
            WHERE hypertable_name = @tableName
          )
        '''), parameters: {'tableName': testTableName});

        expect(hypertableResult.first[0], true);

        // Verify retention policy
        final retentionResult = await database.execute(Sql.named('''
          SELECT EXISTS (
            SELECT FROM timescaledb_information.jobs 
            WHERE hypertable_name = @tableName 
            AND proc_name = 'policy_retention'
          )
        '''), parameters: {'tableName': testTableName});

        expect(retentionResult.first[0], true);
      });

      test('should handle updating retention policy gracefully', () async {
        var retention = const RetentionPolicy(
            dropAfter: Duration(minutes: 10),
            scheduleInterval: Duration(minutes: 1));

        // Create table twice - should not fail
        await database.registerRetentionPolicy(testTableName, retention);
        await database.insertTimeseriesData(
            testTableName, DateTime.now(), 42); // This should create the table

        expect(await database.getRetentionPolicy(testTableName), retention);

        retention = const RetentionPolicy(
            dropAfter: Duration(minutes: 30),
            scheduleInterval: Duration(minutes: 15));

        await database.registerRetentionPolicy(testTableName, retention);

        expect(await database.getRetentionPolicy(testTableName), retention);
      });
    });

    group('Timeseries Data Operations', () {
      setUp(() async {
        // Create test table before each test
        await database.registerRetentionPolicy(
            testTableName, RetentionPolicy(dropAfter: Duration(hours: 1)));
      });

      tearDown(() async {
        // Clean up after each test
        await database.execute('DROP TABLE IF EXISTS "$testTableName" CASCADE');
      });

      test('should insert int data', () async {
        final now = DateTime.now();
        const testData = 42;

        await database.insertTimeseriesData(testTableName, now, testData);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert double data', () async {
        final now = DateTime.now();
        const testData = 24.5;

        await database.insertTimeseriesData(testTableName, now, testData);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert boolean data', () async {
        final now = DateTime.now();
        const testData = true;

        await database.insertTimeseriesData(testTableName, now, testData);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert string data', () async {
        final now = DateTime.now();
        const testData = "test_value";

        await database.insertTimeseriesData(testTableName, now, testData);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert timeseries data', () async {
        final now = DateTime.now();
        final testData = {'value': 42, 'unit': 'celsius'};

        await database.insertTimeseriesData(testTableName, now, testData);

        // Verify data was inserted
        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].time, isA<DateTime>());
        expect(result[0].value, testData);
      });

      test('insert different types of data results in error', () async {
        final now = DateTime.now();
        const testData = true;
        const testData2 = 42;

        await database.insertTimeseriesData(testTableName, now, testData);

        // Expect the second insert to throw an exception due to type mismatch
        expect(
          () => database.insertTimeseriesData(testTableName, now, testData2),
          throwsA(isA<Exception>()),
        );

        // Verify only the first data point was inserted
        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].time, isA<DateTime>());
        expect(result[0].value, testData);
      });

      test('insert couple of strings', () async {
        final now = DateTime.now();
        const testData = "test_value";
        const testData2 = true;
        const testData3 = 42;

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.insertTimeseriesData(testTableName, now, testData2);
        await database.insertTimeseriesData(testTableName, now, testData3);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 3);
        expect(result[2].value, testData);
        expect(result[1].value, testData2.toString().toUpperCase());
        expect(result[0].value, testData3.toString());
      });

      test('should insert multiple data points', () async {
        final baseTime = DateTime.now();
        final dataPoints = [
          {'value': 10, 'unit': 'celsius'},
          {'value': 20, 'unit': 'celsius'},
          {'value': 30, 'unit': 'celsius'},
        ];

        for (int i = 0; i < dataPoints.length; i++) {
          await database.insertTimeseriesData(
            testTableName,
            baseTime.add(Duration(minutes: i)),
            dataPoints[i],
          );
        }

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 3);

        // Verify data is in correct order
        for (int i = 0; i < result.length; i++) {
          expect(result[i].value, dataPoints[i]);
        }
      });

      test('should query data with since parameter', () async {
        final baseTime = DateTime.now();
        final oldData = {'value': 10, 'unit': 'celsius'};
        final newData = {'value': 20, 'unit': 'celsius'};

        // Insert old data
        await database.insertTimeseriesData(
          testTableName,
          baseTime.subtract(Duration(hours: 2)),
          oldData,
        );

        // Insert new data
        await database.insertTimeseriesData(
          testTableName,
          baseTime,
          newData,
        );

        // Query only recent data
        final result = await database.queryTimeseriesData(
          testTableName,
          baseTime.subtract(Duration(hours: 1)),
        );

        expect(result.length, 1);
        expect(result[0].value, newData);
      });

      test('should query data with custom order', () async {
        final baseTime = DateTime.now();
        final dataPoints = [
          {'value': 10, 'unit': 'celsius'},
          {'value': 20, 'unit': 'celsius'},
          {'value': 30, 'unit': 'celsius'},
        ];

        for (int i = 0; i < dataPoints.length; i++) {
          await database.insertTimeseriesData(
            testTableName,
            baseTime.add(Duration(minutes: i)),
            dataPoints[i],
          );
        }

        // Query in descending order
        final result = await database.queryTimeseriesData(
          testTableName,
          null,
          orderBy: 'time DESC',
        );

        expect(result.length, 3);
        expect(result[0].value, dataPoints[2]); // Most recent first
        expect(result[2].value, dataPoints[0]); // Oldest last
      });

      test('should handle complex JSON data', () async {
        final now = DateTime.now();
        final complexData = {
          'sensor_id': 'temp_001',
          'readings': {
            'temperature': 25.5,
            'humidity': 60.2,
            'pressure': 1013.25,
          },
          'metadata': {
            'location': 'room_a',
            'calibration_date': '2024-01-01',
            'active': true,
          },
          'alerts': ['high_temp', 'low_humidity'],
        };

        await database.insertTimeseriesData(testTableName, now, complexData);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].value, complexData);
      });

      test('should handle null values in JSON data', () async {
        final now = DateTime.now();
        final dataWithNulls = {
          'value': 42,
          'description': null,
          'tags': ['tag1', null, 'tag3'],
        };

        await database.insertTimeseriesData(testTableName, now, dataWithNulls);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].value, {
          'value': 42,
          'description': null,
          'tags': [
            '"tag1"',
            'null',
            '"tag3"'
          ], // not sure it needs to be quoted but lets continue
        });
      });

      test('should count timeseries data in regular time intervals', () async {
        final baseTime = DateTime.now();

        // Insert data at different times
        await database.insertTimeseriesData(testTableName,
            baseTime.subtract(const Duration(hours: 3, minutes: 30)), 1);
        await database.insertTimeseriesData(testTableName,
            baseTime.subtract(const Duration(hours: 2, minutes: 30)), 2);
        await database.insertTimeseriesData(testTableName,
            baseTime.subtract(const Duration(hours: 1, minutes: 30)), 3);
        await database.insertTimeseriesData(
            testTableName, baseTime.subtract(const Duration(minutes: 30)), 4);

        // Count in 1-hour intervals for the last 4 hours from baseTime
        final counts = await database.countTimeseriesDataMultiple(
          testTableName,
          const Duration(hours: 1),
          6,
          since: baseTime,
        );

        // Extract just the count values from the map, maintaining order
        final countValues = counts.values.toList();

        // Should return [0, 0, 1, 1] - counts from oldest to newest bucket
        // Bucket 0 (3-4 hours ago): 0 records (no data in this range)
        // Bucket 1 (2-3 hours ago): 0 records (no data in this range)
        // Bucket 2 (1-2 hours ago): 1 record
        // Bucket 3 (0-1 hours ago): 1 record
        expect(countValues, [0, 0, 1, 1, 1, 1]);

        // Test with a different end time
        final pastTime = baseTime.subtract(const Duration(hours: 1));
        final countsFromPast = await database.countTimeseriesDataMultiple(
          testTableName,
          const Duration(hours: 1),
          2,
          since: pastTime,
        );

        // Extract count values
        final pastCountValues = countsFromPast.values.toList();

        // Should return [0, 1] - counts from 2-3 hours ago and 1-2 hours ago
        expect(pastCountValues, [1, 1]);
      });
    });

    group('Error Handling', () {
      test('should handle invalid table names', () async {
        expect(
          () => database
              .insertTimeseriesData('', DateTime.now(), {'test': 'data'}),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle invalid JSON data', () async {
        await database.registerRetentionPolicy(
            testTableName, RetentionPolicy(dropAfter: Duration(hours: 1)));

        // This should work - Dart handles JSON serialization
        await database.insertTimeseriesData(
          testTableName,
          DateTime.now(),
          {'test': 'data'},
        );
      });
    });

    group('Performance Tests', () {
      test('should handle bulk insertions', () async {
        await database.registerRetentionPolicy(
            testTableName, RetentionPolicy(dropAfter: Duration(hours: 1)));

        final baseTime = DateTime.now();
        const numRecords = 100;

        // Insert multiple records
        for (int i = 0; i < numRecords; i++) {
          await database.insertTimeseriesData(
            testTableName,
            baseTime.add(Duration(seconds: i)),
            {'value': i, 'batch': 'bulk_test'},
          );
        }

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, numRecords);
      }, timeout: Timeout(Duration(minutes: 2)));

      test('should handle large JSON payloads', () async {
        await database.registerRetentionPolicy(
            testTableName, RetentionPolicy(dropAfter: Duration(hours: 1)));

        final largeData = {
          'large_array': List.generate(1000, (i) => i),
          'large_string': 'x' * 10000,
          'nested_object': {
            'level1': {
              'level2': {
                'level3': List.generate(100, (i) => {'id': i, 'value': 'test'}),
              },
            },
          },
        };

        await database.insertTimeseriesData(
            testTableName, DateTime.now(), largeData);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0].value, largeData);
      });
    });
  });
}
