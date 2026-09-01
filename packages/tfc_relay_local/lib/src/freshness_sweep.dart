/// The clock that notices silence — and only runs while somebody is watching.
///
/// ## Why a clock at all
///
/// Staleness is a function of time, not of events. The failure this exists to
/// make visible **emits nothing**: a frozen OPC UA session, a PLC that stopped
/// scanning, a weigher that answered its last frame an hour ago. Every one of
/// those looks, to an event-driven pipeline, exactly like a tag that has not
/// changed — and a plausible number under a good quality is the single failure
/// PROJECT.md names as the reason the whole project exists. The shipped stack
/// has `staleAfter` declared and **nothing sweeping for it**, which is that
/// failure waiting to happen on the gateway side.
///
/// ## Why it is listener-gated, and what that costs
///
/// `ClientWrapper`'s effective-status timer is the in-repo pattern and this
/// copies its **three properties**, not just its shape
/// (`packages/tfc_dart/lib/core/state_man.dart:966-992`):
///
///  1. **The clock only runs while someone is watching** (`:970-975`). An
///     always-on `Timer.periodic` leaks past every test that builds a source
///     without draining it ("A Timer is still pending…"), and an unobserved
///     gateway has nobody to tell anyway. The gate here is the fan-in's watcher
///     count: [start] on the transition from zero, [stop] on the return to it.
///  2. **The verdict is re-derived on read, so nothing goes stale while the
///     timer is parked** (`:1000`, `:1005-1031`). [judge] is that
///     re-derivation, and it is what makes the gate *safe* rather than merely
///     cheap — a read taken after an unwatched hour is still correct.
///  3. **A recompute bails when nothing would change** (`:1033-1038`). Here
///     that is the band comparison in [sweep]: a key already carrying worse
///     news than `badStale` stages nothing, so the four-times-per-deadline
///     cadence costs a listening page zero rebuilds until something actually
///     moves.
///
/// The reference implementation's watchdog is always-on
/// (`fake_state_man.dart:71`) — **that is a fake's licence and not a
/// gateway's**. A fake exists for the length of one test; this object exists
/// for the length of a plant shift.
///
/// ## Why health keys are skipped by prefix
///
/// 06-09 found the trap on `days_to_expiry`: a value that changes once a day is
/// *always* older than any freshness deadline, so freshness accounting greys
/// out the indicator permanently and precisely while nothing is wrong. **The
/// trap is not specific to that key.** `PIPE.upstream.<alias>.connected`,
/// `.birth_count`, `.last_death_at`, `.state`, `.epoch` and `PIPE.connected`
/// itself all change only on an event, and every one of them would grey out the
/// same way (08-RESEARCH §D.3).
///
/// So the skip is [PipeKeys.isPipeKey] — a **prefix test**, never an enumerated
/// list. An enumerated list is a list a new key gets added outside of, and the
/// symptom of forgetting is an indicator that reads stale exactly when an
/// operator is deciding whether to believe the rest of the screen.
library;

import 'dart:async';

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// Re-evaluates every key's age and degrades the ones past the deadline.
final class FreshnessSweep {
  FreshnessSweep({
    required this.staleAfter,
    required ValueStore store,
    required Map<String, DateTime> lastArrival,
    required void Function(Map<String, DynamicValue>) degrade,
    DateTime Function()? now,
  })  : _store = store,
        _lastArrival = lastArrival,
        _degrade = degrade,
        _now = now ?? DateTime.now;

  /// How long a value may go unheard-of before it must stop claiming to be
  /// current.
  final Duration staleAfter;

  final ValueStore _store;
  final Map<String, DateTime> _lastArrival;
  final void Function(Map<String, DynamicValue>) _degrade;
  final DateTime Function() _now;

  /// The floor under [intervalFor].
  ///
  /// An implausibly short deadline out of a configuration file must not turn
  /// the sweep into a busy loop on the one isolate serving every client.
  static const Duration minimumInterval = Duration(milliseconds: 5);

