/// The resilience catalogue, in the tree, as data.
///
/// **Why this file exists.** The F1-F28 scenario catalogue lives in
/// `relay-websocket-notes.md` §7.5-7.9 at the main checkout root. That file is
/// untracked, so it is absent from every worktree an executor or a reviewer
/// ever opens, and STATE.md has carried "phases 7, 9 and 11 need it on hand"
/// as a standing concern since Phase 5. This file is the in-tree copy of the
/// rows Phase 7 gates: F1-F21 transcribed character-for-character from
/// `07-RESEARCH.md`'s embedded §7.5 table, and G1-G6 from
/// `07-RESEARCH-PUBSUB.md` §D.1. Nobody needs the external file again to audit
/// this gate.
///
/// The [GateRow.expectation] strings are deliberately **not** wrapped across
/// adjacent literals. A wrapped literal is byte-identical at runtime and not
/// byte-identical on disk, and the whole value of this file is that
/// `grep -F 'no burst of backlogged frames on recovery'` finds the same bytes
/// here, in the research file, and in the case that quotes it.
///
/// **Three declarations, three jobs.**
///
/// [gateRows] is the catalogue. [gateOutstanding] is what the phase has not
/// delivered yet, one entry per undelivered row, each naming the plan that owes
/// it — every plan deletes its own entries in the same commit that lands its
/// rows, and 07-13 asserts the map is empty. [gateDeviations] is the part that
/// keeps the gate honest: every catalogue clause the phase's green does **not**
/// cover, with the reason and where it goes instead.
///
/// **Why an outstanding list rather than a red suite.** 07-RESEARCH §F.6 asks
/// for the manifest to land red, listing the rows nobody has written yet. A
/// permanently red test makes every intermediate plan's phase gate red, and a
/// phase whose own gate is red cannot tell a new failure from a known one — the
/// run report stops being read, which is the failure mode the gate exists to
/// prevent one level up. So the red list is produced once, by running the
/// manifest with this map emptied, and recorded verbatim in 07-01-SUMMARY.md;
/// after that the same information lives here, where it is machine-checked in
/// both directions and shrinks by deletion. This is
/// `fault_contract_test.dart:228-238`'s "the reachable set and the named gap
/// account for every check" doctrine, applied to a catalogue instead of a
/// contract suite.
library;

/// One row of the catalogue.
final class GateRow {
  const GateRow({
    required this.id,
    required this.scenario,
    required this.injection,
    required this.expectation,
    required this.quoteAnchor,
  });

  /// `F1`…`F21`, `G1`…`G6`. The name an auditor reads in the catalogue and
  /// searches for in `test/gate/`.
  final String id;

  /// The row's short name — the catalogue's Scenario column, with the table's
  /// emphasis markers dropped because a short name is not quoted anywhere.
  final String scenario;

  /// The lever the catalogue names.
  ///
  /// For F1-F21 this is §7.5's Injection column, verbatim — which matters,
  /// because five of the nine seeded deviations are about the injection rather
  /// than the expectation (F2's and F17's durations, F6's cut, F7's lever,
  /// F10's process boundary) and a deviation is only checkable against text
  /// nobody paraphrased.
  ///
  /// For G1-G6 §D.1 has **no** injection column — the lever is named inside
  /// the scenario cell — so this is a summary, not a quotation. That is why
  /// [verbatimText] excludes it for those rows.
  final String injection;

  /// The catalogue's Expect column, verbatim.
  ///
  /// §D.1 has no Expect column either: for G1-G6 the assertion *is* the whole
  /// Scenario cell, so that cell is carried here verbatim, emphasis markers
  /// and all.
  final String expectation;

  /// A short distinctive fragment of [expectation] (or, where the row's
  /// operative text is the lever, of [injection]) that the file holding this
  /// row's case must contain.
  ///
  /// This is how the manifest checks that a case *quotes* its catalogue line
  /// instead of paraphrasing it. Each anchor is short enough to survive an
  /// 80-column doc comment on one line, and distinctive enough that it cannot
  /// arrive in a file by accident.
  final String quoteAnchor;

