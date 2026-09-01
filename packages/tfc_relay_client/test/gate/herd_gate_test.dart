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
import 'package:web_socket_channel/web_socket_channel.dart';

import '../support/fault_fixture.dart';
import '../support/gate_fixture.dart';

/// The page every case in this file drives, as `ST101.CNnn.MOT01.setpoint`.
///
/// The plant's own naming (`AREAnn.DEVnn.SUBnn`), so a page reads like a page
/// rather than like `key0…key39` — `resync_gate_test.dart:97-104`'s rule.
List<String> _pageKeys(int n) => [
      for (var i = 1; i <= n; i++)
        'ST101.CN${i.toString().padLeft(2, '0')}.MOT01.setpoint',
    ];

/// How many keys the restart rows put on a page.
///
/// Four, and small on purpose. F9 already owns the every-key-on-a-wide-page
/// clause over a forty-key page, and it argues there why forty is the number
/// that puts a measurable window between the `hello` answer and the snapshot.
/// The restart rows are about *how many panels* come back, not about how wide
/// a page is, and a forty-key page times twenty panels is thirty-two thousand
/// values through one gateway per restart for no additional evidence.
const int _restartPage = 4;

/// What the plant holds before a restart, and after it.
///
/// Two distinct numbers so that "the panel came back" and "the panel is
/// holding what the plant holds *now*" are different observations. A case that
/// re-read the same value could not tell a resynced page from a cache that was
/// never cleared, which is F10's whole subject.
const int _beforeRestart = 1300;
const int _afterRestart = 2500;

/// How long the gateway stays down during the herd's restart.
///
/// **Two seconds, and the number is doing work.** A gateway that is back
/// before anybody's first retry never asks the backoff to spread anything, and
/// F11 would then measure an empty mechanism — every panel would reconnect on
/// its first attempt and the fairness spread would be the accept loop's, not
/// the jitter's.
///
/// Two seconds is also where the attempt bound below discriminates. At 40 ms
/// base and a 2 s cap the schedule walks 20, 40, 80, 160, 320, 640, 1000 ms of
/// expected waiting, and each attempt also costs a dial into a port nobody is
/// listening on — so a panel that backs off makes about seven attempts in the
/// window. A panel whose cap equals its base makes one every 60 ms, which is
/// about thirty-three. At 300 ms the two are four and five, which is not a
/// result; the dial cost dominates a short window and hides the schedule.
const Duration _herdDowntime = Duration(seconds: 2);

/// The backoff schedule the attempt bound is computed from, restated here
/// rather than read off the config the fixture builds.
///
/// 07-04's lesson, and `resync_gate_test.dart:79-88` carries it in the same
/// words: a ceiling that recomputed itself from whatever the client was
/// actually handed would rise to meet a client that had been made to hammer,
/// which is the one failure it exists to catch. These two must move with
/// `faultClientConfig`'s, and the arm says so if they stop agreeing.
const Duration _backoffBase = Duration(milliseconds: 40);
const Duration _backoffCap = Duration(seconds: 2);

/// What one attempt costs beyond its backoff wait: a dial into a port nobody
/// is listening on, through a proxy that has to fail its own upstream connect
/// first. Measured at 30-60 ms on macOS; 40 ms is the conservative end, because
/// a *smaller* overhead makes the ceiling larger and the bound weaker only in
/// the direction that cannot produce a false red.
const Duration _attemptOverhead = Duration(milliseconds: 40);

/// What one panel's establishment costs once the gateway is listening again:
/// a dial, a WebSocket handshake, a `hello` round trip and a snapshot over
/// loopback. Measured at 51-112 ms across the runs in 07-08-SUMMARY.
const Duration _establish = Duration(seconds: 1);

