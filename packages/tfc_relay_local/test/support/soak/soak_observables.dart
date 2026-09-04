/// What a checker is allowed to see, stated as two narrow interfaces rather
/// than as a reference to [SoakDriver].
///
/// **Why the indirection exists at all.** A checker that took the driver would
/// be a checker whose positive control needs a composed pipe: five real panels,
/// a real gateway, a real socket and a bound port, for an arm whose entire job
/// is to prove one counter moves. 11-04's acceptance criteria say the controls
/// run "in seconds", and a control that costs ninety is a control somebody
/// eventually stops running. So each checker declares the narrow thing it
/// needs, `SoakDriver` implements both, and a control substitutes one member of
/// one interface and leaves the rest of the composition alone.
///
/// **It is not a fake of the pipe.** [SoakPanelView] is satisfied by a real
/// `RemoteStateMan` in every lane run — the lying decorator in
/// `soak_meta_test.dart` wraps a *live* panel and overrides one verdict. Phase
/// 10's CR-01 is the standing lesson about fakes making a bug idempotent and
/// invisible, and the shape here is chosen so the fake is never the thing under
/// test: what a control replaces is the *answer*, never the stack that produced
/// it.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'applied_write_ledger.dart';
import 'invariant.dart';

// ------------------------------------------------------- the run-end pass

/// A checker with something to say once the storm has played out.
///
/// Two of this phase's invariants are only half continuous. Invariant 1's
/// distribution — *did anything ever go stale, and did anything ever recover* —
/// is a statement about the whole run and cannot be evaluated at 25 ms;
/// invariant 2's *every write is in exactly one of two places* is false at
/// every instant a write is in flight and true only once the run has stopped
/// issuing them. [finish] is where both are asked, and the driver calls it for
/// every registered checker after the last entry and before the verdict block
/// is read, so a distribution failure prints in the same block as the counters
/// that explain it.
abstract interface class SoakRunEndCheck {
  /// Records anything that can only be judged once. Never throws — the same
  /// rule [InvariantChecker.sample] follows, for the same reason.
  void finish();
}

// ------------------------------------------------------------- one panel

/// One panel's operator-facing surface, as a freshness checker reads it.
///
/// Three members and no more, because three is what CLI-04 says an operator can
/// tell apart: the link is gone ([viewIsStale]), this page's plant-side source
/// is not being re-evaluated ([pageIsStale]), and this one value is what it is
/// ([read]). A checker that could reach further would end up asserting against
/// the client's internals rather than against what a widget renders, and the
/// invariant is about the render.
abstract interface class SoakPanelView {
  /// Its position in the herd. Zero is the control.
  int get index;

  /// `panel-N`.
  String get name;

  /// Whether the link has gone a whole freshness deadline without a frame of
  /// any kind — `RemoteStateMan.viewIsStale`.
  bool get viewIsStale;

  /// Whether this panel's one subscription page is being re-evaluated —
  /// `RemoteStateMan.isSubscriptionStale(defaultPageSubscription)`.
  ///
  /// One page rather than a set, because the fixture files every key of every
  /// panel under `defaultPageSubscription`: the panels are constructed with
  /// their whole key list, and `RemoteStateMan.subscribe` is a view of a store
  /// node rather than a second wire subscription.
  bool get pageIsStale;

  /// The value a widget would render for [key], or null if none has arrived.
  DynamicValue? read(String key);
}

// -------------------------------------------------------- what a write did

/// Which side of a write's life one record describes.
enum SoakWriteStage {
  /// The call was made. Nothing is known about its fate yet.
  issued,

  /// `RemoteStateMan.write` returned — the direct path.
  direct,

  /// `onWriteResolved` emitted.
  ///
  /// **This is the only thing that stream carries**, and it is worth knowing
  /// before reading invariant 2: `_settle` is called from `_requeryWriteStatus`
  /// and nowhere else (`remote_state_man.dart:1096-1101`), so the direct
  /// outcome of a write never appears on it. A checker fed by `onWriteResolved`
  /// alone would see only the writes a reconnect had to reconcile, and would
  /// report a floor of a few dozen as though it were the run's whole write
  /// traffic.
  lateResolution,
}

/// One thing that happened to one write, stamped where it happened.
///
/// **The schedule offset is taken by the driver at the instant, not by the
/// checker at its next tick.** A double resolution is diagnosable only against
/// the faults that were armed when it occurred, and 25 ms of sampling lag is
/// enough to put the reading in the next entry's window.
final class SoakWriteRecord {
  const SoakWriteRecord({
    required this.nth,
    required this.cmd,
    required this.panel,
    required this.key,
    required this.value,
    required this.stage,
    required this.at,
    required this.probe,
    this.outcome,
    this.reachedASocket = false,
  });