  /// The catalogue text a [Deviation.clause] for this row must be a substring
  /// of — every field of this row that was copied out of a source table rather
  /// than written here.
  ///
  /// [injection] is in the list for F-rows and not for G-rows, for the reason
  /// its own doc gives: §7.5 has an Injection column and §D.1 does not. Letting
  /// a clause quote a G-row's injection would let it quote a sentence this file
  /// composed, which is the paraphrase the substring rule exists to forbid.
  List<String> get verbatimText =>
      id.startsWith('F') ? [injection, expectation] : [expectation];
}

/// Whether a row has no case at all, or a case that does not yet judge all of
/// it.
enum OutstandingKind {
  /// No case in `test/gate/` names this row.
  missing,

  /// A case exists and named clauses of the row are not yet asserted.
  partial,
}

/// One row the phase has not finished, and who owes it.
final class Outstanding {
  const Outstanding({
    required this.kind,
    required this.owner,
    required this.clause,
  });

  final OutstandingKind kind;

  /// The plan id that owes this row, `07-\d\d`, from 07-PLAN-INDEX.md's
  /// row-to-plan table.
  final String owner;

  /// What is not yet judged.
  final String clause;
}

/// One catalogue clause the phase's green does not cover.
final class Deviation {
  const Deviation({
    required this.row,
    required this.clause,
    required this.reason,
    required this.followUp,
  });

  /// A row id that [gateRows] declares.
  final String row;

  /// A verbatim substring of one of that row's [GateRow.verbatimText] strings.
  /// Paraphrase it and nobody can check the deviation against the catalogue,
  /// which is the only thing an entry here is for.
  final String clause;

  /// Why the green does not cover it. A descope with a measurement is a
  /// finding; one without is an excuse.
  final String reason;

  /// Where it goes instead: `Phase 8`, `Phase 9`, `Phase 11`,
  /// `post-milestone`, or `none — accepted`. A closed set, because an
  /// open-ended follow-up field becomes a wishlist within two phases.
  final String followUp;
}

