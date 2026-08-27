/// [LeaveGuard.then] must never lose the operator's navigation into a wedge.
///
/// The navigation chrome (the nav bar, the back arrow, the menu items) beams
/// through [LeaveGuard.then]. When a page has installed a guard the answer is
/// asynchronous -- a dialog tap, a save -- and a hung, throwing or superseded
/// guard used to silently swallow the beam, leaving the screen frozen on the
/// tap that asked to leave. These tests pin the resilient behaviour.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/leave_guard.dart';

void main() {
  // A leftover guard from one test must not answer another's request. clear()
  // only nulls the slot when handed the guard that is installed, so install a
  // known one and clear exactly it -- leaving [LeaveGuard] with no guard set.
  setUp(() {
    Future<bool> reset() async => true;
    LeaveGuard.set(reset);
    LeaveGuard.clear(reset);
    expect(LeaveGuard.isSet, isFalse);
  });

  test('no guard installed: go runs synchronously', () {
    var ran = false;
    LeaveGuard.then(() => ran = true);
    expect(ran, isTrue,
        reason: 'the pane-close and beam must run inside the tap handler');
  });

  test('guard allows: go runs', () async {
    final gate = Completer<bool>();
    LeaveGuard.set(() => gate.future);
    var ran = false;
    LeaveGuard.then(() => ran = true);

    expect(ran, isFalse, reason: 'the guard has not answered yet');
    gate.complete(true);
    await pumpEventQueue();
    expect(ran, isTrue);
  });

  test('guard refuses: go does not run', () async {
    LeaveGuard.set(() async => false);
    var ran = false;
    LeaveGuard.then(() => ran = true);
    await pumpEventQueue();
    expect(ran, isFalse);
  });

  test('guard throws: go does not run, error does not escape, next tap works',
      () async {
    LeaveGuard.set(() async => throw StateError('dialog on a dead context'));
    var ran = false;

    // The throw must be handled inside then(); an uncaught async error here
    // would fail the test, which is exactly the regression we are pinning.
    LeaveGuard.then(() => ran = true);
    await pumpEventQueue();
    expect(ran, isFalse, reason: 'a failed guard stays on the page');

    // A hung/failed guard must not lock navigation out: a fresh request with a
    // guard that answers must still proceed.
    LeaveGuard.set(() async => true);
    var ranAgain = false;
    LeaveGuard.then(() => ranAgain = true);
    await pumpEventQueue();
    expect(ranAgain, isTrue, reason: 'the next tap is not swallowed');
  });

  test('a superseded guard does not beam after a newer request', () async {
    final slow = Completer<bool>();
    LeaveGuard.set(() => slow.future);
    var firstRan = false;
    LeaveGuard.then(() => firstRan = true);

    // The operator asks again before the first guard answered; the second
    // request is the one that should win.
    final quick = Completer<bool>();
    LeaveGuard.set(() => quick.future);
    var secondRan = false;
    LeaveGuard.then(() => secondRan = true);

    quick.complete(true);
    await pumpEventQueue();
    expect(secondRan, isTrue);

    // The stale first guard now answers true -- it must be ignored, or it would
    // beam a second time on top of where the second request already went.
    slow.complete(true);
    await pumpEventQueue();
    expect(firstRan, isFalse,
        reason: 'only the newest leave request may run its go');
  });
}
