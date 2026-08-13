/// The write half of the contract: what an operator is owed after they press
/// a button, and what no implementation is allowed to do on their behalf.
///
/// This is the safety-relevant slice. Everything else in the suite is about
/// showing a number honestly; these cases are about *changing the plant*. The
/// interface being contracted here (`state_man_api.dart:111-134`) deliberately
/// diverges from the `Future<void> write` this project is replacing
/// (`state_man.dart:1544`), and the divergence is the whole point: a write that
/// throws to report its outcome has collapsed "the PLC may have applied this"
/// into "this failed", and an operator told "failed" re-sends. Re-sending a
/// setpoint the machine already took is how a second start command reaches a
/// conveyor somebody is standing on.
///
/// Five properties, in the order an operator meets them:
///
///  * **Exactly one of three states.** Applied with a readback, rejected with a
///    reason, or explicitly unknown. Never a throw, and never a fourth thing.
///  * **Applied means applied *and read back*.** The number on the mimic after
///    a write is the number the device holds, not the number that was typed. A
///    PLC that clamps a setpoint to its configured maximum must be visible.
///  * **One attempt per operator action.** No code path may re-send a write.
///    That property is invisible from the API surface — a retry wrapper looks
///    exactly like a slow link — so the contract asserts an observable attempt
///    counter (RESEARCH Risk 6). The auto-retry variant in
///    `broken_write.dart` is the sabotage that keeps this case honest.
///  * **Every action carries an id.** A 26-character ULID minted inside the
///    implementation at call time, because the call *is* the operator action
///    (CONTEXT D-04). Without it there is no way to reconcile, after a
///    reconnect, what became of the write that was in flight.
///  * **Nothing an operator can type can detonate the pipe.** A read-only key
///    is rejected rather than thrown (`M2400DeviceClientAdapter.write` throws
///    `UnsupportedError` today, `state_man.dart:929-931`), and a non-finite
///    value is sanitized rather than allowed to reach `jsonEncode`, which
///    throws on ±Infinity and would fail the frame for every other client on
///    it.
///
/// Shape follows `read_contract.dart` and `freshness_contract.dart`: no
/// implementation is imported, every case is a named top-level function so the
/// sabotage suite can run it against a damaged implementation, and every await
/// is wrapped in [within] so silence fails by name instead of hanging to the
/// runner's timeout. Writes add one wrinkle to that shape — a check that
/// asserts "this does not throw" must not let a throw escape raw, or the
/// sabotage suite's third clause reports a stack frame instead of the promise.
/// [_outcomeOf] is where that conversion happens, once.
library;

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'check.dart';
import 'harness.dart';

/// A motor setpoint on the pre-freezer conveyor line: the ordinary thing an
/// operator writes, and one where the device having its own opinion about the
/// value (a clamp, an interlock) is entirely normal.
const _setpointKey = 'ST101.CN01.MOT01.setpoint';

/// A second writable key, used where a case needs to prove that a bad write to
/// one key left the rest of the source working.
const _otherKey = 'ST201.CN04.MOT01.setpoint';

/// A sensor reading: the natural read-only key. Used when the caller of
/// [runWriteContract] does not name one of its own.
const _sensorKey = 'ST301.CN07.SEN01.temp';

/// A ULID as `ulid.dart` mints it: 26 characters of Crockford base32, which
/// excludes I, L, O and U so an id read off a panel into a support ticket
/// cannot be transcribed wrong.
final _ulid = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$');

/// The write-side of the test-only control surface.
///
/// [StateManHarness] stands in for the plant on the read path; this stands in
/// for the plant's *answers* on the write path. It is separate for the same
/// reason `StateManHarness` is separate from `StateManApi`: a connected client
/// must never be able to make the gateway pretend a device said no, and
/// capability here is defined by surface.
///
/// The levers are named for their Phase 2 proxy counterparts where they
/// overlap ([stallWrites] ↔ `blackhole`, and the link drop these cases use is
/// [StateManHarness.disconnectUpstream] ↔ `flap`), so a case written here
/// transfers to the fault legs unchanged.
///
/// It also carries the one *observable* the wire surface deliberately does not
/// expose. [upstreamWriteAttempts] is the whole reason the no-auto-retry
/// property is testable at all: a retry is invisible from outside — same call,
/// same result, slightly later — so without a count, "writes are never
/// auto-retried" is a claim no test can make. Putting it on `StateManApi`
/// instead would make it a thing a connected client may query, which is an
/// access-control decision and not a testing convenience.
abstract interface class StateManWriteHarness implements StateManHarness {
  /// The device says no to the next write only.
  ///
  /// With [unknown] the gateway instead loses track of it — a PLC timeout, the
  /// answer that must never be reported as a refusal.
  void failNextWrite(WriteReason reason, {bool unknown = false});

