/// F25 — dead subscription, live socket: the Home Assistant wall-dashboard
/// failure, where the screen looks healthy, some widgets update, others are
/// hours stale, and whole-connection liveness cannot see it by construction.
///
/// Injection, verbatim: server stops evaluating one subscription, connection + other subs healthy
/// Expect, verbatim: client flags exactly that subscription stale
///
/// **Which half of this file is real and which is a lever — said out loud,
/// because the reader of the case is not necessarily the reader of the
/// lever.** The catalogue's injection has no shipped producer:
/// `TickEngine._writeTick` (`tick_engine.dart:400-420`; :376-396 before
/// upstream growth) stamps one `wallMs` as `evaluatedAt` for every
/// subscription of every session, so the field is a statement about the
/// tick, not about the subscription, and no shipped gateway can stop
/// evaluating *one* subscription while the rest keep going. F25a therefore
/// reaches the injection through `FrozenSubLever` — a test-only frame
/// builder between one shipped panel and the shipped gateway — and is honest
/// about that both here and in the lever's own doc. Orchestrator ruling 4
/// (09-CONTEXT) made the lever the answer; option (ii), real
/// per-subscription `evaluatedAt`, is the registry's costed `post-milestone`
/// follow-up and is not built.
///
/// F25a is the client half proven end to end: the same property
/// `freshness_test.dart:333-366` pins at the unit level (one frozen sub, one
/// healthy neighbour, `viewIsStale` false throughout) driven over real
/// sockets against the real gateway. The standing temptation this row
/// refuses is named in gate A's registry (F13's staleness-age deviation):
/// no per-subscription *age* is published to make the clause look asserted —
/// the verdict is the surface, `StateManApi` stays at 49 members, and
/// `RemoteStateMan` grows no getter here.
///
/// **F25a is the catalogue's injection reached through a lever; F25b is
/// ROADMAP criterion 3's wording — upstream stops updating while the link
/// stays up — reached through the product; and the row is only honest with
/// both.** F25b uses no lever and no test-only subclass: it is built
/// entirely from Phase 8 machinery (08-05's freshness sweep degrading to
/// `badStale`, 08-09's `PIPE.upstream.<alias>.data_age_ms`), because the
/// failure that actually happens in a fish factory is a PLC that stops
/// answering while its TCP connection stays perfectly healthy, and that one
/// the shipped gateway *can* see. Post-CR-02 the stored gauge is pushed only
/// on link events and arrivals, and `judge()` re-derives the age
/// synchronously on the READ path (`pipe_health.dart:210-216`) — so the
/// climb is observed by **repeated reads inside `until()` windows**, never
/// by subscribing: a subscriber sees a frozen last-pushed age during a
/// silent freeze, and F25b prints that frozen number beside the climbing one.
@Tags(['gate'])
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:tfc_relay_client/tfc_relay_client.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart' show ServerConfig;

import '../support/frozen_sub_lever.dart' hide visibleForTesting;
import '../support/gate_b_fixture.dart';

