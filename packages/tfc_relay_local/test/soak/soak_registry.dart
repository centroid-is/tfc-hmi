/// The soak's ledger of record: what it checks, and where it departs from the
/// catalogue's own words.
///
/// **This is deliberately not a registry of rows.** 11-RESEARCH §F.1 says it
/// in one sentence — *the soak must not have a manifest of rows* — because a
/// row table is the gate's shape, and copying it here would recreate gate A at
/// length instead of adding the thing the soak exists for. Gates A and B keep
/// the per-scenario evidence, one case per catalogue line. What the soak owns
/// is that those behaviours survive being **interleaved** for thirty-five
/// minutes, and the artifact analogous to `gate_manifest_test.dart`'s row
/// audit is therefore this file's two lists:
///
///  * [declaredCheckers] — the five invariants plus the divergence ledger,
///    audited by `judgedSamples >= minimumSamplesForAVerdict` rather than by a
///    row count, and swept in reverse so that a sixth checker cannot appear
///    without the audit knowing about it.
///  * [soakDeviations] — every place this phase does something other than what
///    `relay-websocket-notes.md` §7.8 literally says, with the clause quoted
///    **verbatim**, the number used instead, and the argument.
///
/// **Why the deviations are seeded on day one rather than collected at the
/// end.** 09-01 put its registry first and 07-13 explains why: a departure
/// applied silently is a departure the next reader believes never happened,
/// and by the end of a phase nobody can reconstruct which of the numbers in
/// the code were chosen and which were inherited. All five below were decided
/// at the discuss gate (11-CONTEXT rulings 2 and 3) or forced by a measurement
/// somebody already made, and every one of them is written down before a
/// single fault fires.
///
/// **None of the five is a descope.** Two of them (2 and 3) are *measured
/// refutations* of the catalogue text in the gate-A sense: §7.8 asks for
/// something this repository has already proved cannot be asserted honestly,
/// and the entry carries the measurement that proves it. The other three are
/// scope statements — a duration, a platform and a deployment tier — each of
/// which changes where the evidence comes from and none of which changes what
/// is being claimed.
///
/// The counts are **not** in this file. `soak_manifest_test.dart` writes down
/// how many entries and how many checker names it expects, for
/// `gate_manifest_test.dart:44-50`'s reason: a sweep that derives both sides
/// of its comparison from the same source asserts nothing, and an entry
/// deleted here would take its own count with it.
library;

// ---------------------------------------------------------------- the checkers

/// Invariant 1 — no value is rendered fresh whose age exceeds its deadline.
const String freshnessHonesty = 'freshnessHonesty';

/// Invariant 2 — every write reaches exactly one terminal state.
const String terminalStateWrites = 'terminalStateWrites';

/// Invariant 3 — after each stable window, every subscribed key equals plant
/// truth.
const String eventualResync = 'eventualResync';

/// Invariant 4 — client and server structures stay bounded across the run.
const String boundedMemory = 'boundedMemory';

/// Invariant 5 — a flapping link cannot produce a log flood.
const String boundedLogs = 'boundedLogs';

/// Not an invariant: the divergence ledger, which produces the keyframe
/// verdict.
///
/// It is in this list because it is subject to exactly the same vacuity
/// question as the five checkers — an empty ledger whose control never fired
/// is not evidence that nothing diverged — and 11-06 audits it through the
/// same gate rather than through a second mechanism.
const String divergenceLedger = 'divergenceLedger';

/// Every name the soak may register a checker under.
///
/// The list is a **closed set in both directions**. A checker registered under
/// a name that is not here fails the audit, which is what stops a sixth
/// checker being added without anybody deciding it should exist; and a name
/// here with no checker registered against it prints as *pending* rather than
/// silently reading as covered. 11-04 registers two of these, 11-05 registers
/// two more, and 11-06 registers the last two.
const List<String> declaredCheckers = <String>[
  freshnessHonesty,
  terminalStateWrites,
  eventualResync,
  boundedMemory,
  boundedLogs,
  divergenceLedger,
];

