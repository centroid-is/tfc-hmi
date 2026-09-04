/// The composed pipe under the storm: one real gateway, N real panels behind N
/// real fault proxies, the merged timeline played on one clock, and the
/// population floor underneath all of it.
///
/// **The driver is a player, not an author.** Every random draw in this phase
/// happened at generation time, in `soak_event.dart`, from
/// `SeededScenarioRandom`. Which key a panel subscribes, which value it writes,
/// which panel writes, which alias goes down — all of it arrives here as a
/// `SoakEvent` arm and none of it is decided here. That is what makes a repro
/// log a reproduction rather than a summary, and it is why this file contains
/// no draw at all: `Random(` and `DateTime.now()` are both swept out of the
/// soak trees by freeze 9.
///
/// **What it composes is what ships.** Phase 10's CR-01 is the standing lesson:
/// its timeseries family was dead in the shipping gateway because the one
/// composition that ships — server plus policy plus real store — had never been
/// assembled by any test, while every fake made the bug idempotent and
/// invisible. *Capability flags prove a leg ran; parity proves the legs agree;
/// neither proves the stack a panel talks to was ever assembled.* So this
/// driver stands up the real `RelayServer` building its own session policy
/// through `RelaySession`, real listening sockets, real `RemoteStateMan`
/// panels over real TCP, and the real `LocalStateMan` over per-alias
/// `FakeUpstreamLink`s. The only fake in the picture is the PLC, which is the
/// one participant CI cannot have.
///
/// It composes [gateBFixture] rather than standing a second herd up beside it.
/// That fixture already assembles those five pieces in `buildGateway`'s own
/// order, in this package, with the teardown argument written out — a parallel
/// herd would be a second answer to a question that has one.
///
/// **Panel 0 is the control, and the exclusion is this file's job.** The
/// generator cannot tell a control panel from an ordinary one
/// (`soak_event.dart`'s contract: *"`panels` is the set the storm may target,
/// and the caller excludes the control by not passing it in"*). So [SoakDriver]
/// never passes the control's name to [buildTimeline], never gives its proxy to
/// the link half, and refuses to start against any timeline that names it —
/// see [SoakDriver.start]. The argument for having a control at all is
/// `long_outage_gate_test.dart`'s, applied to a herd: *"the server released the
/// dead session" is only worth saying if the server did not also release live
/// ones — which is exactly what it did on the build before 07-08b, once every
/// six seconds, to every panel in the plant.* An all-faulted population cannot
/// see that class of regression; one healthy panel makes it glaring.
///
/// **One clock, one chained timer, and why there is no second playback.** The
/// merged timeline is a **total** order — 11-02 sorted it on
/// `(offset, streamIndex, indexWithinStream)` precisely so that two entries at
/// one offset have a defined relative order that the length of the list cannot
/// change. Playing it means playing it *in that order*, from one clock. Running
/// the link half through per-proxy `ScenarioPlayback` instances would give each
/// its own `Stopwatch` and discard the very ordering the merge exists to fix,
/// so [SoakDriver] walks `merged` itself with one chained timer off one
/// `Stopwatch` — `ScenarioPlayback`'s own shape and its own reasons (a lever
/// that takes a moment to apply does not push every later offset out; there is
/// only ever one pending timer, so "no timer fires after stop" is a property of
/// the shape) — and pulls the link levers through
/// [ScenarioPlayback.apply], which is the existing exhaustive switch over
/// `FaultMutation` and is not restated here.
///
/// **A lever that fired into nothing is a first-class outcome.** Every arm of
/// [SoakDriver.apply] returns a [SoakApplyOutcome] naming the lever it pulled
/// and saying whether it did anything. A storm that quietly narrows itself —
/// a second `disconnectUpstream` on an alias already down returns early
/// (`fake_upstream_link.dart:397`), an unsubscribe from a panel holding no
/// subscription — is the failure mode both halves of the artifact hide on their
/// own: `repro.log` says it was planned and `events.jsonl` says it was applied,
/// and neither says it did nothing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tfc_dart/core/state_man.dart'
    show KeyMappingEntry, KeyMappings;
import 'package:tfc_relay_local/tfc_relay_local.dart' show UpstreamLinkState;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:tfc_stateman_contract/faults.dart';

import '../gate_b_fixture.dart';
import '../keymap_fixtures.dart' show opcUaEntry;
import 'invariant.dart';
import 'soak_event.dart';
import 'soak_journal.dart';
import 'soak_timeline.dart';

// ------------------------------------------------------------------ the herd

/// How many panels the soak stands up.
///
/// **Five, of which one is the control.** 11-RESEARCH §C.4's number: four
/// stormed panels is enough for the herd effects the phase is about (a reaper
/// taking live sessions, a fan-out that punishes bystanders) and small enough
/// that a 35-minute run on a hosted runner is not measuring the runner.
const int defaultSoakHerdSize = 5;

/// The environment variable that overrides [defaultSoakHerdSize].
///
/// **The same name gate A's fixture uses** (`gate_fixture.dart`, default 20),
/// deliberately: an operator debugging a herd effect sets one variable and both
/// lanes widen. The defaults differ because the lanes do — gate A's herd holds
/// for one scenario, this one holds for thirty-five minutes.
const String herdSizeVariable = 'RELAY_HERD_N';

/// Reads [herdSizeVariable] out of [environment], or [defaultSoakHerdSize].
///
/// Refuses anything under three: two panels is one stormed panel and one
/// control, which cannot show a herd effect at all, and one panel is a control
/// with no storm.
int soakHerdSize(Map<String, String> environment) {
  final raw = environment[herdSizeVariable];
  if (raw == null || raw.isEmpty) return defaultSoakHerdSize;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 3) {
    throw ArgumentError('$herdSizeVariable="$raw" is not a herd: it must parse '
        'as an integer of at least 3 — one control plus at least two stormed '
        'panels, below which there is no herd effect for the control to be a '
        'control against');
  }
  return parsed;
}

/// The panel the storm may never reach.
const int soakControlPanelIndex = 0;

/// Panel *i*'s name, which is also its station id in the token file.
String soakPanelName(int index) => 'panel-$index';

/// The four PLCs the plant stands in for — SVN's own aliases.
const List<String> soakAliases = <String>[
  'ST101',
  'ST201',
  'ST301',
  'BAADER',
];

/// Keys per alias.
///
/// **Ten, not gate B's fifty.** Five panels each subscribing every key of four
/// aliases is `panels × aliases × keys` values per sweep on one isolate; at
/// fifty that is a thousand, and thirty-five minutes of it measures the encoder
/// rather than the invariants. Ten keeps four aliases' worth of realistic
/// `AREA.DEV.SUB` names in play at two hundred values a sweep.
const int soakKeysPerAlias = 10;

/// How often the plant moves every key.
///
/// Slower than gate B's 100 ms for the same reason the page is narrower: this
/// runs for thirty-five minutes rather than for one assertion.
const Duration soakSweepPeriod = Duration(milliseconds: 250);

