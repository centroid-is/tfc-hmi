/// The run: ninety seconds by default, thirty-five minutes by parameter, one
/// function.
///
/// **Why there are two durations and not one.** `soakDeviations` entry 1 — *the
/// 90-second default* — is the argument in full, printed by
/// `soak_manifest_test.dart` on every run, and it is referenced here rather
/// than restated so that there is one wording and one place to change it. The
/// short version, only so this file is readable on its own: the two durations
/// measure two different properties. The 90-second property is that the
/// machinery, the checkers, the positive controls and the journal cannot
/// silently rot between full runs. The 35-minute property is RES-03's actual
/// evidence, and only it can catch something that takes twenty minutes to
/// accumulate. A soak that only runs on demand is broken on the morning you
/// need it, so the short arm runs on every push and the full arm runs on its
/// own job.
///
/// **It is literally the same function.** [_runSoak] takes a [Duration]; the
/// lane calls it with ninety seconds and `RELAY_SOAK` calls it with
/// thirty-five minutes. F2c's precedent, `flap_gate_test.dart:55-90`: *"the
/// same function as F2a with a longer window — literally the same, so 'same
/// assertions' is a fact about the code rather than a claim in a comment"*.
/// There is no second code path for a reader to check.
///
/// **The library timeout and the CI job's `timeout-minutes` move together.**
/// `package:test`'s default is thirty seconds, so a thirty-five-minute case
/// without the annotation below dies at thirty with a message naming this file
/// rather than the soak (11-RESEARCH pitfall 3, measured — see the SUMMARY).
/// Forty-five minutes is the longest arm plus ten of margin. The other half of
/// this number lives in `.github/workflows/test.yml`, and neither may move
/// alone.
///
/// **This file is thin on purpose.** Everything it does is a call into
/// `SoakDriver` and a print — the machinery is `test/support/soak/`'s, and a
/// helper that grows here belongs there.
@Tags(['soak'])
@Timeout(Duration(minutes: 45))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import '../support/soak/applied_write_ledger.dart';
import '../support/soak/checkers/freshness_honesty.dart';
import '../support/soak/checkers/terminal_state.dart';
import '../support/soak/invariant.dart';
import '../support/soak/soak_driver.dart';
import '../support/soak/soak_journal.dart';
import '../support/soak/soak_observables.dart';
import '../support/soak/soak_timeline.dart';
import 'soak_registry.dart';

// ------------------------------------------------------------- the selectors

/// The lane's seed, fixed.
///
/// **Eleven, and fixed rather than drawn.** 11-CONTEXT ruling 4: bit-rot
/// protection is deterministic, and a nightly failure nobody can reproduce is
/// worse than no nightly at all. `RELAY_SOAK_SEED` takes a number for a
/// deliberate re-run, and `RELAY_SOAK_SEED=random` draws one for the rare case
/// where breadth is what is wanted.
const int fixedLaneSeed = 11;

/// The lane arm, on every push.
const Duration shortArm = Duration(seconds: 90);

/// RES-03's arm, behind `RELAY_SOAK`.
const Duration fullArm = Duration(minutes: 35);

const String soakVariable = 'RELAY_SOAK';
const String minutesVariable = 'RELAY_SOAK_MINUTES';
const String seedVariable = 'RELAY_SOAK_SEED';

/// The word that asks for a drawn seed rather than a chosen one.
const String randomSeedWord = 'random';

/// How long this run is declared to be.
///
/// `RELAY_SOAK_MINUTES` wins over `RELAY_SOAK`, which wins over the default.
/// Three inputs and one output, and every case that asserts about the choice
/// asserts about *this function* rather than about a run — which is why
/// "RELAY_SOAK selects thirty-five minutes" costs milliseconds to prove.
Duration chosenDuration(Map<String, String> environment) {
  final minutes = environment[minutesVariable];
  if (minutes != null && minutes.isNotEmpty) {
    final parsed = int.tryParse(minutes);
    if (parsed == null || parsed <= 0) {
      throw ArgumentError('$minutesVariable="$minutes" is not a number of '
          'minutes. A run that fell back to the default here would report a '
          'duration nobody asked for, and every floor in the harness is '
          'scaled off the declared duration');
    }
    return Duration(minutes: parsed);
  }
  final full = environment[soakVariable];
  if (full != null && full.isNotEmpty) return fullArm;
  return shortArm;
}