/// How far apart the first and last panel of the herd may converge.
///
/// **Derived from the mechanism, not fitted to the measurement.** Once the
/// gateway is listening again, the longest any panel can wait is one draw from
/// its current backoff window, and that window is bounded by [_backoffCap] —
/// two seconds. The luckiest panel is one whose retry lands the instant the
/// gateway returns, at nearly zero. So the honest ceiling on the spread is
/// **one capped draw plus one establishment**, which is what this is.
///
/// Measured over six runs on this machine: 1599, 1664, 1704, 1710, 1813 and
/// 1899 ms — clustered just under the cap, which is the shape twenty
/// independent uniform draws from `[0, 2 s)` produce. The band sits 1.58x above
/// the observed worst and it is not fitted to it; the arithmetic above is what
/// sets it, and a change to `faultClientConfig`'s cap has to move it.
///
/// **What this catches and what it does not.** It catches a straggler: one
/// panel waiting a whole capped draw longer than the rest of the herd for the
/// same event, which is "no client starves (fairness across resync bursts)"
/// and which an averaging assertion would hide inside nineteen fast panels.
/// It does **not** catch a backoff that stopped spreading — measured, see
/// 07-08-SUMMARY's sabotage table: collapsing the cap onto the base makes all
/// twenty converge at the same millisecond, so the spread goes to **zero** and
/// a ceiling is structurally blind to it. That mutation is caught by the
/// attempt bound below, which is why both arms are here.
final Duration _fairnessBand = _backoffCap + _establish;