  /// A quarter of the deadline, floored.
  ///
  /// A value is then reported stale within 125% of its deadline rather than
  /// within 200% — `fake_state_man.dart:200-213`'s arithmetic and its reason:
  /// the margin between those two numbers is what keeps a freshness case green
  /// on a loaded machine.
  static Duration intervalFor(Duration staleAfter) {
    final quarter = staleAfter ~/ 4;
    return quarter < minimumInterval ? minimumInterval : quarter;
  }

  /// This sweep's cadence.
  Duration get interval => intervalFor(staleAfter);

  /// The clock. A named field, in the one file `freeze_test.dart`'s
  /// `periodicTimerAllowList` names.
  Timer? _timer;

  /// Whether the clock is running right now.
  bool get running => _timer != null;

  /// How many passes have been made. A diagnostic, and the observable that
  /// tells a case the gate actually opened.
  int get sweeps => _sweeps;
  int _sweeps = 0;

  /// Somebody started watching.
  ///
  /// Sweeps once immediately, for `ClientWrapper._startHealthTimer`'s reason
  /// (`state_man.dart:977-979`): the state the new watcher is about to read may
  /// predate them, and waiting a quarter of a deadline to tell them so is a
  /// quarter of a deadline of a number they should not have believed.
  void start() {
    if (_timer != null) return;
    sweep();
    _timer = Timer.periodic(interval, (_) => sweep());
  }

  /// Nobody is watching any more.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One pass over the store.
  ///
  /// Three rules, and each one is a decision:
  ///
  ///  * **Health keys are skipped by prefix** (HLTH-02, see the library doc).
  ///  * **A key with no recorded arrival is skipped.** Nothing has ever come
  ///    for it, so it is `uncertainNotYetKnown` and not stale — those are
  ///    different statements and the second one implies the first was once
  ///    true.
  ///  * **A key already carrying worse news stages no change.** The comparison
  ///    is `Quality.badStale.band <= cached.quality.band`, deliberately *not*
  ///    `Quality.worst`: worst-wins would return the same verdict but would
  ///    stage a value, and a staged value that happens to equal the cached one
  ///    still costs an allocation and a comparison per key per tick. More to
  ///    the point, a key needing no change should notify nobody
  ///    (`fake_state_man.dart:517`, `:570`).
  void sweep() {
    _sweeps++;
    final now = _now();
    final stale = <String, DynamicValue>{};
    for (final key in _store.keys) {
      final cached = _store.peek(key);
      if (cached == null) continue;
      if (!_isStale(key, cached, now)) continue;
      // copyWith carries sourceTime through untouched. A degradation is not
      // news from upstream, and restamping it would make the value look freshly
      // delivered at the exact moment it stopped being trustworthy.
      stale[key] = cached.copyWith(quality: Quality.badStale);
    }
    if (stale.isEmpty) return;
    _degrade(stale);
  }

  /// The synchronous re-derivation: what [key] should read as *right now*.
  ///
  /// Property 2 of the three above. A caller on the read path gets the correct
  /// verdict whether or not a tick has happened since the deadline passed,
  /// which is what makes the listener gate safe. It does **not** write to the
  /// store: a read is not an event, and a read that notified every listener
  /// would make a diagnostics page's poll a rebuild storm.
  DynamicValue judge(String key, DynamicValue cached) =>
      _isStale(key, cached, _now())
          ? cached.copyWith(quality: Quality.badStale)
          : cached;

  bool _isStale(String key, DynamicValue cached, DateTime now) {
    if (PipeKeys.isPipeKey(key)) return false;
    final arrived = _lastArrival[key];
    if (arrived == null) return false;
    if (now.difference(arrived) < staleAfter) return false;
    if (Quality.badStale.band <= cached.quality.band) return false;
    return true;
  }

  /// Teardown. A timer that outlives its source keeps the isolate alive and
  /// keeps sweeping a store nobody is watching, so a leak in one case surfaces
  /// as an inexplicable notification in the next one.
  void dispose() => stop();
}