/// This run's seed.
///
/// Drawing is the one place in the whole soak where an unseeded source is the
/// point rather than a bug, and it is why `soak_test.dart` carries an entry in
/// `soakDeterminismAllowList`: the drawn number is *printed on line one* and
/// fed back through `RELAY_SOAK_SEED` to reproduce, so it decides nothing that
/// is not immediately recorded.
int chosenSeed(Map<String, String> environment) {
  final raw = environment[seedVariable];
  if (raw == null || raw.isEmpty) return fixedLaneSeed;
  if (raw == randomSeedWord) return _drawSeed();
  final parsed = int.tryParse(raw);
  if (parsed == null) {
    throw ArgumentError('$seedVariable="$raw" is neither a number nor '
        '"$randomSeedWord". Falling back to $fixedLaneSeed would make the run '
        'report a seed it was not asked for, which is the one failure the '
        'whole reproducibility story cannot survive');
  }
  return parsed;
}

// ------------------------------------------------------------------- the run

/// The checkers this run registers, given the driver they will read.
///
/// **The driver arrives as a thunk because the two are mutually referential.**
/// A checker reads the composed pipe and the driver ticks the checker, so one
/// of the two references has to be late. It is this one, and the `late final`
/// at the call site below is the whole of it: `soakCheckers` is called first,
/// the driver is built with what it returns, and nothing dereferences the thunk
/// until `start()` has composed the fixture and started the tickers.
///
/// 11-05 and 11-06 append theirs here. The cadence is the checker's own
/// business — `SoakCheckerRegistration.fast` is 25 ms, `.checkpoint` is 5 s and
/// `.perMinute` is a rate window — and the driver holds no opinion about what
/// any of them measures.
List<SoakCheckerRegistration> soakCheckers(SoakDriver Function() driver) =>
    <SoakCheckerRegistration>[
      SoakCheckerRegistration.fast(FreshnessHonestyChecker(_LateSource(driver))),
      // At the checkpoint cadence rather than the fast one: invariant 2 reads
      // an append-only list by index and a set's length, so five seconds loses
      // nothing — every record carries the schedule offset the DRIVER stamped
      // at the instant, not the one the checker read it at.
      SoakCheckerRegistration.checkpoint(
          TerminalStateChecker(_LateSource(driver))),
    ];

/// A [SoakFreshnessSource] that resolves its driver on every call.
///
/// One indirection and no state: a checker built before the driver exists still
/// reads the live one, and the alternative — handing the checker a setter the
/// driver calls at `start()` — is a second lifecycle to get wrong on the day
/// somebody adds a third registration.
final class _LateSource implements SoakFreshnessSource, SoakWriteSource {
  const _LateSource(this._driver);

  final SoakDriver Function() _driver;

  @override
  int get seed => _driver().seed;

  @override
  Duration get declaredDuration => _driver().declaredDuration;

  @override
  Duration get scheduleOffset => _driver().scheduleOffset;

  @override
  List<SoakPanelView> get panelViews => _driver().panelViews;

  @override
  List<String> get freshnessKeys => _driver().freshnessKeys;

  @override
  int get controlPanelIndex => _driver().controlPanelIndex;

  @override
  int get plantWideArmsApplied => _driver().plantWideArmsApplied;

  @override
  Duration get freshnessBudget => _driver().freshnessBudget;

  @override
  List<SoakWriteRecord> get writeRecords => _driver().writeRecords;

  @override
  List<String> get unresolvedCmds => _driver().unresolvedCmds;

