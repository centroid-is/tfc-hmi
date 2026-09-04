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

import '../support/soak/invariant.dart';
import '../support/soak/soak_driver.dart';
import '../support/soak/soak_journal.dart';
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
  throw UnimplementedError('chosenDuration');
}

/// This run's seed.
///
/// Drawing is the one place in the whole soak where an unseeded source is the
/// point rather than a bug, and it is why `soak_test.dart` carries an entry in
/// `soakDeterminismAllowList`: the drawn number is *printed on line one* and
/// fed back through `RELAY_SOAK_SEED` to reproduce, so it decides nothing that
/// is not immediately recorded.
int chosenSeed(Map<String, String> environment) {
  throw UnimplementedError('chosenSeed');
}

// ------------------------------------------------------------------- the run

/// The checkers this run registers.
///
/// **Empty, and the call sites below still run.** 11-04, 11-05 and 11-06 each
/// append one, against a driver and a run function that already work —
/// `assertNoVacuousVerdict`'s own doc says an empty list passes deliberately,
/// so that the next plan adds a checker instead of performing a refactor.
List<SoakCheckerRegistration> soakCheckers() =>
    const <SoakCheckerRegistration>[];

/// One run. The only difference between the lane and RES-03 is [duration].
Future<SoakDriver> _runSoak(
  Duration duration, {
  required int seed,
  String journalPath = defaultSoakJournalDir,
}) async {
  throw UnimplementedError('_runSoak');
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

  test('the vacuity gate is called with the empty checker list, and the seam '
      'holds', () {
    expect(soakCheckers(), isEmpty,
        reason: 'this plan registers none; 11-04, 11-05 and 11-06 each add '
            'one to soakCheckers()');
    expect(
        () => assertNoVacuousVerdict(
            <InvariantChecker>[for (final one in soakCheckers()) one.checker]),
        returnsNormally,
        reason: 'the call site exists and is exercised empty, so the next '
            'plan adds a checker rather than performing a refactor');
    expect(
        () => assertEveryCheckerIsDeclared(
            <InvariantChecker>[for (final one in soakCheckers()) one.checker],
            declaredCheckers),
        returnsNormally);
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