  /// The run-stable identity: the *n*-th write this run issued.
  final int nth;

  /// The idempotency id. Opaque across runs — see [AppliedWriteLedger].
  final String cmd;

  /// `panel-N`.
  final String panel;

  final String key;
  final Object? value;

  final SoakWriteStage stage;

  /// `applied`, `rejected`, `unknown`, `not_received`, or null at
  /// [SoakWriteStage.issued].
  final String? outcome;

  /// Whether any bytes were offered to a socket for this write.
  ///
  /// **Not a failure when false, and not a loophole in the invariant.** A cmd
  /// that never left the process is removed from `_unresolved` **on purpose**
  /// (`remote_state_man.dart:832-836`): re-querying it on every reconnect for
  /// the rest of the shift is how a panel with a dead link grows an unresolved
  /// set until `writeStatus` is refused for being over `maxKeysPerSubscribe`,
  /// taking the recovery path for the genuine unknowns down with it. A checker
  /// that demanded terminality of such a write would be asserting against that
  /// protection.
  final bool reachedASocket;

  /// The play clock at the instant this was recorded.
  final Duration at;

  /// Whether the driver's write probe issued it, as opposed to a `PanelWrite`
  /// the generator drew.
  final bool probe;

  @override
  String toString() => 'write #$nth $panel $key=$value ${stage.name}'
      '${outcome == null ? '' : ' -> $outcome'}'
      '${stage == SoakWriteStage.direct ? ' (socket=$reachedASocket)' : ''}';
}

// --------------------------------------------------------- the sources

/// What invariant 1 reads.
abstract interface class SoakFreshnessSource {
  /// The run's seed, so a violation can be reproduced from its own text.
  int get seed;

  /// What the run was DECLARED to be — 90 s in the lane, 35 min behind
  /// `RELAY_SOAK`. Every floor scales off this and never off measured elapsed
  /// time (`invariant.dart`'s rule), and it is read from the source rather than
  /// frozen into a checker at construction because a checker is built before
  /// the driver that knows the answer.
  Duration get declaredDuration;

  /// The play clock — the position in the generated timeline right now.
  Duration get scheduleOffset;

  /// Every panel, control first.
  List<SoakPanelView> get panelViews;

  /// The keys a freshness verdict is judged over.
  ///
  /// Includes the `PIPE.` health keys; the checker excludes them **by prefix**,
  /// which is where the exclusion belongs (08-PATTERNS freeze 8). Handing the
  /// checker a pre-filtered list would move the decision here and make the
  /// prefix arm test nothing.
  List<String> get freshnessKeys;

  /// The panel the storm may never aim at.
  int get controlPanelIndex;

  /// How many plant-wide arms the storm has applied so far.
  ///
  /// A gateway restart, a keymapping reload and every upstream arm reach the
  /// control like everybody else — the control's property is *"the storm never
  /// AIMS at it"*, never *"it is never disturbed"*. This counter is what lets
  /// the control's freshness arm be sharp about the panel-targeted half only.
  int get plantWideArmsApplied;

  /// How old a value may be while the panel still renders it fresh.
  Duration get freshnessBudget;
}

/// What invariant 2 reads.
abstract interface class SoakWriteSource {
  /// The run's seed, so a violation can be reproduced from its own text.
  int get seed;

  /// What the run was declared to be. Floors scale off this.
  Duration get declaredDuration;

  /// The play clock.
  Duration get scheduleOffset;

  /// Every write event so far, append-only and in order.
  ///
  /// **Pulled by index rather than pushed.** The checker consumes what it has
  /// not seen on each tick, so a checker registered after the first write still
  /// sees it and there is no subscription lifecycle to get wrong across a
  /// redial — which replaces the panel's whole client object
  /// (`GateBFixture.redial`).
  List<SoakWriteRecord> get writeRecords;

  /// Every command every panel still considers in flight, union across the
  /// herd. `RemoteStateMan.debugUnresolvedCmds`.
  ///
  /// **Invariant 4 reads the same counter** (11-05 task 1): it is the
  /// unresolved-write set `long_outage_gate_test.dart` already watches as a
  /// slope. Invariant 2 asks whether a command is in it; invariant 4 asks
  /// whether it grows. Cross-referenced in both docs so a change to one is
  /// read by whoever owns the other.
  List<String> get unresolvedCmds;

  /// What the plant actually applied.
  AppliedWriteLedger get appliedWrites;
}

// ------------------------------------------------ what a checkpoint measured

