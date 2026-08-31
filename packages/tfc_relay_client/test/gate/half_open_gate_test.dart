/// F4 and F5: the link that is up and carrying nothing.
///
/// **F4 — Asymmetric half-open.** `bufferServerToClient`. The catalogue asks
/// that the app-level freshness deadline fires (rule 1);
/// all values grey out (rule 4) even though socket looks connected.
///
/// **F5 — True half-open both ways.** `blackhole()`. The catalogue asks that
/// `pingInterval` closes the socket within its deadline; freshness deadline
/// fires first or concurrently; no wait for TCP timeouts (minutes).
///
/// This is the fault the whole product is built against, and the one no
/// `onDone` will ever report: the socket is open, the peer is gone, and every
/// surface above the transport reads healthy. F4 is the half where the client's
/// own requests still arrive and the answers are withheld; F5 is the half where
/// both directions are swallowed.
///
/// **What F5a deliberately does not assert.** It does not measure
/// `pingInterval` closing the socket. It measures the *write* resolving as
/// unknown and the link recovering, which is the clause an operator feels; the
/// ping-deadline clause of the row is asserted where the ping is configured,
/// not here.
///
/// **F5b carries three TEMPORARY window exemptions and they are 07-03's first
/// job.** Its three wall-clock reads are the parked flake 07-CONTEXT ruling 6
/// names — a `viewIsStale` read against a 500 ms deadline that failed one run
/// in three on a loaded runner. 07-02 moved the case without editing it, so the
/// reads are marked rather than fixed. 07-03 deletes the three markers, watches
/// the sweep go red, and lands the `until()` windows with a platform-scaled
/// deadline. Unlike the permanent exemptions elsewhere in this directory, these
/// are not an argument that the reads are sound: they are an argument that the
/// move and the fix are two changes and belong in two commits.
///
/// Moved here verbatim from `test/contract/fault_contract_test.dart` in Phase 7
/// (07-02); bodies unchanged.

