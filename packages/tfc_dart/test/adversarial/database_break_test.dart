/// Adversarial tests for [Database] shutdown: what keeps running after the
/// object has been closed.
@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';

/// An AppDatabase whose inserts always fail — a database that has gone away
/// under a running station.
class FailingAppDatabase implements AppDatabase {
  int insertAttempts = 0;
  bool closed = false;

  @override
  Future<bool> tableExists(String tableName) async => true;

  @override
  Future<int> tableInsertBatch(
      String tableName, List<Map<String, dynamic>> rows) async {
    insertAttempts++;
    throw StateError('database is gone');
  }

  @override
  Stream<bool>? get connectionHealth => null;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test('close() must stop the retry-flush loop', () async {
    final backing = FailingAppDatabase();
    final db = Database(backing);

    await db.registerRetentionPolicy(
        't', const RetentionPolicy(dropAfter: Duration(days: 1)));
    await db.insertTimeseriesData('t', DateTime.now().toUtc(), 1);
    await db.flush(); // fails -> _queueForRetry -> _scheduleRetryFlush

    expect(backing.insertAttempts, greaterThan(0), reason: 'sanity');

    await db.close();
    final atClose = backing.insertAttempts;

    // The retry is a bare Future.delayed(5s) with no handle and no
    // disposed-check.
    await Future<void>.delayed(const Duration(seconds: 7));

    expect(backing.insertAttempts, atClose,
        reason: '_scheduleRetryFlush schedules an uncancellable '
            'Future.delayed(5s). It re-queues on failure and re-schedules '
            'itself, so a closed Database keeps a self-perpetuating 5-second '
            'loop alive — holding its whole retry queue — for the rest of the '
            'process. Every config reload that rebuilds the Database adds '
            'another one.');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('work queued AFTER close() must not start the loop up again', () async {
    // The other window. Cancelling the pending timer handles a loop already
    // scheduled when close() runs; it does nothing about a _queueForRetry
    // that arrives afterwards -- an in-flight flush completing, or a
    // collector still holding the Database. Without the shutdown flag that
    // path schedules a brand new immortal timer, so the leak comes straight
    // back through a door the first test does not open.
    final backing = FailingAppDatabase();
    final db = Database(backing);

    await db.registerRetentionPolicy(
        't', const RetentionPolicy(dropAfter: Duration(days: 1)));
    await db.close();

    await db.insertTimeseriesData('t', DateTime.now().toUtc(), 1);
    await db.flush();
    final atClose = backing.insertAttempts;

    await Future<void>.delayed(const Duration(seconds: 7));

    expect(backing.insertAttempts, atClose,
        reason: 'A closed Database must not schedule a retry for work that '
            'arrives after it closed.');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('close() disarms the pending retry wake-up rather than letting it '
      'fire into a shutdown check', () async {
    // The shutdown flag alone would make the loop harmless -- it wakes and
    // returns. Cancelling matters for a different reason: a pending Timer
    // keeps the event loop alive, so a spawned acquisition isolate that has
    // closed its Database still could not exit for another five seconds.
    final backing = FailingAppDatabase();
    final db = Database(backing);

    await db.registerRetentionPolicy(
        't', const RetentionPolicy(dropAfter: Duration(days: 1)));
    await db.insertTimeseriesData('t', DateTime.now().toUtc(), 1);
    await db.flush();

    expect(db.hasPendingRetryForTest, isTrue, reason: 'sanity: armed');

    await db.close();

    expect(db.hasPendingRetryForTest, isFalse,
        reason: 'A closed Database must leave no armed timer behind.');
  }, timeout: const Timeout(Duration(seconds: 40)));
}