// -------------------------------------------------------------- the cadences

/// The fast sampler's cadence — 11-04's freshness checker.
const Duration fastCheckerCadence = Duration(milliseconds: 25);

/// The checkpoint cadence: the journal, the population floor, 11-05 and 11-06.
const Duration checkpointCadence = Duration(seconds: 5);

/// The rate-window cadence — 11-05's log-ceiling checker.
const Duration rateWindowCadence = Duration(minutes: 1);

/// How often the driver reads each panel's connectivity.
///
/// **Finer than [checkpointCadence], and the plan says "every checkpoint".**
/// Five seconds cannot see a panel that flapped down and back inside one
/// second, and a control-panel arm that misses the dip it exists to catch is
/// worse than no arm. The *floor* is evaluated on these samples and the numbers
/// are *journalled* at the checkpoint, so the artifact still reads at the
/// cadence everything else in it does.
const Duration panelSampleCadence = Duration(milliseconds: 250);

// -------------------------------------------------------- the population floor

/// How long the connected-panel count may sit below its floor.
///
/// **Seventy-five seconds, and the arithmetic is the point.** The floor is
/// `herdSize - 1`: one panel may be missing at any instant without penalty,
/// because the storm is entitled to take one down. What is not permitted is
/// staying there, and the window has to be long enough for the longest
/// *legitimate* excursion and short enough to catch a cull.
///
/// The longest legitimate excursion is a token revocation. The session closes
/// 4001 immediately, the panel's single redial is refused, and Phase 6 stops
/// its reconnect loop for good — by design, because a panel that retried a
/// rejected credential would hammer the gateway all shift. The paired
/// [TokenRestore] arrives at a drawn offset inside
/// `SoakEventSchedule.tokenRestoreWindow`, **60 s** at the outside, after which
/// this driver redials and the panel needs a hello and a snapshot. Sixty plus
/// fifteen seconds of slack for that redial is seventy-five.
///
/// What it still catches, and what a longer window would not: a redial loop
/// that gives up, a reaper taking live sessions, and a revocation whose restore
/// did not land — all three are *monotonic*, so they sit below the floor from
/// the moment they start until the end of the run.
///
/// **It is a weak instrument in the 90-second arm and that is stated rather
/// than hidden**: seventy-five of ninety seconds is most of the run, so the
/// short arm's floor catches only a pipe that never stood up. The 35-minute arm
/// is where this number earns its keep, which is the same division of labour
/// `soakDeviations` entry 1 draws for everything else in this phase.
///
/// Overridable per driver — `soak_driver_test.dart` shortens it so that the
/// case proving the floor trips is not itself seventy-five seconds long. What
/// that case is about is the trip, its offset and the run continuing; the value
/// of the grace is this constant's business and is argued here, once.
const Duration populationFloorGraceDefault = Duration(seconds: 75);

// ------------------------------------------------------------- the endpoint

/// Where the driver's panels dial.
///
/// **The seam, built now and deliberately not used yet.** 11-CONTEXT ruling 6
/// records the on-site arm against a deployed SVN gateway as a post-milestone
/// follow-up, and 11-RESEARCH open question 2's answer is that the cost of the
/// seam now is one field and the cost of retrofitting it later is a rewrite of
/// everything that composes. [SoakEndpoint.inProcess] is what every lane runs;
/// [SoakEndpoint.deployed] is the on-site arm's future consumer, and the driver
/// refuses it today with a message that says so rather than half-working.
final class SoakEndpoint {
  /// The gateway this process composes and owns. Every lane, today.
  const SoakEndpoint.inProcess() : deployedGateway = null;

  /// A gateway already running somewhere else — the on-site arm.
  const SoakEndpoint.deployed(Uri uri) : deployedGateway = uri;

  /// Null for [SoakEndpoint.inProcess].
  final Uri? deployedGateway;

  bool get isInProcess => deployedGateway == null;

  @override
  String toString() => deployedGateway?.toString() ?? 'in-process';
}

// -------------------------------------------------------------- the outcome

/// What one timeline entry actually did.
///
/// [lever] is the *name of the mechanism pulled*, not the name of the event —
/// `FakeUpstreamLink.disconnectUpstream` rather than `upstreamLinkDown`. That
/// distinction is what makes the arm-coverage case in `soak_driver_test.dart`
/// worth having on top of the sealed type: a switch collapsed into one
/// `default:` arm still compiles and still handles every event, but it cannot
/// produce fourteen distinct lever names.
final class SoakApplyOutcome {
  /// The lever was pulled and something happened.
  const SoakApplyOutcome.fired(this.kind, this.lever, {this.note})
      : fired = true;

  /// The lever was pulled and the world did not move — the storm quietly
  /// narrowing itself, which is a finding rather than a nothing.
  const SoakApplyOutcome.fizzled(this.kind, this.lever, String this.note)
      : fired = false;

  /// The `SoakEventKinds` name, or `link:<mode>` for the fault half.
  final String kind;

  /// The mechanism this arm pulls, spelled as the code spells it.
  final String lever;

  /// Whether the world moved.
  final bool fired;

  /// Why it did not, or anything worth journalling about a firing.
  final String? note;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'lever': lever,
        'fired': fired,
        if (note != null) 'note': note,
      };

  @override
  String toString() =>
      '$kind via $lever ${fired ? 'fired' : 'FIZZLED'}${note == null ? '' : ' — $note'}';
}

// -------------------------------------------------------------- the registry

/// One checker and the cadence the driver ticks it at.
///
/// The cadence belongs to the checker and not to the driver: a freshness
/// sampler at 25 ms and a rate window at one minute are two different
/// instruments, and a driver that ticked everything at one rate would either
/// make the fast one useless or the slow one a hot loop. [SoakDriver] holds no
/// opinion about what any of them measures.
final class SoakCheckerRegistration {
  const SoakCheckerRegistration(this.checker, this.cadence);

  /// 11-04's freshness sampler.
  SoakCheckerRegistration.fast(InvariantChecker checker)
      : this(checker, fastCheckerCadence);

  /// 11-05's and 11-06's checkpoint-cadence instruments.
  SoakCheckerRegistration.checkpoint(InvariantChecker checker)
      : this(checker, checkpointCadence);

  /// A per-minute rate window.
  SoakCheckerRegistration.perMinute(InvariantChecker checker)
      : this(checker, rateWindowCadence);

  final InvariantChecker checker;
  final Duration cadence;
}

// ------------------------------------------------------------ the population

/// What the driver knows about one panel's connectivity.
///
/// Connectivity only, and deliberately so: freshness is 11-04's, convergence is
/// 11-06's, and a driver that judged either would be a sixth checker nobody
/// declared. What is here is the input to the population floor, plus the two
/// counters that fall out of the same sampling for free and give the control's
/// arm something to be sharp about.
final class SoakPanelHealth {
  SoakPanelHealth(this.index);

  final int index;

  /// How many times this panel went from ready to not-ready.
  int readyDips = 0;

  /// How many samples found it not ready.
  int notReadySamples = 0;