/// The twenty-seven rows Phase 7 gates.
///
/// F1-F21 from `07-RESEARCH.md`'s embedded §7.5 scenario matrix; G1-G6 from
/// `07-RESEARCH-PUBSUB.md` §D.1. The five rules the Expect column refers to
/// (§7.3): (1) two-layer liveness — `pingInterval` **and** an app-level
/// data-freshness deadline; (2) resync on reconnect, not resume — current
/// values for every subscribed key, never deltas; (3) never auto-retry writes;
/// (4) staleness is per-value and visible; (5) design the whole-screen-
/// disconnected state deliberately.
///
/// §D.1's table has no separate Expect column — the assertion is the whole
/// Scenario cell — so for G1-G6 [GateRow.expectation] carries that cell
/// verbatim, emphasis markers and all.
const List<GateRow> gateRows = <GateRow>[
  GateRow(
    id: 'F1',
    scenario: 'Clean drop, single reconnect',
    injection: '`killOnce()`',
    expectation: 'client reconnects with backoff; full resync (rule 2); banner shown and cleared',
    quoteAnchor: 'full resync (rule 2); banner shown and cleared',
  ),
  GateRow(
    id: 'F2',
    scenario: 'Dropout every other second',
    injection: '`flap(1s, 1s)` for 60 s',
    expectation: 'no crash, no unbounded memory/log growth, no reconnect storm (backoff caps attempt rate); UI shows disconnected — never flickers stale values as fresh during the 1 s up-windows unless resync completed',
    quoteAnchor: 'no reconnect storm (backoff caps attempt rate)',
  ),
  GateRow(
    id: 'F3',
    scenario: 'Fast flap, shorter than handshake',
    injection: '`flap(200ms, 200ms)`',
    expectation: 'reconnect attempts that never complete subscribe are discarded cleanly; generation counter (§7.2) prevents a half-finished session\'s callbacks touching state',
    quoteAnchor: 'never complete subscribe are discarded cleanly',
  ),
  GateRow(
    id: 'F4',
    scenario: 'Asymmetric half-open',
    injection: '`bufferServerToClient`',
    expectation: 'app-level freshness deadline fires (rule 1); all values grey out (rule 4) even though socket looks connected',
    quoteAnchor: 'all values grey out (rule 4)',
  ),
  GateRow(
    id: 'F5',
    scenario: 'True half-open both ways',
    injection: '`blackhole()`',
    expectation: '`pingInterval` closes the socket within its deadline; freshness deadline fires first or concurrently; no wait for TCP timeouts (minutes)',
    quoteAnchor: 'no wait for TCP timeouts (minutes)',
  ),
  GateRow(
    id: 'F6',
    scenario: 'Drop during in-flight write',
    injection: 'subscribe, then `cutMidFrame()` on the write request',
    expectation: 'write completes with **unknown** outcome surfaced to caller; never auto-retried (rule 3); reconnect does NOT replay it',
    quoteAnchor: 'reconnect does NOT replay it',
  ),
  GateRow(
    id: 'F7',
    scenario: 'Drop between write sent and response',
    injection: '`blackhole()` right after write frame forwarded',
    expectation: 'same as F6 — outcome unknown, surfaced, not replayed',
    quoteAnchor: 'outcome unknown, surfaced, not replayed',
  ),
  GateRow(
    id: 'F8',
    scenario: 'Value changes during outage',
    injection: 'drop, change key server-side, reconnect',
    expectation: 'resync delivers the new value (rule 2) — the silent-permanent-staleness case; assert the *changed-while-down* key, not just any key',
    quoteAnchor: 'the silent-permanent-staleness case',
  ),
  GateRow(
    id: 'F9',
    scenario: 'Drop during resync',
    injection: 'drop, reconnect, drop again mid-resync burst, reconnect',
    expectation: 'second resync is complete and consistent; no key left with pre-first-drop value',
    quoteAnchor: 'no key left with pre-first-drop value',
  ),
  GateRow(
    id: 'F10',
    scenario: 'Server process restart',
    injection: 'kill/restart real server behind proxy',
    expectation: 'client treats it as F1; server rebuilds subscription state from client\'s re-subscribe (server holds no obligation to remember clients)',
    quoteAnchor: 'no obligation to remember clients',
  ),
  GateRow(
    id: 'F11',
    scenario: 'Thundering herd',
    injection: '20+ clients, restart server',
    expectation: 'all resubscribe; server tick cost stays bounded; no client starves (fairness across resync bursts)',
    quoteAnchor: 'no client starves (fairness across resync bursts)',
  ),
  GateRow(
    id: 'F12',
    scenario: 'Slow client / backpressure',
    injection: 'one client behind `throttle(10KB/s)`, values at 10 Hz',
    expectation: 'server buffer for that client stays bounded via conflation (§7.6); other clients unaffected',
    quoteAnchor: 'bounded via conflation (§7.6); other clients unaffected',
  ),
  GateRow(
    id: 'F13',
    scenario: 'High latency',
    injection: '`latency(500ms, 200ms)`',
    expectation: 'no false disconnects: ping and freshness deadlines tolerate configured RTT; staleness age (rule 4) reflects real delay',
    quoteAnchor: 'staleness age (rule 4) reflects real delay',
  ),
  GateRow(
    id: 'F14',
    scenario: 'Connect refused vs connect timeout',
    injection: '`reject()` vs blackhole pre-connect',
    expectation: 'both paths reach the same backoff loop; Windows-specific: `reject()` keeps ServerSocket open to get fast `ECONNREFUSED`',
    quoteAnchor: 'both paths reach the same backoff loop',
  ),
  GateRow(
    id: 'F15',
    scenario: 'TLS handshake failure',
    injection: 'proxy to a plain-TCP port / wrong cert',
    expectation: 'clear terminal error, no reconnect-forever at full speed against a misconfigured endpoint',
    quoteAnchor: 'no reconnect-forever at full speed',
  ),
  GateRow(
    id: 'F16',
    scenario: 'Client suspend/resume',
    injection: 'SIGSTOP client process 30 s, SIGCONT',
    expectation: 'on resume: detects staleness immediately, reconnects or resyncs; no burst of queued stale timers acting on dead state (generation counter again)',
    quoteAnchor: 'no burst of queued stale timers acting on dead state',
  ),
  GateRow(
    id: 'F17',
    scenario: 'Long outage',
    injection: '`blackhole()` 10 min',
    expectation: 'client memory bounded (no queued writes piling up), server released the dead session; reconnect after works',
    quoteAnchor: 'server released the dead session',
  ),
  GateRow(
    id: 'F18',
    scenario: 'Duplicate/stale frames after reconnect',
    injection: 'scripted server sends old-epoch `values` after resync',
    expectation: 'client discards frames from a previous connection epoch — epoch/generation id in the protocol, asserted here',
    quoteAnchor: 'frames from a previous connection epoch',
  ),
  GateRow(
    id: 'F19',
    scenario: 'Slow link, fits',
    injection: '`throttle(1 Mbit/s)`, busy 200-key page at 10 Hz (~0.58 Mbit/s)',
    expectation: 'full cadence sustained; bounded latency (assert p99); no conflation needed; `PIPE.link_degraded` stays false',
    quoteAnchor: 'no conflation needed; `PIPE.link_degraded` stays false',
  ),
  GateRow(
    id: 'F20',
    scenario: 'Slow link, doesn\'t fit',
    injection: '`throttle(100 kbit/s)`, same page (needs ~5.8x the link)',
    expectation: 'conflation engages: reduced cadence, every delivered value is the *latest* (never an old queued one — assert with a monotonically incremented test key); queue stays bounded; writes/RPC responses still complete promptly via the priority lane; `PIPE.link_degraded` + `PIPE.effective_hz` reflect it and an AlarmMan alarm fires (§7.7)',
    quoteAnchor: 'every delivered value is the *latest*',
  ),
  GateRow(
    id: 'F21',
    scenario: 'Slow link recovers',
    injection: '`throttle(100 kbit/s)` 60 s, then unthrottle',
    expectation: 'conflation disengages, cadence returns to 10 Hz, `PIPE.link_degraded` clears, alarm auto-resolves; no burst of backlogged frames on recovery (the conflating map means there is no backlog to flush)',
    quoteAnchor: 'no burst of backlogged frames on recovery',
  ),
  GateRow(
    id: 'G1',
    scenario: 'Silent divergence goes undetected while the plant is quiet',
    injection: 'MalformedPeer corrupting one frame\'s body, then a quiet plant',
    expectation: '**Silent divergence goes undetected while the plant is quiet.** Force the client to drop one `u` (MalformedPeer corrupting one frame\'s body), then hold every subscribed value constant so no further `u` is produced. Assert the view goes **stale or resyncs** within the deadline. Today it will report **fresh** — the test is expected to fail first.',
    quoteAnchor: 'the view goes **stale or resyncs** within the deadline',
  ),
  GateRow(
    id: 'G2',
    scenario: 'Late joiner under sustained loss',
    injection: 'subscribe while throttled to 100 kbit and flapping',
    expectation: '**Late joiner under sustained loss.** A client subscribing while the link is throttled to 100 kbit and flapping must still reach a fresh, complete view — the snapshot must not be starved by telemetry. Assert the `subscribe` response (priority lane) beats the `u` backlog.',
    quoteAnchor: 'the snapshot must not be starved by telemetry',
  ),
  GateRow(
    id: 'G3',
    scenario: 'Resync storm / gap thrash',
    injection: 'repeated seq gaps (F9\'s drop-during-resync)',
    expectation: '**Resync storm / gap thrash.** Induce repeated seq gaps (F9\'s drop-during-resync, which `07-PATTERNS.md` marks *missing*) and assert resyncs are **coalesced, not stacked** — one in-flight resync per subscription, backoff not reset until it completes, and no unbounded growth in `_inFlight`.',
    quoteAnchor: 'resyncs are **coalesced, not stacked**',
  ),
  GateRow(
    id: 'G4',
    scenario: 'Seq gap across a generation change',
    injection: 'subscribe-on-existing-id re-establish, then an old-generation frame',
    expectation: '**Seq gap across a generation change.** A subscribe-on-existing-id re-establish drops the old send-buffer lane; assert a frame from generation *g* arriving after the snapshot for *g+1* is discarded (BatchReplay), and that the client does **not** count it as a gap and resync again.',
    quoteAnchor: 'does **not** count it as a gap and resync again',
  ),
  GateRow(
    id: 'G5',
    scenario: 'Conflation is not eviction',
    injection: 'held above the ceiling every tick, and held just under it for 40 ticks',
    expectation: '**Conflation is not eviction** (the NATS/Redis two-tier boundary). Paired assertions: held above the ceiling every tick ⇒ evicted with the peak verdict; held just under it for 40 ticks ⇒ **never** evicted and always receiving the latest value.',
    quoteAnchor: 'held just under it for 40 ticks ⇒ **never** evicted',
  ),
  GateRow(
    id: 'G6',
    scenario: 'Slow link recovers',
    injection: 'throttle 60 s, then un-throttle',
    expectation: '**Slow link recovers.** F21 currently has no un-throttle arm (`07-PATTERNS.md`). Throttle 60 s, un-throttle, assert the client converges to current values with **no backlog flush** — the conflating map means recovery has nothing queued to drain.',
    quoteAnchor: 'converges to current values with **no backlog flush**',
  ),
];

