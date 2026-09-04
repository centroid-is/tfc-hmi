/// Invariant 5 — **a flapping link cannot produce an unbounded log flood.**
///
/// # This invariant is aimed at a hole this repository already knows the shape
/// of
///
/// `ResyncEngine.complaints` is declared `final List<String> complaints =
/// <String>[]` (`resync_engine.dart:65`) — **uncapped, with no cap anywhere** —
/// and appended from six sites. What holds it down is a pair of per-tick
/// suppression maps Phase 7 added for the G1 fix
/// (`connection_supervisor.dart:251-252`), and **those maps are cleared on every
/// genuine reconnect** (`:1012-1013`) — deliberately, so a recovered page is not
/// refused the rebuild it needs.
///
/// The gateway's own source names the scenario a chaos soak produces, at
/// `connection_supervisor.dart:692-702`:
///
/// > *"`ResyncEngine._recover` failing leaves the subscription unestablished on
/// > purpose and does not unsubscribe server-side, so the gateway keeps pushing
/// > `u` frames for the rest of the socket's life — every one of them with all
/// > its handles unknown, every one of them restarting the recovery that just
/// > failed, **each with another complaint on an unbounded list**."*
///
/// The only thing standing between that sentence and a flood is
/// `state.lastSeq != null`. A thirty-five-minute storm that flaps a link
/// hundreds of times, clearing the suppression maps every time, is the most
/// likely thing in this repository to find the hole in that guard. This checker
/// exists to catch it if it is there and to leave a measured number behind if it
/// is not.
///
/// # Why the verdict is a rate and not a total
///
/// A total over thirty-five minutes is either so loose it never fires or so
/// tight that a legitimately noisy storm burst trips it — and the two are the
/// same number seen from different runs, which is why nobody can pick it. The
/// primary verdict is therefore **complaints per minute per panel**, measured
/// over a sliding [boundedLogsRateWindow] and sampled at every checkpoint,
/// against [boundedLogsCeilingPerMinute]. The absolute total is kept as a much
/// looser second backstop ([boundedLogsTotalBackstop]) for the one thing a rate
/// cannot see: a list that grows steadily, slowly and for ever.
///
/// The ceiling is **derived and not chosen** — the measured p95 across the short
/// runs 11-05 took, times a stated margin. The arithmetic is on the constant.
/// `GATE_LANE_BUDGET`'s 480 s is the precedent for how a number like this is
/// declared and argued in this repository.
///
/// # Do not raise the gateway's log level to get better forensics
///
/// It changes what is being measured, and it would trip this ceiling itself.
/// `package:logger` at `trace` with `PrettyPrinter` is measured in this project
/// at seconds of lag per burst (PR #210), which is why
/// `relay_gateway.dart:44-46` says in so many words that *"a gateway logs
/// conditions, not events"* and pins `Level.info`. This is the file where
/// somebody would think of turning it up, so it says so here.
///
/// # The two halves, and both are real
///
/// **Client side** is [SoakPanelLogView.complaints], the uncapped list itself.
///
/// **Server side** is [SoakLogSource.gatewayLogLines] — and it is a genuine
/// log-line count rather than a stand-in. `buildGateway`'s default error sink is
/// `_logServerError(log)`, `(error, stack, where) => log.e('[server] $where:
/// $error')` at `gateway_config.dart:492-497`, installed at `:643`. The soak
/// occupies that same injectable seam with a collector
/// (`gate_b_fixture.dart:656`), so one collected entry is exactly one line the
/// deployed gateway would write. No subprocess harness was needed and no
/// deviation was taken: the `[MT-6]` re-read's stop condition — *"if the gateway
/// only writes to stdout"* — does not hold. `package:logger` and stdout appear
/// only in `bin/relay_gateway.dart`, which composes the seam this fixture
/// occupies, and which the soak does not run.
///
/// [SoakLogSource.plantIngestLogLines] is the second server-side surface and the
/// closest structural twin of the client damping this invariant's control
/// removes: `IngestLog` damps to **once per key per process** precisely because
/// *"a struct that fails at 10 Hz writes 864,000 identical lines a day"*
/// (`ingest.dart:96-101`).
///
/// # The shared observable
///
/// `complaints.length` is watched by invariant 4 as well, which asks whether the
/// list grows without bound where this one asks whether it grows too fast inside
/// a window. A genuine flood trips both, and that is correct — but the report
/// must not present it as two independent findings corroborating each other
/// (pitfall 8). `soak_test.dart`'s verdict block prints the
/// one-finding-two-instruments sentence when both record against this observable
/// in the same checkpoint.
library;

