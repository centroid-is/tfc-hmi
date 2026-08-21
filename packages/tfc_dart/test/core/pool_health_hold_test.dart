// The pool health monitor must not sit on a connection between heartbeats.
//
// It used to borrow one and never give it back:
//
//     await pool.withConnection((conn) async {
//       while (pool.isOpen) { port.send(true); ...wait 15s... }
//     });
//
// The borrow lasts the life of the process. With one `Database` per OPC UA
// server, that is one permanently-held connection each — the backend ran 8
// databases and held 16 connections, exactly two apiece: one for the monitor,
// one for actual work. The plant wants one per server.
//
// Nothing consumes the signal it produces: `Database.connectionState` has no
// reader anywhere outside its own tests, and the recovery its comment claims
// ("the health monitor will detect this and recreate the pool/provider") is
// really done by the provider's own `probe` + `invalidateSelf`. It is kept
// anyway, because a heartbeat is cheap once it stops holding a connection —
// what changes is that it borrows briefly and releases.
//
// `_startPoolHealthMonitor` is private and takes a concrete `pg.Pool`, so —
// following the convention already used in `database_drift_health_test.dart` —
// these pin the loop *pattern* rather than the private function.

@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';

/// Records how long a connection is held, and how many are held at once.
class _FakePool {
  bool isOpen = true;
  int borrows = 0;
  int concurrentlyHeld = 0;
  int peakHeld = 0;

  Future<T> withConnection<T>(Future<T> Function() body) async {
    borrows++;
    concurrentlyHeld++;
    peakHeld = peakHeld > concurrentlyHeld ? peakHeld : concurrentlyHeld;
    try {
      return await body();
    } finally {
      concurrentlyHeld--;
    }
  }
}

/// The shape being replaced: borrow once, hold for the life of the pool.
Future<void> _holdingMonitor(_FakePool pool, void Function(bool) send,
    {required Duration beat}) async {
  await pool.withConnection(() async {
    while (pool.isOpen) {
      send(true);
      await Future<void>.delayed(beat);
    }
  });
}

/// The shape being adopted: borrow per beat, release between.
Future<void> _beatingMonitor(_FakePool pool, void Function(bool) send,
    {required Duration beat}) async {
  while (pool.isOpen) {
    try {
      await pool.withConnection(() async {});
      send(true);
    } catch (_) {
      send(false);
    }
    if (!pool.isOpen) break;
    await Future<void>.delayed(beat);
  }
}

void main() {
  const beat = Duration(milliseconds: 10);

  test('the old shape keeps a connection held the whole time', () async {
    final pool = _FakePool();
    final beats = <bool>[];
    unawaited(_holdingMonitor(pool, beats.add, beat: beat));
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(pool.borrows, 1);
    expect(pool.concurrentlyHeld, 1,
        reason: 'still holding between heartbeats — this is the connection '
            'the plant was paying for, once per database');
    pool.isOpen = false;
  });

  test('the new shape releases between heartbeats', () async {
    final pool = _FakePool();
    final beats = <bool>[];
    unawaited(_beatingMonitor(pool, beats.add, beat: beat));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    pool.isOpen = false;

    expect(beats, isNotEmpty, reason: 'it still reports health');
    expect(beats.every((b) => b), isTrue);
    expect(pool.borrows, greaterThan(1), reason: 'one borrow per beat');
    expect(pool.concurrentlyHeld, 0,
        reason: 'nothing held while waiting for the next beat');
    expect(pool.peakHeld, 1,
        reason: 'never more than one at a time, so a pool of 1 suffices');
  });

  test('a failed borrow reports false and the loop keeps going', () async {
    final pool = _FakePool();
    final beats = <bool>[];
    var calls = 0;

    Future<void> monitor() async {
      while (pool.isOpen) {
        try {
          await pool.withConnection(() async {
            if (++calls == 1) throw StateError('connection refused');
          });
          beats.add(true);
        } catch (_) {
          beats.add(false);
        }
        if (!pool.isOpen) break;
        await Future<void>.delayed(beat);
      }
    }

    unawaited(monitor());
    await Future<void>.delayed(const Duration(milliseconds: 35));
    pool.isOpen = false;

    expect(beats.first, isFalse, reason: 'the failure is reported');
    expect(beats.skip(1), contains(true),
        reason: 'and it recovers rather than stopping');
    expect(pool.concurrentlyHeld, 0,
        reason: 'a failed borrow must not leak the connection either');
  });

  test('it stops borrowing once the pool closes', () async {
    final pool = _FakePool();
    unawaited(_beatingMonitor(pool, (_) {}, beat: beat));
    await Future<void>.delayed(const Duration(milliseconds: 25));
    pool.isOpen = false;
    final after = pool.borrows;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(pool.borrows, after, reason: 'no borrows after close');
  });
}
