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
/// await, so concurrent callers join it instead of starting their own -- and
/// drop it again if it fails, so one bad moment does not latch the channel
/// shut forever. Mirrors `AppDatabase._sharedNotificationConnection`.
class _SharedHolder {
  Future<_FakeConnection>? _pending;

  /// Set to make the next open fail, the way an unreachable database does.
  bool failNext = false;

  Future<_FakeConnection> get({Duration delay = Duration.zero}) {
    final pending = _pending ??= Future(() async {
      await Future<void>.delayed(delay);
      if (failNext) throw StateError('database unreachable');
      return _FakeConnection();
    });
    return pending.catchError((Object error) {
      if (identical(_pending, pending)) _pending = null;
      throw error;
    });
  }

  void reset() => _pending = null;
}

/// Caching the future without evicting a failed one. Kept so the tests
/// demonstrate that defect rather than merely assert the fix.
class _LatchingHolder {
  Future<_FakeConnection>? _pending;
  bool failNext = false;

  Future<_FakeConnection> get({Duration delay = Duration.zero}) {
    return _pending ??= Future(() async {
      await Future<void>.delayed(delay);
      if (failNext) throw StateError('database unreachable');
      return _FakeConnection();
    });
  }
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

  group('an open that fails must not be cached', () {
    // Caching the future fixes the leak but introduces a worse failure if the
    // rejected future is kept: every later subscriber joins the same failure.
    // This runs on the reconnect path, where an unreachable database is the
    // normal case, so latching there would silently kill every channel in the
    // process for good.
    test('caching a rejected future latches the channel shut', () async {
      final latching = _LatchingHolder()..failNext = true;
      await expectLater(latching.get(), throwsA(isA<StateError>()));

      // The database is back.
      latching.failNext = false;
      await expectLater(latching.get(), throwsA(isA<StateError>()),
          reason: 'the defect: the rejected future is still cached, so a '
              'healthy database cannot be reached again');
      expect(_FakeConnection.opened, 0);
    });

    test('evicting it lets the next subscriber reconnect', () async {
      final shared = _SharedHolder()..failNext = true;
      await expectLater(shared.get(), throwsA(isA<StateError>()));

      shared.failNext = false;
      final connection = await shared.get();
      expect(connection.id, 1);
      expect(_FakeConnection.opened, 1,
          reason: 'the retry must actually open one, not replay the failure');
    });

    test('concurrent subscribers all fail together, then all recover',
        () async {
      // Twelve arriving at once against a database that is down: they share
      // the one failed attempt, and the next round shares one new connection.
      final shared = _SharedHolder()..failNext = true;
      final attempts = [
        for (var i = 0; i < 12; i++)
          shared.get(delay: const Duration(milliseconds: 5)).then<Object?>(
              (c) => c, onError: (Object e) => e)
      ];
      final results = await Future.wait(attempts);
      expect(results.every((r) => r is StateError), isTrue);
      expect(_FakeConnection.opened, 0);

      shared.failNext = false;
      final recovered = await Future.wait([
        for (var i = 0; i < 12; i++)
          shared.get(delay: const Duration(milliseconds: 5))
      ]);
      expect(_FakeConnection.opened, 1,
          reason: 'recovery must not reintroduce the leak it just fixed');
      expect(recovered.map((c) => c.id).toSet(), {1});
    });
  });
}