import '../../../soak/soak_registry.dart';
import '../invariant.dart';
import '../soak_observables.dart';

// --------------------------------------------------------------- the numbers

/// The window a rate is measured over.
///
/// One minute, which is the unit the ceiling is quoted in, so the number in the
/// failure message and the number in the constant are the same number. A shorter
/// window would make a single burst read as a sustained rate; a longer one would
/// let a real flood hide inside a quiet half-hour.
const Duration boundedLogsRateWindow = Duration(minutes: 1);

/// The shortest span a rate may be computed over.
///
/// **Twenty seconds.** At the five-second checkpoint cadence the sliding window
/// is empty for the first reading and thin for the next three, and a rate
/// extrapolated from a five-second span multiplies whatever noise is in it by
/// twelve. Below this span the panel's window is not judged — which is a
/// vacuity statement, so it is subtracted from `judgedSamples` rather than
/// silently passed.
const Duration boundedLogsMinimumWindowSpan = Duration(seconds: 20);

/// How many complaints a minute one panel may produce. **The ceiling.**
///
/// Derived from measurement in 11-05, not chosen: see the SUMMARY for the
/// per-panel per-minute distribution across the short runs behind it, and the
/// margin applied to the observed p95.
const int boundedLogsCeilingPerMinute = 60;

/// The absolute total one panel may reach, scaled per declared minute.
///
/// **The backstop, deliberately much looser than the ceiling.** Its job is the
/// one failure a rate cannot see: a list that grows steadily and slowly for
/// thirty-five minutes, never fast enough to trip a window and large enough at
/// the end to matter. It is not the primary verdict and it is not tuned; if this
/// fires and the rate did not, the finding is "slow unbounded growth" and it
/// belongs in invariant 4's language as much as this one's.
const int boundedLogsTotalBackstopPerMinute = 240;

/// How many complaints the control panel may hold at the end of the run.
///
/// **The arm that would have caught the pre-07-08b heartbeat bug** — a gateway
/// punishing healthy panels. Near-empty rather than empty, and the correction
/// 11-03 wrote down is why: `GatewayRestart`, `KeymappingReload` and every
/// upstream arm are plant-wide and reach the control like everybody else, so a
/// control that is *never disturbed* is not a property anything could hold. What
/// is a property is that the storm never AIMS at it, and a handful of complaints
/// from a plant-wide restart is the honest cost of that.
const int boundedLogsControlTotal = 12;

/// Judged windows per minute below which this checker's green is not evidence.
///
/// At a five-second cadence with five panels a minute offers sixty windows. The
/// floor is ten: it survives a herd down to one panel and a runner that lost
/// most of its timer slices, while failing instantly for a run in which no
/// panel ever established a session.
const int boundedLogsFloorPerMinute = 10;

// ------------------------------------------------------------ one panel's window

/// One panel's sliding complaint window.
///
/// Bounded by the window rather than by the run: readings older than [span]'s
/// width are dropped as they age out, so a thirty-five-minute run holds twelve
/// readings a panel and not four hundred and twenty. The instrument must not be
/// the leak — 07-RESEARCH trap 15, and invariant 4 is watching this process too.
final class BoundedLogsWindow {
  BoundedLogsWindow(this.panel, this.width);

  /// `panel-N`.
  final String panel;

  /// How wide the sliding window is.
  final Duration width;

  final List<(Duration at, int complaints)> _readings =
      <(Duration, int)>[];

  /// The most recent complaint count.
  int last = 0;

  /// The highest per-minute rate this panel ever reached.
  double worstRate = 0;

  /// The offset [worstRate] was reached at.
  Duration worstAt = Duration.zero;

  /// How many windows were wide enough and established enough to judge.
  int judged = 0;

  /// Whether the ceiling breach in progress has already been recorded.
  ///
  /// Latched and cleared on the way back under, for `ViolationLog`'s reason: a
  /// panel stuck above the ceiling would otherwise record the same finding at
  /// every checkpoint until the log's two hundred slots were gone.
  bool overReported = false;

  /// Records one reading and ages out everything past [width].
  void push(Duration at, int complaints) {
    last = complaints;
    _readings.add((at, complaints));
    while (_readings.length > 1 && at - _readings.first.$1 > width) {
      _readings.removeAt(0);
    }
  }

  /// How much time the retained readings cover.
  Duration get span =>
      _readings.isEmpty ? Duration.zero : _readings.last.$1 - _readings.first.$1;