  /// The next write is taken but the device ends up holding [readback] instead
  /// of the value written — a PLC clamping a setpoint to its configured
  /// maximum, the commonest reason a readback and a typed value differ.
  void clampNextWrite(Object? readback);

  /// Writes go upstream and no answer comes back (Phase 2's `blackhole`).
  ///
  /// The in-flight window, held open so a case can look at it.
  void stallWrites();

  /// Ends the stall and settles everything parked by it — applied by default,
  /// or [applied] `false` for an outcome nobody knows.
  void releaseWrites({bool applied = true});

  /// Whether the device permits writes to [key].
  void setReadOnly(String key, bool readOnly);

  /// How many times this source has attempted [cmd] upstream.
  ///
  /// Must be exactly one, forever. A re-send is an operator decision, never a
  /// machine's.
  int upstreamWriteAttempts(String cmd);

  /// Every `cmd` this source has minted, in the order it minted them.
  List<String> get mintedCmds;
}

/// The [StateManWriteHarness] side of [api], or a failure saying what is
/// missing.
///
/// Reported through `fail` rather than a cast error for the same reason
/// [harnessOf] does it: an implementation that arrives without a write control
/// surface gets a message telling its author what to add, instead of a
/// `_CastError` naming a line in this package.
StateManWriteHarness writeHarnessOf(StateManApi api) {
  if (api is StateManWriteHarness) return api as StateManWriteHarness;
  fail('${api.runtimeType} does not implement StateManWriteHarness, so no '
      'write case can make the plant answer for it. An implementation under '
      'test must expose the test-only write control surface (failNextWrite/'
      'clampNextWrite/stallWrites/releaseWrites/setReadOnly) and the '
      'upstreamWriteAttempts observable declared in '
      'package:tfc_stateman_contract — the attempt count in particular, '
      'because a write that is quietly re-sent is indistinguishable from a '
      'slow one without it.');
}

/// Awaits a write and turns *any* throw into a named failure.
///
/// The contract's central write promise is "never throws to report an
/// outcome", and a check that asserts it must not let the throw escape raw:
/// `expectContractViolation`'s third clause exists precisely to forbid a
/// violation surfacing as a `StateError` from inside an implementation, where
/// the CI message names a stack frame instead of the promise an operator lost.
/// Every await of a write in this file goes through here.
Future<WriteResult> _outcomeOf(Future<WriteResult> write, String what) async {
  try {
    return await within(write, what);
  } on TestFailure {
    // `within`'s own silence-became-a-failure, and any `expect` inside the
    // awaited work. Already diagnostic; passing it through unchanged.
    rethrow;
  } catch (error) {
    fail('$what threw ${error.runtimeType} ($error) instead of resolving with '
        'a WriteResult. A write that throws has collapsed "the PLC may have '
        'applied this" into "this failed", and an operator who is told a '
        'write failed re-sends it — which is how a second start command '
        'reaches a machine that already took the first one');
  }
}

/// The attempt count, read off the implementation's own control surface.
///
/// The default behind [runWriteContract]'s `upstreamWriteAttempts` override.
int _attemptsFromHarness(StateManApi api, String cmd) =>
    writeHarnessOf(api).upstreamWriteAttempts(cmd);