  /// How many samples found its whole view stale.
  int staleViewSamples = 0;

  /// How many samples were taken at all — the denominator, without which the
  /// two counters above are numbers with no scale.
  int samples = 0;

  /// Link mutations the storm applied to this panel's proxy. **Zero for the
  /// control, by construction**, which is the assertion the whole design turns
  /// on.
  int mutationsApplied = 0;

  bool _wasReady = true;

  void observe({required bool ready, required bool staleView}) {
    samples++;
    if (!ready) {
      notReadySamples++;
      if (_wasReady) readyDips++;
    }
    if (staleView) staleViewSamples++;
    _wasReady = ready;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'panel': soakPanelName(index),
        'samples': samples,
        'readyDips': readyDips,
        'notReadySamples': notReadySamples,
        'staleViewSamples': staleViewSamples,
        'mutationsApplied': mutationsApplied,
      };

  @override
  String toString() => '${soakPanelName(index)}: $readyDips dips, '
      '$notReadySamples/$samples not ready, '
      '$staleViewSamples/$samples stale view, '
      '$mutationsApplied mutations';
}

// ---------------------------------------------------------------- the driver

/// The soak, as an object that can be ticked.
///
/// 11-RESEARCH §A.2's argument, which is the same one `long_outage_gate_test`
/// makes for checkpoints over end-state readings: five invariants sampled
/// continuously against five panels are five independent state machines with
/// five different cadences, and interleaved inside one `test()` body they share
/// one stack, one set of locals and one failure message. So the machinery is
/// here and `soak_test.dart` is thin.
///
/// It arrives with **zero checkers registered**, and that is deliberate. It
/// composes the pipe, plays the merged timeline, writes the journal, holds the
/// population and proves all of that at 90 seconds — real evidence on its own,
/// and the thing that must not bit-rot. 11-04, 11-05 and 11-06 then register
/// against a driver that already works.
final class SoakDriver {
  SoakDriver({
    required this.seed,
    required this.duration,
    this.endpoint = const SoakEndpoint.inProcess(),
    this.checkers = const <SoakCheckerRegistration>[],
    this.journalPath = defaultSoakJournalDir,
    Map<String, String>? environment,
    SoakTimeline? timeline,
    int? herdSize,
    Duration? populationFloorGrace,
  })  : herdSize =
            herdSize ?? soakHerdSize(environment ?? Platform.environment),
        floorGrace = populationFloorGrace ?? populationFloorGraceDefault,
        _given = timeline;

  /// The run's seed. Both halves of the storm derive from it and nothing else
  /// does.
  final int seed;

  /// What the run was *declared* to be. Every floor scales off this and never
  /// off measured elapsed time — `invariant.dart`'s rule.
  final Duration duration;

  /// Where the panels dial.
  final SoakEndpoint endpoint;

  /// The checkers to tick, each at its own cadence.
  final List<SoakCheckerRegistration> checkers;

  /// Where `metrics.jsonl`, `events.jsonl`, `repro.log` and any trip records
  /// land.
  final String journalPath;

  /// How many panels, control included.
  final int herdSize;

  /// How long the connected count may sit below [populationFloor] before a
  /// violation is recorded. See [populationFloorGraceDefault] for the
  /// arithmetic.
  final Duration floorGrace;

  final SoakTimeline? _given;

  /// Panel names the storm is allowed to aim at — **everything but the
  /// control**. This is the list [buildTimeline] is given, and the reason the
  /// generated timeline cannot name the control at all.
  List<String> get stormPanels => <String>[
        for (var i = 0; i < herdSize; i++)
          if (i != soakControlPanelIndex) soakPanelName(i),
      ];

  /// The control's name, which no storm entry may contain.
  String get controlPanel => soakPanelName(soakControlPanelIndex);

  // ------------------------------------------------------- built by [start]

  SoakTimeline? _timeline;
  GateBFixture? _fixture;
  SoakJournal? _journal;
  SoakClock? _clock;
  Directory? _tokenDir;
  String? _tokenFilePath;

  /// The storm, once [start] has built or accepted it.
  SoakTimeline get timeline => _require(_timeline, 'timeline');

  /// The composed pipe.
  GateBFixture get fixture => _require(_fixture, 'fixture');

  /// The forensics sink.
  SoakJournal get journal => _require(_journal, 'journal');

  /// Monotonic elapsed and the declared duration. Nothing else.
  SoakClock get clock => _require(_clock, 'clock');

  T _require<T>(T? value, String what) => value ??
      (throw StateError('the soak driver has no $what until start() has '
          'completed; a caller reading one early wants to be told that rather '
          'than shown a default'));

  // ------------------------------------------------------------- observables

  /// Everything recorded, bounded — see [ViolationLog].
  final ViolationLog violationLog = ViolationLog();

  /// The recorded breaches, oldest first.
  List<SoakViolation> get violations => violationLog.entries;

  final List<SoakTimelineEntry> _applied = <SoakTimelineEntry>[];
  final List<SoakApplyOutcome> _outcomes = <SoakApplyOutcome>[];
  final List<String> _fizzled = <String>[];
  final Map<int, SoakPanelHealth> _health = <int, SoakPanelHealth>{};
  final Map<String, int> _leversByKind = <String, int>{};

  /// Timeline entries the driver reached and pulled a lever for, in order.
  List<SoakTimelineEntry> get applied =>
      List<SoakTimelineEntry>.unmodifiable(_applied);

  /// What every applied entry did.
  List<SoakApplyOutcome> get outcomes =>
      List<SoakApplyOutcome>.unmodifiable(_outcomes);

  /// Entries the run never reached — planned and not applied.
  List<SoakTimelineEntry> get neverReached => <SoakTimelineEntry>[
        for (final entry in timeline.merged)
          if (!_applied.contains(entry)) entry,
      ];

  /// Levers that fired into nothing, rendered for a report.
  List<String> get fizzled => List<String>.unmodifiable(_fizzled);

  /// Per-panel connectivity, keyed by index.
  Map<int, SoakPanelHealth> get health => Map<int, SoakPanelHealth>.unmodifiable(_health);

  /// The control's connectivity.
  SoakPanelHealth get controlHealth => _health[soakControlPanelIndex]!;

  /// How many panels are ready right now.
  int get connectedPanels => _fixture == null
      ? 0
      : fixture.panels.where((one) => one.client.isReady).length;

  /// The floor the connected count must return to.
  int get populationFloor => herdSize - 1;

  Duration? _belowFloorSince;

  /// The longest continuous stretch spent below [populationFloor].
  Duration worstBelowFloor = Duration.zero;

  /// `planned` against `applied`, in `ScenarioPlayback.divergenceReport`'s
  /// shape and for its reason: a divergence between what was planned and what
  /// happened is the failure a soak cannot otherwise see, because both halves
  /// look fine on their own.
  String get divergenceReport {
    final missed = neverReached;
    return <String>[
      timeline.reproLog,
      '--- applied ${_applied.length} of ${timeline.merged.length} ---',
      for (final entry in _applied) entry.toString(),
      if (missed.isNotEmpty) ...<String>[
        '--- planned and NEVER REACHED (${missed.length}) ---',
        for (final entry in missed) entry.toString(),
      ],
      if (_fizzled.isNotEmpty) ...<String>[
        '--- applied and FIRED INTO NOTHING (${_fizzled.length}) ---',
        ..._fizzled,
      ],
    ].join('\n');
  }