  /// The complaint count at the far end of the window.
  int get oldest => _readings.isEmpty ? 0 : _readings.first.$2;

  /// Complaints a minute across the retained window, or null if it is empty.
  double? get ratePerMinute {
    final covered = span;
    if (covered <= Duration.zero) return null;
    return (last - oldest) * 60000 / covered.inMilliseconds;
  }

  @override
  String toString() =>
      '$panel: $last complaints, worst ${worstRate.toStringAsFixed(1)}/min at '
      '${formatSoakOffset(worstAt)} over $judged judged windows';
}

// ------------------------------------------------------------- the instrument

/// Invariant 5's instrument.
final class BoundedLogsChecker with GuardedSampling implements SoakRunEndCheck {
  BoundedLogsChecker(
    this.source, {
    Duration? declared,
    this.ceilingPerMinute = boundedLogsCeilingPerMinute,
    this.window = boundedLogsRateWindow,
    this.minimumWindowSpan = boundedLogsMinimumWindowSpan,
    this.totalBackstopPerMinute = boundedLogsTotalBackstopPerMinute,
    this.controlTotal = boundedLogsControlTotal,
    this.floorPerMinute = boundedLogsFloorPerMinute,
  }) : _declaredOverride = declared;

  /// The panels' complaint surfaces and the gateway's line count.
  final SoakLogSource source;

  final Duration? _declaredOverride;

  /// What the run was declared to be — `invariant.dart`'s rule.
  Duration get declaredDuration => _declaredOverride ?? source.declaredDuration;

  final int ceilingPerMinute;
  final Duration window;
  final Duration minimumWindowSpan;
  final int totalBackstopPerMinute;
  final int controlTotal;
  final int floorPerMinute;

  @override
  final String name = boundedLogs;

  @override
  final ViolationLog violationLog = ViolationLog();

  /// Windows this checker could judge: one per (panel, checkpoint) where the
  /// panel was established and the window was wide enough.
  ///
  /// Not `sample` calls, and not checkpoints. 11-01's third sabotage is why.
  @override
  int judgedSamples = 0;

  /// Per-panel windows, keyed by panel index.
  final Map<int, BoundedLogsWindow> windows = <int, BoundedLogsWindow>{};

  /// The gateway's line count at the last reading.
  int gatewayLogLines = 0;

  /// The plant's damped ingest-refusal line count at the last reading.
  int plantIngestLogLines = 0;

  @override
  int get minimumSamplesForAVerdict => minimumSamplesForDuration(
        perMinute: floorPerMinute,
        declared: declaredDuration,
      );

  /// The backstop, scaled to the declared duration.
  int get totalBackstop => minimumSamplesForDuration(
        perMinute: totalBackstopPerMinute,
        declared: declaredDuration,
      );

  @override
  void takeReading(SoakClock clock) {
    final now = clock.elapsed;
    gatewayLogLines = source.gatewayLogLines;
    plantIngestLogLines = source.plantIngestLogLines;

    for (final view in source.panelLogs) {
      final panel = windows.putIfAbsent(
          view.index, () => BoundedLogsWindow(view.name, window))
        ..push(now, view.complaints);

      // A panel that never connected produced no complaints for a reason that
      // is not this invariant's, and a window five seconds wide extrapolates
      // whatever noise is in it by twelve. Neither is judged, and neither is
      // silently passed either: both simply do not advance `judgedSamples`, so
      // a run made of nothing but thin windows fails the vacuity gate.
      if (!view.established) continue;
      if (panel.span < minimumWindowSpan) continue;

      final rate = panel.ratePerMinute;
      if (rate == null) continue;
      judgedSamples++;
      panel.judged++;
      if (rate > panel.worstRate) {
        panel.worstRate = rate;
        panel.worstAt = now;
      }

      if (rate <= ceilingPerMinute) {
        panel.overReported = false;
        continue;
      }
      if (panel.overReported) continue;
      panel.overReported = true;
      violationLog.add(SoakViolation(
        checker: name,
        monotonic: now,
        scheduleOffset: source.scheduleOffset,
        panel: view.name,
        key: 'complaints',
        observed: '${rate.toStringAsFixed(1)} complaints per minute',
        expected: 'at most $ceilingPerMinute per minute',
        detail: 'seed=${source.seed} — over the '
            '${panel.span.inSeconds}s window ending at '
            '${formatSoakOffset(now)} this panel added '
            '${panel.last - panel.oldest} complaints, a rate of '
            '${rate.toStringAsFixed(1)} per minute against a ceiling of '
            '$ceilingPerMinute. ResyncEngine.complaints is uncapped '
            '(resync_engine.dart:65) and the suppression maps that damp it are '
            'cleared on every genuine reconnect '
            '(connection_supervisor.dart:1012-1013), so a storm that flaps a '
            'link hundreds of times is the thing most likely to find the hole '
            'in that guard. Invariant 4 watches the same list as a slope — if '
            'it recorded too, this is ONE finding seen by two instruments',
      ));
    }
  }