@TestOn('vm')
@Tags(['gate', 'faults'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/connection_supervisor.dart' show LinkState;
import 'package:tfc_relay_client/src/failure_taxonomy.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../support/fault_fixture.dart';
import '../support/gate_bands.dart';

void main() {
  group('F4/F5 — the link that is up and carrying nothing', () {
    test('F4: a link that withholds answers degrades honestly — nothing is '
        'aged into looking current', () async {
      final fixture = await faultFixture(
        keys: const {scenarioKey},
        withProxy: true,
        config: faultClientConfig(control: const Duration(milliseconds: 400)),
        // Stamped, unlike the other cases' seeds: the gateway puts `t` on the
        // wire only when the source has one (`session_handlers.dart:297-306`),
        // and this is the one case whose property is about the *age* of the
        // cached reading rather than its value. A real PLC reading always
        // carries one.
        seed: (plant) =>
            plant.setValue(scenarioKey, 1200, sourceTime: DateTime.now().toUtc()),
      );
      await until('the link', () => fixture.client.isReady);
      final held = fixture.client.read(scenarioKey);
      expect(held?.sourceTime, isNotNull,
          reason: 'the cached reading carries no source time, so the '
              'assertion below that its age did not move is comparing two '
              'nulls (the WireValue.t decode defect 04-09 fixed)');

      // The asymmetric half-open: the client's requests still reach the
      // gateway and the gateway's answers are held. The socket stays up, which
      // is what makes this the quiet failure rather than a disconnect.
      fixture.proxy.bufferServerToClient = true;

      final started = DateTime.now();
      Object? failure;
      await fixture.client
          .readFresh(scenarioKey)
          .then<void>((_) {}, onError: (Object error) => failure = error);
      final took = DateTime.now().difference(started);

      expect(failure, isA<TimeoutException>(),
          reason: 'a forced round trip during a half-open came back with '
              '$failure. `readFresh` promises the caller a *fresh* value; the '
              'one thing it must never do is quietly answer from the cache, '
              'because then a panel behind a withheld link shows an operator a '
              'reading it has no current evidence for');
      expect(took, greaterThan(const Duration(milliseconds: 400) - slack),
          reason: 'the call failed in ${took.inMilliseconds} ms, well inside '
              'its own deadline, so something other than the deadline ended '
              'it and the withhold is not what this measured');
      expect(took, lessThan(const Duration(milliseconds: 400) + recovery),
          reason: 'the deadline did not bound the call: a request that '
              'outlives its deadline is the spinner the deadline exists to '
              'prevent');

      expect(fixture.client.read(scenarioKey)?.value, held?.value,
          reason: 'the cached value moved while nothing was arriving, which '
              'means it came from somewhere other than the gateway');
      expect(fixture.client.read(scenarioKey)?.sourceTime, held?.sourceTime,
          reason: 'the cached reading\'s source time advanced during an outage '
              'in which no frame arrived. That is the product\'s one '
              'unforgivable failure: a value that ages itself into looking '
              'current is indistinguishable, on screen, from a live one');

      // And the fault is survivable: releasing the direction brings the client
      // back without a reconnect, because the socket never went away.
      fixture.proxy.bufferServerToClient = false;
      fixture.served.setValue(scenarioKey, 1500);
      await until('the value after the withhold was released',
          () => fixture.client.read(scenarioKey)?.value == 1500,
          budget: recovery);
    });

    test('F5a: a total half-open resolves a write as unknown rather than '
        'refused, and the link recovers', () async {
      final fixture = await faultFixture(
        keys: const {scenarioKey},
        withProxy: true,
        config: faultClientConfig(write: const Duration(milliseconds: 400)),
        seed: (plant) => plant.setValue(scenarioKey, 1200),
      );
      await until('the link', () => fixture.client.isReady);
      expect(fixture.client.read(scenarioKey)?.value, 1200,
          reason: 'the page was not live before the blackhole, so the '
              'recovery arm at the end is about nothing');

      // Both directions swallowed, sockets still up: the fault the whole
      // project is built against, and the one no `onDone` will ever report.
      fixture.proxy.blackhole();

      final outcome = await fixture.client.write(scenarioKey, 1500).timeout(recovery);

      expect(outcome, isA<WriteUnknown>(),
          reason: 'the write came back $outcome. Nobody knows whether the '
              'setpoint reached the device — the request may have crossed '
              'before the link went silent — and reporting a swallowed link as '
              'a refusal tells an operator a machine definitely did not move '
              'when it may well have');
      expect((outcome as WriteUnknown).reason.kind,
          anyOf(FailureKind.deadlineExpired, FailureKind.linkLost,
              FailureKind.linkDown),
          reason: 'the unknown must name something an integrator can act on; '
              'got ${outcome.reason.kind}');
      expect(fixture.client.debugWritesSent, 1,
          reason: 'the write was sent more than once. On a plant that is a '
              'second stroke of a ram the operator commanded once, and no '
              'amount of link trouble makes it acceptable');
      expect(fixture.client.debugUnresolvedCmds, contains(outcome.cmd),
          reason: 'an unknown outcome that is not held for re-query is an '
              'outcome nobody will ever establish');

      fixture.proxy.blackhole(enabled: false);
      fixture.served.setValue(scenarioKey, 1500);
      await until('the link recovering after the blackhole lifted',
          () => fixture.client.read(scenarioKey)?.value == 1500,
          budget: recovery);
    });

    test('F5b: a half-open link stops reading ready, and says so', () async {
      // 04-REVIEW CR-06. The watchdog computed all of this correctly and
      // nothing above it could read a word, so the case the whole product is
      // built around — socket up, no frames, values frozen — presented as
      // LinkState.ready, isReady true, Quality.good, and no observable of any
      // kind for as long as the panel stayed on.
      final fixture = await faultFixture(
        keys: const {scenarioKey},
        withProxy: true,
        config: faultClientConfig(freshness: const Duration(milliseconds: 500)),
        seed: (plant) => plant.setValue(scenarioKey, 1200),
      );
      await until('the link', () => fixture.client.isReady);
      expect(fixture.client.viewIsStale, isFalse, // window-exempt: TEMPORARY — parked wall-clock flake; 07-03 removes this exemption and rewrites as an until() window per 07-CONTEXT ruling 6
          reason: 'the view was already stale on a healthy link, so the '
              'transition below is not a measurement of the blackhole');

      final transitions = <bool>[];
      final watching = fixture.client.viewFreshness.listen(transitions.add);
      addTearDown(watching.cancel);

      fixture.proxy.blackhole();

      await until('the view to be reported stale',
          () => fixture.client.viewIsStale,
          budget: recovery);
      expect(transitions, contains(true),
          reason: 'the freshness stream never emitted, so nothing above this '
              'client could render the staleness it had detected');
      await until('the link to stop reading ready',
          () => !fixture.client.isReady,
          budget: recovery);
      expect(fixture.client.linkState, isNot(LinkState.ready), // window-exempt: TEMPORARY — parked wall-clock flake; 07-03 removes this exemption and rewrites as an until() window per 07-CONTEXT ruling 6
          reason: 'a socket that has said nothing for a whole freshness '
              'deadline is one this client must stop believing in; leaving it '
              'at ready is the operator reading a five-minute-old tank level '
              'as current');

      // And it recovers on its own, which is what makes acting on the silence
      // safe: the reconnect loop is the same one every other kind of drop uses.
      fixture.proxy.blackhole(enabled: false);
      await until('the reconnect', () => fixture.client.isReady,
          budget: recovery);
      expect(fixture.client.viewIsStale, isFalse); // window-exempt: TEMPORARY — parked wall-clock flake; 07-03 removes this exemption and rewrites as an until() window per 07-CONTEXT ruling 6
      fixture.served.setValue(scenarioKey, 1500);
      await until('values flowing again',
          () => fixture.client.read(scenarioKey)?.value == 1500,
          budget: recovery);
    });
  });
}
