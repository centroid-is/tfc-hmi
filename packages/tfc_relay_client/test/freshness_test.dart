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