/// A successful write resolves applied, carrying what the device actually
/// holds.
///
/// "Applied" always means "applied and read back" (`write_result.dart:73-75`).
/// An implementation that resolves applied while echoing the value it was
/// handed has confirmed nothing at all: it has told the operator that what
/// they typed is now true, on no evidence, which is the same lie a stale value
/// tells and harder to see because it arrives as a confirmation.
Future<void> checkAppliedCarriesReadback(StateManApi api) async {
  final plant = writeHarnessOf(api);
  plant.setValue(_setpointKey, 1200);

  final result = await _outcomeOf(
      api.write(_setpointKey, 1450), 'a write to a healthy key resolving');

  expect(result, isA<WriteApplied>(),
      reason: 'a write nothing objected to resolved as '
          '${result.runtimeType}; the ordinary case must be the one an '
          'operator can read as "done"');
  final applied = result as WriteApplied;
  expect(applied.readback, 1450,
      reason: 'the result carried ${applied.readback} where the device holds '
          '1450; "applied" means "applied and read back", and a result that '
          'echoes the typed value confirms nothing — the mimic would show the '
          'operator their own keystrokes back as though the plant had agreed');
  expect(applied.at, greaterThan(0),
      reason: 'an applied write arrived without a timestamp; the write audit '
          'trail and the reconcile-after-reconnect path both order by it');
  expect(applied.cmd, matches(_ulid),
      reason: 'the result carried "${applied.cmd}", which is not the '
          '26-character id this action can be reconciled by');
}

/// A device saying no resolves rejected, with a reason, without throwing.
///
/// An interlock is not an error — it is the safety system doing its job, and
/// the operator needs to be told *which* one. A successful call carrying bad
/// news (`write_result.dart:87-88`), so the reason reaches the screen instead
/// of an exception reaching a `catch` block that logs and shows "write
/// failed".
Future<void> checkRejectedCarriesReasonAndDoesNotThrow(StateManApi api) async {
  final plant = writeHarnessOf(api);
  plant.setValue(_setpointKey, 1200);
  plant.failNextWrite(
      const WriteReason('interlocked', message: 'guard door open'));

  // Reaching the next line at all is half the assertion: _outcomeOf converts a
  // throw into a named failure rather than letting it escape.
  final result = await _outcomeOf(api.write(_setpointKey, 1450),
      'a write the device refuses resolving rather than throwing');

  expect(result, isA<WriteRejected>(),
      reason: 'the device refused the write and the call resolved as '
          '${result.runtimeType}; a refusal is a successful call carrying bad '
          'news, not a failure of the call');
  final rejected = result as WriteRejected;
  expect(rejected.reason.kind, isNotEmpty,
      reason: 'the refusal arrived with no reason kind; "write rejected" with '
          'nothing after it sends an operator to look for a fault the pipe '
          'already knew the name of');
  expect(rejected.reason.kind, 'interlocked',
      reason: 'the reason kind must be the greppable one the device gave '
          '("interlocked"), not a generic one invented on the way out — the '
          'kind is what a support engineer greps six months later');
  expect(rejected.cmd, matches(_ulid),
      reason: 'a rejected write must still carry its id, or the one outcome '
          'an operator is most likely to ask about cannot be looked up');
}

/// A write in flight when the link drops resolves unknown — never a failure.
///
/// The single most important case in this file. The PLC may have applied it.
/// Nobody knows, including the gateway, and the only honest answer is to say
/// so. Reporting it as rejected invites a re-send of a command the machine
/// already took; reporting it as a throw does the same thing with a stack
/// trace attached.
///
/// [dropLinkWithWritesInFlight] overrides how the link is dropped, for an
/// implementation whose link is not the harness's to cut.
Future<void> checkLostLinkYieldsUnknownNeverFailure(
  StateManApi api, {
  void Function(StateManApi api)? dropLinkWithWritesInFlight,
}) async {
  final plant = writeHarnessOf(api);
  final dropLink =
      dropLinkWithWritesInFlight ?? (a) => writeHarnessOf(a).disconnectUpstream();

  plant.setValue(_setpointKey, 1200);
  plant.stallWrites();
  final pending = api.write(_setpointKey, 1450);
  dropLink(api);

  final result = await _outcomeOf(pending,
      'a write that was in flight when the link dropped resolving');

  expect(result, isA<WriteUnknown>(),
      reason: 'the link dropped with a write in flight and the outcome came '
          'back as ${result.runtimeType}; the PLC may have applied it, so '
          'unknown is the only answer that is true — and it is the answer '
          'that stops an operator re-sending a command the machine already '
          'took');
  expect(result, isNot(isA<WriteRejected>()),
      reason: 'an outcome nobody knows was reported as a refusal; "rejected" '
          'means the device said no, and telling an operator that is how a '
          'setpoint gets sent twice');
  expect((result as WriteUnknown).reason.kind, isNotEmpty,
      reason: 'an unknown outcome arrived with no reason kind; the operator '
          'is being asked to go and verify something and must be told why');
}