// -------------------------------------------------------------- the deviations

/// One place the soak does something other than what §7.8 says.
///
/// Modelled on `f_row_registry.dart`'s `Deviation` with one field changed:
/// there is no `row`, because there are no rows, and there is an [instead]
/// instead — the soak's departures are mostly *numbers*, and a departure whose
/// replacement number is not written down cannot be checked by anybody who did
/// not write it.
final class SoakDeviation {
  const SoakDeviation({
    required this.id,
    required this.clause,
    required this.instead,
    required this.reasoning,
  });

  /// A short handle, used in prose and in the printed block.
  final String id;

  /// The §7.8 text this entry departs from, **verbatim**.
  ///
  /// Paraphrase it and nobody can check the deviation against the catalogue,
  /// which is the only thing an entry here is for
  /// (`f_row_registry.dart:142-145`).
  final String clause;

  /// What this phase does instead, stated as a number wherever it is one.
  final String instead;

  /// Why. A departure with a measurement is a finding; one without is an
  /// excuse.
  final String reasoning;
}

/// Every departure from §7.8's literal text, seeded on day one.
///
/// Later plans **append** — 11-04 if the short arm's terminal-state
/// distribution needs gating, 11-05 if the server-side half of the log clause
/// is deviated — and the phase is expected to close between five and seven.
/// None may be deleted without saying what now satisfies the clause.
const List<SoakDeviation> soakDeviations = <SoakDeviation>[
  SoakDeviation(
    id: 'the 90-second default',
    clause: '30+ min',
    instead: '90 s in the lane on every push; 35 min behind RELAY_SOAK',
    reasoning: 'the two durations measure two different properties and the '
        'entry exists so neither is read as the other. The 90-second property '
        'is that the machinery cannot silently rot between full runs: every '
        'checker samples, every positive control is exercised, the journal is '
        'written and parsed. The 35-minute property is RES-03\'s actual '
        'evidence, and only it can catch something that takes twenty minutes '
        'to accumulate. A soak that only runs on demand is broken on the '
        'morning you need it, so the short arm runs on every push and the '
        'full arm runs on its own job. The precedent is literal: gateDeviations '
        'F2 shortens the catalogue\'s 60 s flap to 20 s in the lane and F17 '
        'shortens its 10-minute blackhole to 30 s, both behind the same '
        'RELAY_SOAK variable this arm uses. 11-CONTEXT ruling 2; 07-CONTEXT '
        'user ruling 2 is where the shape came from.',
  ),
  SoakDeviation(
    id: 'invariant 4 is asserted structurally; RSS is journalled and never '
        'asserted',
    clause: 'Client and server heap high-water marks bounded across the run.',
    instead: 'structural checkpoint slopes over the nine structures the clause '
        'is actually about, at 5 s; ProcessInfo.currentRss written to '
        'metrics.jsonl and asserted nowhere',
    reasoning: 'this is not weaker than §7.8; it is the only version of §7.8 '
        'that can fail on a real leak. The doctrine is already in the tree, '
        'measured, at long_outage_gate_test.dart:71-83, and it is quoted here '
        'in full so that this entry can be checked without opening that file: '
        '"Memory is asserted structurally and never off ProcessInfo.currentRss. '
        '07-RESEARCH assumption A9: RSS on this VM moves by megabytes for '
        'reasons that have nothing to do with the code under test, so a bound '
        'loose enough not to flake is loose enough not to catch a leak. What '
        'is asserted instead is the structure the clause is actually about — '
        'the unresolved-write set and the count of writes that reached a '
        'socket — sampled through the outage so that a leak shows as a slope '
        'rather than as one end-state reading, which is teardown_test.dart\'s '
        'checkpoint doctrine. No line of code in either arm reads '
        'ProcessInfo.currentRss — the only two occurrences of that name in '
        'this file are in this paragraph, and there is no coarse 10x '
        'smoke-detector ceiling in the soak arm either: a ceiling loose enough '
        'to survive the VM\'s own allocator is one no leak this row could '
        'produce would ever trip, and it would read like a memory assertion to '
        'the next person." A high-water mark is an RSS reading by another '
        'name, so the clause as written is the ceiling that paragraph refuses. '
        'RSS is still recorded at every checkpoint, because a human reading '
        'the journal next to the structures is exactly what it is good for. '
        '11-CONTEXT ruling 3.',
  ),
  SoakDeviation(
    id: 'invariant 2 reconciles continuously against a test-only plant-side '
        'ledger',
    clause: 'server logs applied writes, compared after the run',
    instead: 'a test-only append-only ledger on the plant side of the fake '
        'upstream, reconciled continuously and again at end of run',
    reasoning: 'there is no after-the-run comparison to make. The server\'s '
        'own WriteOutcomeLog prunes on every record and every read — '
        'write_outcome_log.dart:211-214, removeWhere against a horizon of '
        'now() - ttl — and the ttl is ServerConfig.writeOutcomeTtl, default '
        '60 s at server_config.dart:337. After thirty-five minutes it holds at '
        'most the last minute of the run, so a comparison performed at the end '
        'would be a comparison of the last sixty seconds wearing the label of '
        'the whole soak, which is worse than no comparison at all. F17b '
        'already found the operational half of this: past the TTL the gateway '
        'cannot tell "never arrived" from "arrived, and forgotten". The '
        'replacement is strictly more information — every applied write is on '
        'the ledger for the whole run, so "applied twice?" is answerable at '
        'minute 35 for a write that happened at minute 3. The ledger is '
        'test-only and lives under test/, per 08-03 task 2\'s rule that levers '
        'never go on a production class. 11-CONTEXT ruling 3.',
  ),
  SoakDeviation(
    id: 'the full arm is judged on Ubuntu only',
    clause: 'Client and server heap high-water marks bounded across the run.',
    instead: 'the 35-minute arm runs on ubuntu-latest only; the 90-second arm '
        'runs on all three OSes',
    reasoning: 'the descriptor half of invariant 4 cannot be judged on '
        'Windows: openSocketCount() needs /proc/self/fd or lsof and '
        'canCountOpenSockets is false there (fd_count.dart:46, with '
        'openSocketCountSkipReason saying so in the words a run report will '
        'show), and macOS runners are billed at ten times Linux for a '
        'thirty-five-minute job. This entry exists so that a green full run is '
        'not read as a three-platform verdict — a result judged on a column of '
        'the matrix where it never ran is precisely the failure '
        'gate_manifest_test.dart\'s skip audit was built to catch, and at this '
        'scale nobody would notice it from the run report. The short arm still '
        'runs everywhere, so the machinery is exercised on all three platforms '
        'even though the endurance evidence comes from one.',
  ),
  SoakDeviation(
    id: 'no docker-compose integration tier',
    clause: 'F10–F11 and the chaos soak belong in the docker-compose '
        'integration tier like #93\'s split compose files',
    instead: 'in-process fixtures on ephemeral ports with real sockets, in '
        'packages/tfc_relay_local/test/soak/',
    reasoning: 'that tier was never built, and this repository\'s integration '
        'story went somewhere else: real sockets and real gateways composed '
        'in process, on ports drawn at bind time so two worktrees can run the '
        'suite at once. For this phase in particular the in-process form is '
        'stronger rather than merely cheaper, because every invariant '
        'observable is a live object — debugUnresolvedCmds, complaints, the '
        'resync engine\'s in-flight map, the plant-side ledger — where a '
        'compose tier would leave the soak scraping logs for the same facts '
        'and inferring the ones that never get logged. §7.8 was written before '
        'any of those observables existed. The one thing the compose tier '
        'would add that this does not is process isolation between client and '
        'server, and 11-CONTEXT ruling 6 records the honest version of that: '
        'the on-site arm against a deployed gateway, post-milestone, with the '
        'config seam built now so the retrofit is not a rewrite.',
  ),
];
