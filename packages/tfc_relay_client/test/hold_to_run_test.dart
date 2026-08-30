/// The operator's end of hold-to-run: two of the three release paths, and the
/// structural properties that make the third one safe.
///
/// Source: 05-CONTEXT decision 2 — a pure-Dart `HoldToRunController` with
/// **injectable** release triggers, so that tap-cancel, app-lifecycle and
/// disconnect arrive as plain callbacks and streams and each release path can
/// be driven by a test with no Flutter in the process. The Flutter gesture and
/// lifecycle binding is documented in 05-08 rather than built.
///
/// Source: 05-CONTEXT decision 3 — the PLC's deadman is ~1 s, roughly ten
/// missed pulses at 10 Hz. The cases here run at a much shorter cadence
/// injected through the constructor, because the property is "the counter
/// stopped", never "it stopped in 1000 ms".
///
/// **Why the counter and not a flag.** A panel that sets a boolean on press
/// and clears it on release leaves a machine running when it crashes in
/// between: the clear is the message that never gets sent. A counter inverts
/// that — a panel that crashes stops sending, and stopping is the safe state.
/// Everything asserted below is a statement about the counter stopping.
///
/// The third path, the link dying, is in `hold_to_run_fault_test.dart` against
/// a real gateway through the real proxy. It cannot live here: the in-memory
/// harness has no link to lose, and the in-memory channel pair forwards
/// client-to-server verbatim by design (05-RESEARCH trap 8), so a severed link
/// is not a fault it can produce.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/hold_to_run_controller.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

/// The tag the deadman counter lands on. One key, and it is the one the caller
/// named: the tag *is* the counter (D-P5-D).
const _key = 'ST101.CN01.MOT01.jog';

/// A key the plant refuses writes to, for the engage that does not take.
const _refusedKey = 'ST301.CN21.SEN01.temp';

/// The cadence these cases inject.
///
/// Far below `ClientConfig.holdPulsePeriod`'s 100 ms on purpose: the property
/// is that the counter stops, and a case that waited on the production cadence
/// would spend seconds proving something that takes milliseconds. The number
/// arrives through the constructor precisely so this is possible — a
/// controller that owned its own cadence would make every case here a
/// wall-clock test of the plant's number.
const Duration _pulse = Duration(milliseconds: 25);

/// Longer than three pulse periods, which is what "it stopped" has to be
/// measured over.
///
/// The one shape a poll cannot establish is the absence of an event: polling
/// for "no further pulse" succeeds at the first instant before the next one.
const Duration _quiet = Duration(milliseconds: 200);

/// How many pulses must land before "and then it stopped" means anything.
///
/// Anti-vacuity, and it is the whole risk in this file: a hold that never fed
/// anything stops trivially, and a case that did not check would report a
/// controller with a broken timer as a controller that releases correctly.
const int _pulsesBeforeRelease = 4;

