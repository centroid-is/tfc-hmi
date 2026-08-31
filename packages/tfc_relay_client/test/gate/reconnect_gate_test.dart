/// F1 and F8: a clean drop, and the value that changed while the link was down.
///
/// **F1 — Clean drop, single reconnect.** `killOnce()`. The catalogue asks for
/// a client that reconnects with backoff;
/// full resync (rule 2); banner shown and cleared.
///
/// **F8 — Value changes during outage.** Drop, change key server-side,
/// reconnect. The catalogue asks that resync delivers the new value (rule 2) —
/// the silent-permanent-staleness case; assert the *changed-while-down* key,
/// not just any key.
///
/// The two rows share one case because they are one fault seen from two sides,
/// and the F8 clause is what stops the F1 clause being vacuous: a client that
/// reconnected, resynced and re-delivered the value it already had would
/// satisfy "full resync" on the report and leave an operator looking at a
/// setpoint the plant no longer holds. The case therefore changes the key while
/// the link is down and asserts the *changed* value came back, which is the
/// catalogue's own instruction for F8.
///
/// Moved here verbatim from `test/contract/fault_contract_test.dart` in Phase 7
/// (07-02). The body is unchanged: what it proves and how it proves it were
/// settled when it was written, and a move that edited the assertions would
/// make a red afterwards ambiguous between the move and the edit.

@TestOn('vm')
@Tags(['gate', 'faults'])
library;

import 'package:test/test.dart';

import '../support/fault_fixture.dart';
import '../support/gate_bands.dart';

void main() {
  group('F1/F8 — a clean drop, and what changed while it was down', () {
    test('F1/F8: a clean drop mid-subscription reconnects, resyncs, and delivers '
        'what changed while it was down', () async {
      final fixture = await faultFixture(
        keys: const {scenarioKey},
        withProxy: true,
        seed: (plant) => plant.setValue(scenarioKey, 1200),
      );
      await until('the link', () => fixture.client.isReady);

      // Anti-vacuity: the page has to have been live before the drop, or
      // "it came back" is a statement about a client that never worked.
      expect(fixture.client.read(scenarioKey)?.value, 1200,
          reason: 'the subscription was not carrying the seeded value before '
              'the link was cut, so nothing below is about a recovery');
      final dialsBefore = fixture.seam.dials;
      expect(dialsBefore, greaterThan(0),
          reason: 'the client never dialled at all, so the fixture — not the '
              'fault — is what this case would be measuring');

      fixture.proxy.killOnce();
      // Changed while the link is down, which is F8's half of F1 and the only
      // reason the recovery assertion is not vacuous: a client that resynced
      // and re-delivered the *old* value would look identical without it.
      fixture.served.setValue(scenarioKey, 1500);

      await until(
          'the resync to deliver the value that changed during the outage',
          () => fixture.client.read(scenarioKey)?.value == 1500,
          budget: recovery);

      expect(fixture.seam.dials, greaterThan(dialsBefore),
          reason: 'the value arrived without a second dial, so the link was '
              'never actually cut and this case proves nothing about '
              'reconnecting');
      expect(fixture.client.isReady, isTrue, // window-exempt: the until() above already waited for the resynced value to arrive — a completed event; this asserts readiness is consistent with that arrival, not that readiness becomes true
          reason: 'the value arrived but the client is not back at ready, so '
              'the next call an operator makes still waits on the barrier');
    });
  });
}
