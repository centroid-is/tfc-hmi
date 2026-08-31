/// F13: a slow link is slow, not down.
///
/// **F13 — High latency.** `latency(500ms, 200ms)`. The catalogue asks for no
/// false disconnects: ping and freshness deadlines tolerate configured RTT;
/// staleness age (rule 4) reflects real delay.
///
/// A panel that reconnects on latency turns a congested switch into a reconnect
/// storm, and the storm is what keeps the switch congested — so the property is
/// as much about what must *not* happen as about the answer arriving.
///
/// **What this case does not yet assert, and why the row stays `partial`.** It
/// imposes a flat 100 ms one-way delay with no jitter, against a catalogue row
/// written for 500 ms ± 200 ms; and it does not assert the second clause at all
/// — that the staleness age a value carries reflects the real delay rather than
/// merely staying inside a deadline. 07-05 owns both. The row keeps an
/// outstanding entry marked `partial` rather than being deleted, because a row
/// deleted from that list reads on the progress line as a promise this repo has
/// finished keeping.
///
/// Moved here verbatim from `test/contract/fault_contract_test.dart` in Phase 7
/// (07-02); body unchanged.

@TestOn('vm')
@Tags(['gate', 'faults'])
library;

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../support/fault_fixture.dart';
import '../support/gate_bands.dart';

void main() {
  group('F13 — a link that is merely slow', () {
    test('F13: a slow link is slow, not down', () async {
      final fixture = await faultFixture(
        keys: const {scenarioKey},
        withProxy: true,
        config: faultClientConfig(control: f13Deadline, write: f13Deadline),
        seed: (plant) => plant.setValue(scenarioKey, 1200),
      );
      await until('the link', () => fixture.client.isReady);
      final dialsBefore = fixture.seam.dials;

      // Live: it reaches the connection that is already open, which is the
      // only shape "the link degrades while the panel is connected" comes in.
      fixture.proxy.latency = f13Latency;

      final started = DateTime.now();
      final value = await fixture.client.readFresh(scenarioKey).timeout(recovery);
      final took = DateTime.now().difference(started);

      expect(value.quality, Quality.good,
          reason: 'a slow answer is still an answer; degrading its quality '
              'because it took 200 ms would grey a healthy plant');
      expect(took, greaterThan(f13Latency * 2 - slack),
          reason: 'the round trip took ${took.inMilliseconds} ms, less than '
              'the two one-way delays the proxy was told to impose. The lever '
              'did not reach the open connection, so this case is measuring an '
              'ordinary link');
      expect(took, lessThan(f13Deadline),
          reason: 'a round trip of ${took.inMilliseconds} ms exceeded the '
              'deadline it was given. That is not a fault report, it is a '
              'false one: the gateway answered');

      // And no false disconnect over a window. Instants are useless here —
      // the whole point is that nothing happens for a while.
      await Future<void>.delayed(settle);
      expect(fixture.seam.dials, dialsBefore,
          reason: 'the client redialled during a link that was merely slow. A '
              'panel that reconnects on latency turns a congested switch into '
              'a reconnect storm, and the storm is what keeps the switch '
              'congested');
      expect(fixture.client.isReady, isTrue, // window-exempt: the settle delay above completed and the dials assertion just proved no redial happened during it; the property is that readiness STAYED true across that elapsed window, and until() would accept a client that became ready late — which is precisely the false disconnect this case forbids
          reason: 'the client left ready on a link that was answering');
    });
  });
}
