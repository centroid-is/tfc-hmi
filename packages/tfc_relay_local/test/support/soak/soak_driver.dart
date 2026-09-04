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

import 'package:tfc_relay_client/tfc_relay_client.dart';
import 'package:tfc_relay_local/tfc_relay_local.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:tfc_stateman_contract/faults.dart';

import '../gate_b_fixture.dart';
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
    throw UnimplementedError('divergenceReport');
  }

  /// One line per checker, plus the driver's own population and control lines.
  ///
  /// **Printed on a green run too.** A green run's numbers are the baseline the
  /// next red run is read against, and a block that only appears on failure is
  /// a block nobody has ever seen working.
  String get verdictBlock {
    throw UnimplementedError('verdictBlock');
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
    throw UnimplementedError('start');
  }

  /// Walks [SoakTimeline.merged] on one chained timer and returns when the run
  /// has played out or [stop] has been called.
  Future<void> play() async {
    throw UnimplementedError('play');
  }

  /// [start], then [play]. The whole run, minus the verdict, which the caller
  /// prints.
  Future<void> run() async {
    await start();
    await play();
  }

  /// Stops the storm and every ticker. Idempotent, and no timer fires after it.
  void stop() {
    throw UnimplementedError('stop');
  }

  /// Backwards, no `.timeout`, journal last.
  ///
  /// Backwards because that is the order `gate_b_fixture.dart` argues for and
  /// this driver is one layer above it: tickers, then the storm, then the pipe,
  /// then the journal. The journal goes last because it is the only thing a
  /// failed run leaves behind, and a `.timeout` on a dispose path is a sink
  /// half-written (project memory: no `.timeout` in dispose paths).
  Future<void> dispose() async {
    throw UnimplementedError('dispose');
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
    throw UnimplementedError('panelForMode');
  }

  /// Pulls the lever one [SoakEvent] names.
  ///
  /// **An exhaustive switch over the sealed type, with no `default:` arm
  /// anywhere.** A fifteenth arm added to `soak_event.dart` is a compile error
  /// here rather than a storm entry that logs itself and does nothing — which
  /// is the entire reason 11-02 made the type sealed.
  Future<SoakApplyOutcome> apply(SoakEvent event) async {
    throw UnimplementedError('apply');
  }
}
