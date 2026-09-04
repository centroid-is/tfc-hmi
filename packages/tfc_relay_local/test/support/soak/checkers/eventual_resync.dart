/// Invariant 3 — after each generated stable window, every subscribed key on
/// every panel equals plant truth, on **value and quality**.
///
/// **The gift of a pure generator.** Because the whole schedule exists before
/// the clock starts, 11-02 computed every interval in which nothing is armed
/// and nothing arms for at least [minStableWindow]. Those are the windows in
/// which convergence is *required* rather than hoped for, and this checker is
/// told where they are instead of watching for quiet reactively. Reactive
/// detection would have been vacuous most runs — 11-02 measured it: without
/// injection only 13 of 20 seeds clear an eight-window floor and the best
/// window in any run is 25.5 s.
///
/// **Quality is compared and not only value**, and this is the decision that
/// makes the epoch path visible at all. A panel rendering the right number
/// under `badStale` is a panel that has stopped vouching for it; treating that
/// as a match would report the whole `epochChange` cause as convergence and
/// the taxonomy would be five arms wide. `SoakPlantTruth.quality` is always
/// good — the fake plant publishes nothing degraded — so any degradation a
/// panel renders was produced by the pipe, which is exactly what is worth
/// asking about.
///
/// **Two comparisons, because the fixture has two kinds of key.**
/// `GateBPlantDriver` sweeps every clean key to one monotonically increasing
/// integer every 250 ms, and a `PlantMutate` pins one key to a fixed value
/// republished every cycle thereafter. An overridden key is judged on equality
/// because its expected value stands still. A swept key is judged on **lag in
/// sweeps**, because a value that changes four times a second is never
/// instantaneously equal to anything: demanding equality would report the
/// wire's own transit time as a divergence, two hundred of them per sample, on
/// a healthy pipe. See [convergedLagSweeps] for the allowance and where it came
/// from.
///
/// **What this checker does NOT do is judge.** A mismatch is a divergence
/// *event* handed to the [DivergenceLedger] with an attributed cause, not a
/// violation. The only things it records as violations are the two failures
/// that are about the instrument rather than about the pipe: a run that
/// produced no qualifying windows, and the never-faulted control panel
/// diverging in a window the storm never disturbed.
library;

import 'package:tfc_relay_client/tfc_relay_client.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../divergence_ledger.dart';
import '../invariant.dart';
import '../soak_event.dart';
import '../soak_observables.dart';
import '../soak_timeline.dart';

/// How many sweeps behind plant truth a panel may be and still be converged.
///
/// **One, and every term is somebody else's number.** The plant moves every key
/// every `soakSweepPeriod` (250 ms) and the pipe is asynchronous: at any
/// instant the newest sweep may be anywhere between the fake link's cache and
/// the panel's store — through ingest, a gateway tick at `ServerConfig.minTick`,
/// an encode, a socket and a decode. A sample taken between a sweep and its
/// delivery legitimately sees the previous value, and that is one sweep.
///
/// **Two sweeps is 500 ms of lag with nothing armed**, which is well past every
/// mechanism that could legitimately be holding the value, so it is a
/// divergence. The measurement behind that claim is printed on every run by
/// [EventualResyncChecker.convergenceReport]: the lag distribution at window
/// ends, which on a healthy run sits at zero and one.
///
/// Stated as a count of sweeps rather than as a duration on purpose — the
/// quantity that actually exists is "how many of the plant's own frames has
/// this panel missed", and converting it to milliseconds at the comparison site
/// would invite somebody to tune the milliseconds.
const int convergedLagSweeps = 1;

/// How often invariant 3 reads the herd.
///
/// **250 ms, the plant's own sweep period**, and neither the checkpoint cadence
/// nor the fast one. Five seconds would give a ten-second window two readings,
/// which cannot measure a convergence time and cannot tell a divergence that
/// healed in the first second from one that survived; 25 ms would take forty
/// readings of two hundred values a second for the whole run to resolve
/// something the plant only moves four times a second. Sampling at the rate the
/// observable actually changes is the whole of the argument.
///
/// The cost is bounded by the windows: this checker does nothing outside one,
/// so the lane arm samples for thirty of its ninety seconds and the
/// thirty-five-minute arm for 160 of its 2,100.
const Duration resyncCheckerCadence = Duration(milliseconds: 250);

