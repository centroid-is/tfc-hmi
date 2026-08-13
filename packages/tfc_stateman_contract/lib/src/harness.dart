/// How a contract case drives an implementation, and how it observes one.
///
/// A contract check is handed a `StateManApi` and nothing else, but every
/// interesting property of a state source is about what happens *when a value
/// arrives* — and no method on the wire surface makes a value arrive. On a real
/// source a PLC does that; under test something has to stand in for the PLC.
/// [StateManHarness] is that something: the small control surface an
/// implementation exposes **for testing only**, declared here rather than in
/// the implementation so this package keeps its defining property — it imports
/// no implementation, and the factory passed to a `run…Contract` function is
/// the only coupling to one.
///
/// The lever names are deliberately the ones CONTEXT lists for the fake and,
/// where they overlap, the ones Phase 2's fault proxy will pull. A case written
/// against this interface transfers to the fault legs unchanged.
///
/// [Notifications] is the other half: rebuild counting. Most of what this phase
/// promises operators is a *count* — k changed keys cost k rebuilds, an
/// unchanged value costs none, a disposed source costs none ever again — and a
/// count is only meaningful next to a deadline, so the wait for the next
/// notification is a future that [within] can turn into a named failure.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// The test-only control surface: what stands in for the plant.
///
/// An implementation under test implements this alongside `StateManApi`. It is
/// not part of the wire surface and must never be: `api_surface_test.dart`
/// exists precisely to keep methods like these off the interface a connected
/// client can invoke.
abstract interface class StateManHarness {
  /// Delivers [value] for [key], as one upstream update.
  ///
  /// [sourceTime] defaults to null rather than to "now" on purpose: a source
  /// that stamps every arriving sample with its receive time makes two
  /// identical readings unequal, and the unchanged-value guard — the whole
  /// k-of-n rebuild property — silently stops working. That failure has its
  /// own sabotage variant.
  void setValue(String key, Object? value,
      {Quality quality = Quality.good, DateTime? sourceTime});

  /// Delivers many keys as exactly **one** batch.
  ///
  /// Separate from repeated [setValue] calls because the batch is the unit the
  /// notification-count promise is made about: 1500 keys arriving together must
  /// cost one pass and k notifications, not 1500 of each.
  void setValues(Map<String, Object?> values);

  /// Re-delivers the current value for [key] under a different [quality].
  ///
  /// Simulates the value going stale, the upstream link dropping, or a write
  /// going pending — the states an operator must be able to see without the
  /// number itself changing.
  void setQuality(String key, Quality quality);

  /// The tag is gone upstream: [key] reports [Quality.errorConfig] and never
  /// updates again.
  ///
  /// A renamed or deleted PLC tag, which is a configuration fault rather than a
  /// transient — waiting does not fix it, so the value must not keep rendering
  /// as a plausible last-known number.
  void dropKey(String key);
}

/// The [StateManHarness] side of [api], or a failure saying what is missing.
///
/// Reported through `fail` rather than a cast error so an implementation that
/// arrives without a control surface gets a message telling its author what to
/// add, instead of a `_CastError` naming a line in this package.
StateManHarness harnessOf(StateManApi api) {
  // An explicit cast, not a promotion: `StateManHarness` is not a subtype of
  // `StateManApi`, and Dart promotes only towards subtypes. The `is` test above
  // it is what makes the cast safe, and what turns the failure into the message
  // below instead of a `_CastError`.
  if (api is StateManHarness) return api as StateManHarness;
  fail('${api.runtimeType} does not implement StateManHarness, so no contract '
      'case can make a value arrive for it. An implementation under test must '
      'expose the test-only control surface (setValue/setValues/setQuality/'
      'dropKey) declared in package:tfc_stateman_contract.');
}

/// Counts notifications from one node, and lets a case wait for the next one.
///
/// Created by [observe]. Counting is the point: `expect(seen.count, 0)` is how
/// "re-delivering an identical value rebuilds nothing" is stated, and it is a
/// statement about the absence of an event, which can only be made after a
/// barrier that would have carried the event if there were one.
final class Notifications {
  final ValueListenable<DynamicValue> _node;
  late final VoidCallback _listener;

  int _count = 0;
  int _unconsumed = 0;
  Completer<void>? _waiting;

  Notifications._(this._node) {
    _listener = _onNotify;
    _node.addListener(_listener);
  }

  /// How many notifications this node has fired since [observe] was called.
  int get count => _count;

  /// Completes on the next notification — or immediately if one has already
  /// arrived and not yet been awaited.
  ///
  /// The already-arrived case is not an optimisation: an in-process
  /// implementation notifies **synchronously** inside `setValue`, so by the
  /// time a case awaits, the event it is waiting for is in the past. Without
  /// this, every check would hang against a correct local implementation and
  /// pass only against a slow remote one.
  Future<void> get next {
    if (_unconsumed > 0) {
      _unconsumed--;
      return Future<void>.value();
    }
    return (_waiting ??= Completer<void>()).future;
  }

  /// Stops counting. Removing a listener that was never added is a no-op, so
  /// this is safe after the source has been disposed.
  void stop() => _node.removeListener(_listener);

  void _onNotify() {
    _count++;
    final waiting = _waiting;
    if (waiting == null) {
      _unconsumed++;
    } else {
      _waiting = null;
      waiting.complete();
    }
  }
}

/// Starts counting notifications from [node].
Notifications observe(ValueListenable<DynamicValue> node) =>
    Notifications._(node);
