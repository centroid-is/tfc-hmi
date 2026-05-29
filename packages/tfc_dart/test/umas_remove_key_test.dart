/// Phase 7 Plan 02 (v1.1.x): TDD coverage for the new
/// `ModbusDeviceClientAdapter.removeUmasKey(String key)` API and the
/// subject-lifecycle contract on remove (D-08).
///
/// Pins the contract enumerated in 07-02-PLAN.md `must_haves.truths`:
///   * removeUmasKey('foo') drops 'foo' from `_umasKeysByGroup`
///     (whichever group held it) and nulls `_umasTableBuiltFor`.
///   * The cached BehaviorSubject is closed BEFORE the map entry is
///     removed (D-08) so subscribers see `onDone` exactly once.
///   * After removeUmasKey, a future `subscribe('foo')` allocates a
///     FRESH BehaviorSubject via `_umasSubjectFor` (SPEC symbol/cache
///     invalidation contract — TD-021 seed path re-runs on the next
///     subscribe).
///   * Unknown-key `removeUmasKey` is a silent no-op (D-05 idempotency).
///   * `removeUmasKey` → `addUmasKey` round-trip restores the key.
///   * After `removeUmasKey` + `debugPumpPollTick`, the injected fake
///     UmasClient records NO further read attempt for the removed key
///     (SPEC Acceptance #4).
///
/// Run: `cd packages/tfc_dart && dart test test/umas_remove_key_test.dart`
@TestOn('vm')
library;

import 'dart:async';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/modbus_device_client.dart';
import 'package:tfc_dart/core/state_man.dart'
    show ConnectionStatus, ModbusPollGroupConfig;
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

/// Wrapper subclass that reports a fixed `connected` status without
/// opening a real socket. `_pollUmasGroup`'s first guard checks
/// `wrapper.connectionStatus`; bypassing it lets Test 7 exercise the
/// fallback-poll path against an injected fake UmasClient. Mirrors the
/// Plan 01 fixture in `umas_add_key_test.dart`.
class _ConnectedWrapper extends ModbusClientWrapper {
  _ConnectedWrapper()
      : super('mock', 0, 1,
            clientFactory: (h, p, u) => ModbusClientTcp(h,
                serverPort: p,
                unitId: u,
                connectionMode: ModbusConnectionMode.doNotConnect));

  @override
  ConnectionStatus get connectionStatus => ConnectionStatus.connected;
}

/// Recording fake — overrides every UmasClient method the adapter
/// touches on a poll-tick and appends a description to [calls].
/// Throws a recoverable [UmasException] from `readVariableByName` so
/// the adapter's `_pollUmasGroup` catches it (per the existing fallback
/// `catch (e)` at modbus_device_client.dart) instead of crashing the
/// test. Mirrors the Plan 01 `_RecordingUmasClient` shape so Plan 02's
/// new Test 7 can reuse the same recorder pattern.
class _RecordingUmasClient extends UmasClient {
  _RecordingUmasClient()
      : super(
            sendFn: (_) async => ModbusResponseCode.requestSucceed) {
    // Skip the readPlcStatus prime in `readUmasVariable` (the adapter
    // short-circuits when blockCrcs != null) so the recorded call
    // lands on `readVariableByName` directly.
    debugSetBlockCrcs(const <int>[0xDEADBEEF]);
    debugSetProjectCrc(0xCAFEBABE);
    debugSetSessionState(UmasSessionState.paired);
  }

  final List<String> calls = <String>[];

  @override
  Future<TypedVariableValue> readVariableByName(String path) async {
    calls.add('readVariableByName:$path');
    throw UmasException(
        errorCode: 0,
        message: 'recorded by _RecordingUmasClient (no real PLC)');
  }

  @override
  Future<List<int>> monitorRegister(
      List<(UmasVariable, UmasDataTypeRef)> refs) async {
    for (final r in refs) {
      calls.add('monitorRegister:${r.$1.name}');
    }
    return List<int>.generate(refs.length, (i) => i);
  }

  @override
  Future<List<TypedVariableValue>> monitorReadAll() async {
    calls.add('monitorReadAll');
    return <TypedVariableValue>[];
  }

  @override
  Future<void> monitorReset() async {
    calls.add('monitorReset');
  }
}