  /// One line per checker, plus the driver's own population and control lines.
  ///
  /// **Printed on a green run too.** A green run's numbers are the baseline the
  /// next red run is read against, and a block that only appears on failure is
  /// a block nobody has ever seen working.
  String get verdictBlock {
    final lines = <String>[
      'soak verdict — seed=$seed duration=$duration endpoint=$endpoint',
      '  timeline    : ${timeline.merged.length} planned, '
          '${_applied.length} applied, ${neverReached.length} never reached, '
          '${_fizzled.length} fired into nothing',
      '  levers      : ${_leversByKind.entries.map((e) => '${e.key}:${e.value}').join(', ')}',
      '  population  : floor $populationFloor of $herdSize, connected now '
          '$connectedPanels, worst stretch below floor '
          '${formatSoakOffset(worstBelowFloor)} (grace '
          '${formatSoakOffset(floorGrace)})',
      for (var i = 0; i < herdSize; i++)
        '  ${i == soakControlPanelIndex ? 'CONTROL     ' : 'panel $i     '}: '
            '${_health[i]}',
    ];
    if (checkers.isEmpty) {
      lines.add('  checkers    : none registered — 11-04, 11-05 and 11-06 '
          'each add theirs against a driver that already works');
    } else {
      for (final registration in checkers) {
        final checker = registration.checker;
        lines.add('  ${checker.name.padRight(12)}: '
            '${checker.judgedSamples} judged readings against a floor of '
            '${checker.minimumSamplesForAVerdict}, ticked every '
            '${registration.cadence.inMilliseconds} ms, '
            '${checker.violations.length} violations');
      }
    }
    lines.add('  violations  : ${violationLog.total} recorded '
        '(${violationLog.entries.length} retained, ${violationLog.overflow} '
        'overflowed)');
    if (violationLog.entries.isNotEmpty) {
      lines.add('  first       : ${violationLog.entries.first}');
    }
    return lines.join('\n');
  }

  // ------------------------------------------------------------------ the run

  /// Builds the storm, refuses one that can reach the control, composes the
  /// pipe, writes `repro.log` and `config.json`, and starts the clock.
  ///
  /// **The refusal is the point and it happens before anything is composed.** A
  /// control panel the storm can reach is not a control, and the failure would
  /// otherwise be silent: every assertion still passes, and the one arm that
  /// could have caught a gateway punishing healthy panels has quietly stopped
  /// being able to.
  Future<void> start() async {
    if (!endpoint.isInProcess) {
      throw UnsupportedError('this driver composes its own gateway; dialling '
          '${endpoint.deployedGateway} is the on-site arm, which 11-CONTEXT '
          'ruling 6 records as a post-milestone follow-up. The seam is here '
          'so that arm is a change to this method rather than a rewrite of '
          'everything that composes — it is deliberately not built');
    }

    final storm = _given ??
        buildTimeline(
          seed: seed,
          duration: duration,
          // The control's name is NOT in this list, and that is the whole
          // mechanism: `soak_event.dart`'s contract puts the exclusion on the
          // caller because the generator cannot tell one panel from another.
          panels: stormPanels,
          aliases: soakAliases,
          keys: stormKeys,
        );
    _refuseIfTheStormCanReachTheControl(storm);
    _timeline = storm;

    // Before anything is composed: a run killed on the way up still leaves its
    // seed and its timeline behind.
    final journal = _journal = SoakJournal.open(seed: seed, path: journalPath);
    journal.writeReproLog(storm.reproLog);
    journal.writeConfig(<String, Object?>{
      'declaredDurationMs': duration.inMilliseconds,
      'herdSize': herdSize,
      'controlPanel': controlPanel,
      'stormPanels': stormPanels,
      'aliases': soakAliases,
      'keysPerAlias': soakKeysPerAlias,
      'sweepPeriodMs': soakSweepPeriod.inMilliseconds,
      'populationFloor': populationFloor,
      'populationFloorGraceMs': floorGrace.inMilliseconds,
      'panelSampleCadenceMs': panelSampleCadence.inMilliseconds,
      'checkpointCadenceMs': checkpointCadence.inMilliseconds,
      'endpoint': endpoint.toString(),
      'checkers': <String>[for (final one in checkers) one.checker.name],
      'mergedEntries': storm.merged.length,
      'stableWindows': storm.stableWindows.length,
    });

    _tokenDir = Directory.systemTemp.createTempSync('relay-soak-tokens-');
    _tokenFilePath = '${_tokenDir!.path}/tokens.json';
    _writeTokenFile();

    _fixture = await gateBFixture(
      panels: herdSize,
      aliases: soakAliases,
      keysPerAlias: soakKeysPerAlias,
      proxyPerPanel: true,
      sweepPeriod: soakSweepPeriod,
      serverConfig: ServerConfig(
        tick: ServerConfig.minTick,
        auth: AuthConfig(tokenFilePath: _tokenFilePath!),
      ),
      tokenFor: _tokenForPanel,
    );

    for (var i = 0; i < herdSize; i++) {
      _health[i] = SoakPanelHealth(i);
    }
    _clock = SoakClock(declaredDuration: duration);
    _startTickers();
  }

  /// Walks [SoakTimeline.merged] on one chained timer and returns when the run
  /// has played out or [stop] has been called.
  ///
  /// One timer, chained off one [Stopwatch], for `ScenarioPlayback`'s two
  /// reasons held whole: a lever that takes a moment to apply does not push
  /// every later offset out, and there is only ever one pending timer, so "no
  /// timer fires after [stop]" is a property of the shape rather than a
  /// bookkeeping claim.
  ///
  /// The run does not end at the last entry — it ends at [duration]. A storm
  /// whose last draw lands at minute 31 still has four minutes of plant, of
  /// checkers and of the population floor to answer for.
  Future<void> play() async {
    if (_stopped) {
      throw StateError('this driver has been stopped; build a new one rather '
          'than restarting it — a stopped driver schedules nothing, so play() '
          'would return a future that never completes and the failure would '
          'name the test file instead of this object');
    }
    final existing = _finished;
    if (existing != null) return existing.future;
    final finished = _finished = Completer<void>();
    _playClock.start();
    _schedule();
    await finished.future;
    // Whatever is still in flight — a write, a query, a redial — is given the
    // chance to land and to record itself before the verdict is read. `.wait`
    // rather than a loop of awaits: every one of these already carries its own
    // catchError into the violation log, so none of them can throw here.
    await Future.wait(_inFlight);
  }

  /// [start], then [play]. The whole run, minus the verdict, which the caller
  /// prints.
  Future<void> run() async {
    await start();
    await play();
  }