  @override
  AppliedWriteLedger get appliedWrites => _driver().appliedWrites;
}

/// One run. The only difference between the lane and RES-03 is [duration].
Future<SoakDriver> _runSoak(
  Duration duration, {
  required int seed,
  String journalPath = defaultSoakJournalDir,
}) async {
  // First, and before any composition. A run killed by a CI timeout, an OOM or
  // a cancelled workflow still names its seed, which is the cheapest insurance
  // available and the difference between a failure that can be reproduced and
  // one that cannot.
  announceSoakSeed(seed, declaredDuration: duration);

  late final SoakDriver driver;
  final checkers = soakCheckers(() => driver);
  driver = SoakDriver(
    seed: seed,
    duration: duration,
    checkers: checkers,
    journalPath: journalPath,
  );
  addTearDown(driver.dispose);

  await driver.run();

  // The run's public output, printed on a green run too: a green run's numbers
  // are the baseline the next red run is read against, and a block that only
  // appears on failure is a block nobody has ever seen working.
  print(driver.verdictBlock);

  final registered = <InvariantChecker>[
    for (final one in checkers) one.checker,
  ];
  // The reverse sweep first: a checker nobody declared prints nowhere in the
  // block above, so it is invisible whether it passed or was never there.
  assertEveryCheckerIsDeclared(registered, declaredCheckers);
  assertNoVacuousVerdict(registered);

  expect(driver.neverReached, isEmpty,
      reason: 'the run did not reach every entry of its own timeline, so the '
          'storm it played is not the storm its repro log '
          'describes:\n${driver.divergenceReport}');

  // Every violation the run recorded, the driver's own and every checker's.
  //
  // **The checkers' logs are asserted here and not only printed.** 11-03 landed
  // this call site with no checkers registered, so `driver.violations` was the
  // whole of it; a checker's log rendered into the verdict block and never
  // compared to `isEmpty` would be a breach that prints and passes — which is
  // the same failure the vacuity gate exists for, one layer out.
  final recorded = <SoakViolation>[
    ...driver.violations,
    for (final one in registered) ...one.violations,
  ];
  final total = driver.violationLog.total +
      registered.fold<int>(0, (sum, one) => sum + one.violations.length);

  // The first violation quoted in full, and the rest counted. Two hundred
  // renderings in a failure message is a message nobody reads to the end, and
  // the first occurrence is the diagnostic — `ViolationLog` keeps the first
  // rather than the last for exactly this.
  expect(recorded, isEmpty,
      reason: 'the soak recorded $total violations across the driver and '
          '${registered.length} checkers. The first, in full:\n\n  '
          '${recorded.isEmpty ? '(none)' : recorded.first}\n\n'
          'The rest are in ${driver.journalPath}/, one trip record each, with '
          'the twenty checkpoints before them and the command that reproduces '
          'the run.\n\n${driver.verdictBlock}');

  return driver;
}

// ----------------------------------------------------------------- the cases