/// The three outcomes are distinguishable through the public API.
///
/// Asserted with a local exhaustive `switch` over the sealed type, mirroring
/// `write_result_test.dart:59-71`. That switch is a compile-time tripwire as
/// much as a runtime one: adding or removing a state breaks compilation here
/// first, in a file whose comments explain what each state costs an operator.
///
/// The runtime half matters just as much. An implementation that maps two
/// outcomes onto one — the commonest shape being "anything that is not applied
/// is a failure" — passes every check that only looks at the happy path.
Future<void> checkUnknownIsDistinctFromRejected(StateManApi api) async {
  final plant = writeHarnessOf(api);
  plant.setValue(_setpointKey, 1200);

  // The tripwire. Every state named, and named in the words the operator
  // consequence is written in, so removing one is a compile error here.
  String label(WriteResult result) => switch (result) {
        WriteApplied() => 'applied',
        WriteRejected() => 'rejected — the device said no',
        WriteUnknown() => 'unknown — verify, never auto-retry',
        WriteNotReceived() => 'not received — the operator may re-send',
      };

  plant.failNextWrite(const WriteReason('out_of_range'));
  final refused = await _outcomeOf(
      api.write(_setpointKey, 9999), 'a refused write resolving');

  plant.failNextWrite(const WriteReason('plc_timeout'), unknown: true);
  final lost = await _outcomeOf(
      api.write(_setpointKey, 1450), 'a write of unknown outcome resolving');

  expect(label(refused), 'rejected — the device said no',
      reason: 'a refusal came back as "${label(refused)}"');
  expect(label(lost), contains('never auto-retry'),
      reason: 'an outcome nobody knows came back as "${label(lost)}"; the two '
          'must stay distinguishable, because the operator action they call '
          'for is opposite — a refusal means fix the condition and try again, '
          'an unknown means go and look at the machine before touching '
          'anything');
  expect(lost.runtimeType, isNot(refused.runtimeType),
      reason: 'the two outcomes arrived as the same type, so no caller can '
          'tell them apart no matter how carefully it switches');
}

/// Exactly one upstream attempt per `cmd`, on every outcome.
///
/// The property RESEARCH Risk 6 exists for, and the one this whole observable
/// was added to make testable. A well-meaning retry wrapper — the kind every
/// HTTP client ships with switched on — is invisible from the API surface:
/// same call, same result type, a few hundred milliseconds later. On a plant
/// it is a second actuation of machinery an operator commanded once.
///
/// Both outcomes are asserted, because the unknown path is where a retry
/// actually gets written: nobody adds a retry to a call that succeeded.
///
/// [upstreamWriteAttempts] overrides where the count is read from, for an
/// implementation that keeps it somewhere other than its own harness.
Future<void> checkExactlyOneUpstreamAttemptPerCmd(
  StateManApi api, {
  int Function(StateManApi api, String cmd)? upstreamWriteAttempts,
}) async {
  final plant = writeHarnessOf(api);
  final attemptsFor = upstreamWriteAttempts ?? _attemptsFromHarness;
  plant.setValue(_setpointKey, 1200);

  final applied = await _outcomeOf(
      api.write(_setpointKey, 1450), 'an ordinary write resolving');
  expect(attemptsFor(api, applied.cmd), 1,
      reason: 'one operator action cost '
          '${attemptsFor(api, applied.cmd)} upstream write attempts; a re-send '
          'is an operator decision, never a machine\'s, and a duplicated write '
          'is a duplicated actuation of the plant');

  plant.failNextWrite(const WriteReason('plc_timeout'), unknown: true);
  final lost = await _outcomeOf(api.write(_setpointKey, 1460),
      'a write of unknown outcome resolving');
  expect(attemptsFor(api, lost.cmd), 1,
      reason: 'a write whose outcome nobody knows was attempted '
          '${attemptsFor(api, lost.cmd)} times; unknown is not proof that '
          'nothing happened, so retrying it is precisely the case where a '
          'helpful retry wrapper actuates the machine a second time');
}

