/// The two kinds of "not fresh", kept apart and proved apart.
///
/// Source: 04-RESEARCH Finding 5 — **121 tick notifications in 7001 ms**, with
/// wire-measured inter-tick deltas `[51, 50, 50, 49, 50, 51, …]`, dead flat at
/// **50.0 ms** over 121 samples, and **zero update frames** in that window
/// because nothing in the plant changed. Two things follow, and both are
/// asserted below rather than assumed.
///
/// First, the tick alone is the liveness signal, so a watchdog that only
/// counted *updates* would call a quiet plant dead. Second — and this is why
/// every deadline in this file is written as a multiple of an **injected**
/// period and never as a millisecond count copied from the wire — reading
/// CLI-04's "3× tick" against that measured 50 ms cadence yields a 150 ms
/// deadline. One garbage collection pause on the panel, or one Wi-Fi
/// retransmit on the plant WAN, and every value on the screen greys out at
/// once while the gateway is perfectly healthy. The operator learns within a
/// week that grey means nothing, and the freshness indicator — the whole
/// product — is dead. So the deadline is configured, defaulting to 3 s, and
/// what these cases pin is the **ratio**: stale at three times whatever period
/// the client was told to expect.
///
/// The other half is F25, the dead subscription on a live socket
/// (04-RESEARCH Finding 3): ticks keep arriving, the link is provably up, and
/// one subscription's `evaluatedAt` has stopped advancing because its
/// plant-side source stopped evaluating. Without the per-sub group below, that
/// value renders as current forever — a socket that is up is not a promise
/// that the number on the screen is. And the client must never "fix" it by
/// resyncing: the stream is fine, the plant is not, and a resync loop against
/// a healthy gateway is how one dead PLC tag takes out the whole panel.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:tfc_relay_client/src/client_config.dart';
import 'package:tfc_relay_client/src/freshness_watchdog.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart' show within;
import 'package:test/test.dart';

/// The injected heartbeat period the client is configured to expect.
///
/// Deliberately **not** the gateway's measured 50 ms fan-out cadence: the
/// client cannot learn that number (04-RESEARCH Finding 5 — `HelloResult`
/// carries no tick field and the live handshake returned `capabilities: {}`),
/// and every assertion here is a multiple of this local constant so the suite
/// says nothing about the server's tuning.
const Duration period = Duration(milliseconds: 100);

/// The configured freshness deadline, as a ratio of [period]. CLI-04's "3×".
final Duration deadline = period * 3;

/// A gateway wall-clock instant, verbatim from the tick payload captured in
/// 04-RESEARCH Finding 5 (`{serverTime: 1786711225813, subs: {s1: {seq: 0,
/// evaluatedAt: 1786711225813}}}`). Real epoch ms, because Finding 5b verified
/// live that `hello.serverTime`, `tick.serverTime` and `SubTick.evaluatedAt`
/// are all wall clock and can be subtracted from one another.
const int serverEpochMs = 1786711225813;

/// STATE.md Phase 2 handoff timing bands: Linux is the quiet CI box, every
/// other platform is a developer machine with a browser open.
final Duration slack =
    Platform.isLinux ? const Duration(milliseconds: 20) : const Duration(milliseconds: 75);
final Duration ceiling =
    Platform.isLinux ? const Duration(milliseconds: 100) : const Duration(milliseconds: 150);

/// A config whose freshness deadline is [deadline] — three injected periods.
///
/// `deadlineFloor` is lowered explicitly, which is the point of it being a
/// parameter (04-01): a suite that had to wait out the production 3 s floor to
/// watch one transition would take a minute to run and nobody would run it.
ClientConfig testConfig() => ClientConfig(
      freshnessDeadline: deadline,
      deadlineFloor: const Duration(milliseconds: 10),
    );

