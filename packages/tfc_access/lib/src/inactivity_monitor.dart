import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

/// A countdown that only exists while something is listening.
///
/// Inactivity drops an elevated session back to anonymous — spec §5, fifteen
/// minutes by default. The interesting part is not the countdown but *when it
/// is allowed to run*: the timer is started in the [expirations] stream's
/// `onListen` and stopped in its `onCancel`, so a caller that never listens
/// never pays for a timer.
///
/// That is not decoration. An always-on `Timer.periodic` in shared plumbing has
/// failed unrelated widget tests in this repo before: a pending timer at the
/// end of a `testWidgets` body fails the test even when the widget under test
/// never touched the thing that armed it, so a timer in a provider that half
/// the app happens to construct turns into red tests in files nobody edited.
/// Starting in `onListen` and stopping in `onCancel` means the cost is paid by
/// exactly the code that asked for it. `test/inactivity_monitor_test.dart` has
/// a test named `'no timer is armed while nothing is listening'` whose only job
/// is to fail if this ever regresses.
///
/// One-shot on purpose: after emitting, nothing is armed. A timed-out session
/// drops to anonymous once, and whoever owns the session re-arms deliberately.
class InactivityMonitor {
  InactivityMonitor({required this.timeout});

  /// How long a quiet period ends the session. Never mutated — see [arm].
  final Duration timeout;

  late final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast(
    onListen: () => _restart(timeout),
    onCancel: _disarm,
  );

  Timer? _timer;

  /// Emits once when [timeout] elapses with no [poke].
  ///
  /// Broadcast, and the countdown's on/off switch: it starts in this stream's
  /// `onListen` and stops in its `onCancel`. `onCancel` on a broadcast
  /// controller fires when the *last* listener goes, which is exactly the
  /// gating wanted.
  Stream<DateTime> get expirations => _controller.stream;

  /// Record activity: re-arm for the full [timeout].
  ///
  /// A deliberate no-op when nothing is listening. There is no session to keep
  /// alive if nothing is watching one, and arming here is precisely the bug
  /// this class exists to prevent.
  void poke() => _restart(timeout);

  /// Re-arm for [within] instead of the full [timeout], without changing what
  /// a later [poke] arms for.
  ///
  /// This is what a re-attaching controller calls. A session's authority is its
  /// `expiresAt`, not elapsed wall clock, so a listener returning after a gap
  /// must arm for the time *remaining* — otherwise detaching and re-attaching
  /// would extend the session indefinitely.
  ///
  /// [timeout] stays final and unmutated on purpose. Without this method the
  /// only route through the API is a fresh `InactivityMonitor(timeout:
  /// remaining)` per re-attach, which works exactly once and then makes every
  /// subsequent [poke] re-arm for that remainder instead of the full fifteen
  /// minutes. A test asserts that the next poke after an `arm` restores the
  /// full timeout.
  ///
  /// A no-op when nothing is listening, exactly like [poke].
  void arm(Duration within) => _restart(within);

  /// True only while at least one listener is attached and a timer is armed.
  @visibleForTesting
  bool get isRunning => _timer != null;

  /// Close the stream and cancel anything outstanding. Safe to call twice, and
  /// [poke] and [arm] stay harmless afterwards.
  Future<void> dispose() async {
    _disarm();
    if (!_controller.isClosed) await _controller.close();
  }

  void _restart(Duration within) {
    if (_controller.isClosed || !_controller.hasListener) return;
    _timer?.cancel();
    _timer = Timer(within, _fire);
  }

  void _disarm() {
    _timer?.cancel();
    _timer = null;
  }

  /// `clock.now()` rather than `DateTime.now()`, so a caller can pin the
  /// timestamp under `withClock`.
  void _fire() {
    _disarm();
    if (!_controller.isClosed) _controller.add(clock.now());
  }
}