/// Every write mints its own id, and the result carries it back.
///
/// Two operator actions that collide on one id merge into a single entry in
/// the gateway's dedup log, and one of the two silently reports the other's
/// outcome (`ulid.dart:10-14`). The id must also come back on the result, or
/// there is nothing to reconcile against after a reconnect.
Future<void> checkEachWriteMintsADistinctCmd(StateManApi api) async {
  final plant = writeHarnessOf(api);
  plant.setValue(_setpointKey, 1200);

  final before = plant.mintedCmds.length;
  final first =
      await _outcomeOf(api.write(_setpointKey, 1450), 'the first write '
          'resolving');
  final second =
      await _outcomeOf(api.write(_setpointKey, 1460), 'the second write '
          'resolving');

  expect(first.cmd, isNot(second.cmd),
      reason: 'two operator actions carried the same id "${first.cmd}"; they '
          'merge into one entry in the dedup log and one of the two reports '
          'the other\'s outcome');
  expect(first.cmd, matches(_ulid),
      reason: '"${first.cmd}" is not the 26-character Crockford base32 id the '
          'write path is reconciled by');
  expect(second.cmd, matches(_ulid),
      reason: '"${second.cmd}" is not the 26-character Crockford base32 id the '
          'write path is reconciled by');
  expect(plant.mintedCmds.skip(before), containsAllInOrder([first.cmd, second.cmd]),
      reason: 'the ids the results came back with are not the ids this source '
          'minted, in the order it minted them; the result is then carrying an '
          'id that identifies some other action');
}

/// While a write is in flight the value itself says so.
///
/// CONTEXT D-04: the pending badge is a property of the value the widget is
/// already watching ([Quality.goodWritePending]), not a handle object the call
/// site has to hold and keep in sync. The window matters — over a slow link it
/// is the only thing telling an operator that their press was registered, and
/// without it they press again.
///
/// The value must keep its last *confirmed* reading through the window. A
/// source that optimistically shows the typed value has told the operator the
/// write landed before anything upstream agreed.
///
/// [stallWrites] overrides how the in-flight window is held open.
Future<void> checkWritePendingIsVisibleWhileInFlight(
  StateManApi api, {
  void Function(StateManApi api)? stallWrites,
}) async {
  final plant = writeHarnessOf(api);
  final stall = stallWrites ?? (a) => writeHarnessOf(a).stallWrites();

  plant.setValue(_setpointKey, 1200);
  final node = api.listen(_setpointKey);
  final seen = observe(node);

  stall(api);
  final pending = api.write(_setpointKey, 1450);
  await within(seen.next, 'the value reporting that a write is in flight');

  expect(node.value.quality, Quality.goodWritePending,
      reason: 'a write is in flight and the value reads as '
          '${node.value.quality.code}; over a slow link the pending badge is '
          'the only thing telling an operator their press was registered, and '
          'an operator who sees nothing presses again');
  expect(node.value.asInt, 1200,
      reason: 'the value showed the number that was typed while the write was '
          'still in flight; that is a confirmation nothing upstream has given, '
          'and the readback is the only confirmation there is');

  plant.releaseWrites();
  final result = await _outcomeOf(pending, 'the released write resolving');

  expect(result, isA<WriteApplied>(),
      reason: 'the stalled write was released as applied and came back as '
          '${result.runtimeType}');
  expect(node.value.quality, Quality.good,
      reason: 'the write completed and the value still reads as '
          '${node.value.quality.code}; a pending badge that never clears is a '
          'permanent amber box the operator learns to ignore');
}

/// A write to a read-only key is rejected, not thrown.
///
/// Read-only devices are real: `M2400DeviceClientAdapter.write` throws
/// `UnsupportedError` today (`state_man.dart:929-931`), which is exactly what
/// the pipe must not do — the throw travels up through whatever generic
/// error handling the page has and arrives as "something went wrong", when the
/// truthful answer, "this device does not take writes", is a sentence the
/// operator can act on and a page editor can prevent.
///
/// When the caller of [runWriteContract] names a [readOnlyKey], it is a key
/// that implementation genuinely refuses; the harness lever is applied to it
/// anyway, and is a no-op for a key already refused.
Future<void> checkReadOnlyKeyIsRejectedNotThrown(
  StateManApi api, {
  String? readOnlyKey,
}) async {
  final plant = writeHarnessOf(api);
  final key = readOnlyKey ?? _sensorKey;
  plant.setReadOnly(key, true);
  plant.setValue(key, 4);

  final result = await _outcomeOf(api.write(key, 9),
      'a write to a read-only key resolving rather than throwing');

  expect(result, isA<WriteRejected>(),
      reason: 'writing a key the device does not permit came back as '
          '${result.runtimeType}; an UnsupportedError here reaches the page as '
          '"something went wrong", where "this device does not take writes" is '
          'the sentence that stops the operator trying again');
  expect((result as WriteRejected).reason.kind, isNotEmpty,
      reason: 'a read-only refusal arrived with no reason kind, so nothing '
          'downstream can distinguish it from an interlock and offer the right '
          'next step');
}

