// One LISTEN/NOTIFY connection, however many channels subscribe at once.
//
// On 2026-08-21 a workstation held 13 Postgres connections. Twelve were
// `LISTEN "table_SB<n>.Checkweigher<n>.Last<Accept|Reject>Weight_changes"`,
// one channel each, all opened within three seconds of startup.
//
// The code already meant to share one connection:
//
//     _notificationConnection ??= await _createNotificationConnection();
//
// but `??=` with an await on the right is not atomic. The null check runs,
// the await suspends, and only then does the assignment land. Twelve series
// subscribing concurrently all saw null, all opened a connection, and the
// last assignment won — leaving eleven orphaned but open, each holding its
// own LISTEN.
//
// A single session can hold any number of channels: verified on the server
// (one backend, five channels via `pg_listening_channels()`), and the driver
// is built for it — `_Channels` keys listeners by channel name, issues LISTEN
// only for a channel's first listener, and demultiplexes notifications by
// name. So the connection count should be one regardless of channel count.
//
// These tests pin the guard itself rather than a live database: the defect is
// entirely in when the assignment happens relative to the await.

@TestOn('vm')
library;

import 'dart:async';

import 'package:test/test.dart';

/// Stands in for the lazily-created connection, counting how many were built.
class _FakeConnection {
  static int opened = 0;
  final int id;
  _FakeConnection() : id = ++opened;
}

/// The shape the fix uses: hold the in-flight *future*, assigned before any
/// await, so concurrent callers join it instead of starting their own.
class _SharedHolder {
  Future<_FakeConnection>? _pending;

  Future<_FakeConnection> get({Duration delay = Duration.zero}) {
    return _pending ??= Future(() async {
      await Future<void>.delayed(delay);
      return _FakeConnection();
    });
  }

  void reset() => _pending = null;
}

/// The shape that was there before: a nullable value, assigned after the
/// await. Kept so the tests demonstrate the defect rather than assert it.
class _RacyHolder {
  _FakeConnection? _conn;

  Future<_FakeConnection> get({Duration delay = Duration.zero}) async {
    // Written out rather than as `??=` so the nullability is explicit; the
    // ordering — check, await, assign — is what the original had.
    if (_conn == null) {
      await Future<void>.delayed(delay);
      _conn = _FakeConnection();
    }
    return _conn!;
  }
}

void main() {
  setUp(() => _FakeConnection.opened = 0);

  group('the defect being fixed', () {
    test('a nullable value assigned after an await opens one per caller',
        () async {
      final racy = _RacyHolder();
      await Future.wait([
        for (var i = 0; i < 12; i++)
          racy.get(delay: const Duration(milliseconds: 5))
      ]);
      // Twelve checkweigher series, twelve connections — the 13 observed in
      // the field, less the pooled one.
      expect(_FakeConnection.opened, 12);
    });
  });

  group('holding the future instead', () {
    test('twelve concurrent subscribers share one connection', () async {
      final shared = _SharedHolder();
      final conns = await Future.wait([
        for (var i = 0; i < 12; i++)
          shared.get(delay: const Duration(milliseconds: 5))
      ]);
      expect(_FakeConnection.opened, 1);
      expect(conns.map((c) => c.id).toSet(), {1},
          reason: 'every subscriber must get the same connection');
    });

    test('a later subscriber joins the one already open', () async {
      final shared = _SharedHolder();
      final first = await shared.get();
      final second = await shared.get();
      expect(_FakeConnection.opened, 1);
      expect(identical(first, second), isTrue);
    });

    test('a single subscriber still opens exactly one', () async {
      final shared = _SharedHolder();
      await shared.get();
      expect(_FakeConnection.opened, 1);
    });

    test('after a reset the next subscriber opens a fresh one', () async {
      // The cancel path drops the connection on error; the next listener has
      // to be able to build another.
      final shared = _SharedHolder();
      await shared.get();
      shared.reset();
      await shared.get();
      expect(_FakeConnection.opened, 2);
    });
  });
}
