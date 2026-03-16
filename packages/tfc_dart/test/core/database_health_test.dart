import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// Tests for Database.connectionState behavior when the underlying health
/// stream closes or errors (e.g., Drift isolate crash).
///
/// The bug: when the health stream goes silent (isolate dies), the cached
/// `_lastConnectionState` stays `true`, so `connectionState` keeps serving
/// stale "connected" to new listeners. The fix adds onDone/onError handlers
/// and a heartbeat timeout.
void main() {
  group('Database connectionState on health stream close', () {
    late AppDatabase appDb;
    late StreamController<bool> healthController;
    late Database database;

    setUp(() {
      appDb = AppDatabase.inMemoryForTest();
      healthController = StreamController<bool>.broadcast();
      appDb.connectionHealthBroadcastForTest = healthController.stream;
    });

    tearDown(() async {
      await database.dispose();
      await healthController.close();
      await appDb.close();
    });

    test(
        'connectionState emits false when health stream closes without final event',
        () async {
      database = Database(appDb);

      // Simulate: health stream sends true (connected), then closes (isolate died)
      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Close the health stream without sending false — simulates isolate crash
      await healthController.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Collect the last event from connectionState
      final lastEvent = await database.connectionState.first;
      expect(lastEvent, isFalse,
          reason:
              'After health stream closes, connectionState should emit false');
    });

    test('connectionState emits false when health subscription errors',
        () async {
      database = Database(appDb);

      // Simulate: health stream sends true, then errors out
      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      healthController.addError(StateError('Isolate crashed'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The last emitted state should be false
      final lastEvent = await database.connectionState.first;
      expect(lastEvent, isFalse,
          reason:
              'After health stream errors, connectionState should emit false');
    });

    test('new listeners get false after health stream has closed', () async {
      database = Database(appDb);

      // Simulate: connected, then isolate dies
      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await healthController.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // A NEW listener subscribing AFTER the health stream closed should get false
      final newListenerEvent = await database.connectionState.first;
      expect(newListenerEvent, isFalse,
          reason:
              'New listener after health stream close should get false, not stale true');
    });

    test('connectionState emits true then false on close', () async {
      database = Database(appDb);

      final events = <bool>[];
      final sub = database.connectionState.listen(events.add);

      // Wait for any initial cached event
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Health says connected
      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Health stream closes (isolate crash)
      await healthController.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      // Must see connected true followed by disconnected false (from onDone).
      // The initial false may or may not appear depending on timing.
      expect(events, containsAllInOrder([true, false]),
          reason:
              'Should see connected true, then disconnected false');
    });
  });

  group('Database connectionState heartbeat timeout', () {
    late AppDatabase appDb;
    late StreamController<bool> healthController;
    late Database database;

    setUp(() {
      appDb = AppDatabase.inMemoryForTest();
      healthController = StreamController<bool>.broadcast();
      appDb.connectionHealthBroadcastForTest = healthController.stream;
    });

    tearDown(() async {
      await database.dispose();
      await healthController.close();
      await appDb.close();
    });

    test('emits false after heartbeat timeout with no events', () async {
      // Use a short timeout for testing
      database = Database(appDb, healthTimeout: const Duration(seconds: 1));

      final events = <bool>[];
      final sub = database.connectionState.listen(events.add);

      // Send initial connected event
      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now go silent — no more health events
      // Wait for the timeout to fire
      await Future<void>.delayed(const Duration(seconds: 2));

      await sub.cancel();

      // Should have: initial false, true (from health), false (from timeout)
      expect(events.last, isFalse,
          reason: 'After heartbeat timeout, should emit false');
    });

    test('heartbeat timeout resets on each health event', () async {
      database = Database(appDb, healthTimeout: const Duration(seconds: 1));

      final events = <bool>[];
      final sub = database.connectionState.listen(events.add);

      // Send events at 0ms, 500ms, 1000ms — each resets the 1s timeout
      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      healthController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Only 500ms since last event — timeout should NOT have fired yet
      expect(events.where((e) => e == false).length, lessThanOrEqualTo(1),
          reason:
              'Timeout should not fire while events keep arriving within window');

      // Now wait for timeout
      await Future<void>.delayed(const Duration(seconds: 2));

      await sub.cancel();

      expect(events.last, isFalse,
          reason: 'After going silent, timeout should fire and emit false');
    });
  });
}