void main() {
  test(
      // Lettered F25a the moment F25b lands (task 2, same file): the
      // manifest's gapless-letters arm requires a row's only case to carry
      // no letter.
      'F25: one subscription stops being evaluated — the lever\'s injection '
      '— and the client flags exactly that subscription stale while the '
      'neighbour keeps updating', () async {
    final serverConfig = ServerConfig(tick: ServerConfig.minTick);
    final clientConfig = ClientConfig();
    final fixture = await gateBFixture(panels: 1, serverConfig: serverConfig);

    // Two lever legs in front of the one gateway, one per hand-dialled
    // panel — the fixture's proxyPerPanel shape. Only the frozen leg's lever
    // is ever pulled; the healthy leg's identical, un-pulled lever is what
    // lets the freeze-every-subscription sabotage bite the neighbour arm.
    final frozenLever = await FrozenSubLever.start(targetPort: fixture.port);
    addTearDown(frozenLever.shutdown);
    final healthyLever = await FrozenSubLever.start(targetPort: fixture.port);
    addTearDown(healthyLever.shutdown);

    // Registered after the fixture's own teardowns, so both panels dispose
    // before the gateway closes — the dial-storm ordering the fixture's
    // library doc argues.
    final frozenPanel = RemoteStateMan(
      uri: frozenLever.uri,
      config: clientConfig,
      keys: fixture.keys,
    );
    addTearDown(frozenPanel.dispose);
    final healthyPanel = RemoteStateMan(
      uri: healthyLever.uri,
      config: clientConfig,
      keys: fixture.keys,
    );
    addTearDown(healthyPanel.dispose);

    await until(
      'both lever-leg panels ready with a value for every key',
      () =>
          frozenPanel.isReady &&
          healthyPanel.isReady &&
          fixture.keys.every((key) =>
              frozenPanel.read(key) != null && healthyPanel.read(key) != null),
      budget: const Duration(seconds: 30),
    );

    // The per-subscription limit, read from the two configs the pipe was
    // built with rather than restated as a number: the gateway advertises
    // its tick in `hello`, the client multiplies and floors at the link
    // deadline (`freshness_watchdog.dart`, `_subscriptionLimitMs`).
    final linkMs = clientConfig.freshnessDeadline.inMilliseconds;
    final derived = (serverConfig.tick.inMilliseconds *
            clientConfig.subscriptionStalenessMultiple)
        .round();
    final limitMs = derived > linkMs ? derived : linkMs;
    print('F25a per-subscription limit from the client\'s own config: '
        'max(tick ${serverConfig.tick.inMilliseconds} ms × '
        '${clientConfig.subscriptionStalenessMultiple}, link deadline '
        '$linkMs ms) = $limitMs ms');

    // Anti-vacuity: before the freeze, the frozen leg's values are advancing
    // and neither subscription is stale — sampled through the same window.
    const plantKey = 'ST101.CN01.MOT01.setpoint';
    var staleBeforeFreeze = false;
    final beforeFreeze = frozenPanel.read(plantKey)?.value;
    expect(beforeFreeze, isA<int>(),
        reason: 'anti-vacuity: the frozen leg holds no plant value at all '
            'before the freeze, so nothing below would be measuring a live '
            'subscription going dead');
    await until(
      'the soon-to-be-frozen subscription\'s values advancing before the '
      'freeze',
      () {
        staleBeforeFreeze = staleBeforeFreeze ||
            frozenPanel.isSubscriptionStale(defaultPageSubscription) ||
            healthyPanel.isSubscriptionStale(defaultPageSubscription);
        final now = frozenPanel.read(plantKey)?.value;
        return now is int && now > (beforeFreeze as int);
      },
    );
    expect(staleBeforeFreeze, isFalse,
        reason: 'anti-vacuity: a subscription already stale before the '
            'injection would make the flip below vacuous — the case would be '
            'measuring the fixture, not the lever');

    // The injection. Everything after this line is the catalogue's row.
    final linkTransitions = <LinkState>[];
    final watchingLink = frozenPanel.linkStates.listen(linkTransitions.add);
    addTearDown(watchingLink.cancel);
    var healthyEverStale = false;
    var frozenViewEverStale = false;
    final flip = Stopwatch()..start();
    frozenLever.freeze(defaultPageSubscription);

    await until(
      'the client flags exactly that subscription stale — the frozen page '
      'on the frozen leg',
      () {
        healthyEverStale = healthyEverStale ||
            healthyPanel.isSubscriptionStale(defaultPageSubscription) ||
            fixture.panel.client.isSubscriptionStale(defaultPageSubscription);
        frozenViewEverStale = frozenViewEverStale || frozenPanel.viewIsStale;
        return frozenPanel.isSubscriptionStale(defaultPageSubscription);
      },
      budget: Duration(milliseconds: limitMs * 3),
    );
    flip.stop();
    print('F25a verdict flipped ${flip.elapsedMilliseconds} ms after '
        'freeze() against the $limitMs ms limit '
        '(${frozenLever.rewrittenTicks} ticks rewritten, '
        '${frozenLever.droppedUpdates} updates dropped so far)');

    await until(
      'the frozen leg\'s stale set naming exactly the page subscription',
      () {
        healthyEverStale = healthyEverStale ||
            healthyPanel.isSubscriptionStale(defaultPageSubscription) ||
            fixture.panel.client.isSubscriptionStale(defaultPageSubscription);
        frozenViewEverStale = frozenViewEverStale || frozenPanel.viewIsStale;
        final verdict = frozenPanel.staleSubscriptions;
        return verdict.length == 1 &&
            verdict.contains(defaultPageSubscription);
      },
    );

    // The dead widget stands still while the one next to it keeps moving —
    // the wall-dashboard picture, asserted from both sides.
    final frozenAtFlip = frozenPanel.read(plantKey)?.value;
    final healthyAtFlip = healthyPanel.read(plantKey)?.value as int;
    await until(
      'the healthy neighbour delivering three more sweeps past the flip',
      () {
        healthyEverStale = healthyEverStale ||
            healthyPanel.isSubscriptionStale(defaultPageSubscription) ||
            fixture.panel.client.isSubscriptionStale(defaultPageSubscription);
        frozenViewEverStale = frozenViewEverStale || frozenPanel.viewIsStale;
        final now = healthyPanel.read(plantKey)?.value;
        return now is int && now >= healthyAtFlip + 3;
      },
    );
    expect(frozenPanel.read(plantKey)?.value, frozenAtFlip,
        reason: 'the lever drops the frozen subscription\'s updates from the '
            'pin tick on, so its value cannot have moved a whole limit after '
            'the flip — a moving value here means the injection is not the '
            'fault this case claims to inject');

    expect(healthyEverStale, isFalse,
        reason: 'one dead PLC tag must not grey the values next to it: the '
            'healthy leg\'s panel and the direct-dial observer were sampled '
            'through every window above and neither may ever have read '
            'stale');
    expect(frozenViewEverStale, isFalse,
        reason: 'viewIsStale must stay false throughout: ticks kept arriving '
            'on the frozen leg, so the link is provably alive — link-down '
            'and one-value-dead are the two states CLI-04 exists to keep '
            'apart, and greying the whole view over one dead tag is the '
            'wrong one');
    expect(linkTransitions.where((state) => state != LinkState.ready).toList(),
        isEmpty,
        reason: 'linkState never leaves connected: the socket stayed up and '
            'frames kept arriving, so any transition away from ready during '
            'the freeze means the client tore down a healthy link over a '
            'plant-side fault — the resync-loop failure the 04-CONTEXT '
            'ruling forbids');

    // The lever did what the case says it did — and only on its own leg.
    expect(frozenLever.rewrittenTicks, greaterThan(0),
        reason: 'anti-vacuity: no tick was ever rewritten, so the verdict '
            'above flipped for some other reason than this injection');
    expect(frozenLever.droppedUpdates, greaterThan(0),
        reason: 'anti-vacuity: no update was ever dropped, so the frozen '
            'value standing still was luck, not the injection');
    expect(healthyLever.rewrittenTicks, 0,
        reason: 'the healthy leg\'s lever was never pulled, so a rewrite '
            'there means the lever froze more than the one subscription the '
            'case names');
    expect(healthyLever.droppedUpdates, 0,
        reason: 'as above: the healthy neighbour\'s updates must all have '
            'reached it');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