/// Records every fresh/stale transition the watchdog announces, in order.
final class TransitionLog {
  final List<bool> staleFlags = <bool>[];
  final Completer<Duration> _firstStale = Completer<Duration>();
  final Completer<Duration> _firstFreshAgain = Completer<Duration>();
  final Stopwatch _since = Stopwatch()..start();

  /// When the view first went stale, measured from construction.
  Future<Duration> get firstStale => _firstStale.future;

  /// When the view first came back, measured from construction.
  Future<Duration> get firstFreshAgain => _firstFreshAgain.future;

  void record(bool stale) {
    staleFlags.add(stale);
    if (stale && !_firstStale.isCompleted) {
      _firstStale.complete(_since.elapsed);
    }
    if (!stale && _firstStale.isCompleted && !_firstFreshAgain.isCompleted) {
      _firstFreshAgain.complete(_since.elapsed);
    }
  }
}

void main() {
  group('the link watchdog: one timer, reset by any inbound frame', () {
    test('frames every period keep the view fresh across ten periods', () async {
      final log = TransitionLog();
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: log.record);
      addTearDown(watchdog.dispose);

      watchdog.sawFrame(InboundFrame.tick);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(period);
        watchdog.sawFrame(InboundFrame.tick);
      }

      expect(watchdog.viewIsStale, isFalse,
          reason: 'a link delivering a frame every period was called dead, so '
              'the operator saw a grey screen in front of a running plant');
      expect(log.staleFlags, isEmpty,
          reason: 'a healthy link produced a freshness transition at all: '
              'grey that flickers is grey the operator stops reading');
    });

    test('the view goes stale at three times the injected period', () async {
      final log = TransitionLog();
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: log.record);
      addTearDown(watchdog.dispose);

      watchdog.sawFrame(InboundFrame.tick);
      final wentStaleAt = await within(
        log.firstStale,
        'the view going stale after the frames stopped',
        budget: deadline + ceiling + period,
      );

      expect(wentStaleAt, greaterThanOrEqualTo(deadline - slack),
          reason: 'the view greyed before the configured deadline had passed, '
              'which is how a GC pause greys a whole plant');
      expect(wentStaleAt, lessThanOrEqualTo(deadline + ceiling),
          reason: 'a dead link kept rendering as live past its deadline, and a '
              'stale number the operator believes is the failure this whole '
              'product exists to prevent');
      expect(log.staleFlags, equals(<bool>[true]),
          reason: 'one death produced more than one transition');
    });

    test('resuming frames brings the view back exactly once', () async {
      final log = TransitionLog();
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: log.record);
      addTearDown(watchdog.dispose);

      watchdog.sawFrame(InboundFrame.tick);
      await within(log.firstStale, 'the view going stale after the frames stopped',
          budget: deadline + ceiling + period);
      watchdog.sawFrame(InboundFrame.tick);
      await within(log.firstFreshAgain, 'the view coming back when frames resumed',
          budget: ceiling);

      expect(log.staleFlags, equals(<bool>[true, false]),
          reason: 'a link that died and recovered did not read as exactly one '
              'death and one recovery');
      expect(watchdog.viewIsStale, isFalse,
          reason: 'frames are arriving again and the view is still grey');
    });

    test('a tick frame alone keeps the view fresh, so an idle plant is never called dead',
        () async {
      await expectKindKeepsViewFresh(InboundFrame.tick);
    });

    test('an update frame alone keeps the view fresh, so a busy plant is never called dead',
        () async {
      await expectKindKeepsViewFresh(InboundFrame.update);
    });

    test('an rpc response alone keeps the view fresh, so a polling panel is never called dead',
        () async {
      await expectKindKeepsViewFresh(InboundFrame.rpcResponse);
    });

    test('one timer serves the whole link no matter how many frames land', () {
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: (_) {});
      addTearDown(watchdog.dispose);

      expect(watchdog.debugTimerCount, 0,
          reason: 'a watchdog armed itself before a single frame had arrived, '
              'so a panel greys before it has even connected');
      for (var i = 0; i < 50; i++) {
        watchdog.sawFrame(InboundFrame.update);
      }
      expect(watchdog.debugTimerCount, 1,
          reason: 'the link is one link: N timers is N cancellations to get '
              'right on every reconnect, and the one that is missed fires '
              'against a socket that no longer exists');
    });

    test('disposal cancels the timer and no transition fires afterwards', () async {
      final log = TransitionLog();
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: log.record);

      watchdog.sawFrame(InboundFrame.tick);
      expect(watchdog.debugTimerCount, 1);
      watchdog.dispose();
      expect(watchdog.debugTimerCount, 0,
          reason: 'a disposed watchdog left a timer running, which keeps the '
              'isolate alive and fires a callback into a torn-down page');

      await Future<void>.delayed(deadline + ceiling);
      expect(log.staleFlags, isEmpty,
          reason: 'a disposed watchdog still announced a transition');
    });
  });

  group('per-subscription staleness: the dead subscription on a live socket', () {
    test('one frozen subscription is stale while the view and its neighbour are fresh', () {
      final log = TransitionLog();
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: log.record);
      addTearDown(watchdog.dispose);

      // Ticks keep arriving and s1 keeps being evaluated; s2's plant-side
      // source stopped at the first tick and never moved again. This is F25.
      var serverTime = serverEpochMs;
      const frozenAt = serverEpochMs;
      for (var i = 0; i <= 5; i++) {
        watchdog.sawTick(TickParams(serverTime: serverTime, subs: {
          's1': SubTick(seq: i, evaluatedAt: serverTime),
          's2': const SubTick(seq: 0, evaluatedAt: frozenAt),
        }));
        serverTime += period.inMilliseconds;
      }

      expect(watchdog.isSubscriptionStale('s2'), isTrue,
          reason: 'a subscription whose source stopped evaluating five periods '
              'ago still rendered as current, which is the operator trusting a '
              'dead number on a live screen');
      expect(watchdog.isSubscriptionStale('s1'), isFalse,
          reason: 'a healthy neighbour was condemned along with the dead one, '
              'so one dead PLC tag greys the values next to it');
      expect(watchdog.staleSubscriptions, equals(<String>{'s2'}));
      expect(watchdog.viewIsStale, isFalse,
          reason: 'the link is delivering ticks and the whole view was still '
              'called dead: link-down and one-value-dead are the two states '
              'CLI-04 exists to keep apart');
      expect(log.staleFlags, isEmpty,
          reason: 'a plant fault announced itself as a stream fault');
    });

    test('a wrong local clock does not make every subscription look stale', () {
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: (_) {});
      addTearDown(watchdog.dispose);

      const frozenAt = serverEpochMs;
      final serverTime = serverEpochMs + period.inMilliseconds;
      watchdog.sawTick(TickParams(serverTime: serverTime, subs: {
        's1': SubTick(seq: 1, evaluatedAt: serverTime),
        's2': const SubTick(seq: 0, evaluatedAt: frozenAt),
      }));

      // A panel whose clock is right: the 52 ms same-machine skew measured in
      // 04-RESEARCH Finding 5b.
      const rightClockSkewMs = 52;
      // A moment chosen so the frozen subscription is past the deadline and
      // its still-evaluating neighbour is not. The case would prove nothing at
      // an instant where both were stale, or where neither was.
      final localNow = serverTime +
          rightClockSkewMs +
          deadline.inMilliseconds -
          period.inMilliseconds ~/ 2;
      final rightClock =
          watchdog.staleSubscriptionsAt(localNow, clockOffsetMs: rightClockSkewMs);

      // The same panel with its clock set ten minutes fast. `clockOffset` is
      // captured at hello as `localNow - serverTime`, so it carries the error
      // too, and CLI-05 says that warns — it never greys the plant.
      const tenMinutesMs = 10 * 60 * 1000;
      final wrongClock = watchdog.staleSubscriptionsAt(
        localNow + tenMinutesMs,
        clockOffsetMs: rightClockSkewMs + tenMinutesMs,
      );

      expect(rightClock, equals(<String>{'s2'}),
          reason: 'the frozen subscription was not caught between ticks');
      expect(wrongClock, equals(rightClock),
          reason: 'a panel with a wrong wall clock condemned subscriptions the '
              'gateway says are current: a disagreement about what time it is '
              'is not a disagreement about the process, and CLI-05 says warn, '
              'never grey the plant');
    });

    test('fifty subscriptions add no timers — one link, one deadline', () {
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: (_) {});
      addTearDown(watchdog.dispose);

      final subs = <String, SubTick>{
        for (var i = 0; i < 50; i++)
          's$i': const SubTick(seq: 0, evaluatedAt: serverEpochMs),
      };
      watchdog.sawTick(TickParams(serverTime: serverEpochMs, subs: subs));

      expect(watchdog.debugTimerCount, 1,
          reason: 'per-subscription staleness grew a timer per subscription: a '
              '1500-key page is then 1500 cancellations to get right on every '
              'reconnect, and the one that is missed fires into a dead page');
    });

    test('a subscription that starts evaluating again is fresh again, with nothing resynced',
        () {
      final log = TransitionLog();
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: log.record);
      addTearDown(watchdog.dispose);

      const frozenAt = serverEpochMs;
      final lateTime = serverEpochMs + deadline.inMilliseconds * 2;
      watchdog.sawTick(TickParams(serverTime: lateTime, subs: {
        's1': const SubTick(seq: 0, evaluatedAt: frozenAt),
      }));
      expect(watchdog.isSubscriptionStale('s1'), isTrue);

      watchdog.sawTick(TickParams(serverTime: lateTime, subs: {
        's1': SubTick(seq: 1, evaluatedAt: lateTime),
      }));

      expect(watchdog.isSubscriptionStale('s1'), isFalse,
          reason: 'a source that started evaluating again stayed condemned, so '
              'the operator has to reload the page to believe a live value');
      expect(log.staleFlags, isEmpty,
          reason: 'a plant fault that healed itself moved the whole view, which '
              'is the resync this class must never ask for');
    });

    test('an unsubscribed subscription stops being reported', () {
      final watchdog =
          FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: (_) {});
      addTearDown(watchdog.dispose);

      final lateTime = serverEpochMs + deadline.inMilliseconds * 2;
      watchdog.sawTick(TickParams(serverTime: lateTime, subs: {
        's1': const SubTick(seq: 0, evaluatedAt: serverEpochMs),
      }));
      expect(watchdog.staleSubscriptions, equals(<String>{'s1'}));

      watchdog.forgetSubscription('s1');

      expect(watchdog.staleSubscriptions, isEmpty,
          reason: 'an id nobody is subscribed to any more kept raising a fault '
              'about a value no screen displays');
    });
  });
}

/// Drives [kind] alone, once per [period], and fails if the view ever greys.
///
/// Written as one helper over the frame vocabulary because the bite is in the
/// *alone*: a watchdog rescheduling only on ticks passes the idle-link cases
/// above and dies here, on the plant that is busy enough that updates have
/// displaced the tick.
Future<void> expectKindKeepsViewFresh(InboundFrame kind) async {
  final log = TransitionLog();
  final watchdog =
      FreshnessWatchdog(config: testConfig(), onViewFreshnessChanged: log.record);
  addTearDown(watchdog.dispose);

  watchdog.sawFrame(kind);
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(period);
    watchdog.sawFrame(kind);
  }

  expect(watchdog.viewIsStale, isFalse,
      reason: 'a link carrying nothing but ${kind.name} frames was called dead, '
          'so the plant greyed while data was arriving');
  expect(log.staleFlags, isEmpty,
      reason: 'a ${kind.name} frame did not reset the freshness clock');
}
