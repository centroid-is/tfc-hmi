import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:tfc/core/database.dart';

void main() {
  group('Database Integration Tests', () {
    late Database database;
    late DatabaseConfig config;

    // Test table names
    const testTableName = 'test_timeseries';
    const testTableName2 = 'test_timeseries_2';
    const databaseName = 'testdb';

    setUpAll(() async {
      // Configure database connection for integration tests
      config = DatabaseConfig(
        postgres: Endpoint(
          host: 'localhost', // Docker container host
          port: 5432,
          database: databaseName,
          username: 'testuser',
          password: 'testpass',
        ),
        sslMode: SslMode.disable,
      );

      database = Database(config);

      // Connect to database
      await database.connect();

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

        await database.createTimeseriesTable(testTableName, retention);

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

      test('should handle existing table gracefully', () async {
        var retention = const Duration(minutes: 10);

        // Create table twice - should not fail
        await database.createTimeseriesTable(testTableName2, retention);

        expect(await database.getRetentionDuration(testTableName2), retention);

        retention = const Duration(minutes: 30);

        await database.createTimeseriesTable(testTableName2, retention);

        expect(await database.getRetentionDuration(testTableName2), retention);
      });
    });

    group('Timeseries Data Operations', () {
      setUp(() async {
        // Create test table before each test
        await database.createTimeseriesTable(testTableName, Duration(hours: 1));
      });

      tearDown(() async {
        // Clean up after each test
        await database.execute('DROP TABLE IF EXISTS "$testTableName" CASCADE');
      });

      test('should insert trivial data', () async {
        final now = DateTime.now();
        const testData = 42;

        await database.insertTimeseriesData(testTableName, now, testData);

        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0][1], testData);
      });

      test('should insert timeseries data', () async {
        final now = DateTime.now();
        final testData = {'value': 42, 'unit': 'celsius'};

        await database.insertTimeseriesData(testTableName, now, testData);

        // Verify data was inserted
        final result = await database.queryTimeseriesData(testTableName, null);
        expect(result.length, 1);
        expect(result[0][0], isA<DateTime>());
        expect(result[0][1], testData);
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
          expect(result[i][1], dataPoints[i]);
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
        expect(result[0][1], newData);
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
        expect(result[0][1], dataPoints[2]); // Most recent first
        expect(result[2][1], dataPoints[0]); // Oldest last
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
        expect(result[0][1], complexData);
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
        expect(result[0][1], dataWithNulls);
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
        await database.createTimeseriesTable(testTableName, Duration(hours: 1));

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
        await database.createTimeseriesTable(testTableName, Duration(hours: 1));

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
        await database.createTimeseriesTable(testTableName, Duration(hours: 1));

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
        expect(result[0][1], largeData);
      });
    });
  });
}