  /// Stops the storm and every ticker. Idempotent, and no timer fires after it.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _pending?.cancel();
    _pending = null;
    _playClock.stop();
    for (final ticker in _tickers) {
      ticker.cancel();
    }
    _tickers.clear();
    for (final recovery in _recoveries) {
      recovery.cancel();
    }
    _recoveries.clear();
    final finished = _finished;
    if (finished != null && !finished.isCompleted) finished.complete();
  }

  /// Backwards, no `.timeout`, journal last.
  ///
  /// Backwards because that is the order `gate_b_fixture.dart` argues for and
  /// this driver is one layer above it: tickers, then the storm, then the pipe,
  /// then the journal. The journal goes last because it is the only thing a
  /// failed run leaves behind, and a `.timeout` on a dispose path is a sink
  /// half-written (project memory: no `.timeout` in dispose paths).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    stop();
    for (final held in _subscriptions.values) {
      await held.cancel();
    }
    _subscriptions.clear();
    await _fixture?.dispose();
    final dir = _tokenDir;
    if (dir != null && dir.existsSync()) dir.deleteSync(recursive: true);
    // Last, and with no timeout: the artifact is the only thing a failed run
    // leaves behind.
    await _journal?.close();
  }

  // ---------------------------------------------------------------- internals

  final Stopwatch _playClock = Stopwatch();
  final List<Timer> _tickers = <Timer>[];
  final List<Timer> _recoveries = <Timer>[];
  final List<Future<void>> _inFlight = <Future<void>>[];
  final Map<String, StreamSubscription<DynamicValue>> _subscriptions =
      <String, StreamSubscription<DynamicValue>>{};
  final Set<int> _revoked = <int>{};
  Completer<void>? _finished;
  Timer? _pending;
  int _index = 0;
  int _reloads = 0;
  bool _stopped = false;
  bool _disposed = false;

  /// Plant keys only — the `PIPE.*` health keys the fixture also subscribes are
  /// deliberately not here.
  ///
  /// `[MT-6]`'s instruction is that the driver must not make 11-04's job
  /// harder: its freshness checker excludes the health keys by prefix, because
  /// a `PIPE.` value is the pipe reporting on itself and is not a plant reading
  /// that can be stale. Rather than only avoiding the problem, this getter
  /// hands the next plan the exact set it wants.
  List<String> get plantKeys => <String>[
        for (final alias in soakAliases) ...gateBPage(alias, soakKeysPerAlias),
      ];

  /// The key pool the storm draws its writes and mutations from.
  ///
  /// A slice of [plantKeys] rather than all of it, matching
  /// `SoakEventSchedule.keysPerAlias`: a storm that spread its mutations over
  /// forty keys would touch each one about twice in thirty-five minutes, and
  /// invariant 3's comparison wants keys that actually move.
  List<String> get stormKeys => <String>[
        for (final alias in soakAliases)
          ...gateBPage(alias, soakKeysPerAlias)
              .take(SoakEventSchedule.keysPerAlias),
      ];

  /// Panel *i*'s credential. Deterministic, long enough for
  /// `FileTokenValidator.minTokenLength`, and visibly a fixture rather than
  /// something anybody would mistake for a plant secret.
  String _tokenForPanel(int index) =>
      'soak-${soakPanelName(index)}-000000000000000';

  /// Writes the credential set as it now stands, owner-only.
  ///
  /// **A file rewrite, not an in-memory call, and that is the shape of the real
  /// mechanism.** `AuthConfig` holds a path and never a secret, so revocation
  /// at SVN is an operator editing the mounted file and the gateway re-reading
  /// it. `RelayServer.reloadTokens` is the re-read; this is the edit.
  void _writeTokenFile() {
    final path = _tokenFilePath!;
    File(path).writeAsStringSync(jsonEncode(<String, Object?>{
      'tokens': <String, Object?>{
        for (var i = 0; i < herdSize; i++)
          if (!_revoked.contains(i))
            _tokenForPanel(i): <String, Object?>{
              'stationId': soakPanelName(i),
              'role': 'operate',
            },
      },
    }));
    if (!Platform.isWindows) {
      // `FileTokenValidator.load` refuses a credential file any other account
      // can read, which is the right rule and one a temp file does not meet by
      // default.
      Process.runSync('chmod', <String>['600', path]);
    }
  }

  /// Throws unless every entry of [storm] leaves the control alone.
  void _refuseIfTheStormCanReachTheControl(SoakTimeline storm) {
    if (storm.panels.contains(controlPanel)) {
      throw StateError('this timeline was generated with $controlPanel in its '
          'panel list, so the storm may aim at the control. The exclusion is '
          'the CALLER\'s — soak_event.dart cannot tell a control panel from an '
          'ordinary one — and a control the storm can reach is not a control: '
          'every invariant still passes and the one arm that could catch a '
          'gateway punishing healthy panels has quietly stopped being able to');
    }
    for (final entry in storm.merged) {
      final payload = entry.payload;
      if (payload is! SoakEvent) continue;
      final aimed = _panelNamedBy(payload);
      if (aimed == controlPanel) {
        throw StateError('timeline entry $entry aims at $controlPanel, which '
            'is the control panel this run\'s strongest assertion rests on. '
            'A control the storm can reach is not a control, and the failure '
            'would be silent — every invariant would still pass');
      }
    }
  }

  /// Which panel an event is aimed at, or null for the plant-wide arms.
  String? _panelNamedBy(SoakEvent event) => switch (event) {
        PanelSubscribe(:final panel) => panel,
        PanelUnsubscribe(:final panel) => panel,
        PanelWrite(:final panel) => panel,
        PanelQuery(:final panel) => panel,
        TokenRevocation(:final stationId) => stationId,
        TokenRestore(:final stationId) => stationId,
        // Plant-wide by nature: an upstream link, an epoch, the routing table
        // and the gateway process itself belong to everybody. The control is
        // not exempt from a gateway restart — nothing could make it so — which
        // is why the control's property is "the storm never AIMS at it" rather
        // than "it is never disturbed".
        UpstreamLinkDown() ||
        UpstreamLinkUp() ||
        UpstreamEpochBump() ||
        UpstreamMassDegrade() ||
        UpstreamSlowResolve() ||
        GatewayRestart() ||
        KeymappingReload() ||
        PlantMutate() =>
          null,
      };

  int _indexOfPanel(String name) {
    for (var i = 0; i < herdSize; i++) {
      if (soakPanelName(i) == name) return i;
    }
    throw StateError('no panel named "$name" in a herd of $herdSize');
  }

  void _startTickers() {
    _tickers.add(Timer.periodic(panelSampleCadence, (_) => _samplePanels()));
    _tickers.add(Timer.periodic(checkpointCadence, (_) => _checkpoint()));
    for (final registration in checkers) {
      _tickers.add(Timer.periodic(registration.cadence,
          (_) => registration.checker.sample(clock)));
    }
  }

  /// One connectivity reading per panel, and the floor evaluated against it.
  void _samplePanels() {
    if (_stopped || _disposed) return;
    final panels = fixture.panels;
    for (var i = 0; i < panels.length; i++) {
      final client = panels[i].client;
      _health[i]!.observe(
        ready: client.isReady,
        staleView: client.viewIsStale,
      );
    }
    _evaluatePopulationFloor();
  }

  /// The floor: at most one panel missing, and never for longer than
  /// [floorGrace].
  ///
  /// A breach is a **violation with its offset**, never an abort. A soak that
  /// stopped at the first breach would report one finding and leave the other
  /// four invariants' thirty minutes unmeasured, which is the whole argument
  /// for a driver that ticks checkers rather than a `test()` body that asserts.
  void _evaluatePopulationFloor() {
    final connected = connectedPanels;
    final now = clock.elapsed;
    if (connected >= populationFloor) {
      _belowFloorSince = null;
      return;
    }
    final since = _belowFloorSince ??= now;
    final stretch = now - since;
    if (stretch > worstBelowFloor) worstBelowFloor = stretch;
    if (stretch <= floorGrace) return;
    // One violation per breach, not one per sample: the log is capped at two
    // hundred and a permanently culled herd would otherwise fill it with the
    // same finding four times a second and push every other checker's first
    // occurrence out.
    if (_floorBreachReported) return;
    _floorBreachReported = true;
    _record(SoakViolation(
      checker: 'population',
      monotonic: now,
      scheduleOffset: _playClock.elapsed,
      detail: 'only $connected of $herdSize panels have been connected for '
          '${formatSoakOffset(stretch)}, under a floor of $populationFloor and '
          'past a grace of ${formatSoakOffset(floorGrace)}. Every per-panel '
          'invariant is now passing on a fraction of the population with '
          'nothing else saying so',
      observed: connected,
      expected: populationFloor,
    ));
  }

  bool _floorBreachReported = false;

  void _record(SoakViolation violation) {
    violationLog.add(violation);
    _journal?.writeTrip(violation, armedModes: _armedModesAt(violation));
  }

  /// Which link modes the *timeline* had armed at a violation's offset.
  ///
  /// A lookup into the artifact everybody else reads, never a running mirror of
  /// proxy state — `soak_journal.dart`'s rule, and its reason: a mirror can
  /// disagree with the proxy, and the one thing worse than not recording the
  /// armed modes is recording the wrong ones.
  List<String> _armedModesAt(SoakViolation violation) {
    final at = violation.scheduleOffset;
    if (at == null || _timeline == null) return const <String>[];
    final armed = <String>{};
    for (final entry in timeline.merged) {
      if (entry.offset > at) break;
      final payload = entry.payload;
      if (payload is! FaultMutation) continue;
      if (payload.arms) {
        armed.add(payload.mode);
      } else {
        armed.remove(payload.mode);
      }
    }
    return armed.toList(growable: false);
  }

  void _checkpoint() {
    if (_stopped || _disposed) return;
    journal.checkpoint(clock, <String, Object?>{
      'connectedPanels': connectedPanels,
      'populationFloor': populationFloor,
      'worstBelowFloorMs': worstBelowFloor.inMilliseconds,
      'appliedEntries': _applied.length,
      'fizzled': _fizzled.length,
      'violations': violationLog.total,
      'panels': <Object?>[for (final one in _health.values) one.toJson()],
      'rss': ProcessInfo.currentRss,
      'checkers': <String, Object?>{
        for (final one in checkers)
          one.checker.name: <String, Object?>{
            'judgedSamples': one.checker.judgedSamples,
            'floor': one.checker.minimumSamplesForAVerdict,
            'violations': one.checker.violations.length,
          },
      },
    });
  }

  void _schedule() {
    if (_stopped) return;
    final finished = _finished;
    if (_index >= timeline.merged.length) {
      // The storm is spent but the run is not: hold to the declared duration so
      // the tail of a run is measured rather than skipped.
      final remaining = duration - _playClock.elapsed;
      if (remaining <= Duration.zero) {
        _playClock.stop();
        if (finished != null && !finished.isCompleted) finished.complete();
        return;
      }
      _pending = Timer(remaining, () {
        _pending = null;
        if (_stopped) return;
        _playClock.stop();
        if (finished != null && !finished.isCompleted) finished.complete();
      });
      return;
    }
    final due = timeline.merged[_index].offset - _playClock.elapsed;
    _pending = Timer(due < Duration.zero ? Duration.zero : due, _fire);
  }

  Future<void> _fire() async {
    _pending = null;
    if (_stopped) return;
    final entry = timeline.merged[_index];
    SoakApplyOutcome outcome;
    try {
      outcome = await _applyEntry(entry);
    } catch (error, stack) {
      // A lever that threw is a violation and not the end of the run: the other
      // four hundred entries still have something to say.
      outcome = SoakApplyOutcome.fizzled(
          _kindOf(entry), 'threw', '$error\n${stack.toString().split('\n').take(3).join('\n')}');
      _record(SoakViolation(
        checker: 'population',
        monotonic: clock.elapsed,
        scheduleOffset: entry.offset,
        detail: 'the lever for $entry threw: $error',
      ));
    }
    // Checked after the await, for `ScenarioPlayback._fire`'s reason: stop()
    // may have run while a lever that awaits its own teardown was in flight,
    // and appending here would leave an applied log with an entry after the
    // stop that ended the run.
    if (_stopped) return;
    _applied.add(entry);
    _outcomes.add(outcome);
    _leversByKind.update(outcome.kind, (n) => n + 1, ifAbsent: () => 1);
    if (!outcome.fired) _noteFizzle(entry.offset, outcome);
    journal.event(clock, <String, Object?>{
      'offsetMs': entry.offset.inMilliseconds,
      'stream': SoakStreams.labelOf(entry.streamIndex),
      'payload': entry.payload.toString(),
      ...outcome.toJson(),
    });
    _index++;
    _schedule();
  }

  String _kindOf(SoakTimelineEntry entry) {
    final payload = entry.payload;
    if (payload is SoakEvent) return payload.kind;
    if (payload is FaultMutation) return 'link:${payload.mode}';
    return 'unknown';
  }

  /// Link and quiet-clear entries go to a proxy; event entries go to [apply].
  Future<SoakApplyOutcome> _applyEntry(SoakTimelineEntry entry) async {
    final payload = entry.payload;
    // `_applyEvent` and not `apply`: the public entry point records a fizzle
    // itself, so that a lever pulled from anywhere is reported, and `_fire`
    // below records for every stream. Going through `apply` here would count
    // an event's fizzle twice.
    if (payload is SoakEvent) return _applyEvent(payload);
    if (payload is FaultMutation) {
      final index = panelForMode(payload.mode);
      final panel = fixture.panels[index];
      // `ScenarioPlayback.apply` and not a second switch: it is the existing
      // exhaustive switch over the sealed FaultMutation, and a ninth proxy
      // lever must fail to compile in one place, not two.
      await ScenarioPlayback.apply(panel.proxy, payload);
      _health[index]!.mutationsApplied++;
      return SoakApplyOutcome.fired(
          'link:${payload.mode}', 'FaultProxy.${payload.mode}',
          note: 'panel $index');
    }
    throw StateError('a merged timeline entry carried a ${payload.runtimeType}, '
        'which is neither a SoakEvent nor a FaultMutation: $entry');
  }

  void _track(Future<void> work, String what) {
    _inFlight.add(work.catchError((Object error) {
      _record(SoakViolation(
        checker: 'population',
        monotonic: _clock == null ? Duration.zero : clock.elapsed,
        scheduleOffset: _playClock.elapsed,
        detail: '$what failed after the lever returned: $error',
      ));
    }));
  }

  // ------------------------------------------------------------- the levers

  /// Which panel's proxy carries [mode].
  ///
  /// **By mode, never round-robin, and the control is not in the range.** The
  /// link half arms and clears: a `flap` armed at +12 s is cleared at +19 s by
  /// a later entry or by a quiet window's injected clear. Partitioning entries
  /// by position would send an arm to one panel and its clear to another,
  /// leaving the first flapping for the rest of the run and the second clearing
  /// something it never had. Partitioning by *mode* keeps every arm with its
  /// own clear, and with `ScenarioWeights.soak`'s four arming modes and four
  /// stormed panels it also happens to give each stormed panel its own weather:
  /// panel 1 flaps, panel 2 is slow, panel 3 is throttled, panel 4 is
  /// blackholed. The control gets none of it, which is the whole point.
  int panelForMode(String mode) {
    final declared = faultModes.indexOf(mode);
    if (declared < 0) {
      throw ArgumentError.value(mode, 'mode', 'not in faultModes, so no proxy '
          'lever answers to it and the storm would arm nothing');
    }
    final stormed = herdSize - 1;
    return 1 + declared % stormed;
  }

  /// Pulls the lever one [SoakEvent] names.
  ///
  /// **An exhaustive switch over the sealed type, with no `default:` arm
  /// anywhere.** A fifteenth arm added to `soak_event.dart` is a compile error
  /// here rather than a storm entry that logs itself and does nothing — which
  /// is the entire reason 11-02 made the type sealed.
  Future<SoakApplyOutcome> apply(SoakEvent event) async {
    final outcome = await _applyEvent(event);
    // Recorded here rather than only on the playback path, so that a lever
    // pulled by anything — a case, a later plan's own harness — cannot fire
    // into nothing without the driver saying so. `_applyEntry` deliberately
    // calls `_applyEvent` instead, or a played event would be counted twice.
    if (!outcome.fired) _noteFizzle(_playClock.elapsed, outcome);
    return outcome;
  }

  void _noteFizzle(Duration at, SoakApplyOutcome outcome) =>
      _fizzled.add('[${formatSoakOffset(at)}] $outcome');

  Future<SoakApplyOutcome> _applyEvent(SoakEvent event) async {
    switch (event) {
      case UpstreamLinkDown(:final alias):
        final link = fixture.linkFor(alias);
        if (link.inner.state == UpstreamLinkState.disconnected) {
          return SoakApplyOutcome.fizzled(event.kind,
              'FakeUpstreamLink.disconnectUpstream',
              '$alias was already down; disconnectUpstream returns early '
                  '(fake_upstream_link.dart:397), so this entry narrowed the '
                  'storm instead of widening it');
        }
        link.inner.disconnectUpstream();
        return SoakApplyOutcome.fired(
            event.kind, 'FakeUpstreamLink.disconnectUpstream');

      case UpstreamLinkUp(:final alias):
        final link = fixture.linkFor(alias);
        if (link.inner.state != UpstreamLinkState.disconnected) {
          return SoakApplyOutcome.fizzled(
              event.kind,
              'FakeUpstreamLink.reconnectUpstream',
              '$alias was already up, so its paired recovery restored nothing');
        }
        link.inner.reconnectUpstream();
        return SoakApplyOutcome.fired(
            event.kind, 'FakeUpstreamLink.reconnectUpstream');

      case UpstreamEpochBump(:final alias):
        // The plain fake's bump, not `GateBLink.bumpEpoch`'s four-step
        // choreography. The choreographed one raises a latch that only
        // `completeReBrowse` lowers, and nothing in the timeline carries a
        // re-browse-complete arm — closing it on a driver-invented timer would
        // be the driver authoring an event, which is the one thing this class
        // must not do. `soak_event.dart`'s own doc names `FakeUpstreamLink
        // .bumpEpoch()` as this arm's lever.
        final link = fixture.linkFor(alias);
        final before = link.inner.epoch;
        link.inner.bumpEpoch();
        return SoakApplyOutcome.fired(
            event.kind, 'FakeUpstreamLink.bumpEpoch',
            note: '$alias $before -> ${link.inner.epoch}');

      case UpstreamMassDegrade(:final alias):
        // 08-09's pair, kept separate on the fake precisely so this reads as
        // one announcement for however many keys.
        final link = fixture.linkFor(alias);
        final before = link.inner.statusNotifications;
        link.inner.applyLinkLoss();
        link.inner.announceLinkState();
        return SoakApplyOutcome.fired(
            event.kind, 'FakeUpstreamLink.applyLinkLoss+announceLinkState',
            note: '$alias, announcements $before -> '
                '${link.inner.statusNotifications}');

      case UpstreamSlowResolve(:final alias, :final latency):
        final link = fixture.linkFor(alias);
        link.inner.readLatency = latency;
        link.inner.writeLatency = latency;
        // Cleared after the span the GENERATOR declares for this kind, not
        // after one this file invented: `recoverySpanOf` is what the generator
        // uses to keep the storm out of a quiet window, so honouring it is the
        // driver agreeing with the timeline rather than authoring against it.
        // Without a clear the alias stays slow for the rest of the run, and no
        // arm emits a reset.
        _scheduleRecovery(
            SoakEventSchedule.recoverySpanOf(event.kind), () {
          link.inner.readLatency = Duration.zero;
          link.inner.writeLatency = Duration.zero;
        });
        return SoakApplyOutcome.fired(
            event.kind, 'FakeUpstreamLink.readLatency+writeLatency',
            note: '$alias ${latency.inMilliseconds}ms for '
                '${SoakEventSchedule.recoverySpanOf(event.kind).inSeconds}s');

      case GatewayRestart():
        final before = fixture.server.port;
        await fixture.restartGateway();
        return SoakApplyOutcome.fired(
            event.kind, 'GateBFixture.restartGateway',
            note: 'rebound port $before; every panel redials');

      case TokenRevocation(:final stationId):
        final index = _indexOfPanel(stationId);
        if (_revoked.contains(index)) {
          return SoakApplyOutcome.fizzled(event.kind,
              'RelayServer.reloadTokens',
              '$stationId was already revoked, so the rewrite changed nothing '
                  'and no session was swept');
        }
        _revoked.add(index);
        _writeTokenFile();
        await fixture.server.reloadTokens();
        return SoakApplyOutcome.fired(
            event.kind, 'RelayServer.reloadTokens',
            note: '$stationId dropped from the token file and swept (4001)');

      case TokenRestore(:final stationId):
        final index = _indexOfPanel(stationId);
        if (!_revoked.remove(index)) {
          return SoakApplyOutcome.fizzled(
              event.kind,
              'GateBFixture.redial',
              '$stationId was not revoked, so there was nothing to restore');
        }
        _writeTokenFile();
        await fixture.server.reloadTokens();
        // The rewrite alone does not bring the panel back. Phase 6 ends the
        // reconnect loop for good on a refused credential — by design — so a
        // restore is an application restart, and that is what `redial` is.
        // Not awaited: a panel coming back must not hold the storm's clock.
        _track(fixture.redial(index), 'the redial of $stationId after restore');
        return SoakApplyOutcome.fired(event.kind, 'GateBFixture.redial',
            note: '$stationId back in the token file; a new client dialled');

      case KeymappingReload():
        // Alternating between the shipped table and the same table plus one
        // spare key nobody subscribes. Deterministic — a function of how many
        // reloads the timeline has already asked for — so it stays replayable,
        // and not a no-op: re-ingesting a byte-identical table would classify
        // nothing, add nothing and re-point nothing, which is a lever firing
        // into its own reflection.
        final spare = _reloads.isEven;
        final next = spare
            ? KeyMappings(nodes: <String, KeyMappingEntry>{
                ...fixture.mappings.nodes,
                _spareKey: opcUaEntry(
                    alias: soakAliases.first, identifier: _spareKey),
              })
            : fixture.mappings;
        _reloads++;
        final result = fixture.plant.router.applyKeyMappings(next);
        final moved = result.added.length +
            result.removed.length +
            result.changed.length;
        if (moved == 0) {
          return SoakApplyOutcome.fizzled(event.kind,
              'KeyRouter.applyKeyMappings',
              're-ingesting the routing table added, removed and changed '
                  'nothing, so nothing was re-pointed');
        }
        return SoakApplyOutcome.fired(
            event.kind, 'KeyRouter.applyKeyMappings',
            note: '${result.added.length} added, ${result.removed.length} '
                'removed, ${result.changed.length} changed, '
                '${result.rejected.length} rejected');

      case PanelSubscribe(:final panel, :final keys):
        final client = fixture.panels[_indexOfPanel(panel)].client;
        final opened = <String>[];
        for (final key in keys) {
          final handle = '$panel|$key';
          if (_subscriptions.containsKey(handle)) continue;
          _subscriptions[handle] = client.subscribe(key).listen((_) {});
          opened.add(key);
        }
        if (opened.isEmpty) {
          return SoakApplyOutcome.fizzled(
              event.kind,
              'RemoteStateMan.subscribe',
              '$panel already held every one of ${keys.join('+')}');
        }
        return SoakApplyOutcome.fired(event.kind, 'RemoteStateMan.subscribe',
            note: '$panel opened ${opened.join('+')}');

      case PanelUnsubscribe(:final panel, :final keys):
        final dropped = <String>[];
        for (final key in keys) {
          final held = _subscriptions.remove('$panel|$key');
          if (held == null) continue;
          await held.cancel();
          dropped.add(key);
        }
        if (dropped.isEmpty) {
          return SoakApplyOutcome.fizzled(
              event.kind,
              'StreamSubscription.cancel',
              '$panel held no subscription to ${keys.join('+')}, so this '
                  'unsubscribe cancelled nothing');
        }
        return SoakApplyOutcome.fired(
            event.kind, 'StreamSubscription.cancel',
            note: '$panel dropped ${dropped.join('+')}');

      case PanelWrite(:final panel, :final key, :final value):
        final index = _indexOfPanel(panel);
        final client = fixture.panels[index].client;
        if (!client.isReady) {
          return SoakApplyOutcome.fizzled(event.kind, 'RemoteStateMan.write',
              '$panel is not connected, so the operator action never reached '
                  'a socket');
        }
        // Not awaited: a write's three-state outcome can take the whole write
        // deadline, and a storm that waited for it would drift its own
        // timeline. The future carries its own catchError into the violation
        // log; a refusal is an ordinary outcome and lands on `onWriteResolved`,
        // which is 11-05's to judge.
        _track(client.write(key, value).then((_) {}),
            'the write $panel $key=$value');
        return SoakApplyOutcome.fired(event.kind, 'RemoteStateMan.write',
            note: '$panel $key=$value');

      case PanelQuery(:final panel, :final series, :final window):
        final client = fixture.panels[_indexOfPanel(panel)].client;
        if (!client.isReady) {
          return SoakApplyOutcome.fizzled(
              event.kind,
              'ClientTimeseriesApi.queryTimeseriesData',
              '$panel is not connected, so the query never reached a socket');
        }
        // Anchored on a fixed instant rather than on the wall clock: freeze 9
        // keeps `DateTime.now()` out of the soak trees, and a query window is
        // not a measurement of anything here. There is no database in this
        // lane, so a refusal is entirely ordinary — what the soak asserts is
        // that a query answers or refuses and never drops the session.
        _track(
            client.timeseries
                .queryTimeseriesData(series, _queryAnchor,
                    from: _queryAnchor.subtract(window))
                .then((_) {}, onError: (Object _) {}),
            'the query $panel $series');
        return SoakApplyOutcome.fired(
            event.kind, 'ClientTimeseriesApi.queryTimeseriesData',
            note: '$panel $series over ${window.inMinutes}m');

      case PlantMutate(:final key, :final value):
        final alias = key.split('.').first;
        if (!soakAliases.contains(alias)) {
          return SoakApplyOutcome.fizzled(event.kind,
              'GateBPlantDriver.overrideRaw',
              'no link carries "$key", so the plant did not move');
        }
        // `overrideRaw` rather than one `setValue`: the plant driver sweeps
        // every key every 250 ms, so a single write is overwritten before any
        // panel could see it. An override is what a real device does — it
        // keeps reporting the new number until something changes it — and it
        // is what makes "plant truth" a thing invariant 3 can compare against.
        fixture.driver.overrideRaw(fixture.linkFor(alias), key, value);
        return SoakApplyOutcome.fired(
            event.kind, 'GateBPlantDriver.overrideRaw',
            note: '$key=$value from the next poll cycle on');
    }
  }

  /// A key no panel subscribes, so [KeymappingReload] can move the routing
  /// table without moving anything a checker is watching.
  static const String _spareKey = 'ST101.CN99.SPARE01.setpoint';

  /// A fixed instant for [PanelQuery]'s window. Not a clock: freeze 9 keeps the
  /// wall out of the soak trees, and this decides nothing.
  static final DateTime _queryAnchor = DateTime.utc(2026, 1, 1);

  void _scheduleRecovery(Duration after, void Function() recover) {
    late final Timer timer;
    timer = Timer(after, () {
      _recoveries.remove(timer);
      if (_stopped || _disposed) return;
      recover();
    });
    _recoveries.add(timer);
  }
}
