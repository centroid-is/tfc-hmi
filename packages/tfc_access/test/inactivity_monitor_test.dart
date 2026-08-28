import 'package:tfc_access/tfc_access.dart';
import 'package:test/test.dart';

/// These tests use real (short) durations rather than `fake_async`: this
/// package has no such dependency, and the whole file runs in about a second.
///
/// Where a test has to say "the countdown was restarted", it asserts a *lower
/// bound* on how long the emission took rather than checking a value at a
/// precise instant. A slow machine can only make a `Future.delayed` overshoot,
/// which pushes the measured elapsed time up — so a lower bound cannot go
/// flaky in the direction a loaded CI runner pushes it.
void main() {
  group('listener gating', () {
    test('no timer is armed while nothing is listening', () async {
      // The test this file exists for. An always-on `Timer.periodic` in shared
      // plumbing has failed unrelated widget tests in this repo before: a
      // pending timer at the end of a `testWidgets` body fails the test even
      // when the widget under test never touched it. If `_arm` were moved out
      // of the controller's `onListen` and into the constructor, the very
      // first expectation below would fail.
      const timeout = Duration(milliseconds: 30);
      final monitor = InactivityMonitor(timeout: timeout);

      expect(monitor.isRunning, isFalse,
          reason: 'construction alone must not arm a timer');
      monitor.poke();
      expect(monitor.isRunning, isFalse,
          reason: 'poke with no listener must not arm a timer');
      monitor.poke();
      expect(monitor.isRunning, isFalse);

      await Future<void>.delayed(timeout * 3);
      expect(monitor.isRunning, isFalse,
          reason: 'three timeouts of wall clock with nobody listening must '
              'still leave nothing armed');

      // And nothing was emitted in the meantime: a listener attaching now must
      // wait a fresh countdown for its first event, not receive a banked one.
      final seen = <DateTime>[];
      final sub = monitor.expirations.listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(seen, isEmpty);

      await sub.cancel();
      await monitor.dispose();
    });

    test('a freshly constructed monitor is not running', () {
      final monitor = InactivityMonitor(timeout: const Duration(seconds: 15));
      expect(monitor.isRunning, isFalse);
    });

    test('listening to expirations starts the countdown', () async {
      final monitor = InactivityMonitor(timeout: const Duration(seconds: 15));
      final sub = monitor.expirations.listen((_) {});
      expect(monitor.isRunning, isTrue);
      await sub.cancel();
      await monitor.dispose();
    });

    test('cancelling the only subscription stops the countdown', () async {
      final monitor = InactivityMonitor(timeout: const Duration(seconds: 15));
      final sub = monitor.expirations.listen((_) {});
      expect(monitor.isRunning, isTrue);
      await sub.cancel();
      expect(monitor.isRunning, isFalse);
      await monitor.dispose();
    });

    test('two listeners both receive the expiry, and the last cancel stops it',
        () async {
      const timeout = Duration(milliseconds: 40);
      final monitor = InactivityMonitor(timeout: timeout);
      final a = <DateTime>[];
      final b = <DateTime>[];
      final subA = monitor.expirations.listen(a.add);
      final subB = monitor.expirations.listen(b.add);

      await Future<void>.delayed(timeout * 3);
      expect(a, hasLength(1));
      expect(b, hasLength(1));

      // Re-arm so there is something to observe being stopped.
      monitor.poke();
      expect(monitor.isRunning, isTrue);
      await subA.cancel();
      expect(monitor.isRunning, isTrue,
          reason: 'one listener remains, so the countdown must keep running');
      await subB.cancel();
      expect(monitor.isRunning, isFalse,
          reason: 'onCancel on a broadcast controller fires when the last '
              'listener goes — that is exactly the gating wanted');
      await monitor.dispose();
    });
  });

  group('the countdown', () {
    test('emits exactly one expiry after a quiet period', () async {
      const timeout = Duration(milliseconds: 30);
      final monitor = InactivityMonitor(timeout: timeout);
      final seen = <DateTime>[];
      final sw = Stopwatch()..start();
      final sub = monitor.expirations.listen(seen.add);

      await Future<void>.delayed(timeout * 4);
      expect(seen, hasLength(1));
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(25),
          reason: 'the expiry cannot land before the timeout has elapsed');

      await sub.cancel();
      await monitor.dispose();
    });

    test('the emitted value is the moment of expiry', () async {
      const timeout = Duration(milliseconds: 30);
      final before = DateTime.now();
      final monitor = InactivityMonitor(timeout: timeout);
      final sub = monitor.expirations.listen((_) {});
      final at = await monitor.expirations.first;
      final after = DateTime.now();

      expect(at.isBefore(before), isFalse);
      expect(at.isAfter(after), isFalse);

      await sub.cancel();
      await monitor.dispose();
    });

    test('poke during the countdown restarts it', () async {
      const timeout = Duration(milliseconds: 80);
      final monitor = InactivityMonitor(timeout: timeout);
      final sw = Stopwatch()..start();
      final first = monitor.expirations.first;

      await Future<void>.delayed(const Duration(milliseconds: 40));
      monitor.poke();
      await first;

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(110),
          reason: 'a poke at ~40ms restarts the 80ms countdown, so the expiry '
              'cannot land on the original 80ms deadline');
      await monitor.dispose();
    });

    test('it is one-shot: after emitting, nothing is armed and nothing repeats',
        () async {
      const timeout = Duration(milliseconds: 25);
      final monitor = InactivityMonitor(timeout: timeout);
      final seen = <DateTime>[];
      final sub = monitor.expirations.listen(seen.add);

      await Future<void>.delayed(timeout * 3);
      expect(seen, hasLength(1));
      expect(monitor.isRunning, isFalse,
          reason: 'a timed-out session drops to anonymous once; the controller '
              're-arms deliberately');

      await Future<void>.delayed(timeout * 3);
      expect(seen, hasLength(1), reason: 'no repeat');

      await sub.cancel();
      await monitor.dispose();
    });
  });

  group('arm', () {
    test('arm(within) fires after within, not after the full timeout',
        () async {
      final monitor =
          InactivityMonitor(timeout: const Duration(milliseconds: 400));
      final sw = Stopwatch()..start();
      final first = monitor.expirations.first;
      monitor.arm(const Duration(milliseconds: 30));
      await first;

      expect(sw.elapsedMilliseconds, lessThan(200),
          reason: 'the explicit 30ms window governs this countdown, not the '
              '400ms constructor timeout');
      await monitor.dispose();
    });

    test('the next poke after an arm restores the full timeout', () async {
      // The bullet that stops a caller reaching for a fresh
      // InactivityMonitor(timeout: remaining) on every re-attach: that works
      // exactly once, and then silently shortens every subsequent session.
      const timeout = Duration(milliseconds: 120);
      final monitor = InactivityMonitor(timeout: timeout);
      final sw = Stopwatch()..start();
      final first = monitor.expirations.first;

      monitor.arm(const Duration(milliseconds: 25));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      monitor.poke();
      await first;

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(110),
          reason: 'arm must not overwrite the stored timeout — the poke at '
              '~10ms has to re-arm for the full 120ms, not for the 25ms the '
              'previous arm used');
      await monitor.dispose();
    });

    test('timeout is unchanged by arm', () async {
      const timeout = Duration(milliseconds: 120);
      final monitor = InactivityMonitor(timeout: timeout);
      final sub = monitor.expirations.listen((_) {});
      monitor.arm(const Duration(milliseconds: 25));
      expect(monitor.timeout, timeout);
      await sub.cancel();
      await monitor.dispose();
    });

    test('arm with no listener attached is a no-op', () async {
      final monitor =
          InactivityMonitor(timeout: const Duration(milliseconds: 30));
      monitor.arm(const Duration(milliseconds: 10));
      expect(monitor.isRunning, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(monitor.isRunning, isFalse,
          reason: 'arm is gated exactly like poke: no listener, no timer');
      await monitor.dispose();
    });
  });

  group('dispose', () {
    test('dispose closes the stream and leaves nothing armed', () async {
      final monitor =
          InactivityMonitor(timeout: const Duration(milliseconds: 30));
      var done = false;
      final sub = monitor.expirations.listen((_) {}, onDone: () => done = true);
      expect(monitor.isRunning, isTrue);

      await monitor.dispose();
      expect(monitor.isRunning, isFalse);
      expect(done, isTrue);
      await sub.cancel();
    });

    test('poke after dispose does not throw', () async {
      final monitor =
          InactivityMonitor(timeout: const Duration(milliseconds: 30));
      await monitor.dispose();
      expect(monitor.poke, returnsNormally);
      expect(() => monitor.arm(const Duration(milliseconds: 5)),
          returnsNormally);
      expect(monitor.isRunning, isFalse);
    });

    test('dispose twice does not throw', () async {
      final monitor =
          InactivityMonitor(timeout: const Duration(milliseconds: 30));
      await monitor.dispose();
      await monitor.dispose();
      expect(monitor.isRunning, isFalse);
    });
  });
}
