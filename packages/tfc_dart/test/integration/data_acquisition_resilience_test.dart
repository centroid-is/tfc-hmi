// TDD Tests for Data Acquisition Resilience (Issue #60)
//
// These tests verify that the data acquisition system properly handles:
// 1. Database unavailability at startup
// 2. Database going down during operation
// 3. Isolate crashes and respawn
// 4. Data queuing during outages
//
// Run with: dart test test/integration/data_acquisition_resilience_test.dart

@Tags(['docker'])
library;

import 'dart:async';
import 'dart:isolate';

import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/state_man.dart';

import 'docker_compose.dart';

void main() {
  final testDb = TestDb(
    composeFile: 'docker-compose.resilience.yml',
    containerName: 'test-db-resilience',
    port: 5442,
  );

  group('Data Acquisition Resilience', () {
    setUpAll(() async {
      await testDb.start();
      await testDb.waitForReady();
    });

    tearDownAll(() async {
      await testDb.stop();
    });

    group('Database retry queue', () {
      late Database database;

      setUp(() async {
        database = await testDb.connect();
      });
      tearDown(() async {
        await database.dispose();
        await database.close();
      });
      test(
          'WHEN database is down THEN inserts are queued and flushed on recovery',
          () async {
        // Arrange
        const tableName = 'resilience_test_1';
        final stateMan = await StateMan.create(
          config: StateManConfig(opcua: []),
          keyMappings: KeyMappings(nodes: {}),
        );
        final collector = Collector(
          config: CollectorConfig(collect: true),
          stateMan: stateMan,
          database: database,
        );

        final streamController = StreamController<DynamicValue>();
        final entry = CollectEntry(key: tableName, name: tableName);

        // Start collecting
        await collector.collectEntryImpl(entry, streamController.stream,
            skipFirstSample: false);

        // Insert one value while DB is up (creates table)
        streamController.add(DynamicValue(value: 'before'));
        await Future.delayed(const Duration(milliseconds: 200));
        await database.flush();

        // Verify initial insert
        var data = await _queryTable(database, tableName);
        expect(data.length, 1);

        // Stop database
        await testDb.stopContainer();
        await Future.delayed(const Duration(seconds: 1));

        // Insert values during outage - should be queued
        for (var i = 0; i < 5; i++) {
          streamController.add(DynamicValue(value: 'during_$i'));
          await Future.delayed(const Duration(milliseconds: 50));
        }

        // Restart database
        await testDb.startContainer();
        await testDb.waitForReady();

        // Wait for retry queue to flush
        await Future.delayed(const Duration(seconds: 8));
        await database.flush();

        // Verify all data was inserted
        data = await _queryTable(database, tableName);
        expect(data.length, 6, reason: 'Should have 1 + 5 items');

        // Cleanup
        streamController.close();
        collector.close();

        // Ensure DB is back up for next test
        await testDb.startContainer();
        await testDb.waitForReady();
      }, timeout: Timeout(Duration(seconds: 60)));

      test('WHEN queue overflows THEN oldest items are dropped, newest kept',
          () async {
        // Arrange
        const tableName = 'resilience_test_2';
        final stateMan = await StateMan.create(
          config: StateManConfig(opcua: []),
          keyMappings: KeyMappings(nodes: {}),
        );
        final collector = Collector(
          config: CollectorConfig(collect: true),
          stateMan: stateMan,
          database: database,
        );

        final streamController = StreamController<DynamicValue>();
        final entry = CollectEntry(key: tableName, name: tableName);

        await collector.collectEntryImpl(entry, streamController.stream,
            skipFirstSample: false);

        // Create table while DB is up
        streamController.add(DynamicValue(value: 'init'));
        await Future.delayed(const Duration(milliseconds: 200));
        await database.flush();

        // Stop database
        await testDb.stopContainer();
        await Future.delayed(const Duration(seconds: 1));

        // Insert MORE than queue capacity (100)
        const totalItems = 120;
        for (var i = 0; i < totalItems; i++) {
          streamController.add(DynamicValue(value: 'item_$i'));
          await Future.delayed(const Duration(milliseconds: 10));
        }

        // Restart database
        await testDb.startContainer();
        await testDb.waitForReady();

        // Wait for retry queue to flush
        await Future.delayed(const Duration(seconds: 8));
        await database.flush();

        // Verify: init + 100 newest items (oldest 20 dropped)
        final data = await _queryTable(database, tableName);
        expect(data.length, 101);

        // Verify oldest were dropped (item_0 to item_19 should NOT be present)
        final values = data.map((d) => d.value as String).toSet();
        for (var i = 0; i < 20; i++) {
          expect(values.contains('item_$i'), isFalse,
              reason: 'item_$i should have been dropped');
        }

        // Verify newest are present (item_20 to item_119)
        for (var i = 20; i < 120; i++) {
          expect(values.contains('item_$i'), isTrue,
              reason: 'item_$i should be in database');
        }

        // Cleanup
        streamController.close();
        collector.close();

        // Ensure DB is back up for next test
        await testDb.startContainer();
        await testDb.waitForReady();
      }, timeout: Timeout(Duration(seconds: 60)));
    });

    group('Isolate startup retry', () {
      test('WHEN DB is down at startup THEN isolate retries until DB is up',
          () async {
        // Stop DB and wait for all connections to be truly dead
        await testDb.stopContainer();
        await Future.delayed(const Duration(seconds: 3));

        final messagePort = ReceivePort();
        final timestamps = <String>[];

        messagePort.listen((msg) {
          if (msg == 'initialized') {
            timestamps.add(DateTime.now().toIso8601String());
          }
        });

        // Spawn isolate - it should retry connecting to DB
        final errorPort = ReceivePort();
        final exitPort = ReceivePort();

        await Isolate.spawn(
          _isolateWithDbRetry,
          _IsolateConfig(
            dbConfigJson: testDb.config().toJson(),
            sendPort: messagePort.sendPort,
          ),
          onError: errorPort.sendPort,
          onExit: exitPort.sendPort,
        );

        // Wait 2 seconds - isolate should NOT have connected yet (retry delay is 2s)
        await Future.delayed(const Duration(seconds: 2));
        final beforeDbStart = timestamps.length;

        // Start DB
        await testDb.startContainer();
        await testDb.waitForReady();

        // Wait for isolate to connect
        await Future.delayed(const Duration(seconds: 8));
        final afterDbStart = timestamps.length;

        // Isolate should have connected AFTER we started the DB
        expect(afterDbStart, greaterThan(beforeDbStart),
            reason: 'Isolate should connect after DB starts');

        // Cleanup
        messagePort.close();
        errorPort.close();
        exitPort.close();
      }, timeout: Timeout(Duration(seconds: 60)));
    });

    group('Database edge cases', () {
      late Database database;

      setUp(() async {
        database = await testDb.connect();
      });
      tearDown(() async {
        try {
          await database.dispose();
          await database.close();
        } catch (_) {
          // Database may already be disposed/closed by the test
        }
      });

      test('WHEN dispose is called THEN pending data is flushed', () async {
        const tableName = 'dispose_flush_test';
        final stateMan = await StateMan.create(
          config: StateManConfig(opcua: []),
          keyMappings: KeyMappings(nodes: {}),
        );
        final collector = Collector(
          config: CollectorConfig(collect: true),
          stateMan: stateMan,
          database: database,
        );

        final streamController = StreamController<DynamicValue>();
        final entry = CollectEntry(key: tableName, name: tableName);

        await collector.collectEntryImpl(entry, streamController.stream,
            skipFirstSample: false);

        // Insert values (will be buffered, not flushed yet)
        for (var i = 0; i < 3; i++) {
          streamController.add(DynamicValue(value: 'item_$i'));
          await Future.delayed(const Duration(milliseconds: 50));
        }

        // Don't call flush - just dispose
        await database.dispose();

        // Reconnect and verify data was flushed
        final db2 = await testDb.connect();
        final data = await _queryTable(db2, tableName);
        expect(data.length, 3, reason: 'dispose() should flush pending data');

        streamController.close();
        collector.close();
      }, timeout: Timeout(Duration(seconds: 30)));

      test('WHEN DB is down THEN registerRetentionPolicy does not throw',
          () async {
        await testDb.stopContainer();
        await Future.delayed(const Duration(seconds: 2));

        // This should NOT throw
        await database.registerRetentionPolicy(
          'nonexistent_table',
          const RetentionPolicy(
              dropAfter: Duration(days: 30), scheduleInterval: null),
        );

        // Restart DB for next tests
        await testDb.startContainer();
        await testDb.waitForReady();
      }, timeout: Timeout(Duration(seconds: 30)));

      test(
          'WHEN retention policy registered during outage THEN applied when table created',
          () async {
        const tableName = 'retention_recovery_test';

        // Stop DB
        await testDb.stopContainer();
        await Future.delayed(const Duration(seconds: 2));

        // Register retention policy while DB is down (should not throw)
        await database.registerRetentionPolicy(
          tableName,
          const RetentionPolicy(
              dropAfter: Duration(days: 7), scheduleInterval: null),
        );

        // Start DB
        await testDb.startContainer();
        await testDb.waitForReady();

        // Insert data - this should create table WITH the retention policy
        await database.insertTimeseriesData(
            tableName, DateTime.now().toUtc(), 'test_value');
        await database.flush();

        // Verify table was created
        final data = await _queryTable(database, tableName);
        expect(data.length, 1, reason: 'Table should be created with data');
      }, timeout: Timeout(Duration(seconds: 30)));
    });

    group('Isolate respawn on crash', () {
      test('WHEN isolate crashes THEN it is respawned automatically', () async {
        // Ensure DB is up for this test
        await testDb.startContainer();
        await testDb.waitForReady();
        var spawnCount = 0;
        final spawnPort = ReceivePort();

        spawnPort.listen((msg) {
          if (msg == 'spawned') spawnCount++;
        });

        // Spawn with respawn wrapper
        _spawnWithRespawn(
          dbConfigJson: testDb.config().toJson(),
          spawnPort: spawnPort.sendPort,
          shouldCrash: true,
        );

        // Wait for crash + respawn cycle
        await Future.delayed(const Duration(seconds: 10));

        expect(spawnCount, greaterThanOrEqualTo(2),
            reason: 'Should have respawned after crash');

        spawnPort.close();
      }, timeout: Timeout(Duration(seconds: 30)));
    });

  });
}