/// Polls [done] until it holds or [budget] runs out, and fails naming [what].
///
/// `fault_fixture.dart:160-172`'s waiter and its argument, kept local because
/// this file starts no gateway and importing the socket fixture for one helper
/// would make an in-memory suite depend on a package that binds ports.
Future<void> _until(
  String what,
  bool Function() done, {
  Duration budget = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(budget);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after ${budget.inMilliseconds} ms waiting for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A plant with the deadman tag seeded, torn down with the case.
///
/// Seeded before anything engages: `FakeStateMan.keys` does not name a tag
/// until a value has been set on it, and the refusal arm needs a key that
/// exists in order to be refused rather than unknown.
FakeStateMan _plant() {
  final plant = FakeStateMan();
  addTearDown(plant.dispose);
  plant.setValue(_key, 0);
  plant.setValue(_refusedKey, 0);
  return plant;
}

/// The source file the structural group reads. Relative to the package root,
/// which is the working directory `dart test` runs in.
const _controllerPath = 'lib/src/hold_to_run_controller.dart';

void main() {
  group('the operator lets go', () {
    test('the operator letting go stops the counter', () async {
      final plant = _plant();
      final controller = HoldToRunController(
        api: plant,
        key: _key,
        pulsePeriod: _pulse,
      );
      addTearDown(controller.dispose);

      final engagement = await controller.press();
      expect(engagement, isA<WriteApplied>(),
          reason: 'the engage on a key nothing objected to came back as '
              '${engagement.runtimeType}, so this case has no live hold and '
              'everything below it is about a controller that never started');
      expect(controller.isHeld, isTrue);
      expect(controller.debugTimerCount, 1,
          reason: 'a held hold with no timer is a button that lights and a '
              'machine that never jogs');

      await _until(
          'the deadman counter to pass $_pulsesBeforeRelease on the tag',
          () => (plant.read(_key)?.asInt ?? 0) >= _pulsesBeforeRelease);

      await controller.release();

      expect(controller.debugReleaseReason, HoldEnded.operatorLetGo,
          reason: 'the release recorded '
              '${controller.debugReleaseReason} rather than the operator '
              'letting go, and the reason is what the panel puts on the screen '
              'instead of "the link died" — two different sentences to '
              'somebody holding a button that has stopped working');
      expect(controller.isHeld, isFalse);
      expect(controller.debugTimerCount, 0,
          reason: 'the pulse timer outlived the release. A timer nobody owns '
              'fires into a hold that has ended, and the next thing it does '
              'depends on whether some later engage happens to be live');
      expect(plant.read(_key)?.asInt, 0,
          reason: 'the release write never put 0 on the tag. The counter '
              'stopping is what stops the machine within the deadman window, '
              'but the 0 is what stops it now — and a controller that cancels '
              'its timer without releasing looks identical until you read the '
              'tag');

      // The window, not an instant: the failure this catches is a timer that
      // fires once more after the finger came off.
      final pulsesAtRelease = controller.debugPulsesSent;
      expect(pulsesAtRelease, greaterThanOrEqualTo(_pulsesBeforeRelease - 1),
          reason: 'only $pulsesAtRelease pulses were ever emitted, so the '
              '"it stopped" window below is measuring a controller that had '
              'barely started');
      await Future<void>.delayed(_quiet);
      expect(controller.debugPulsesSent, pulsesAtRelease,
          reason: 'the controller emitted a pulse after the operator let go. '
              'On a plant that is the deadman being fed by a button nobody is '
              'holding, which is the one failure this whole design exists to '
              'make impossible');
      expect(plant.read(_key)?.asInt, 0,
          reason: 'the deadman counter moved after the release, so something '
              'is still feeding a hold that ended');
    });

    test('releasing twice writes one zero and keeps the first reason',
        () async {
      final plant = _plant();
      final controller = HoldToRunController(
        api: plant,
        key: _key,
        pulsePeriod: _pulse,
      );
      addTearDown(controller.dispose);

      await controller.press();
      await _until('the counter to move at all',
          () => (plant.read(_key)?.asInt ?? 0) >= 2);
      final attemptsBefore = plant.mintedCmds.length;

      await controller.release();
      final afterFirst = plant.mintedCmds.length;
      await controller.release(reason: HoldEnded.lifecycle);

      expect(plant.mintedCmds.length, afterFirst,
          reason: 'the second release wrote to the plant again. A disconnect '
              'racing an operator\'s finger is the ordinary case, not the '
              'exotic one, and two zeros on the wire for one release is a '
              'second actuation of a tag the PLC is watching');
      expect(afterFirst, greaterThan(attemptsBefore),
          reason: 'the first release wrote nothing, so the assertion above is '
              'comparing two numbers that were never going to differ');
      expect(controller.debugReleaseReason, HoldEnded.operatorLetGo,
          reason: 'the later call overwrote why the hold ended. The panel '
              'would then tell the operator the app was backgrounded when in '
              'fact they let go');
    });

    test('an engage the plant refuses starts no pulse at all', () async {
      final plant = _plant();
      plant.setReadOnly(_refusedKey, true);
      final controller = HoldToRunController(
        api: plant,
        key: _refusedKey,
        pulsePeriod: _pulse,
      );
      addTearDown(controller.dispose);

      final engagement = await controller.press();

      expect(engagement, isA<WriteRejected>(),
          reason: 'the plant refuses writes to $_refusedKey and the engage '
              'came back as ${engagement.runtimeType}');
      expect(controller.isHeld, isFalse,
          reason: 'the device said no and the controller reports a live hold, '
              'so the operator is looking at a lit button for a machine that '
              'never agreed to move');
      expect(controller.debugTimerCount, 0,
          reason: 'a refused engage started a pulse timer, which is a UI '
              'keeping a deadman fed for a hold that does not exist');
      await Future<void>.delayed(_quiet);
      expect(controller.debugPulsesSent, 0,
          reason: 'the controller fed a hold the plant refused');
    });
  });

  group('the app stops being in front of the operator', () {
    test('an app-lifecycle event stops the counter', () async {
      final plant = _plant();
      // A plain broadcast-free StreamController and nothing else: no Flutter,
      // no WidgetsBindingObserver, no import that would pull the analyzer into
      // this package's solve. That the trigger is injectable *is* the design
      // (05-CONTEXT decision 2) — this case is what it buys.
      final lifecycle = StreamController<void>();
      addTearDown(lifecycle.close);
      final controller = HoldToRunController(
        api: plant,
        key: _key,
        pulsePeriod: _pulse,
        releaseOn: lifecycle.stream,
      );
      addTearDown(controller.dispose);

      await controller.press();
      await _until(
          'the deadman counter to pass $_pulsesBeforeRelease on the tag',
          () => (plant.read(_key)?.asInt ?? 0) >= _pulsesBeforeRelease);

      lifecycle.add(null);
      await _until('the hold to end after the lifecycle event',
          () => !controller.isHeld);

      expect(controller.debugReleaseReason, HoldEnded.lifecycle,
          reason: 'the hold ended as ${controller.debugReleaseReason} after a '
              'lifecycle event. A finger on a button nobody is looking at is '
              'not a hold, and the reason is how the panel says so when the '
              'operator comes back to it');
      expect(controller.debugTimerCount, 0,
          reason: 'the pulse timer survived the app going away, which is a '
              'backgrounded panel jogging a machine');
      expect(plant.read(_key)?.asInt, 0,
          reason: 'the tag never went to 0, so the hold was abandoned rather '
              'than released');

      final pulsesAtRelease = controller.debugPulsesSent;
      await Future<void>.delayed(_quiet);
      expect(controller.debugPulsesSent, pulsesAtRelease,
          reason: 'the controller kept feeding the deadman after the app was '
              'backgrounded');
    });

    test('disposing releases a live hold and is idempotent', () async {
      final plant = _plant();
      final controller = HoldToRunController(
        api: plant,
        key: _key,
        pulsePeriod: _pulse,
      );

      await controller.press();
      await _until('the counter to move at all',
          () => (plant.read(_key)?.asInt ?? 0) >= 2);

      await controller.dispose();

      expect(controller.debugReleaseReason, HoldEnded.disposed,
          reason: 'a page torn down under a live hold ended it as '
              '${controller.debugReleaseReason}; disposed is what tells the '
              'next reader of a log that nobody let go, the screen closed');
      expect(controller.debugTimerCount, 0,
          reason: 'the pulse timer outlived the controller that owns it — the '
              'orphaned-timer failure the client asserts a ceiling against '
              'everywhere else');
      expect(plant.read(_key)?.asInt, 0);

      // Idempotent: a page can be disposed twice, and the second one must not
      // write a second zero or throw into a teardown nobody is awaiting.
      final attempts = plant.mintedCmds.length;
      await controller.dispose();
      expect(plant.mintedCmds.length, attempts,
          reason: 'the second dispose wrote to the plant again');
    });
  });

  group('the controller carries no queue and one timer', () {
    // Structural, and it stays structural on purpose (T-05-28). The gate that
    // drops a pulse the link cannot carry lives in `RemoteStateMan` (05-04);
    // the thing that must not exist is a *second* buffer above it, because
    // `_WsSink.add` goes straight to a `dart:io` sink that buffers without
    // bound and offers no `bufferedAmount` and no `flush()` (flutter#103306).
    // A behavioural case cannot see the collection that is not there.
    late List<String> code;

    setUp(() {
      final source = File(_controllerPath);
      // Anti-vacuity: a sweep against a file that is not there passes by
      // having nothing to read, and the working directory `dart test` was
      // invoked from is exactly the sort of thing that changes silently.
      expect(source.existsSync(), isTrue,
          reason: 'the controller was not found at $_controllerPath, so every '
              'sweep below read nothing and passed by default. dart test was '
              'invoked from ${Directory.current.path}');
      code = source
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('///'))
          .where((line) => !line.trimLeft().startsWith('//'))
          .toList();
      expect(code, isNotEmpty,
          reason: 'the controller is entirely comments, so the sweeps below '
              'are reading an empty list');
    });

    test('there is no pending-pulse collection anywhere in the file', () {
      final collections = code
          .where((line) =>
              line.contains('List<') ||
              line.contains('Queue') ||
              line.contains('[]'))
          .toList();

      expect(collections, isEmpty,
          reason: 'the controller holds a collection: $collections. A pulse '
              'that cannot be sent must be dropped, never stored — the socket '
              'underneath already buffers without bound and reports nothing '
              'about it, so a queue here is a burst of stale deadman counter '
              'values delivered the instant a stalled link recovers, which is '
              'a machine jogging on a finger that came off a minute ago');
    });

    test('the controller watches no link state of its own', () {
      final watchers =
          code.where((line) => line.contains('LinkState')).toList();

      expect(watchers, isEmpty,
          reason: 'the controller names LinkState: $watchers. One thing '
              'watches the link and it is the client that owns it — '
              'RemoteStateMan releases every live hold on leaving ready '
              '(remote_state_man.dart, `_wasReady`). A second watcher is a '
              'second thing that can disagree with the first about whether a '
              'machine should still be moving');
    });

    test('exactly one timer field is declared', () {
      final declarations =
          code.where((line) => line.contains('Timer? ')).toList();

      expect(declarations, hasLength(1),
          reason: 'the controller declares ${declarations.length} timer '
              'fields: $declarations. One nullable field, cancelled and '
              'nulled, is the design — `freshness_watchdog.dart:138` says it '
              'in one line ("not a list: the type is the design"), and the '
              'reason is that every extra timer is another thing a teardown '
              'can miss, firing afterwards into a hold that has ended');
    });
  });
}