/// The health namespace, excluded by prefix.
///
/// `PIPE.` keys are produced by the gateway and never by the plant, so there is
/// no plant truth to compare them against. Excluded **by prefix here** rather
/// than by handing the checker a pre-filtered list, which is 08-PATTERNS freeze
/// 8's rule: a filtered list moves the decision to the caller and makes this
/// exclusion untestable.
const String pipeKeyPrefix = 'PIPE.';

/// One key on one panel, seen to disagree with the plant.
final class _OpenDivergence {
  _OpenDivergence({
    required this.panelIndex,
    required this.key,
    required this.openedAt,
    required this.openedAtSchedule,
    required this.windowIndex,
    required this.generationAtOpen,
    required this.complaintsAtOpen,
  });

  final int panelIndex;
  final String key;
  final Duration openedAt;
  final Duration openedAtSchedule;
  final int windowIndex;
  final int generationAtOpen;
  final int complaintsAtOpen;

  /// The generation seen at the previous sample, so a reading that straddles a
  /// rebuild can be told from one taken after it settled.
  int generationAtLastSample = -1;
}

/// Invariant 3.
final class EventualResyncChecker
    with GuardedSampling
    implements SoakRunEndCheck {
  EventualResyncChecker(this._source, this.ledger);

  final SoakResyncSource _source;

  /// Where every divergence goes. Held rather than created so that
  /// `soak_test.dart` can register both and the audit sees both.
  final DivergenceLedger ledger;

  @override
  String get name => 'eventualResync';

  @override
  final ViolationLog violationLog = ViolationLog();

  final Map<String, _OpenDivergence> _open = <String, _OpenDivergence>{};

  /// How many divergences this checker has emitted, for the ledger's `nth`.
  int _emitted = 0;

  int _windowsJudged = 0;
  int _keysComparedThisWindow = 0;
  int _keysComparedTotal = 0;
  int _currentWindow = -1;
  int _plantWideArmsAtWindowStart = 0;
  bool _windowDisturbed = false;

  /// Every lag reading taken at a window's last sample, in sweeps.
  final List<int> _lagAtWindowEnd = <int>[];

  /// How long each divergence took to heal, in milliseconds. The distribution
  /// [minStableWindow] is measured against.
  final List<int> _convergenceMs = <int>[];

  /// Divergences the never-faulted control panel produced, by window.
  final List<String> _controlDivergences = <String>[];

  /// Whether the ledger's positive control has fired.
  bool _controlFired = false;

  /// One panel-and-key the control lies about, chosen at the first window's
  /// end. Null until then.
  String? _controlTarget;

  // ------------------------------------------------------------- the counters

  /// **Windows measured, not readings taken.** A window in which nothing was
  /// compared is not a window — every panel could have been down — so
  /// [_windowsJudged] advances only when [_keysComparedThisWindow] is non-zero,
  /// and that is asserted rather than assumed at [finish].
  @override
  int get judgedSamples => _windowsJudged;

  /// One fewer than the timeline will generate, floored at one.
  ///
  /// **The numbers, from 11-02's own arithmetic and re-derived here so a
  /// printed count can be checked:** `computeStableWindows` puts **3** windows
  /// of 10 s in the 90-second lane (the quiet-fraction cap binds) and **8**
  /// windows of 20 s in the 35-minute arm (the cadence term binds). So the
  /// floors are **2** and **7**.
  ///
  /// **Why one is subtracted rather than none.** A window in which every panel
  /// is down compares nothing and is honestly not a window; the storm is
  /// entitled to take panels down, and 11-05 measured a 35-minute run in which
  /// panel-1 was absent for the last fifteen minutes. Demanding every window
  /// would make this floor a statement about the population rather than about
  /// the instrument. One is the whole of the slack, and a run that loses two
  /// windows has something worth failing over.
  ///
  /// **The zero-window case is the sharp one** and it is handled separately at
  /// [finish], not by this floor: `max(1, ...)` means a timeline that generated
  /// no windows at all fails against a floor of one, naming both numbers.
  @override
  int get minimumSamplesForAVerdict {
    final generated = computeStableWindows(_source.declaredDuration).length;
    final floor = generated - 1;
    return floor < 1 ? 1 : floor;
  }

  // -------------------------------------------------------------- the sample

  @override
  void takeReading(SoakClock clock) {
    final windows = _source.stableWindows;
    final at = _source.scheduleOffset;
    final index = _windowContaining(windows, at);

    if (index != _currentWindow) {
      if (_currentWindow >= 0) _closeWindow(clock, _currentWindow);
      _currentWindow = index;
      if (index >= 0) {
        _keysComparedThisWindow = 0;
        _plantWideArmsAtWindowStart = _source.plantWideArmsApplied;
        _windowDisturbed = false;
      }
    }
    if (index < 0) return;
    if (_source.plantWideArmsApplied != _plantWideArmsAtWindowStart) {
      _windowDisturbed = true;
    }

    final keys = <String>[
      for (final key in _source.freshnessKeys)
        if (!key.startsWith(pipeKeyPrefix)) key,
    ];

    for (final panel in _source.panelResyncViews) {
      for (final key in keys) {
        final plant = _source.plantTruthFor(key);
        if (plant == null) continue;
        final client = panel.read(key);
        if (client == null) continue;
        _keysComparedThisWindow++;
        _keysComparedTotal++;

        final lag = _lagOf(client, plant);
        if (_converged(client, plant)) {
          if (lag != null) _lagAtWindowEnd.add(lag);
          _heal(clock, panel, key, client, plant, index);
          continue;
        }
        if (lag != null) _lagAtWindowEnd.add(lag);
        _openOrTrack(panel, key, at, clock, index);
      }
    }

    _maybeFireControl(clock, at, index);
  }

  /// Whether the panel's reading agrees with the plant on value and quality.
  bool _converged(DynamicValue client, SoakPlantTruth plant) {
    if (client.quality != plant.quality) return false;
    if (plant.overridden) return client.value == plant.value;
    final lag = _lagOf(client, plant);
    if (lag == null) return client.value == plant.value;
    return lag >= 0 && lag <= convergedLagSweeps;
  }

  /// How many sweeps behind the plant this reading is, or null when the pair
  /// is not two integers off the same counter.
  int? _lagOf(DynamicValue client, SoakPlantTruth plant) {
    if (plant.overridden) return null;
    final sweep = plant.sweepIndex;
    final held = client.value;
    if (sweep == null || held is! int) return null;
    return sweep - held;
  }

  void _openOrTrack(SoakPanelResyncView panel, String key, Duration at,
      SoakClock clock, int windowIndex) {
    final id = '${panel.name}|$key';
    final open = _open[id];
    if (open == null) {
      _open[id] = _OpenDivergence(
        panelIndex: panel.index,
        key: key,
        openedAt: clock.elapsed,
        openedAtSchedule: at,
        windowIndex: windowIndex,
        generationAtOpen: panel.pageRebuilds,
        complaintsAtOpen: panel.complaints.length,
      )..generationAtLastSample = panel.pageRebuilds;
      return;
    }
    open.generationAtLastSample = panel.pageRebuilds;
  }

  void _heal(SoakClock clock, SoakPanelResyncView panel, String key,
      DynamicValue client, SoakPlantTruth plant, int windowIndex) {
    final id = '${panel.name}|$key';
    final open = _open.remove(id);
    if (open == null) return;
    final healedIn = (clock.elapsed - open.openedAt).inMilliseconds;
    _convergenceMs.add(healedIn);
    _emit(
      open: open,
      panel: panel,
      client: client,
      plant: plant,
      healedWithinMs: healedIn,
      clock: clock,
    );
  }

  void _emit({
    required _OpenDivergence open,
    required SoakPanelResyncView panel,
    required DynamicValue? client,
    required SoakPlantTruth plant,
    required int? healedWithinMs,
    required SoakClock clock,
  }) {
    final cause = attribute(
      panel: panel,
      client: client,
      plant: plant,
      key: open.key,
      generationAtOpen: open.generationAtOpen,
      generationAtLastSample: open.generationAtLastSample,
      complaintsAtOpen: open.complaintsAtOpen,
    );
    if (panel.index == _source.controlPanelIndex &&
        !_windowDisturbed &&
        cause != DivergenceCause.epochChange) {
      _controlDivergences.add('${open.key} in window ${open.windowIndex} '
          '(${cause.name})');
    }
    ledger.record(DivergenceEvent(
      nth: ++_emitted,
      panelId: panel.name,
      subId: defaultPageSubscription,
      key: open.key,
      scheduleOffset: open.openedAtSchedule,
      wallOffsetMs: open.openedAt.inMilliseconds,
      cause: cause,
      healedWithinMs: healedWithinMs,
      clientValue: client?.value,
      plantValue: plant.value,
      clientQuality: client?.quality,
      plantQuality: plant.quality,
      generation: panel.pageRebuilds,
      windowIndex: open.windowIndex,
    ));
  }

  /// Which of the six explains this divergence.
  ///
  /// **The precedence is the design and it is stated here rather than implied
  /// by the order of the ifs below.** Several causes can be true of one
  /// reading — an unestablished page also has bad quality, and an epoch bump
  /// also rebuilds the page — so the taxonomy has to say which claim is the
  /// explanation. It runs from *most specific mechanism the client itself named
  /// in words* down to *nobody can say*:
  ///
  ///  1. [DivergenceCause.resyncFailure] — the client wrote it down.
  ///  2. [DivergenceCause.unknownHandle] — the client wrote it down.
  ///  3. [DivergenceCause.epochChange] — the storm bumped this link's epoch and
  ///     the panel is refusing to vouch for the value. Expected, and the only
  ///     one excluded from residue.
  ///  4. [DivergenceCause.generationChange] — the reading straddled a rebuild.
  ///     A detector artifact, and it stays in residue for that reason.
  ///  5. [DivergenceCause.lostPush] — an established page holding a superseded
  ///     value under **good** quality, on a page the gateway rebuilt while this
  ///     divergence was open. That rebuild is the tick-sequence detector firing
  ///     (`connection_supervisor.dart:761-784`); it is the only public trace it
  ///     leaves when it works.
  ///  6. [DivergenceCause.unattributed] — everything else, and the number the
  ///     verdict turns on.
  ///
  /// **Nothing here reads a hint this harness planted.** Every input is a
  /// surface the shipping client publishes for its own reasons, which is what
  /// stops the taxonomy being tunable: widening any of these means claiming a
  /// mechanism fired that the client never said fired.
  DivergenceCause attribute({
    required SoakPanelResyncView panel,
    required DynamicValue? client,
    required SoakPlantTruth plant,
    required String key,
    required int generationAtOpen,
    required int generationAtLastSample,
    required int complaintsAtOpen,
  }) {
    final fresh = panel.complaints.skip(complaintsAtOpen);
    if (fresh.any((one) => one.contains(unestablishedComplaint)) ||
        !panel.established) {
      return DivergenceCause.resyncFailure;
    }
    if (fresh.any((one) => one.contains(unknownHandleComplaint))) {
      return DivergenceCause.unknownHandle;
    }
    if (_source.epochBumpedAliases.contains(key.split('.').first) &&
        client != null &&
        client.quality != Quality.good) {
      return DivergenceCause.epochChange;
    }
    if (panel.pageRebuilds != generationAtLastSample) {
      return DivergenceCause.generationChange;
    }
    if (client != null &&
        client.quality == Quality.good &&
        (panel.pageRebuilds != generationAtOpen ||
            fresh.any((one) => one.contains(lostPushSurvivedRebuild)))) {
      return DivergenceCause.lostPush;
    }
    return DivergenceCause.unattributed;
  }

  // ------------------------------------------------------------ the control

  /// The ledger's warrant: one induced divergence, run through the whole chain.
  ///
  /// **It reuses the divergence gate's own lever, and the subtlety is not
  /// optional.** `divergence_gate_test.dart` arm A corrupts the **staleness**
  /// frame on a quiet plant — the last frame the plant will ever send for that
  /// key — because corrupting a value-change frame lets the following staleness
  /// frame heal it 350 ms later through the ordinary gap path, and the row then
  /// passes against a client with the bug still in it. It took two red rounds to
  /// find, and a control that misses it proves nothing.
  ///
  /// **What that translates to here, and where it is a substitution.** The soak
  /// has no message-corruption seam: its panels dial through `FaultProxy`, whose
  /// eight levers are all connection-shaped, and adding one would be a change to
  /// a shipping package this plan does not make. So the control substitutes the
  /// *answer* and never the stack that produced it — 11-04's lying-decorator
  /// shape, and `soak_observables.dart`'s standing rule. What it substitutes is
  /// arm A's exact outcome: a value the plant has already superseded, held under
  /// **good** quality, on an established page. And it copies the subtlety by
  /// substituting a reading that **cannot heal** — the lie is held, not injected
  /// once — so the event the ledger records is residue-shaped rather than one
  /// the next frame repairs.
  ///
  /// **It never touches a panel any other checker reads.** The substitution
  /// lives inside this method, one reading wide; invariant 1 and invariant 5 see
  /// the real panel. What that costs is stated plainly: this control proves the
  /// recorder and the **attribution** work end to end, and it does not prove the
  /// checker would have seen a real lost push on the wire. That claim belongs to
  /// `divergence_gate_test.dart` G1a, which makes it against a real frame.
  ///
  /// **It is excluded from the verdict's totals**, or a control that fired every
  /// run would print *needed* every run and the verdict would mean nothing.
  void _maybeFireControl(SoakClock clock, Duration at, int windowIndex) {
    if (_controlFired || windowIndex < 0) return;
    // Never the control panel: its own arm requires zero divergences, and a
    // positive control that fired on it would be two arms fighting.
    SoakPanelResyncView? target;
    for (final panel in _source.panelResyncViews) {
      if (panel.index == _source.controlPanelIndex) continue;
      if (!panel.established) continue;
      target = panel;
      break;
    }
    if (target == null) return;
    final keys = <String>[
      for (final key in _source.freshnessKeys)
        if (!key.startsWith(pipeKeyPrefix)) key,
    ];
    for (final key in keys) {
      final plant = _source.plantTruthFor(key);
      final live = target.read(key);
      if (plant == null || live == null) continue;
      if (plant.overridden || plant.sweepIndex == null) continue;
      if (live.quality != Quality.good) continue;

      // Arm A's outcome, exactly: the number the panel held before the frame it
      // never received, under the good quality it was carrying at the time.
      // Twenty sweeps back is five seconds of plant — far enough that no
      // allowance could call it converged, and a real number this panel really
      // did render.
      final superseded = DynamicValue(
          value: plant.sweepIndex! - _controlLagSweeps,
          quality: Quality.good);
      _controlFired = true;
      _controlTarget = '${target.name}|$key';
      final open = _OpenDivergence(
        panelIndex: target.index,
        key: key,
        openedAt: clock.elapsed,
        openedAtSchedule: at,
        windowIndex: windowIndex,
        // The rebuild the tick-sequence detector performs, which is what makes
        // this a `lostPush` rather than an `unattributed`: the control asserts
        // the ATTRIBUTION as well as the recording, so a taxonomy that stopped
        // attributing would fail here rather than print a clean verdict.
        generationAtOpen: target.pageRebuilds - 1,
        complaintsAtOpen: target.complaints.length,
      )..generationAtLastSample = target.pageRebuilds;
      final cause = attribute(
        panel: target,
        client: superseded,
        plant: plant,
        key: key,
        generationAtOpen: open.generationAtOpen,
        generationAtLastSample: open.generationAtLastSample,
        complaintsAtOpen: open.complaintsAtOpen,
      );
      ledger.record(DivergenceEvent(
        nth: ++_emitted,
        panelId: target.name,
        subId: defaultPageSubscription,
        key: key,
        scheduleOffset: at,
        wallOffsetMs: clock.elapsed.inMilliseconds,
        cause: cause,
        healedWithinMs: null,
        clientValue: superseded.value,
        plantValue: plant.value,
        clientQuality: superseded.quality,
        plantQuality: plant.quality,
        generation: target.pageRebuilds,
        windowIndex: windowIndex,
        isControl: true,
      ));
      return;
    }
  }

  /// How far behind the control's substituted reading sits.
  ///
  /// Twenty sweeps is five seconds of plant at `soakSweepPeriod`: past every
  /// allowance by a factor of twenty, so the control cannot be mistaken for a
  /// timing artifact.
  static const int _controlLagSweeps = 20;

  /// Which panel-and-key the control lied about, for a case to assert against.
  String? get controlTarget => _controlTarget;

  /// Whether the control fired.
  bool get controlFired => _controlFired;

  // ------------------------------------------------------------ the windows

  int _windowContaining(List<StableWindow> windows, Duration at) {
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].contains(at)) return i;
    }
    return -1;
  }

  void _closeWindow(SoakClock clock, int index) {
    if (_keysComparedThisWindow == 0) {
      violationLog.add(SoakViolation(
        checker: name,
        monotonic: clock.elapsed,
        scheduleOffset: _source.scheduleOffset,
        detail: 'stable window $index compared ZERO keys, so it is not a '
            'window and this run has one fewer than its floor believes. Either '
            'every panel was down across it or the key list was empty — read '
            'the population line in metrics.jsonl to see which',
      ));
      return;
    }
    _windowsJudged++;
    // Everything still open at the window's end is RESIDUE: it survived the
    // interval in which the timeline guaranteed nothing was armed, which is
    // the whole of what invariant 3 asserts.
    for (final id in _open.keys.toList()) {
      final open = _open[id]!;
      if (open.windowIndex != index) continue;
      SoakPanelResyncView? panel;
      for (final one in _source.panelResyncViews) {
        if (one.index == open.panelIndex) panel = one;
      }
      final plant = _source.plantTruthFor(open.key);
      _open.remove(id);
      if (plant == null || panel == null) continue;
      _emit(
        open: open,
        panel: panel,
        client: panel.read(open.key),
        plant: plant,
        healedWithinMs: null,
        clock: clock,
      );
    }
  }

  // ------------------------------------------------------- the run-end pass

  @override
  void finish() {
    try {
      if (_currentWindow >= 0) _closeWindow(_clockAtFinish(), _currentWindow);

      final generated = _source.stableWindows.length;
      if (generated == 0) {
        violationLog.add(SoakViolation(
          checker: name,
          monotonic: _source.scheduleOffset,
          scheduleOffset: _source.scheduleOffset,
          observed: 0,
          expected: minimumSamplesForAVerdict,
          detail: 'this run generated ZERO stable windows against a floor of '
              '$minimumSamplesForAVerdict, so invariant 3 judged nothing and '
              'its green is not evidence. The windows are computed from the '
              'duration alone by computeStableWindows, so this is a TIMELINE '
              'problem and not a checker one: the fix is the quiet-window '
              'cadence in soak_timeline.dart, and it carries its own '
              'reproducibility proof to re-run',
        ));
      }

      if (_controlDivergences.isNotEmpty) {
        violationLog.add(SoakViolation(
          checker: name,
          monotonic: _source.scheduleOffset,
          scheduleOffset: _source.scheduleOffset,
          panel: 'panel-${_source.controlPanelIndex}',
          observed: _controlDivergences.length,
          expected: 0,
          detail: 'the never-faulted control panel diverged from plant truth '
              'in ${_controlDivergences.length} instance(s) inside windows the '
              'storm never disturbed: ${_controlDivergences.take(5).join('; ')}'
              '. The storm cannot aim at this panel — buildTimeline is given '
              'the other four names — so a divergence here in an undisturbed '
              'window is the gateway punishing a healthy panel, which is the '
              'pre-07-08b bug class',
        ));
      }
    } catch (error) {
      violationLog.add(SoakViolation(
        checker: name,
        monotonic: _source.scheduleOffset,
        scheduleOffset: null,
        detail: 'the run-end pass threw, so the last window was not closed and '
            'its residue is unrecorded: $error',
      ));
    }
  }

  SoakClock _clockAtFinish() => SoakClock.frozenAt(_source.scheduleOffset,
      declaredDuration: _source.declaredDuration);

  // ----------------------------------------------------------- the report

  /// The measurement [minStableWindow] is judged against, printed every run.
  ///
  /// **N = 10 s was a hypothesis, not a constant to inherit** — 11-PLAN-INDEX
  /// assumption A4 says so, and `soak_timeline.dart` says it at the constant.
  /// The derivation was: the per-subscription staleness limit is `tickMs x 30`
  /// and the ordinary tick is 50-100 ms, so 1.5-3 s covers detection and a
  /// resync round trip on a recovered link is sub-second, leaving better than
  /// 3x margin at ten seconds.
  ///
  /// What this report prints is the **observed** convergence time — how long
  /// each divergence took to heal — as p50, p95 and max. If p95 approaches N
  /// then N is too short and the checker is reporting divergences that were
  /// simply not finished converging, which is the worst possible failure for an
  /// artifact whose whole purpose is separating real residue from noise.
  String get convergenceReport {
    final lags = <int>[..._lagAtWindowEnd]..sort();
    final healed = <int>[..._convergenceMs]..sort();
    return <String>[
      '  eventualResync:  windows judged against a floor of '
          '$minimumSamplesForAVerdict '
          '(${_source.stableWindows.length} generated), '
          '$_keysComparedTotal key comparisons',
      '    convergence time (ms) : ${_quantiles(healed)} '
          'against minStableWindow=${minStableWindow.inMilliseconds}ms',
      '    lag at sample (sweeps): ${_quantiles(lags)} '
          'against an allowance of $convergedLagSweeps',
      '    control panel (panel-${_source.controlPanelIndex}): '
          '${_controlDivergences.length} divergences in undisturbed windows',
    ].join('\n');
  }

  String _quantiles(List<int> sorted) {
    if (sorted.isEmpty) return 'n=0 (nothing to summarise)';
    int at(double fraction) {
      final index = (sorted.length * fraction).floor();
      return sorted[index >= sorted.length ? sorted.length - 1 : index];
    }

    return 'n=${sorted.length} p50=${at(0.5)} p95=${at(0.95)} '
        'max=${sorted.last}';
  }

  @override
  String toString() => convergenceReport;
}