Future<List<TimeseriesData<dynamic>>> _queryTable(
    Database db, String tableName) async {
  try {
    return await db.queryTimeseriesData(
        tableName, DateTime.now().subtract(const Duration(hours: 1)));
  } catch (e) {
    return [];
  }
}


class _IsolateConfig {
  final Map<String, dynamic> dbConfigJson;
  final SendPort sendPort;
  final bool shouldCrash;

  _IsolateConfig({
    required this.dbConfigJson,
    required this.sendPort,
    this.shouldCrash = false,
  });
}

@pragma('vm:entry-point')
Future<void> _isolateWithDbRetry(_IsolateConfig config) async {
  final dbConfig = DatabaseConfig.fromJson(config.dbConfigJson);

  var delay = const Duration(seconds: 2);
  const maxDelay = Duration(seconds: 30);
  const maxAttempts = 15;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final appDb = await AppDatabase.create(dbConfig);
      // Force actual connection by running a query
      await appDb.tableExists('_connection_test');

      // ignore: unused_local_variable
      final db = Database(appDb);
      config.sendPort.send('initialized');

      // Crash OUTSIDE try-catch to actually terminate the isolate
      if (config.shouldCrash) {
        await Future.delayed(const Duration(milliseconds: 100));
        break; // Exit loop, crash below
      }

      await Completer<void>().future;
      return;
    } catch (e) {
      if (attempt == maxAttempts) rethrow;
      await Future.delayed(delay);
      delay = delay * 2;
      if (delay > maxDelay) delay = maxDelay;
    }
  }

  // Intentional crash outside try-catch
  if (config.shouldCrash) {
    throw Exception('Intentional crash for testing respawn');
  }
}

Future<void> _spawnWithRespawn({
  required Map<String, dynamic> dbConfigJson,
  required SendPort spawnPort,
  bool shouldCrash = false,
}) async {
  var restartDelay = const Duration(seconds: 2);
  const maxDelay = Duration(seconds: 30);

  Future<void> spawn() async {
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    void scheduleRespawn() {
      errorPort.close();
      exitPort.close();
      Future.delayed(restartDelay, () {
        restartDelay = restartDelay * 2;
        if (restartDelay > maxDelay) restartDelay = maxDelay;
        spawn();
      });
    }

    errorPort.listen((_) => scheduleRespawn());
    exitPort.listen((_) => scheduleRespawn());

    spawnPort.send('spawned');

    await Isolate.spawn(
      _isolateWithDbRetry,
      _IsolateConfig(
        dbConfigJson: dbConfigJson,
        sendPort: ReceivePort().sendPort,
        shouldCrash: shouldCrash,
      ),
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
    );

    restartDelay = const Duration(seconds: 2);
  }

  await spawn();
}