/// Every structure invariant 4 watches, read at one instant.
///
/// **A whole reading rather than a getter per structure**, and the reason is the
/// one thing a slope detector cannot survive without: the readings in a
/// checkpoint row have to be simultaneous. A checker that pulled ten getters
/// would take ten readings across however long the pulls took, and under a
/// storm that window contains a gateway restart — which is how a row ends up
/// with a session count from before it and a subscription count from after.
///
/// [skips] is what makes a platform skip **visible**. `openSocketCount()` cannot
/// answer on Windows (`fd_count.dart:46`), and the difference between "this
/// structure read zero" and "this structure could not be read here" is the whole
/// of `gate_manifest_test.dart`'s skip audit at one structure's scale. A skipped
/// structure is absent from [plantWide] and present here with the reason the
/// platform gave, in its own words.
final class SoakStructureReading {
  const SoakStructureReading({
    required this.perPanel,
    required this.plantWide,
    this.skips = const <String, String>{},
  });

  /// Panel index -> structure name -> size. The client-side half.
  final Map<int, Map<String, int>> perPanel;

  /// Structure name -> size, for the server and the process. The half that has
  /// no panel to attribute it to.
  final Map<String, int> plantWide;

  /// Structure name -> why it could not be read on this platform.
  final Map<String, String> skips;
}

/// What invariant 4 reads.
abstract interface class SoakStructureSource {
  /// The run's seed, so a violation can be reproduced from its own text.
  int get seed;

  /// What the run was declared to be. Floors scale off this.
  Duration get declaredDuration;

  /// The play clock.
  Duration get scheduleOffset;

  /// The panel the storm may never aim at.
  int get controlPanelIndex;

  /// How many plant-wide arms the storm has applied so far.
  ///
  /// The same counter invariant 1 reads, for the same reason: the control's
  /// property is *"the storm never AIMS at it"* and never *"it is never
  /// disturbed"*, so the control's flat-structures arm is written against the
  /// panel-targeted half of the storm only (11-03's correction).
  int get plantWideArmsApplied;

  /// One simultaneous reading of every watched structure.
  SoakStructureReading readStructures();
}

/// One panel's complaint surface, as invariant 5 reads it.
abstract interface class SoakPanelLogView {
  /// Its position in the herd. Zero is the control.
  int get index;

  /// `panel-N`.
  String get name;

  /// Whether this panel currently holds an established session.
  ///
  /// **`RemoteStateMan.isReady`, and it is the closest public predicate to
  /// "has an established subscription".** A panel that never connected produced
  /// no complaints for a reason that is not the invariant's, so its windows are
  /// not judged — but the client exposes readiness rather than
  /// per-subscription establishment (`lastSeq != null` lives inside
  /// `ConnectionSupervisor`), and reaching for the private one would mean
  /// editing `tfc_relay_client/lib`, which this plan measures and does not
  /// change. The substitution is conservative in the right direction: a ready
  /// panel whose page is not established still gets judged, which is precisely
  /// the state `connection_supervisor.dart:692-702` warns the flood comes from.
  bool get established;

  /// `RemoteStateMan.complaints.length` — the uncapped list itself.
  int get complaints;
}

/// What invariant 5 reads.
abstract interface class SoakLogSource {
  /// The run's seed, so a violation can be reproduced from its own text.
  int get seed;

  /// What the run was declared to be. Floors scale off this.
  Duration get declaredDuration;

  /// The play clock.
  Duration get scheduleOffset;

  /// The panel the storm may never aim at.
  int get controlPanelIndex;

  /// Every panel's complaint surface, control first.
  List<SoakPanelLogView> get panelLogs;

  /// How many lines the **gateway** has produced.
  ///
  /// **This is a real log-line count and not a stand-in.** `buildGateway`'s
  /// default error sink is `_logServerError(log)` —
  /// `(error, stack, where) => log.e('[server] $where: $error')`,
  /// `gateway_config.dart:492-497`, installed at `:643` — so one entry here is
  /// exactly one line the deployed gateway would write. The soak occupies the
  /// same injectable seam with a collector instead of a logger
  /// (`gate_b_fixture.dart:656`), which is why the server half of this
  /// invariant is countable in process and needed no subprocess harness.
  int get gatewayLogLines;

  /// How many ingest refusals actually reached a log sink.
  ///
  /// `IngestLog.logged`, not `IngestLog.refusals`: the class damps to **once
  /// per key per process** precisely because *"a struct that fails at 10 Hz
  /// writes 864,000 identical lines a day"* (`ingest.dart:96-101`). It is the
  /// server-side twin of the client damping this invariant's control removes,
  /// and watching the damped number is what makes a broken damper visible.
  int get plantIngestLogLines;
}