void main() {
  group(
      'ModbusDeviceClientAdapter — removeUmasKey (Phase 7 Req #3 + Acceptance #4)',
      () {
    ModbusDeviceClientAdapter buildAdapter({
      Map<String, String?> names = const {},
      Map<String, String> groupByKey = const {},
      List<ModbusPollGroupConfig> pollGroups = const [],
      bool umasEnabled = true,
      ModbusClientWrapper? wrapper,
    }) {
      final w = wrapper ??
          ModbusClientWrapper('127.0.0.1', 0, 1,
              clientFactory: (h, p, u) =>
                  ModbusClientTcp(h, serverPort: p, unitId: u));
      return ModbusDeviceClientAdapter(
        w,
        specs: const {},
        variableNames: names,
        umasEnabled: umasEnabled,
        umasPollGroupByKey: groupByKey,
        pollGroups: pollGroups,
        serverAlias: 'plc1',
      );
    }

    test("removeUmasKey drops the key from _umasKeysByGroup", () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'precondition: constructor must seed "foo" in default');

        adapter.removeUmasKey('foo');

        final defaultKeys =
            adapter.debugUmasKeysByGroup['default'] ?? const <String>[];
        expect(defaultKeys, isNot(contains('foo')),
            reason: 'removeUmasKey must drop "foo" from _umasKeysByGroup '
                '(whichever group held it)');
      } finally {
        adapter.dispose();
      }
    });

    test('removeUmasKey nulls _umasTableBuiltFor to trigger rebuild', () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        adapter.removeUmasKey('foo');

        expect(adapter.debugUmasTableBuiltFor, isNull,
            reason: 'removeUmasKey must dirty the table so the next '
                '_pollUmasGroup tick rebuilds without "foo"');
      } finally {
        adapter.dispose();
      }
    });

    test('removeUmasKey closes the BehaviorSubject so subscribers see onDone',
        () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        var done = false;
        final stream = adapter.subscribe('foo');
        final sub = stream.listen((_) {}, onDone: () => done = true);
        // Let microtasks settle so the BehaviorSubject is fully wired
        // and the eager-read fire-and-forget has had its chance to run.
        await Future<void>.delayed(Duration.zero);

        adapter.removeUmasKey('foo');
        await Future<void>.delayed(Duration.zero);

        expect(done, isTrue,
            reason: 'removeUmasKey must close the cached BehaviorSubject '
                'BEFORE removing the map entry (D-08) so any active '
                'subscriber sees onDone exactly once');
        await sub.cancel();
      } finally {
        adapter.dispose();
      }
    });

    test("After removeUmasKey, subscribe('foo') gets a fresh BehaviorSubject",
        () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        final subject1 = adapter.subscribe('foo');
        // Let the eager-read settle so subject1 is fully alive.
        await Future<void>.delayed(Duration.zero);

        adapter.removeUmasKey('foo');
        await Future<void>.delayed(Duration.zero);

        final subject2 = adapter.subscribe('foo');

        expect(identical(subject1, subject2), isFalse,
            reason: 'subscribe after removeUmasKey must allocate a fresh '
                'BehaviorSubject via _umasSubjectFor (SPEC symbol/cache '
                'invalidation contract — TD-021 seed path re-runs)');

        // Stronger pin: subject2 must NOT immediately fire onDone — it
        // is a fresh open subject, not the closed remnant of subject1.
        var subject2Done = false;
        final sub2 =
            subject2.listen((_) {}, onDone: () => subject2Done = true);
        await Future<void>.delayed(Duration.zero);
        expect(subject2Done, isFalse,
            reason: 'a fresh subject for re-subscribe must be open, not the '
                'closed remnant of the pre-remove subject');
        await sub2.cancel();
      } finally {
        adapter.dispose();
      }
    });

    test('removeUmasKey on an unknown key is a silent no-op', () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'precondition: "foo" registered via constructor');
        final builtBefore = adapter.debugUmasTableBuiltFor;

        adapter.removeUmasKey('does-not-exist');

        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'removeUmasKey on an unknown key must NOT mutate any '
                'group list (D-05 silent no-op — matches Set.remove)');
        expect(adapter.debugUmasTableBuiltFor, equals(builtBefore),
            reason: 'removeUmasKey on an unknown key must NOT dirty '
                '_umasTableBuiltFor (D-05 — no log, no state change)');
      } finally {
        adapter.dispose();
      }
    });

    test('removeUmasKey followed by addUmasKey re-registers the key',
        () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'precondition: constructor must seed "foo" in default');

        adapter.removeUmasKey('foo');
        expect(
            adapter.debugUmasKeysByGroup['default'] ?? const <String>[],
            isNot(contains('foo')),
            reason: 'sanity: removeUmasKey must drop "foo"');

        adapter.addUmasKey('foo');

        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'addUmasKey after removeUmasKey must restore "foo" to '
                'the default group — pins Plan 01 + Plan 02 interaction '
                '(elevator-was-stuck-then-toggled-then-moves workflow)');
      } finally {
        adapter.dispose();
      }
    });

    test(
        'addUmasKey + tick records read; removeUmasKey + next tick records '
        'NO read for the removed key (SPEC Acceptance #4)', () async {
      final wrapper = _ConnectedWrapper();
      final adapter = buildAdapter(
        names: {'foo': 'A.b'},
        wrapper: wrapper,
      );
      final fake = _RecordingUmasClient();
      try {
        adapter.debugSetUmasClient(fake);
        // Start from a clean poll set so the assertion is unambiguous.
        adapter.unsubscribeUmas('foo');
        adapter.addUmasKey('foo');

        await adapter.debugPumpPollTick('default');

        final mentionsFooOrPathPostAdd = fake.calls.any(
          (c) => c.contains('foo') || c.contains('A.b'),
        );
        expect(mentionsFooOrPathPostAdd, isTrue,
            reason: 'after addUmasKey + tick, a read attempt for "foo" '
                'should have been recorded (got ${fake.calls})');

        // Capture the delta marker so the next assertion is scoped to
        // calls recorded after removeUmasKey, not the whole history.
        final callsAtMark = fake.calls.length;

        adapter.removeUmasKey('foo');
        await adapter.debugPumpPollTick('default');

        final newCalls = fake.calls.sublist(callsAtMark);
        final mentionsFooOrPathPostRemove = newCalls.any(
          (c) => c.contains('foo') || c.contains('A.b'),
        );
        expect(mentionsFooOrPathPostRemove, isFalse,
            reason: 'after removeUmasKey + tick, no further read attempts '
                'for "foo" should be recorded — SPEC Acceptance #4 '
                '(new calls since remove = $newCalls)');
      } finally {
        adapter.dispose();
      }
    });
  });
}