/// The rows this phase has not delivered yet, keyed by row id.
///
/// Seeded with all twenty-seven as [OutstandingKind.missing], each owned by the
/// plan 07-PLAN-INDEX.md's row-to-plan table assigns it. **Every later plan
/// deletes its own entries in the same commit that lands its rows**, and 07-13
/// asserts this map is empty — that assertion is the phase's own closing
/// condition.
///
/// A [OutstandingKind.partial] entry is for a row that *has* a case whose named
/// clauses are not all asserted yet. A partial entry for a row with no case is
/// a missing entry wearing the wrong label, and the manifest says so.
const Map<String, Outstanding> gateOutstanding = <String, Outstanding>{
  'F10': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-08',
    clause: 'the same-port close and rebind, and what the new epoch proves '
        'about server-side memory',
  ),
  'F11': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-08',
    clause: 'twenty clients over real sockets: convergence spread as a band, '
        'no evictions, the fd baseline restored',
  ),
  'F12': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-08',
    clause: 'the isolation clause — one throttled client, the other\'s cadence '
        'band unchanged',
  ),
  'F13': Outstanding(
    kind: OutstandingKind.partial,
    owner: '07-11',
    clause: 'the *age* half of "staleness age (rule 4) reflects real delay". '
        '07-05 uprated the case to the catalogue\'s 500 ms ± 200 ms and added '
        'the operator-visible clause it could assert — that no staleness or '
        'link transition occurs at all across a slow window, judged over '
        'collected transitions and corroborated by a provoked one. What it '
        'could not assert is an age *number*, because the client publishes '
        'none: viewIsStale and staleSubscriptions are a boolean and a set, and '
        'DynamicValue.sourceTime is null on this path (measured). The only '
        'per-subscription age in the client is FreshnessWatchdog._evaluatedAt, '
        'kept in the gateway\'s clock and exposed solely as the verdict '
        'derived from it (freshness_watchdog.dart:217). 07-11 wires the '
        'staleness surface (07-CONTEXT ruling 1); when it carries an age, this '
        'row asserts that the age tracks the injected delay. No getter was '
        'invented here to make the clause look asserted',
  ),
  'F15': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-12',
    clause: 'the six TLS arms, the wss smoke row and the auth contrast',
  ),
  'F16': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-09',
    clause: 'the Isolate.pause harness and the resume assertions, with a '
        'per-platform capability probe',
  ),
  'F17': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-09',
    clause: 'the client half: structural memory bounds, the session reaped, '
        'and reconnect-after-works',
  ),
  'F19': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-10',
    clause: 'the 200-key page at 10 Hz on 1 Mbit, p99 inter-frame interval, no '
        'verdict fires',
  ),
  'F20': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-11',
    clause: 'the four assertable clauses plus the honesty arm on the newly '
        'wired staleness surface; two clauses stay in gateDeviations',
  ),
  'F21': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-11',
    clause: 'the recovery: cadence returns, staleness clears, and the burst '
        'measured rather than banded away',
  ),
  'G1': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-07',
    clause: 'two divergence arms and two control arms, then the tick-sequence '
        'fix and resync-on-unknown-handle',
  ),
  'G2': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-08',
    clause: 'the late joiner reaching a complete view over a throttled, '
        'flapping link',
  ),
  'G5': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-10',
    clause: 'the paired boundary over a real socket, plus the text arm '
        'protecting the server-side pair',
  ),
  'G6': Outstanding(
    kind: OutstandingKind.missing,
    owner: '07-11',
    clause: 'recovery with no backlog flush, asserted honestly',
  ),
};

