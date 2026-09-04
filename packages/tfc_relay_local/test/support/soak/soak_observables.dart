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
