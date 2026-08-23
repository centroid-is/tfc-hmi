import 'package:logger/logger.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/database.dart';

import 'fake_write_backend.dart';

/// A Dart `int` is 64-bit. It used to be given a 32-bit column.
///
/// The consequence was not "some values are wrong", it was "this tag stops
/// recording, permanently". A UDINT/DWORD/ULINT counter, or an OPC UA
/// UInt32/UInt64, crosses 2^31 and every insert for it fails
/// `22003: integer out of range`. Counters do not come back down, so every
/// batch from then on fails too — and because the whole multi-row INSERT is
/// rejected, the well-behaved rows batched alongside die with it.
///
/// The second half of the defect was that 22003 was classified as neither
/// permanent nor connection-related, so the batch went round the five-second
/// retry loop forever, re-queueing itself, silently, until it aged out at the
/// queue cap.
void main() {
  Logger.level = Level.off;

  group('column width', () {
    test('an int gets a 64-bit column', () {
      expect(Database.postgresTypeFor(1), 'BIGINT',
          reason: 'INTEGER is int4. Every Dart int is int8.');
    });

    test('a value past 2^31 is not narrowed', () {
      expect(Database.postgresTypeFor(2147483648), 'BIGINT');
      expect(Database.postgresTypeFor(-2147483649), 'BIGINT');
    });

    test('a list of ints gets a 64-bit array column', () {
      expect(Database.postgresTypeFor(<int>[1, 2]), 'BIGINT[]');
    });

    test('the other types are untouched', () {
      expect(Database.postgresTypeFor(1.5), 'DOUBLE PRECISION');
      expect(Database.postgresTypeFor(true), 'BOOLEAN');
      expect(Database.postgresTypeFor('x'), 'TEXT');
      expect(Database.postgresTypeFor(Duration.zero), 'INTERVAL');
      expect(Database.postgresTypeFor(DateTime(2026)), 'TIMESTAMPTZ');
      expect(Database.postgresTypeFor(<double>[1.5]), 'DOUBLE PRECISION[]');
    });
  });

  group('classifying 22003', () {
    // The isolate-mode form: Drift wraps pg.ServerException in a
    // DriftRemoteException whose toString still carries the SQLSTATE.
    Object drift(String code, String msg) =>
        Exception('Severity.error $code: $msg');

    test('a data exception is recognised', () {
      expect(
          Database.isDataErrorForTest(
              drift('22003', 'integer out of range')),
          isTrue);
    });

    test('the rest of class 22 is recognised too', () {
      // All of class 22 is a complaint about the values, not the server.
      expect(
          Database.isDataErrorForTest(
              drift('22P02', 'invalid input syntax for type integer')),
          isTrue);
      expect(
          Database.isDataErrorForTest(
              drift('22001', 'value too long for type character varying')),
          isTrue);
    });

    test('a schema error is NOT a data error', () {
      // 42703 has its own recovery (add the column); it must not be diverted
      // into the drop path.
      expect(
          Database.isDataErrorForTest(
              drift('42703', 'column "x" does not exist')),
          isFalse);
    });

    test('an outage is NOT a data error', () {
      expect(
          Database.isDataErrorForTest(
              drift('08006', 'connection failure')),
          isFalse);
      expect(
          Database.isDataErrorForTest(
              Exception('SocketException: Connection refused')),
          isFalse);
    });

    test('a data exception is also permanent, so _withRetry does not spin', () {
      expect(
          Database.isPermanentDbErrorForTest(
              drift('22003', 'integer out of range')),
          isTrue);
    });

    test('the classes that were already permanent still are', () {
      expect(
          Database.isPermanentDbErrorForTest(
              drift('42703', 'column "x" does not exist')),
          isTrue);
      expect(
          Database.isPermanentDbErrorForTest(drift('23505', 'duplicate key')),
          isTrue);
      expect(
          Database.isPermanentDbErrorForTest(drift('08006', 'connection failure')),
          isFalse);
    });
  });

  group('a poisoned batch, end to end', () {
    late FakeWriteBackend backend;
    late Database db;

    setUp(() {
      backend = FakeWriteBackend();
      db = Database(backend);
    });

    tearDown(() => db.close());

    test('is dropped once and counted, not retried forever', () async {
      backend.rejectWith =
          Exception('Severity.error 22003: integer out of range');

      await db.insertTimeseriesData('counter', DateTime.utc(2026), 42);
      await db.flush();

      final attemptsRightAfter = backend.insertAttempts;
      expect(attemptsRightAfter, 1);

      // The retry loop woke up every five seconds and re-sent the identical
      // batch. Waiting well past two of those wake-ups is what proves it no
      // longer does.
      await Future<void>.delayed(const Duration(seconds: 12));
      expect(backend.insertAttempts, attemptsRightAfter,
          reason: 'A batch the server rejects on its contents must not be '
              're-sent. Every extra attempt here was a five-second heartbeat '
              'that ran for the life of the process.');

      expect(db.getStats()['poisoned_rows'], 1);
      expect(db.getStats()['poisoned_rows_by_table'], {'counter': 1});
      expect(db.queuedRowCount, 0,
          reason: 'It must not be sitting in the retry queue either, where it '
              'would starve everything behind it.');
    });

    test('does not take a later, healthy batch with it', () async {
      backend.rejectWith =
          Exception('Severity.error 22003: integer out of range');
      await db.insertTimeseriesData('counter', DateTime.utc(2026), 42);
      await db.flush();

      // The column gets widened by hand; the tag starts recording again.
      backend.rejectWith = null;
      await db.insertTimeseriesData('counter', DateTime.utc(2026, 1, 2), 43);
      await db.flush();

      expect(backend.storedValues, [43]);
      expect(db.getStats()['poisoned_rows'], 1);
    });

    test('an outage is still retried, and still recovers', () async {
      // The counterpart assertion: the drop path must not swallow the case it
      // was never meant to touch.
      backend.down = true;
      await db.insertTimeseriesData('t', DateTime.utc(2026), 1.0);
      await db.flush();
      expect(db.getStats()['poisoned_rows'], 0);
      expect(db.queuedRowCount, 1);

      backend.down = false;
      await Future<void>.delayed(const Duration(seconds: 7));
      expect(backend.storedValues, [1.0]);
      expect(db.getStats()['dropped_rows'], 0);
    });
  });
}