/// How many attempts a schedule that is **never reset** fits into [window].
///
/// Full jitter draws uniformly from `[0, min(cap, base * 2^n))`, so attempt *n*
/// waits half that window on average, and each attempt also costs a dial.
/// `resync_gate_test.dart:146-157`'s function, restated here for the same
/// reason its constants are: two files that shared it would share a mutation.
///
/// **A full-jitter schedule has no hard ceiling** — every draw can come back
/// near zero — so the only honest bound is this expectation with a margin, and
/// the margin is applied at the call site where it is visible.
int _attemptsIn(Duration window, Duration base, Duration cap, Duration cost) {
  var elapsed = 0;
  var attempts = 0;
  var next = base.inMilliseconds;
  while (elapsed < window.inMilliseconds) {
    attempts++;
    elapsed += next ~/ 2 + cost.inMilliseconds;
    final doubled = next * 2;
    next = doubled > cap.inMilliseconds ? cap.inMilliseconds : doubled;
  }
  return attempts;
}

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

  group('F10 — the gateway goes away and comes back', () {
    test('F10: a gateway that comes back on the same port is an ordinary '
        'reconnect', () async {
      final keys = _pageKeys(_restartPage).toSet();
      final fixture = await gateFixture(
        clients: 1,
        keys: keys,
        seed: (plant) =>
            plant.setValues({for (final key in keys) key: _beforeRestart}),
      );
      final panel = fixture.clients.single;

      // Anti-vacuity: the page was carrying the plant's pre-restart values
      // before the gateway was touched. A page that never held them cannot be
      // shown to have been rebuilt.
      expect(
          [for (final key in keys) panel.client.read(key)?.value],
          everyElement(_beforeRestart),
          reason: 'the panel did not hold the pre-restart value for every key, '
              'so "the page came back" below would be comparing the plant '
              'against keys that had never arrived in the first place');

      final epochBefore = fixture.server.sessions.sessions.single.epoch;
      final handlesBefore = fixture.server.handles.size;
      expect(handlesBefore, keys.length,
          reason: 'the gateway minted $handlesBefore handles for a page of '
              '${keys.length} keys. The handle table is keyed by key '
              '(`handle_table.dart:75`), so this is the number the rebuild is '
              'compared against and it has to be the page size before the '
              'comparison means anything');

      final retries = await fixture.restartGateway();

      // Read immediately, before the panel can have redialled: this is the
      // clause. `server` is the replacement — the getter re-reads the slot —
      // and the replacement has never heard of anybody.
      final sessionsAtRebind = fixture.sessionCount;
      final handlesAtRebind = fixture.server.handles.size;

      // The plant moves to a value it never held while the old gateway was
      // up, so a cache that survived the restart is a cache holding the wrong
      // number rather than a cache holding a stale-but-equal one.
      fixture.served
          .setValues({for (final key in keys) key: _afterRestart});

      final at = await fixture.untilAllRead(keys.first, _afterRestart);
      await until(
          'the whole page to agree with the plant after the restart',
          () => keys.every(
              (key) => panel.client.read(key)?.value == _afterRestart));

      final epochAfter = fixture.server.sessions.sessions.single.epoch;

      print('F10: rebind took $retries retries on port ${fixture.port}; the '
          'replacement held $sessionsAtRebind sessions and '
          '$handlesAtRebind handles at the instant it came up, '
          '${fixture.sessionCount} and ${fixture.server.handles.size} after '
          'the panel resubscribed; epoch $epochBefore -> $epochAfter; the '
          'panel reconverged in ${at.single} ms');

      expect(sessionsAtRebind, 0,
          reason: 'the replacement gateway came up already holding '
              '$sessionsAtRebind sessions. The row\'s clause is that the '
              'server holds no obligation to remember clients, and a gateway '
              'that started with a session in its registry would be serving a '
              'subscription nobody had asked it for — a stale subscription '
              'that looks live, which is T-07-28 exactly');
      expect(handlesAtRebind, 0,
          reason: 'the replacement gateway came up holding $handlesAtRebind '
              'handles. The handle table is the other half of the same '
              'memory: a table that survived the restart would let a `u` frame '
              'name a handle the new session never announced');

      expect(fixture.sessionCount, 1,
          reason: 'the panel reached its post-restart value but the gateway is '
              'holding ${fixture.sessionCount} sessions rather than one. The '
              'page was therefore not rebuilt from this panel\'s '
              're-subscribe, or the panel is holding two');
      expect(fixture.server.handles.size, keys.length,
          reason: 'the rebuilt page holds ${fixture.server.handles.size} '
              'handles against ${keys.length} keys. The subscription was '
              'rebuilt purely from the panel\'s re-subscribe, so the count has '
              'to be the page size — more means something was remembered');

      expect(epochAfter, isNot(epochBefore),
          reason: 'the replacement gateway minted the same epoch as the one it '
              'replaced ($epochAfter). The epoch is what tells the panel that '
              'the establishment it is talking to is a different one, and two '
              'gateways sharing an epoch is how a frame from the first is '
              'accepted by a client talking to the second');

      expect(panel.observedClose.closeCode, isNull,
          reason: 'the panel is sitting on a closed socket '
              '(${panel.observedClose}) after a restart it was supposed to '
              'have recovered from');
      expect(fixture.evictions, isEmpty,
          reason: 'the gateway threw the panel off during a restart: '
              '${fixture.evictions}. A restart drains with 4002 and that is '
              'not counted here — anything in this list is a heartbeat, a '
              'credential or a send buffer verdict, and none of them should '
              'fire because a gateway was replaced');
      expect(panel.client.complaints, isEmpty,
          reason: 'the panel complained during the restart: '
              '${panel.client.complaints}. A gateway coming back on the same '
              'port is an ordinary reconnect and F1 makes no complaints');
      expect(fixture.gatewayComplaints, isEmpty,
          reason: 'the gateway reported errors across the restart: '
              '${fixture.gatewayComplaints}');
    });
  });

  group('F11 — twenty of them at once', () {
    test('F11: twenty panels come back together without anybody starving',
        () async {
      final keys = _pageKeys(_restartPage).toSet();
      final fixture = await gateFixture(
        keys: keys,
        seed: (plant) =>
            plant.setValues({for (final key in keys) key: _beforeRestart}),
      );
      final n = fixture.clients.length;

      expect(fixture.sessionCount, n,
          reason: 'the herd is $n panels and the gateway is holding '
              '${fixture.sessionCount} sessions before anything was injected');
      final handlesBefore = fixture.server.handles.size;
      final attemptsBefore = [for (final one in fixture.clients) one.attempts];

      final retries = await fixture.restartGateway(downtime: _herdDowntime);
      final sessionsAtRebind = fixture.sessionCount;

      fixture.served
          .setValues({for (final key in keys) key: _afterRestart});

      final at = await fixture.untilAllRead(keys.first, _afterRestart);
      final spread = at.reduce((a, b) => a > b ? a : b) -
          at.reduce((a, b) => a < b ? a : b);
      final attempts = [
        for (var i = 0; i < n; i++)
          fixture.clients[i].attempts - attemptsBefore[i],
      ];
      final totalAttempts = attempts.reduce((a, b) => a + b);
      final ceiling = _attemptsIn(
              _herdDowntime, _backoffBase, _backoffCap, _attemptOverhead) *
          2;

      print('F11: $n panels, ${_herdDowntime.inMilliseconds} ms of downtime, '
          '$retries rebind retries; convergence instants (ms from the '
          'restart) $at; spread $spread ms against a '
          '${_fairnessBand.inMilliseconds} ms band; reconnect attempts per '
          'panel $attempts (total $totalAttempts, ceiling '
          '${ceiling * n} for a schedule that never resets)');

      // ALL RESUBSCRIBE. Not `isReady`, which a panel reaches before its
      // snapshot lands: every one of them has to be holding a value the plant
      // set *after* the gateway it was talking to stopped existing.
      for (final one in fixture.clients) {
        expect(
            [for (final key in keys) one.client.read(key)?.value],
            everyElement(_afterRestart),
            reason: 'panel ${one.index} came back holding '
                '${[for (final key in keys) one.client.read(key)?.value]} '
                'against a plant at $_afterRestart. The row\'s first clause is '
                '"all resubscribe", and a panel that reconnected without '
                'resyncing is the silent-permanent-staleness case with twenty '
                'chances to happen instead of one');
      }

      // FAIRNESS. The spread, not the mean: nineteen panels back in 200 ms and
      // one back in nine seconds is the starvation this row forbids, and an
      // averaging assertion reports it as a healthy herd.
      expect(spread, lessThan(_fairnessBand.inMilliseconds),
          reason: 'the first panel converged at ${at.reduce((a, b) => a < b ? a : b)} '
              'ms and the last at ${at.reduce((a, b) => a > b ? a : b)} ms, a '
              'spread of $spread ms against a '
              '${_fairnessBand.inMilliseconds} ms band. One panel waiting far '
              'longer than the herd for the same event is what "no client '
              'starves (fairness across resync bursts)" forbids');

      // THE MECHANISM THAT SPREADS THE HERD. Full jitter is why twenty panels
      // do not arrive as one connection flood, and the bound is on the attempt
      // count rather than on an interval because a full-jitter draw has no
      // floor — 07-06 deviation 3 measured four consecutive last-intervals at
      // 848, 264, 753 and 419 ms and concluded that any band tight enough to
      // catch a broken schedule also catches a legitimate low draw.
      expect(totalAttempts, lessThan(ceiling * n),
          reason: 'the herd made $totalAttempts reconnect attempts across '
              '${_herdDowntime.inMilliseconds} ms of downtime, against a '
              'ceiling of ${ceiling * n} for $n panels on a schedule that is '
              'never reset. This is the self-inflicted connection flood '
              '(T-07-25): the backoff is the only thing between a gateway '
              'restart and every panel in the plant dialling it at once');

      // NO LEAKS. The descriptor half is the control arm's, for the reason the
      // library doc gives; what is asserted here is the gateway's own memory.
      expect(sessionsAtRebind, 0,
          reason: 'the replacement gateway came up holding $sessionsAtRebind '
              'sessions');
      expect(fixture.sessionCount, n,
          reason: 'the gateway is holding ${fixture.sessionCount} sessions at '
              'steady state against $n panels. More than $n means a session '
              'from before the restart is still registered — the gateway '
              'remembering a client it has no obligation to remember, and '
              'ticking for a socket nobody is reading');
      expect(fixture.server.handles.size, handlesBefore,
          reason: 'the handle table holds ${fixture.server.handles.size} '
              'handles after the restart against $handlesBefore before it. '
              'The table is keyed by key and not by session, so $n panels on '
              'one page cost ${keys.length} handles however many times they '
              'reconnect — a number that grew with the herd would be a '
              'per-client leak in the one structure that is supposed to be '
              'shared');

      // NO VERDICT MISFIRES. ROADMAP criterion 4's first clause.
      expect([for (final one in fixture.clients) one.observedClose.closeCode],
          everyElement(isNull),
          reason: 'these panels are sitting on closed sockets after the herd '
              'reconverged: ${fixture.observedCloses}');
      expect(fixture.evictions, isEmpty,
          reason: 'the gateway threw ${fixture.evictions.length} panels off '
              'while twenty of them were reconnecting: ${fixture.evictions}. '
              'A herd arriving at once is load, not misbehaviour, and a '
              'heartbeat or backpressure verdict firing here is the gateway '
              'punishing panels for the gateway\'s own restart');

      // ESCAPED ASYNC ERRORS. Twenty reconnecting panels is exactly the shape
      // that leaks one.
      expect(fixture.gatewayComplaints, isEmpty,
          reason: 'the gateway reported '
              '${fixture.gatewayComplaints.length} errors while the herd '
              'reconnected: ${fixture.gatewayComplaints}');
      for (final one in fixture.clients) {
        expect(one.client.complaints, isEmpty,
            reason: 'panel ${one.index} complained during the herd restart: '
                '${one.client.complaints}');
      }

      // SERVER COST is cited, not re-run. `fanout_test.dart:80-120` drives
      // fifty sessions through the gateway's encode-once path and proves one
      // encode serves every session watching the same key. Those sessions have
      // no sockets, which is why this file exists — and it is also why
      // re-running the encode-once claim over twenty real sockets would
      // measure loopback rather than the property.
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  group('the gateway\'s unauthenticated slots, measured', () {
    test('a session that never says hello holds a slot until the reaper takes '
        'it', () async {
      final keys = _pageKeys(1).toSet();
      final fixture = await gateFixture(
        clients: 1,
        keys: keys,
        seed: (plant) =>
            plant.setValues({for (final key in keys) key: _beforeRestart}),
      );
      final authenticated = fixture.sessionCount;

      // Real WebSocket upgrades that complete and then say nothing. A raw TCP
      // connect would not do: the gateway mints a `RelaySession` at the
      // upgrade, so a socket that never became a WebSocket never took a slot.
      const silent = 4;
      final quiet = <WebSocketChannel>[];
      for (var i = 0; i < silent; i++) {
        final ws =
            WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:${fixture.port}'));
        await ws.ready;
        ws.stream.listen((_) {}, onError: (Object _) {}, cancelOnError: true);
        quiet.add(ws);
      }
      addTearDown(() async {
        for (final ws in quiet) {
          await ws.sink.close().catchError((Object _) {});
        }
      });

      final held = Stopwatch()..start();
      await until(
        'the gateway to register all $silent silent sockets as sessions',
        () => fixture.unauthenticatedSlots >= silent,
      );
      final peak = fixture.unauthenticatedSlots;

      // The only assertion: the reaper does eventually take them. The ceiling
      // itself is not enforced — 07-CONTEXT orchestrator ruling 4 — and the
      // two numbers printed below are the input to whether `maxSessions`
      // belongs in `ServerConfig` at all.
      await until(
        'the heartbeat reaper to take every unauthenticated session',
        () => fixture.unauthenticatedSlots == 0,
        budget: const Duration(seconds: 20),
      );
      held.stop();

      print('unauthenticated slots: $peak sockets completed the WebSocket '
          'upgrade and never said hello, held beside $authenticated '
          'authenticated sessions; the reaper took the last of them '
          '${held.elapsedMilliseconds} ms after they connected, against a '
          '6000 ms heartbeat deadline. The emergent bound is connect rate x '
          'that deadline; nothing enforces a ceiling and nothing here asks '
          'for one');

      expect(peak, silent,
          reason: 'the gateway registered $peak unauthenticated sessions for '
              '$silent silent sockets. If it registers fewer than one slot per '
              'socket then the number this arm reports is not the bound it '
              'claims to be measuring');
      expect(fixture.sessionCount, authenticated,
          reason: 'the reaper took the silent sessions and left '
              '${fixture.sessionCount} rather than the $authenticated '
              'authenticated ones. A reaper that also took the panel would be '
              'reaping on the wrong predicate');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