void main() {
  test('the storm runs unattended against five real panels and a real '
      'gateway', () async {
    final environment = Platform.environment;
    final duration = chosenDuration(environment);
    final wall = Stopwatch()..start();
    await _runSoak(duration, seed: chosenSeed(environment));
    wall.stop();

    print('soak wall clock: ${wall.elapsed} against a declared $duration');
    expect(
        wall.elapsed,
        allOf(
          greaterThan(duration - const Duration(seconds: 10)),
          lessThan(duration + const Duration(seconds: 30)),
        ),
        reason: 'a run that finished early played a storm shorter than the '
            'one it declared, and every floor in the harness is scaled off '
            'the DECLARED duration — so an early finish is a set of floors '
            'nothing had time to reach. A run that overran by more than half '
            'a minute spent it somewhere the timeline does not describe');
  });

  test('the duration is chosen by three variables and nothing else', () {
    expect(chosenDuration(const <String, String>{}), shortArm);
    expect(chosenDuration(const <String, String>{'RELAY_SOAK': '1'}), fullArm,
        reason: 'this case reads the CHOSEN duration and does not run the '
            'arm, which is why it costs milliseconds. 11-07 runs the full arm '
            'once, for real, on its own job; a thirty-five-minute case in the '
            'RED loop is a plan nobody can execute, and a plan nobody '
            'executes is where a stale assertion lives');
    expect(chosenDuration(const <String, String>{'RELAY_SOAK_MINUTES': '1'}),
        const Duration(minutes: 1));
    expect(
        chosenDuration(
            const <String, String>{'RELAY_SOAK': '1', 'RELAY_SOAK_MINUTES': '2'}),
        const Duration(minutes: 2),
        reason: 'the explicit number wins over the flag, or a debugging run '
            'would silently become thirty-five minutes');
    expect(chosenDuration(const <String, String>{'RELAY_SOAK': ''}), shortArm,
        reason: 'an empty variable is an unset one — a CI matrix that writes '
            'the name with no value must not start a 35-minute job');
  });

  test('the seed is fixed by default, chosen by number, or drawn by word', () {
    expect(chosenSeed(const <String, String>{}), fixedLaneSeed);
    expect(chosenSeed(const <String, String>{'RELAY_SOAK_SEED': '99'}), 99);
    expect(() => chosenSeed(const <String, String>{'RELAY_SOAK_SEED': 'twelve'}),
        throwsArgumentError,
        reason: 'a misspelled seed must not silently become the fixed one: '
            'the run would then report a seed it was not asked for');

    final drawn = <int>{
      for (var i = 0; i < 8; i++)
        chosenSeed(const <String, String>{'RELAY_SOAK_SEED': 'random'}),
    };
    expect(drawn.length, greaterThan(1),
        reason: 'eight draws produced one number, so "random" is not drawing');
  });

  test('a drawn seed reproduces when it is fed back', () {
    final drawn = chosenSeed(const <String, String>{'RELAY_SOAK_SEED': 'random'});
    final first = buildTimeline(
        seed: drawn,
        duration: shortArm,
        panels: const <String>['panel-1', 'panel-2', 'panel-3', 'panel-4'],
        aliases: soakAliases);
    final second = buildTimeline(
        seed: chosenSeed(<String, String>{'RELAY_SOAK_SEED': '$drawn'}),
        duration: shortArm,
        panels: const <String>['panel-1', 'panel-2', 'panel-3', 'panel-4'],
        aliases: soakAliases);
    expect(second.reproLog, first.reproLog,
        reason: 'the number a run prints on line one is the whole of its '
            'reproducibility story: if feeding it back does not rebuild the '
            'same storm, the line is decoration');
  });

  test('every registered checker is declared, and each is ticked at its own '
      'cadence', () {
    // Built against a driver that is never started: registration itself must
    // not dereference the thunk, which is the property that lets
    // `soakCheckers` be called before the driver exists.
    late final SoakDriver unstarted;
    final registrations = soakCheckers(() => unstarted);
    unstarted = SoakDriver(seed: 1, duration: shortArm, herdSize: 3);
    final checkers = <InvariantChecker>[
      for (final one in registrations) one.checker,
    ];

    expect(checkers.map((one) => one.name),
        containsAll(<String>[freshnessHonesty, terminalStateWrites]),
        reason: '11-04 registers invariants 1 and 2; 11-05 and 11-06 append '
            'theirs to the same list');
    expect(
        () => assertEveryCheckerIsDeclared(checkers, declaredCheckers),
        returnsNormally);
    expect(
        registrations
            .firstWhere((one) => one.checker.name == freshnessHonesty)
            .cadence,
        fastCheckerCadence,
        reason: 'the freshness verdict is sampled at 25 ms because a sampler '
            'that took one reading per up-window could miss the flicker a '
            'one-second flap half produces (flap_gate_test.dart:55-160)');
  });

  test('a registered checker\'s floor scales with the arm that is running',
      () {
    late final SoakDriver lane;
    late final SoakDriver full;
    final short = soakCheckers(() => lane).first.checker;
    final long = soakCheckers(() => full).first.checker;
    lane = SoakDriver(seed: 1, duration: shortArm, herdSize: 3);
    full = SoakDriver(seed: 1, duration: fullArm, herdSize: 3);

    expect(long.minimumSamplesForAVerdict,
        greaterThan(short.minimumSamplesForAVerdict),
        reason: 'a floor that did not scale would be one the short arm could '
            'not reach and one the long arm passed in its first minute — '
            'invariant.dart\'s rule, applied at the registration site where '
            'the declared duration is finally known');
  });

  test('the seed reaches stdout before anything is composed', () async {
    final printed = <String>[];
    await runZoned(
      () => _runSoak(const Duration(seconds: 8),
          seed: 4242, journalPath: _tempJournal()),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => printed.add(line),
      ),
    );
    expect(printed, isNotEmpty);
    expect(printed.first, startsWith('soak seed=4242'),
        reason: 'a run killed by a CI timeout, an OOM or a cancelled workflow '
            'still names its seed, and only if the seed is the first thing '
            'out. What was printed first instead: ${printed.first}');
    expect(printed.first, contains('RELAY_SOAK_SEED=4242'),
        reason: 'the line carries the literal command that reproduces it');
  });

  test('two runs at one seed and one duration play the same storm', () async {
    const duration = Duration(seconds: 12);
    final firstDir = _tempJournal();
    final secondDir = _tempJournal();

    await _runSoak(duration, seed: 7, journalPath: firstDir);
    await _runSoak(duration, seed: 7, journalPath: secondDir);

    expect(File('$secondDir/repro.log').readAsStringSync(),
        File('$firstDir/repro.log').readAsStringSync(),
        reason: 'the planned storm is a pure function of the seed, so two '
            'repro logs at one seed are byte-identical or the generator is '
            'not pure');

    final first = _appliedStorm(firstDir);
    final second = _appliedStorm(secondDir);
    expect(second, first,
        reason: 'the same storm was PLANNED both times and must have been '
            'PLAYED both times: what is compared is every applied entry\'s '
            'offset, stream and payload, in order. The two clock fields and '
            'the outcome note are deliberately not compared — they are '
            'measurements of the machine (a wall reading, a bound port, an '
            'epoch id), and a reproducibility check that demanded they match '
            'would be asserting that two runs took the same amount of time');
    expect(first, isNotEmpty,
        reason: 'two empty event streams are trivially equal, so a 12-second '
            'storm that applied nothing would pass this case having proved '
            'nothing at all');
  });
}

/// Every applied entry's reproducible identity, in order.
///
/// `monotonicMs`, `wallMs`, `event` and `note` are dropped: the first two are
/// the machine's, the third is a counter over the same list, and the fourth
/// carries measurements — the port a restarted gateway bound, the epoch a bump
/// minted. What remains is what the storm *was*.
List<String> _appliedStorm(String dir) => <String>[
      for (final line in File('$dir/events.jsonl').readAsLinesSync())
        if (line.trim().isNotEmpty)
          () {
            final record = jsonDecode(line) as Map<String, Object?>;
            return '${record['offsetMs']}|${record['stream']}|'
                '${record['payload']}|${record['kind']}';
          }(),
    ];

/// A journal directory an auxiliary case owns, so it cannot overwrite the
/// artifact the real arm writes to `build/soak/`.
String _tempJournal() {
  final dir = Directory.systemTemp.createTempSync('relay-soak-run-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir.path;
}

// The draw itself. Isolated here, at the bottom, so the one unseeded source in
// the soak trees is a single line somebody can find — and so the freeze-9
// allow-list entry naming this file names something small.
int _drawSeed() => Random().nextInt(1 << 31);
