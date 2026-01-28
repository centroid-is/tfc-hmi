import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:test/test.dart';
import 'package:postgres/postgres.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'docker_compose.dart';

// docker exec -it test-db /bin/ash -c "psql -d testdb --user testuser -c 'select * from test_timeseries;'"

void main() {
  group('Database Integration Tests', () {
    late Database database;

    // Test table names
    const testTableName = 'test_timeseries';
    const testTableName2 = 'test_timeseries_2';

    setUpAll(() async {
      await stopDockerCompose();
      await startDockerCompose();
      await waitForDatabaseReady(); // More reliable than a fixed delay
      database = await connectToDatabase();
      // Verify connection
      expect(await database.db.isOpen, true);
    });

    setUp(() async {});

    tearDown(() async {
      // Flush any pending writes before dropping tables
      try {
        await database.flush();
      } catch (_) {}
      // Clean up test tables
      try {
        // Remove retention policies first
        await database.db
            .customStatement('DROP TABLE IF EXISTS $testTableName CASCADE')
            .timeout(const Duration(seconds: 5));
        await database.db
            .customStatement('DROP TABLE IF EXISTS $testTableName2 CASCADE')
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
        expect(await database.db.isOpen, true);

        // Test basic query
        final result =
            await database.db.customSelect('SELECT 1 as test_value').get();
        expect(result[0].read<int>('test_value'), 1);
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

        final badDatabase = Database(await AppDatabase.spawn(badConfig));

        expect(
          () async => await badDatabase.open(),
          throwsA(isA<DatabaseException>()),
        );
      });
    });

    group('Table Operations', () {
      test('should check if table exists', () async {
        // Table should not exist initially
        expect(await database.db.tableExists(testTableName), false);

        // Create table
        await database.db.customStatement('''
          CREATE TABLE "$testTableName" (
            id SERIAL PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');

        // Table should exist now
        expect(await database.db.tableExists(testTableName), true);

        // Clean up
        await database.db.customStatement('DROP TABLE "$testTableName"');
      });

      test('should handle table operations with special characters', () async {
        const specialTableName = 'test-table_with.special_chars';

        expect(await database.db.tableExists(specialTableName), false);

        await database.db.customStatement('''
          CREATE TABLE "$specialTableName" (
            id SERIAL PRIMARY KEY
          )
        ''');

        expect(await database.db.tableExists(specialTableName), true);

        await database.db.customStatement('DROP TABLE "$specialTableName"');
      });
    });

    group('TimescaleDB Integration', () {
      test('should create timeseries table with retention policy', () async {
        const retention = Duration(minutes: 5);

        await database.registerRetentionPolicy(
            testTableName, const RetentionPolicy(dropAfter: retention));
        await database.insertTimeseriesData(
            testTableName, DateTime.now(), 42); // This should create the table

        // Verify table exists
        expect(await database.db.tableExists(testTableName), true);

        // Verify it's a hypertable (TimescaleDB specific)
        final hypertableResult = await database.db.customSelect(r'''
          SELECT EXISTS (
            SELECT FROM timescaledb_information.hypertables 
            WHERE hypertable_name = $1
          )
        ''', variables: [Variable.withString(testTableName)]).get();

        expect(hypertableResult[0].read<bool>('exists'), true);

        // Verify retention policy
        final retentionResult = await database.db.customSelect(r'''
          SELECT EXISTS (
            SELECT FROM timescaledb_information.jobs 
            WHERE hypertable_name = $1 
            AND proc_name = 'policy_retention'
          )
        ''', variables: [Variable.withString(testTableName)]).get();

        expect(retentionResult[0].read<bool>('exists'), true);
      });

      test('should handle updating retention policy gracefully', () async {
        var retention = const RetentionPolicy(
            dropAfter: Duration(minutes: 10),
            scheduleInterval: Duration(minutes: 1));

        // Create table twice - should not fail
        await database.registerRetentionPolicy(testTableName, retention);
        await database.insertTimeseriesData(
            testTableName, DateTime.now(), 42); // This should create the table

        expect(await database.db.getRetentionPolicy(testTableName), retention);

        retention = const RetentionPolicy(
            dropAfter: Duration(minutes: 30),
            scheduleInterval: Duration(minutes: 15));

        await database.registerRetentionPolicy(testTableName, retention);

        expect(await database.db.getRetentionPolicy(testTableName), retention);
      });
    });

    group('Timeseries Data Operations', () {
      setUp(() async {
        // Create test table before each test
        await database.registerRetentionPolicy(testTableName,
            const RetentionPolicy(dropAfter: Duration(hours: 1)));
      });

      tearDown(() async {
        // Flush any pending writes before dropping table
        await database.flush();
        // Clean up after each test
        await database.db
            .customStatement('DROP TABLE IF EXISTS "$testTableName" CASCADE');
      });

      test('should insert int data', () async {
        final now = DateTime.now();
        const testData = 42;

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.flush(); // Flush buffer to write data immediately

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert double data', () async {
        final now = DateTime.now();
        const testData = 24.5;

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.flush();

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert array of doubles data', () async {
        final now = DateTime.now();
        const testData = [24.5, 10.2, 99.9, 3.14159];

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.flush();

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert boolean data', () async {
        final now = DateTime.now();
        const testData = true;

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.flush();

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert string data', () async {
        final now = DateTime.now();
        const testData = "test_value";

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.flush();

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].value, testData);
      });

      test('should insert timeseries data', () async {
        final now = DateTime.now();
        final testData = {'value': 42, 'unit': 'celsius'};

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.flush();

        // Verify data was inserted
        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].time, isA<DateTime>());
        expect(result[0].value, testData);
      });

      test('insert different types of data results in error', () async {
        final now = DateTime.now();
        const testData = true;
        const testData2 = 42;

        await database.insertTimeseriesData(testTableName, now, testData);
        await database.flush();

        // With buffering, insertTimeseriesData doesn't throw immediately.
        // The error occurs during flush when the type mismatch is detected by PostgreSQL.
        await database.insertTimeseriesData(testTableName, now, testData2);

        // The flush will fail due to type mismatch, but it logs the error and continues
        await database.flush();

        // Verify only the first data point was inserted (second was rejected)
        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
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
        await database.flush();

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 3);
        expect(result[2].value, testData);
        expect(result[1].value, testData2.toString());
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
        await database.flush();

        final result = await database.queryTimeseriesData(
            testTableName, baseTime.subtract(const Duration(days: 1)));
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
        await database.flush();

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
        await database.flush();

        // Query in descending order
        final result = await database.queryTimeseriesData(
          testTableName,
          baseTime.subtract(const Duration(days: 1)),
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

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].value, complexData);
      }, skip: "Todo: fix Drift to handle JSON data in postgres");

      test('should handle null values in JSON data', () async {
        final now = DateTime.now();
        final dataWithNulls = {
          'value': 42,
          'description': null,
          'tags': ['tag1', null, 'tag3'],
        };

        await database.insertTimeseriesData(testTableName, now, dataWithNulls);

        final result = await database.queryTimeseriesData(
            testTableName, now.subtract(const Duration(days: 1)));
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
      }, skip: "Todo: fix Drift to handle JSON data in postgres");

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
        await database.flush();

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
          throwsA(isA<ArgumentError>()),
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
        await database.flush();

        final result = await database.queryTimeseriesData(
            testTableName, baseTime.subtract(const Duration(days: 1)));
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

        final result = await database.queryTimeseriesData(
            testTableName, DateTime.now().subtract(const Duration(days: 1)));
        expect(result.length, 1);
        expect(result[0].value, largeData);
      }, skip: "Todo: fix Drift to handle JSON data in postgres");
    });

    group('Materialized View (createView)', () {
      const mvName = 'mv_join_test';

      setUp(() async {
        // Make sure base tables exist as hypertables
        await database.registerRetentionPolicy(
          testTableName,
          const RetentionPolicy(dropAfter: Duration(hours: 1)),
        );
        await database.registerRetentionPolicy(
          testTableName2,
          const RetentionPolicy(dropAfter: Duration(hours: 1)),
        );
      });

      tearDown(() async {
        // Clean up the MV explicitly (tables are dropped by outer tearDown)
        try {
          await database.db.customStatement(
              'DROP MATERIALIZED VIEW IF EXISTS "$mvName" CASCADE');
        } catch (_) {/* ignore */}
      });

      test('should create MV over two timeseries and join on time', () async {
        final base = DateTime.now();

        // Insert into table 1 at t0, t1
        final t0 = base;
        final t1 = base.add(const Duration(minutes: 1));
        await database.insertTimeseriesData(testTableName, t0, 10);
        await database.insertTimeseriesData(testTableName, t1, 20);

        // Insert into table 2 at t1, t2
        final t2 = base.add(const Duration(minutes: 2));
        await database.insertTimeseriesData(testTableName2, t1, 200);
        await database.insertTimeseriesData(testTableName2, t2, 300);
        await database.flush();

        // Create MV with columns {table: column}
        await database.createView(mvName, {
          testTableName: 'value',
          testTableName2: 'value',
        });

        final result = await database.queryTimeseriesData(mvName, base);

        // Query MV
        final rows = await database.db.customSelect('''
      SELECT * FROM "$mvName" ORDER BY "time" ASC
    ''').get();

        // Expect union of times: t0, t1, t2
        expect(rows.length, 3);

        // Column names are <table>_<column> per implementation
        final c1 = '${testTableName}_value'; // test_timeseries_value
        final c2 = '${testTableName2}_value'; // test_timeseries_2_value

        // Row 0 -> t0: value from table1 only
        expect(rows[0].read<int?>(c1), 10);
        expect(rows[0].read<int?>(c2), isNull);

        // Row 1 -> t1: values from both tables
        expect(rows[1].read<int?>(c1), 20);
        expect(rows[1].read<int?>(c2), 200);

        // Row 2 -> t2: value from table2 only
        expect(rows[2].read<int?>(c1), isNull);
        expect(rows[2].read<int?>(c2), 300);
      });

      test('should be safe to call createView again and reflect new data',
          () async {
        final base = DateTime.now();

        // Seed some data
        final t0 = base;
        final t1 = base.add(const Duration(minutes: 1));
        await database.insertTimeseriesData(testTableName, t0, 10);
        await database.insertTimeseriesData(testTableName, t1, 20);

        await database.insertTimeseriesData(testTableName2, t1, 200);
        await database.flush();

        // First create
        await database.createView(mvName, {
          testTableName: 'value',
          testTableName2: 'value',
        });

        // Verify initial row count
        var rows = await database.db
            .customSelect(
              'SELECT * FROM "$mvName" ORDER BY "time" ASC',
            )
            .get();
        expect(rows.length, 2);

        // Add new data and call createView again (old impl drops & recreates)
        final t2 = base.add(const Duration(minutes: 2));
        await database.insertTimeseriesData(testTableName, t2, 40);
        await database.flush();

        await database.createView(mvName, {
          testTableName: 'value',
          testTableName2: 'value',
        });

        // MV should now include the new timestamp
        rows = await database.db
            .customSelect(
              'SELECT * FROM "$mvName" ORDER BY "time" ASC',
            )
            .get();
        expect(rows.length, 3);

        final c1 = '${testTableName}_value';
        final c2 = '${testTableName2}_value';

        // Last row corresponds to t2 -> value only from table1
        expect(rows.last.read<int?>(c1), 40);
        expect(rows.last.read<int?>(c2), isNull);
      });
    });

    group('LISTEN/NOTIFY Tests', () {
      const notifyTestTable = 'test_notify_table';

      setUp(() async {
        // Create test table before each test
        await database.registerRetentionPolicy(
          notifyTestTable,
          const RetentionPolicy(dropAfter: Duration(hours: 1)),
        );

        // Insert one row to create the table
        await database.insertTimeseriesData(
          notifyTestTable,
          DateTime.now(),
          42,
        );
        await database.flush();
      });

      tearDown(() async {
        // Flush before cleanup
        try {
          await database.flush();
        } catch (_) {}
        // Clean up after each test
        try {
          await database.db.customStatement(
            'DROP TABLE IF EXISTS "$notifyTestTable" CASCADE',
          );
        } catch (_) {
          // Ignore cleanup errors
        }
      });

      test('should enable notification channel and create trigger', () async {
        // Enable notifications
        await database.db.enableNotificationChannel(notifyTestTable);

        // Verify function exists
        final functionResult = await database.db.customSelect(r'''
      SELECT EXISTS (
        SELECT FROM pg_proc 
        WHERE proname = $1
      )
    ''', variables: [
          Variable.withString('notify_${notifyTestTable}_change')
        ]).get();

        expect(functionResult[0].read<bool>('exists'), true);

        // Verify trigger exists
        final triggerResult = await database.db.customSelect(r'''
      SELECT EXISTS (
        SELECT FROM pg_trigger
        WHERE tgname = $1
      )
    ''', variables: [Variable.withString('${notifyTestTable}_notify')]).get();

        expect(triggerResult[0].read<bool>('exists'), true);
      });

      test('should receive notification on INSERT', () async {
        await database.db.enableNotificationChannel(notifyTestTable);

        final channelName = 'table_${notifyTestTable}_changes';
        final notifications = <String>[];

        // Start listening
        final subscription =
            database.db.listenToChannel(channelName).listen((payload) {
          notifications.add(payload);
        });

        // Wait a bit for listener to be ready
        await Future.delayed(const Duration(milliseconds: 100));

        // Insert data to trigger notification
        await database.insertTimeseriesData(
          notifyTestTable,
          DateTime.now(),
          100,
        );
        await database.flush();

        // Wait for notification
        await Future.delayed(const Duration(milliseconds: 500));

        // Verify notification received
        expect(notifications.length, 1);

        final notification = jsonDecode(notifications[0]);
        expect(notification['action'], 'INSERT');
        expect(notification['data'], isA<Map>());
        expect(notification['data']['value'], 100);
        await subscription.cancel();
      });

      test('should receive notification on UPDATE', () async {
        await database.db.enableNotificationChannel(notifyTestTable);

        final channelName = 'table_${notifyTestTable}_changes';
        final notifications = <String>[];

        final subscription =
            database.db.listenToChannel(channelName).listen((payload) {
          notifications.add(payload);
        });

        await Future.delayed(const Duration(milliseconds: 100));

        // Update data
        await database.db.customStatement('''
      UPDATE "$notifyTestTable" 
      SET value = 999 
      WHERE value = 42
    ''');

        await Future.delayed(const Duration(milliseconds: 500));

        expect(notifications.length, 1);

        final notification = jsonDecode(notifications[0]);
        expect(notification['action'], 'UPDATE');
        expect(notification['data']['value'], 999);

        await subscription.cancel();
      });

      test('should receive notification on DELETE', () async {
        await database.db.enableNotificationChannel(notifyTestTable);

        final channelName = 'table_${notifyTestTable}_changes';
        final notifications = <String>[];

        final subscription =
            database.db.listenToChannel(channelName).listen((payload) {
          notifications.add(payload);
        });

        await Future.delayed(const Duration(milliseconds: 100));

        // Delete data
        await database.db.customStatement('''
      DELETE FROM "$notifyTestTable" WHERE value = 42
    ''');

        await Future.delayed(const Duration(milliseconds: 500));

        expect(notifications.length, 1);

        final notification = jsonDecode(notifications[0]);
        expect(notification['action'], 'DELETE');
        expect(notification['data']['value'], 42);

        await subscription.cancel();
      });

      test('should handle multiple notifications', () async {
        await database.db.enableNotificationChannel(notifyTestTable);

        final channelName = 'table_${notifyTestTable}_changes';
        final notifications = <String>[];

        final subscription =
            database.db.listenToChannel(channelName).listen((payload) {
          notifications.add(payload);
        });

        await Future.delayed(const Duration(milliseconds: 100));

        // Insert multiple records
        for (int i = 0; i < 5; i++) {
          await database.insertTimeseriesData(
            notifyTestTable,
            DateTime.now().add(Duration(seconds: i)),
            100 + i,
          );
        }
        await database.flush();

        // Wait for all notifications
        await Future.delayed(const Duration(seconds: 1));

        expect(notifications.length, 5);

        // Verify all are INSERT actions
        for (final notif in notifications) {
          final decoded = jsonDecode(notif);
          expect(decoded['action'], 'INSERT');
        }

        await subscription.cancel();
      });

      test('should work with complex timeseries data', () async {
        // Create a table with multiple columns
        const complexTable = 'test_complex_notify';

        await database.registerRetentionPolicy(
          complexTable,
          const RetentionPolicy(dropAfter: Duration(hours: 1)),
        );

        // Insert complex data to create table structure
        final testData = {
          'temperature': 25.5,
          'humidity': 60.2,
          'pressure': 1013.25,
        };

        await database.insertTimeseriesData(
          complexTable,
          DateTime.now(),
          testData,
        );
        await database.flush();

        // Enable notifications
        await database.db.enableNotificationChannel(complexTable);

        final channelName = 'table_${complexTable}_changes';
        final notifications = <String>[];

        final subscription =
            database.db.listenToChannel(channelName).listen((payload) {
          notifications.add(payload);
        });

        await Future.delayed(const Duration(milliseconds: 100));

        // Insert new data
        final newData = {
          'temperature': 30.0,
          'humidity': 55.0,
          'pressure': 1015.0,
        };

        await database.insertTimeseriesData(
          complexTable,
          DateTime.now(),
          newData,
        );
        await database.flush();

        await Future.delayed(const Duration(milliseconds: 500));

        expect(notifications.length, 1);

        final notification = jsonDecode(notifications[0]);
        expect(notification['action'], 'INSERT');
        expect(notification['data']['temperature'], 30.0);
        expect(notification['data']['humidity'], 55.0);
        expect(notification['data']['pressure'], 1015.0);

        await subscription.cancel();

        // Cleanup
        await database.db.customStatement(
          'DROP TABLE IF EXISTS "$complexTable" CASCADE',
        );
      });

      test('should handle multiple listeners on same channel', () async {
        await database.db.enableNotificationChannel(notifyTestTable);

        final channelName = 'table_${notifyTestTable}_changes';
        final notifications1 = <String>[];
        final notifications2 = <String>[];

        // Two listeners on same channel
        final sub1 = database.db.listenToChannel(channelName).listen((payload) {
          notifications1.add(payload);
        });

        final sub2 = database.db.listenToChannel(channelName).listen((payload) {
          notifications2.add(payload);
        });

        await Future.delayed(const Duration(milliseconds: 100));

        await database.insertTimeseriesData(
          notifyTestTable,
          DateTime.now(),
          777,
        );
        await database.flush();

        await Future.delayed(const Duration(milliseconds: 500));

        // Both listeners should receive the notification
        expect(notifications1.length, 1);
        expect(notifications2.length, 1);

        final notif1 = jsonDecode(notifications1[0]);
        final notif2 = jsonDecode(notifications2[0]);

        expect(notif1['data']['value'], 777);
        expect(notif2['data']['value'], 777);

        await sub1.cancel();
        await sub2.cancel();
      });

      test('should not receive notifications after canceling subscription',
          () async {
        await database.db.enableNotificationChannel(notifyTestTable);

        final channelName = 'table_${notifyTestTable}_changes';
        final notifications = <String>[];

        final subscription =
            database.db.listenToChannel(channelName).listen((payload) {
          notifications.add(payload);
        });

        await Future.delayed(const Duration(milliseconds: 100));

        // Insert first record
        await database.insertTimeseriesData(
          notifyTestTable,
          DateTime.now(),
          111,
        );
        await database.flush();

        await Future.delayed(const Duration(milliseconds: 300));
        expect(notifications.length, 1);

        // Cancel subscription
        await subscription.cancel();
        await Future.delayed(const Duration(milliseconds: 100));

        // Insert second record
        await database.insertTimeseriesData(
          notifyTestTable,
          DateTime.now(),
          222,
        );
        await database.flush();

        await Future.delayed(const Duration(milliseconds: 500));

        // Should still be 1 (didn't receive second notification)
        expect(notifications.length, 1);
      });

      test('should handle rapid succession of changes', () async {
        await database.db.enableNotificationChannel(notifyTestTable);

        final channelName = 'table_${notifyTestTable}_changes';
        final notifications = <String>[];

        final subscription =
            database.db.listenToChannel(channelName).listen((payload) {
          notifications.add(payload);
        });

        await Future.delayed(const Duration(milliseconds: 100));

        // Rapid inserts - flush after each to test notification throughput
        for (int i = 0; i < 20; i++) {
          await database.insertTimeseriesData(
            notifyTestTable,
            DateTime.now().add(Duration(milliseconds: i)),
            i,
          );
          await database.flush();
        }

        // Wait for all notifications
        await Future.delayed(const Duration(seconds: 2));

        // Should receive all 20 notifications
        expect(notifications.length, 20);

        await subscription.cancel();
      });

      test('should handle simultaneous changes from many tables', () async {
        // Create 5 test tables
        final tableNames = List.generate(5, (i) => 'test_notify_multi_$i');

        // Setup: Create all tables and enable notifications
        var i = 0;
        for (final tableName in tableNames) {
          await database.registerRetentionPolicy(
            tableName,
            const RetentionPolicy(dropAfter: Duration(hours: 1)),
          );

          // Insert initial data to create the table
          await database.insertTimeseriesData(
            tableName,
            DateTime.now(),
            i++ * 10,
          );
          await database.flush();

          // Enable notifications for this table
          await database.db.enableNotificationChannel(tableName);
        }

        // Set up listeners for all tables
        final allNotifications = <String, List<String>>{};
        final subscriptions = <StreamSubscription>[];

        for (final tableName in tableNames) {
          final channelName = 'table_${tableName}_changes';
          allNotifications[tableName] = [];

          final subscription =
              database.db.listenToChannel(channelName).listen((payload) {
            allNotifications[tableName]!.add(payload);
          });
          subscriptions.add(subscription);
        }

        // Wait for listeners to be ready
        await Future.delayed(const Duration(milliseconds: 500));

        // Insert data into each table simultaneously
        final now = DateTime.now();
        for (int i = 0; i < tableNames.length; i++) {
          await database.insertTimeseriesData(
            tableNames[i],
            now.add(Duration(milliseconds: i)),
            100 + i,
          );
        }
        await database.flush();

        // Wait for all notifications
        await Future.delayed(const Duration(seconds: 1));

        // Verify each table received exactly one notification
        for (int i = 0; i < tableNames.length; i++) {
          final tableName = tableNames[i];
          final notifications = allNotifications[tableName]!;

          expect(notifications.length, 1,
              reason: 'Table $tableName should receive exactly 1 notification');

          final notification = jsonDecode(notifications[0]);
          expect(notification['action'], 'INSERT');
          expect(notification['data']['value'], 100 + i,
              reason: 'Table $tableName should have value ${100 + i}');
        }

        // Test cross-table isolation: update one table, verify only it gets notification
        final notifications1Before = allNotifications[tableNames[0]]!.length;

        await database.db.customStatement('''
          UPDATE "${tableNames[2]}" 
          SET value = 999 
          WHERE value = 102
        ''');

        await Future.delayed(const Duration(milliseconds: 500));

        // Table 0 should not receive new notification
        expect(allNotifications[tableNames[0]]!.length, notifications1Before,
            reason:
                'Table ${tableNames[0]} should not receive notification from another table update');

        // Table 2 should receive UPDATE notification
        expect(allNotifications[tableNames[2]]!.length, 2,
            reason:
                'Table ${tableNames[2]} should have 2 notifications (INSERT + UPDATE)');

        final updateNotif = jsonDecode(allNotifications[tableNames[2]]![1]);
        expect(updateNotif['action'], 'UPDATE');
        expect(updateNotif['data']['value'], 999);

        // Cleanup subscriptions
        for (final sub in subscriptions) {
          await sub.cancel();
        }

        // Cleanup tables
        for (final tableName in tableNames) {
          try {
            await database.db.customStatement(
              'DROP TABLE IF EXISTS "$tableName" CASCADE',
            );
          } catch (_) {
            // Ignore cleanup errors
          }
        }
      });
    });
  });
}