/// A poison value cannot detonate the frame it travels in.
///
/// Dart's `jsonEncode` throws on NaN and ±Infinity rather than emitting null
/// the way JavaScript does (`sanitize.dart:1-9`). A single non-finite value on
/// the write path therefore does not fail one write — it fails the frame, and
/// the frame is shared with every other client on the pipe. The value must be
/// sanitized to null and marked [Quality.badNonFinite], which renders as a
/// fault, rather than allowed anywhere near an encoder.
Future<void> checkNonFiniteWriteIsSanitizedNotThrown(StateManApi api) async {
  final plant = writeHarnessOf(api);
  plant.setValue(_setpointKey, 1200);
  plant.setValue(_otherKey, 3);

  final result = await _outcomeOf(api.write(_setpointKey, double.infinity),
      'a write of a non-finite value resolving rather than throwing on encode');

  expect(result, isA<WriteApplied>(),
      reason: 'a sanitized write came back as ${result.runtimeType}; the '
          'poison is defused at the boundary, so what reaches the device is an '
          'ordinary write of a null');
  expect((result as WriteApplied).readback, isNull,
      reason: 'the readback of a non-finite write must be null: JSON cannot '
          'carry ±Infinity at all, and a readback that still holds one is a '
          'value that will throw on the next encode instead of this one');

  final cached = api.read(_setpointKey);
  expect(cached?.quality, Quality.badNonFinite,
      reason: 'the key reads as ${cached?.quality.code} after a non-finite '
          'write; the operator must see a fault, not a blank box that looks '
          'like an unbound tag');
  expect(cached?.value, isNull,
      reason: 'a non-finite value survived into the store, where the next '
          'encode of any frame carrying it throws for every client on the '
          'pipe');

  // The barrier: the poison failed its own write, not the source.
  final after = await _outcomeOf(api.write(_otherKey, 5),
      'an ordinary write to another key after the poison one');
  expect(after, isA<WriteApplied>(),
      reason: 'a non-finite write to one key left the source unable to write '
          'another; one open-circuit 4-20 mA input would take the whole write '
          'path down');
}

/// The store shows what the device holds, not what was typed.
///
/// A PLC clamping a setpoint to its configured maximum is ordinary, and it is
/// the case that separates a source which reads back from one which merely
/// remembers. If the mimic shows 5000 while the machine runs at 1500, the
/// operator has been told the plant is doing something it is not — and has been
/// told it *by the confirmation*, which is the one message they had no reason
/// to doubt.
Future<void> checkStoredValueIsTheReadbackNotTheTypedValue(
    StateManApi api) async {
  final plant = writeHarnessOf(api);
  plant.setValue(_setpointKey, 1200);
  plant.clampNextWrite(1500);

  final result = await _outcomeOf(api.write(_setpointKey, 5000),
      'a write the device clamped resolving');

  expect(result, isA<WriteApplied>(),
      reason: 'a clamped write is still an applied one and came back as '
          '${result.runtimeType}');
  expect((result as WriteApplied).readback, 1500,
      reason: 'the operator typed 5000, the device holds 1500, and the result '
          'carried ${result.readback}');
  expect(api.read(_setpointKey)?.asInt, 1500,
      reason: 'the cache holds ${api.read(_setpointKey)?.asInt} where the '
          'device holds 1500; the mimic would show a setpoint the plant is not '
          'running at, and show it as confirmed');
  expect(api.listen(_setpointKey).value.asInt, 1500,
      reason: 'listen() and the device disagree about the setpoint — the '
          'widget bound to this key draws the number nobody upstream agreed '
          'to');
}

/// The case names, declared once so [runWriteContract] can override a case by
/// name without the string appearing twice.
const _appliedCase =
    'an applied write carries the device readback, never the value typed';
const _rejectedCase =
    'a rejected write carries a greppable reason and completes normally';
const _linkLostCase =
    'a write in flight when the link drops is unknown, never a failure';
const _distinctCase =
    'unknown and rejected stay distinguishable through the public API';
