// Tests for WatchdogUnresponsiveTracker: the pure decision logic behind the
// connection watchdog's "isolate is wedged" escalation (state_man.dart).
//
// Background (plant debugging, PRs #345/#346): when a secured OPC UA
// connection dies, the client isolate can wedge in native code and stop
// answering state queries. Every poll then comes back null and the watchdog
// used to retry silently forever. The tracker turns that run of consecutive
// null polls into a loud, rate-limited "unresponsive" declaration.
//
// All times are injected DateTimes -- no real waiting.

import 'package:test/test.dart';
import 'package:tfc_dart/core/state_man.dart';

void main() {
  final t0 = DateTime(2026, 8, 25, 12, 0, 0);

  WatchdogUnresponsiveTracker makeTracker(
          {Duration unresponsiveAfter = const Duration(seconds: 30)}) =>
      WatchdogUnresponsiveTracker(unresponsiveAfter: unresponsiveAfter);

  group('OpcuaSupervisionConfig.unresponsiveAfter', () {
    test('defaults to 30 seconds', () {
      const config = OpcuaSupervisionConfig();
      expect(config.unresponsiveAfter, const Duration(seconds: 30));
    });

    test('is injectable', () {
      const config =
          OpcuaSupervisionConfig(unresponsiveAfter: Duration(seconds: 3));
      expect(config.unresponsiveAfter, const Duration(seconds: 3));
    });
  });

  group('WatchdogUnresponsiveTracker', () {
    test('starts responsive', () {
      final tracker = makeTracker();
      expect(tracker.isUnresponsive, isFalse);
      expect(tracker.unresponsiveFor(t0), Duration.zero);
    });

    test('not unresponsive before the window elapses', () {
      final tracker = makeTracker();
      // Polls take ~5s each when timing out; simulate that cadence.
      tracker.recordNullPoll(t0);
      expect(tracker.isUnresponsive, isFalse);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 5)));
      expect(tracker.isUnresponsive, isFalse);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 29)));
      expect(tracker.isUnresponsive, isFalse);
      // No announcement while still inside the window.
      expect(
          tracker.shouldAnnounce(t0.add(const Duration(seconds: 29))), isFalse);
    });

    test('unresponsive once unresponsiveAfter of consecutive nulls elapsed',
        () {
      final tracker = makeTracker();
      tracker.recordNullPoll(t0);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 30)));
      expect(tracker.isUnresponsive, isTrue);
    });

    test('elapsed time is measured from the FIRST null of the run, not poll '
        'counts', () {
      // Two polls 40s apart (each timed out for ~5s and the loop slept in
      // between) must already read unresponsive: it is wall time since the
      // first null that matters, not how many polls happened.
      final tracker = makeTracker();
      tracker.recordNullPoll(t0);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 40)));
      expect(tracker.isUnresponsive, isTrue);
    });

    test('a single good poll fully resets', () {
      final tracker = makeTracker();
      tracker.recordNullPoll(t0);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 35)));
      expect(tracker.isUnresponsive, isTrue);
      expect(tracker.shouldAnnounce(t0.add(const Duration(seconds: 35))),
          isTrue);

      tracker.recordGoodPoll();
      expect(tracker.isUnresponsive, isFalse);
      expect(tracker.unresponsiveFor(t0.add(const Duration(seconds: 36))),
          Duration.zero);

      // A fresh run of nulls starts a fresh window...
      final t1 = t0.add(const Duration(seconds: 40));
      tracker.recordNullPoll(t1);
      expect(tracker.isUnresponsive, isFalse);
      tracker.recordNullPoll(t1.add(const Duration(seconds: 29)));
      expect(tracker.isUnresponsive, isFalse);
      tracker.recordNullPoll(t1.add(const Duration(seconds: 31)));
      expect(tracker.isUnresponsive, isTrue);
      // ...and the announcement rate limit was reset too: the new run may
      // announce immediately once unresponsive, even though the previous
      // announcement was less than a minute ago.
      expect(tracker.shouldAnnounce(t1.add(const Duration(seconds: 31))),
          isTrue);
    });

    test('never unresponsive while polls succeed', () {
      final tracker = makeTracker();
      var now = t0;
      for (var i = 0; i < 100; i++) {
        tracker.recordGoodPoll();
        now = now.add(const Duration(seconds: 5));
        expect(tracker.isUnresponsive, isFalse);
        expect(tracker.shouldAnnounce(now), isFalse);
        expect(tracker.unresponsiveFor(now), Duration.zero);
      }
    });

    test('interleaved good polls keep resetting the run', () {
      final tracker = makeTracker();
      var now = t0;
      // null, null, good, null, null, good, ... over far more than 30s of
      // wall time: never unresponsive because no CONSECUTIVE run lasts 30s.
      for (var i = 0; i < 20; i++) {
        tracker.recordNullPoll(now);
        now = now.add(const Duration(seconds: 5));
        tracker.recordNullPoll(now);
        now = now.add(const Duration(seconds: 5));
        tracker.recordGoodPoll();
        expect(tracker.isUnresponsive, isFalse);
      }
    });

    test('announcements are rate-limited to one per minute', () {
      final tracker = makeTracker();
      tracker.recordNullPoll(t0);
      var now = t0.add(const Duration(seconds: 35));
      tracker.recordNullPoll(now);
      expect(tracker.isUnresponsive, isTrue);

      // First announcement fires.
      expect(tracker.shouldAnnounce(now), isTrue);
      // Immediately after: suppressed.
      expect(tracker.shouldAnnounce(now), isFalse);

      // 5s cadence of further null polls for the next 59s: all suppressed.
      final firstAnnounce = now;
      while (now.difference(firstAnnounce) < const Duration(seconds: 55)) {
        now = now.add(const Duration(seconds: 5));
        tracker.recordNullPoll(now);
        expect(tracker.shouldAnnounce(now), isFalse,
            reason: 'suppressed at +${now.difference(firstAnnounce)}');
      }

      // At/after one minute since the last announcement: fires again.
      now = firstAnnounce.add(const Duration(seconds: 60));
      tracker.recordNullPoll(now);
      expect(tracker.shouldAnnounce(now), isTrue);
      // And is suppressed again right after.
      expect(tracker.shouldAnnounce(now.add(const Duration(seconds: 5))),
          isFalse);
    });

    test('shouldAnnounce never fires while responsive', () {
      final tracker = makeTracker();
      expect(tracker.shouldAnnounce(t0), isFalse);
      tracker.recordNullPoll(t0);
      // Inside the window: not yet unresponsive, so no announcement -- and
      // the refusal must not consume the rate-limit budget.
      expect(tracker.shouldAnnounce(t0.add(const Duration(seconds: 10))),
          isFalse);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 30)));
      expect(tracker.shouldAnnounce(t0.add(const Duration(seconds: 30))),
          isTrue);
    });

    test('unresponsiveFor reports elapsed time since the first null', () {
      final tracker = makeTracker();
      tracker.recordNullPoll(t0);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 5)));
      expect(tracker.unresponsiveFor(t0.add(const Duration(seconds: 5))),
          const Duration(seconds: 5));
      tracker.recordNullPoll(t0.add(const Duration(minutes: 9))); // the plant
      expect(tracker.unresponsiveFor(t0.add(const Duration(minutes: 9))),
          const Duration(minutes: 9));
    });

    test('honours an injected unresponsiveAfter window', () {
      final tracker =
          makeTracker(unresponsiveAfter: const Duration(seconds: 3));
      tracker.recordNullPoll(t0);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 2)));
      expect(tracker.isUnresponsive, isFalse);
      tracker.recordNullPoll(t0.add(const Duration(seconds: 3)));
      expect(tracker.isUnresponsive, isTrue);
    });
  });
}
