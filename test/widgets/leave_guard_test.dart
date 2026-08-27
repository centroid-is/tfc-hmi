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

  test('a guard cleared mid-flight does not beam behind the next request',
      () async {
    // The page that installed the guard goes away while its answer is still
    // coming (the editor's dispose() calls clear()). The next request then
    // takes the synchronous no-guard path and beams immediately -- and the
    // stale answer must not beam a second time on top of it.
    final slow = Completer<bool>();
    Future<bool> guard() => slow.future;
    LeaveGuard.set(guard);

    var goes = 0;
    LeaveGuard.then(() => goes++);
    expect(goes, 0, reason: 'the guard has not answered yet');

    LeaveGuard.clear(guard);
    LeaveGuard.then(() => goes++);
    expect(goes, 1, reason: 'no guard left, so this one beams synchronously');

    slow.complete(true);
    await pumpEventQueue();
    expect(goes, 1, reason: 'the abandoned request must not beam again');
  });

  test('a guard replaced mid-flight does not beam over the page that took over',
      () async {
    // Programmatic navigation does not ask the guard (see the class doc), so
    // the page underneath a pending "Unsaved changes" answer can be swapped
    // out from under it. The answer then belongs to nobody.
    final slow = Completer<bool>();
    LeaveGuard.set(() => slow.future);
    var staleGo = false;
    LeaveGuard.then(() => staleGo = true);

    LeaveGuard.set(() async => true); // another page takes over

    slow.complete(true);
    await pumpEventQueue();
    expect(staleGo, isFalse,
        reason: 'the page that asked to leave is gone; its go must not run');
  });

  test('a second request does not ask the guard again, and wins the answer',
      () async {
    // The editor's guard pops its dialog and then awaits _saveToPrefs(), which
    // does not mark the page clean until it has finished writing. A tap in that
    // window must not put a second dialog on screen or start a second save.
    final gate = Completer<bool>();
    var asked = 0;
    LeaveGuard.set(() {
      asked++;
      return gate.future;
    });

    var first = false;
    var second = false;
    LeaveGuard.then(() => first = true);
    LeaveGuard.then(() => second = true);
    expect(asked, 1, reason: 'one question at a time -- no second dialog');

    gate.complete(true);
    await pumpEventQueue();
    expect(first, isFalse, reason: 'superseded by the later request');
    expect(second, isTrue, reason: 'the newest destination is the one taken');
  });

  test('go throwing is contained and does not wedge the next request',
      () async {
    LeaveGuard.set(() async => true);
    LeaveGuard.then(() => throw StateError('beam failed'));
    await pumpEventQueue();

    var ranAgain = false;
    LeaveGuard.then(() => ranAgain = true);
    await pumpEventQueue();
    expect(ranAgain, isTrue, reason: 'a failed beam does not lock navigation');
  });
}