const _attemptCase =
    'exactly one upstream attempt per cmd — nothing re-sends an operator write';
const _cmdCase = 'every write mints its own 26-character cmd';
const _pendingCase = 'a write in flight is visible as pending on the value';
const _readOnlyCase = 'a write to a read-only key is rejected, not thrown';
const _nonFiniteCase = 'a non-finite write is sanitized, not detonated';
const _readbackCase = 'the store shows the readback, not the value that was typed';

/// Every write property, keyed by the sentence it asserts.
///
/// The key is the test name, so a failure in CI reads as the promise that was
/// broken rather than as a function identifier. Exported for the sabotage
/// suite and for the `runStateManContract` umbrella.
const writeChecks = <String, Check<StateManApi>>{
  _appliedCase: checkAppliedCarriesReadback,
  _rejectedCase: checkRejectedCarriesReasonAndDoesNotThrow,
  _linkLostCase: checkLostLinkYieldsUnknownNeverFailure,
  _distinctCase: checkUnknownIsDistinctFromRejected,
  _attemptCase: checkExactlyOneUpstreamAttemptPerCmd,
  _cmdCase: checkEachWriteMintsADistinctCmd,
  _pendingCase: checkWritePendingIsVisibleWhileInFlight,
  _readOnlyCase: checkReadOnlyKeyIsRejectedNotThrown,
  _nonFiniteCase: checkNonFiniteWriteIsSanitizedNotThrown,
  _readbackCase: checkStoredValueIsTheReadbackNotTheTypedValue,
};

/// Registers the write contract against implementations from [make].
///
/// Two capability flags, following the `http_client_conformance_tests`
/// precedent (RESEARCH Q4): one suite has to judge implementations that differ
/// in what they can do, and the alternative — a second suite, or a check that
/// quietly passes when it cannot run — is how a capability becomes untested
/// everywhere. [supportsWrites] `false` skips the whole group with a reason on
/// the record; [readOnlyKey] `null` skips the read-only case alone, because an
/// implementation with nothing read-only about it has no way to satisfy it
/// honestly.
///
/// The three hook parameters exist for an implementation whose harness cannot
/// answer for itself — a remote source whose upstream attempt count lives on
/// the server and arrives over a side channel, or one whose link is cut by
/// something other than [StateManHarness.disconnectUpstream]. Left null, each
/// case reads its lever off [StateManWriteHarness], which is what every
/// in-memory implementation and every sabotage variant does.
///
/// One fresh instance per case, disposed by `addTearDown`: the attempt counter
/// and the minted-id list are only meaningful when nothing from a previous
/// case has touched them.
void runWriteContract(
  StateManApi Function() make, {
  bool supportsWrites = true,
  String? readOnlyKey,
  int Function(StateManApi api, String cmd)? upstreamWriteAttempts,
  void Function(StateManApi api)? stallWrites,
  void Function(StateManApi api)? dropLinkWithWritesInFlight,
}) {
  final cases = <String, Check<StateManApi>>{
    ...writeChecks,
    if (upstreamWriteAttempts != null)
      _attemptCase: (api) => checkExactlyOneUpstreamAttemptPerCmd(api,
          upstreamWriteAttempts: upstreamWriteAttempts),
    if (stallWrites != null)
      _pendingCase: (api) =>
          checkWritePendingIsVisibleWhileInFlight(api, stallWrites: stallWrites),
    if (dropLinkWithWritesInFlight != null)
      _linkLostCase: (api) => checkLostLinkYieldsUnknownNeverFailure(api,
          dropLinkWithWritesInFlight: dropLinkWithWritesInFlight),
    if (readOnlyKey != null)
      _readOnlyCase: (api) =>
          checkReadOnlyKeyIsRejectedNotThrown(api, readOnlyKey: readOnlyKey),
  };
  // Nothing read-only to write to: the case cannot be satisfied honestly, so
  // it is removed rather than passed vacuously.
  if (readOnlyKey == null) cases.remove(_readOnlyCase);

  group('write', () {
    cases.forEach((property, check) {
      test(property, () async {
        final api = make();
        addTearDown(api.dispose);
        await check(api);
      });
    });
  },
      skip: supportsWrites
          ? null
          : 'this implementation declares no write support; the write '
              'contract is skipped rather than passed, so the capability is '
              'visible in the run report instead of absent from it');
}