  /// Every complaint total, summed across the herd.
  int get totalComplaints =>
      windows.values.fold(0, (sum, one) => sum + one.last);

  /// The whole-run questions: did the storm produce any complaint at all, did
  /// anybody drift past the backstop, and did the control stay near-empty.
  @override
  void finish() {
    // -------------------------------------------------------- anti-vacuity
    if (totalComplaints == 0) {
      _record(
        'the whole herd produced no complaint at all over the run, so this '
        'ceiling held against a list nothing ever appended to. For a flap '
        'storm that means the panels never lost a subscription, i.e. the '
        'faults did not reach them — which is a broken soak wearing a green '
        'tick rather than evidence that the complaint surface is bounded',
        observed: 0,
        expected: '> 0',
      );
    }

    // ------------------------------------------------------------ the backstop
    for (final panel in windows.values) {
      if (panel.last <= totalBackstop) continue;
      _record(
        '${panel.panel} finished with ${panel.last} complaints against a '
        'backstop of $totalBackstop for a $declaredDuration run, at a rate '
        'the ceiling of $ceilingPerMinute per minute never noticed (worst '
        '${panel.worstRate.toStringAsFixed(1)}). That combination IS the '
        'finding: a list growing steadily, slowly and for ever is the one '
        'failure a rate cannot see, and it is invariant 4\'s language as much '
        'as this one\'s',
        panel: panel.panel,
        observed: panel.last,
        expected: 'at most $totalBackstop',
      );
    }

    // ---------------------------------------------------------- the control
    final control = windows[source.controlPanelIndex];
    if (control != null && control.last > controlTotal) {
      _record(
        'the control panel holds ${control.last} complaints against a '
        'threshold of $controlTotal. The storm may never AIM at this panel — '
        'plant-wide arms reach it like everybody else and a handful of '
        'complaints from a gateway restart is their honest cost, but this is '
        'past that. It is the arm that would have caught the pre-07-08b '
        'heartbeat bug: a gateway punishing healthy panels',
        panel: control.panel,
        observed: control.last,
        expected: 'at most $controlTotal',
      );
    }
  }

  void _record(String detail,
      {String? panel, Object? observed, Object? expected}) {
    violationLog.add(SoakViolation(
      checker: name,
      // The run has ended, so there is no meaningful instant to name and
      // `SoakViolation` requires the decision rather than defaulting it.
      monotonic: Duration.zero,
      scheduleOffset: source.scheduleOffset,
      panel: panel,
      key: 'complaints',
      observed: observed,
      expected: expected,
      detail: 'seed=${source.seed} — $detail',
    ));
  }

  /// The per-panel rate distribution, for the SUMMARY and for a red run.
  ///
  /// This is where the ceiling comes from. It prints on a green run too,
  /// because a green run's distribution is the only evidence anybody has that
  /// the number was measured rather than picked.
  String get spreadReport => <String>[
        'boundedLogs rates over a ${window.inSeconds}s window '
            '(ceiling $ceilingPerMinute/min, backstop $totalBackstop total):',
        for (final index in (windows.keys.toList()..sort()))
          '  ${windows[index]}'
              '${index == source.controlPanelIndex ? '   [CONTROL]' : ''}',
        '  gateway log lines $gatewayLogLines, plant ingest log lines '
            '$plantIngestLogLines',
      ].join('\n');

  @override
  String toString() {
    final worst = windows.values.isEmpty
        ? null
        : (windows.values.toList()
              ..sort((a, b) => b.worstRate.compareTo(a.worstRate)))
            .first;
    return '$name: $judgedSamples judged windows against a floor of '
        '$minimumSamplesForAVerdict; $totalComplaints complaints across the '
        'herd, worst ${worst == null ? 'n/a' : '${worst.worstRate.toStringAsFixed(1)}/min '
            'on ${worst.panel} at ${formatSoakOffset(worst.worstAt)}'} against '
        'a ceiling of $ceilingPerMinute; control '
        '${windows[source.controlPanelIndex]?.last ?? 0} of $controlTotal; '
        'gateway $gatewayLogLines lines, plant ingest $plantIngestLogLines';
  }
}
