/// The herd family: the rows that need more than one panel on one gateway.
///
/// **F10 — Server process restart.** The catalogue's expectation is that the
/// client treats it as F1; server rebuilds subscription state from client's
/// re-subscribe (server holds no obligation to remember clients). F10 is F11
/// with N=1 and it ships beside it because it is F11's debugging step: a herd
/// that fails for a reason one panel would have shown is a bad afternoon.
///
/// **What the restart in this file is, said plainly.** It is an **in-process
/// `RelayServer.close()` followed by a rebind on the same port**, not a process
/// boundary. What that proves is the whole operational content of the row: the
/// epoch changes, the gateway's subscription registry starts empty, and the
/// page that comes back was rebuilt purely from the panel's own re-subscribe.
/// What it does **not** prove is anything about process startup, port reuse
/// across a `SIGKILL`, or a listener socket surviving into a child. Those need
/// a real process boundary, which needs a docker-compose tier this project does
/// not have, and they belong to the Phase 11 chaos soak. The deviations
/// registry carries the entry (`f_row_registry.dart`, row F10) and it points
/// here.
///
/// **F11 — Thundering herd.** all resubscribe; server tick cost stays bounded;
/// no client starves (fairness across resync bursts). Two halves of this row
/// already existed and neither is the row. `fanout_test.dart:80-120` runs fifty
/// clients through the gateway's encode-once path and proves the **server-cost**
/// half — one encode serves every session watching the same key — but those
/// clients are in-memory `Plant` sessions with no sockets, so they cannot
/// resubscribe, cannot starve and cannot be evicted. That half is cited here
/// and deliberately **not** re-run over sockets: it is measured where it is
/// cheap and it is measured correctly. What this file adds is the other half,
/// which is only expressible over real sockets: twenty real panels, a real
/// gateway restart, and the three things a herd can do wrong.
///
/// **F12 — Slow client / backpressure.** server buffer for that client stays
/// bounded via conflation (§7.6); other clients unaffected. The second clause
/// is this file's; the first is asserted from the gateway's side in
/// `backpressure_test.dart:327-393`, and asserted here as the panel-visible
/// consequence — the throttled panel keeps arriving at the *latest* value and
/// is never thrown off.
///
/// **G2 — Late joiner under sustained loss.** A client subscribing while the
/// link is throttled to 100 kbit and flapping must still reach a fresh,
/// complete view — the snapshot must not be starved by telemetry. Assert the
/// `subscribe` response (priority lane) beats the `u` backlog.
///
/// **Why the descriptor clause is not inside F11.** `openSocketCount` cannot
/// answer on Windows — there is no `/proc/self/fd` and no `lsof`
/// (`fd_count.dart:40-55`) — so an arm that measures descriptors has to skip
/// there. Putting that skip on F11 itself would make the row green-by-skip on
/// one column of the matrix, which is precisely the "capability switched off"
/// failure the manifest's own no-silent-skip sweep exists to catch one level
/// up. So F11 runs everywhere and judges everything a panel can observe, and
/// the descriptor measurement lives in the supporting control arm below, whose
/// per-test skip carries `openSocketCountSkipReason` verbatim.
@TestOn('vm')
@Tags(['gate', 'faults'])
library;

import 'package:test/test.dart';
import 'package:tfc_stateman_contract/faults.dart';

import '../support/gate_fixture.dart';

/// The page every case in this file drives, as `ST101.CNnn.MOT01.setpoint`.
///
/// The plant's own naming (`AREAnn.DEVnn.SUBnn`), so a page reads like a page
/// rather than like `key0…key39` — `resync_gate_test.dart:97-104`'s rule.
List<String> _pageKeys(int n) => [
      for (var i = 1; i <= n; i++)
        'ST101.CN${i.toString().padLeft(2, '0')}.MOT01.setpoint',
    ];

void main() {
  group('the fixture can see what it is about to measure', () {
    test('the herd fixture holds N real panels, and the counters can see them',
        () async {
      final keys = _pageKeys(4).toSet();
      final n = herdSize;
      final baseline = openSocketCount();

      // **Registered before the fixture, so it runs after it.** `addTearDown`
      // is last-registered-first, and `gateFixture` registers four groups of
      // teardowns of its own while it is being awaited — so a leak check
      // written on the line after the fixture call runs *first*, against a
      // herd that is still fully connected. Measured, the first time this was
      // written that way: six descriptors, two listeners in LISTEN and two
      // pairs ESTABLISHED, reported as a leak by a check that had simply run
      // too early.
      addTearDown(() async {
        final settled = await untilSocketsSettle(baseline);
        print('herd control arm: open sockets settled at $settled against a '
            'baseline of $baseline');
        expect(settled, lessThanOrEqualTo(baseline),
            reason: 'the herd released its panels, its gateway and its proxy '
                'and the process is still holding ${settled - baseline} more '
                'socket descriptors than it did before the fixture was built. '
                'TIME_WAIT is not a descriptor (`fd_count.dart:28-31`, '
                'measured over 1245 system-wide entries), so this is a socket '
                'nobody closed');
      });

      final fixture = await gateFixture(
        keys: keys,
        seed: (plant) => plant.setValues({for (final key in keys) key: 1}),
      );
      final held = openSocketCount();

      print('herd control arm: ${fixture.clients.length} panels; the gateway '
          'holds ${fixture.sessionCount} sessions; open sockets $baseline -> '
          '$held (delta ${held - baseline})');

      expect(fixture.clients.length, n,
          reason: 'the fixture built ${fixture.clients.length} panels against '
              'a declared herd size of $n. Every number this file reports is '
              'per-herd, so a fixture that quietly built one panel would make '
              'the herd rows pass as single-client rows wearing herd names');

      expect(fixture.sessionCount, n,
          reason: 'the gateway is holding ${fixture.sessionCount} sessions '
              'against $n panels this fixture built. Every leak arm in this '
              'file counts sessions, so a counter that cannot see $n held '
              'connections cannot see a leak either — it would report zero '
              'before and zero after and call that a clean teardown');

      expect(held - baseline, greaterThanOrEqualTo(n),
          reason: 'standing up $n panels moved the open-socket count by '
              '${held - baseline}, which is fewer than one descriptor per '
              'panel. Each of them costs four in this process — the panel\'s '
              'socket, the proxy\'s accepted socket, the proxy\'s upstream '
              'socket and the gateway\'s accepted socket — so a delta below '
              '$n means the count is not seeing this fixture\'s connections '
              'at all, and the leak assertion built on it is vacuous');
    },
        skip: canCountOpenSockets ? null : openSocketCountSkipReason);
  });
}