/// Every catalogue clause the phase's green will **not** cover.
///
/// "Twenty-seven green" is a claim. "Twenty-seven green, and here are the
/// clauses that green does not assert" is a document. RES-01's checkbox
/// evidence (07-RESEARCH §F.5 item 3) is this list quoted in the verification
/// document, which is why the manifest prints it as a formatted block on every
/// run rather than only asserting over it.
///
/// Later plans **append**. None may delete an entry without saying what now
/// asserts the clause — a deletion with no replacement assertion is the gate
/// quietly widening its own promise.
const List<Deviation> gateDeviations = <Deviation>[
  Deviation(
    row: 'F20',
    clause: 'queue stays bounded',
    reason: 'the §7.6 design rule this clause rests on — drain the conflating '
        'map "only if the socket\'s previous write actually completed" — is '
        'not implementable on this transport as measured. 07-RESEARCH §B.3: '
        '700 KB pushed onto a 100 kbit/s link returned in 5 ms with zero bytes '
        'received and RSS up 2.9 MB, on both sink.add and await '
        'sink.addStream, so dart:io offers no egress-completion signal to gate '
        'the drain on and "bounded" cannot be asserted from inside the client. '
        'A descope with a number is a finding; one without is an excuse.',
    followUp: 'post-milestone',
  ),
  Deviation(
    row: 'F20',
    clause: '`PIPE.link_degraded` + `PIPE.effective_hz` reflect it and an AlarmMan alarm fires (§7.7)',
    reason: 'the PIPE.* health keys ship with upstream fan-in, not with the '
        'transport: they are produced by the upstream layer and there is no '
        'AlarmMan wiring in the pipe yet. Roadmap decision, recorded in '
        'PROJECT.md. What replaces it here is the honesty arm on the staleness '
        'surface — a starved subscription renders stale, which is the operator-'
        'visible half of the clause.',
    followUp: 'Phase 8',
  ),
  Deviation(
    row: 'F19',
    clause: '`PIPE.link_degraded` stays false',
    reason: 'same surface, same phase: the key does not exist yet, so "stays '
        'false" would be asserted about nothing. F19 asserts the observable '
        'the key would be derived from — full cadence sustained and a bounded '
        'p99 inter-frame interval — and the negative-verdict arm stands in for '
        'the flag until the flag exists.',
    followUp: 'Phase 8',
  ),
  Deviation(
    row: 'F21',
    clause: '`PIPE.link_degraded` clears, alarm auto-resolves',
    reason: 'the clearing half of the same unbuilt surface. F21 asserts that '
        'the cadence returns and that the client-side staleness the phase does '
        'wire clears on recovery; the flag and the alarm auto-resolution '
        'arrive with the health keys and their AlarmMan binding.',
    followUp: 'Phase 8',
  ),
  Deviation(
    row: 'F2',
    clause: '`flap(1s, 1s)` for 60 s',
    reason: 'the default lane runs the flap for 20 s — twenty transitions, '
        'which is enough for a backoff storm or a per-cycle leak to show as a '
        'rate rather than as a single sample, which is teardown_test.dart\'s '
        'checkpoint doctrine applied to time. The full 60 s runs behind '
        'RELAY_SOAK. 07-CONTEXT user ruling 2; declared here rather than '
        'quietly applied, because a gate that silently shortens its own '
        'scenarios is the "capability switched off" failure in another '
        'register.',
    followUp: 'none — accepted',
  ),
  Deviation(
    row: 'F17',
    clause: '`blackhole()` 10 min',
    reason: 'the default lane blackholes for 30 s, which exceeds the 6 s '
        'heartbeat deadline five times over — the mechanism the row is about '
        'is the server releasing a dead session, and it fires at the first '
        'deadline, not at the tenth minute. Ten minutes does not fit an 8-'
        'minute lane budget. The full duration runs behind RELAY_SOAK. '
        '07-CONTEXT user ruling 2.',
    followUp: 'none — accepted',
  ),
  Deviation(
    row: 'F6',
    clause: 'subscribe, then `cutMidFrame()` on the write request',
    reason: 'the cut arm stays on the plaintext leg and is not repeated under '
        'TLS. The proxy counts wire bytes, so under TLS cutMidFrame(n) '
        'truncates a TLS record and the connection dies at the record layer — '
        'the WebSocket layer never sees a partial application frame, so the '
        'row\'s actual injection is unreachable there. 06-RESEARCH §C.4; '
        '07-CONTEXT orchestrator ruling 3.',
    followUp: 'none — accepted',
  ),
  Deviation(
    row: 'F6',
    clause: 'on the write request',
    reason: 'the cut lands on the *response*, not the request, because '
        'cutMidFrame arms the server→client line only — deliberately, and for '
        'a reason recorded at fault_proxy.dart:973-977: a cut counted across '
        'both directions would fire on the client\'s own request bytes and end '
        'the connection before the response existed. No lever in this '
        'repository truncates client→server, so a partial frame reaching the '
        '*gateway\'s* decoder is unreachable and the case delivers one to the '
        'client\'s instead. The row loses nothing an operator feels: because '
        'the request arrives whole the plant genuinely moves, so the case '
        'asserts the harder half — the caller is told "unknown" about a write '
        'that did happen, and the plant\'s attempt counter is 1 before and '
        'after the recovery. Measured in 07-05: cutting at half a measured '
        '125-byte frame kills the link in under 100 ms with upstream attempts '
        'at exactly 1.',
    followUp: 'none — accepted',
  ),
  Deviation(
    row: 'F7',
    clause: '`blackhole()` right after write frame forwarded',
    reason: 'the lever is killOnce after a stalled write, not blackhole. '
        'Recorded at write_in_flight_gate_test.dart:23-41: a blackhole swallows '
        'both directions, so the client\'s own close never reaches the gateway '
        'and the replacement session has to establish beside a session the '
        'gateway still believes in — one run in four wedged the reconnect past '
        'a fifteen-second budget. killOnce injects the same observable (the '
        'link dies with the write upstream) deterministically.',
    followUp: 'none — accepted',
  ),
  Deviation(
    row: 'F10',
    clause: 'kill/restart real server behind proxy',
    reason: 'the restart is an in-process RelayServer close and rebind on the '
        'same port, not a process boundary. It still proves the row\'s whole '
        'operational content — a new epoch, no client state remembered across '
        'it, and a subscription map rebuilt purely from the client\'s '
        're-subscribe (07-RESEARCH §F.2). A real process boundary needs a tier '
        'this project does not have; it belongs to the chaos soak.',
    followUp: 'Phase 11',
  ),
];
