/// Phase 7 Plan 03 (v1.1.x): TDD coverage for the
/// `ModbusDeviceClientAdapter.subscribe(key)` auto-register contract.
///
/// Pins the contract enumerated in 07-03-PLAN.md `must_haves.truths`:
///   * subscribe('foo') on a UMAS-by-name key NOT in any
///     `_umasKeysByGroup[*]` list auto-registers via the addUmasKey
///     path BEFORE returning the subject stream.
///   * Auto-register honors the retained `umasPollGroupByKey` mapping
///     (Plan 01's lookup is reused — group inheritance, not always
///     'default').
///   * subscribe('foo') on a UMAS-by-name key ALREADY in
///     `_umasKeysByGroup` is unchanged (no double-register).
///   * TD-021 eager-read at modbus_device_client.dart still fires on
///     first subscribe — auto-register runs IN ADDITION to, not
///     INSTEAD of, the eager read. Pinned via a fake UmasClient
///     injected by `debugSetUmasClient` that records every
///     `readVariableByName` call.
///
/// Run: `cd packages/tfc_dart && dart test test/umas_subscribe_auto_register_test.dart`
@TestOn('vm')
library;

import 'dart:async';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/modbus_device_client.dart';
import 'package:tfc_dart/core/state_man.dart' show ModbusPollGroupConfig;
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

/// Recording fake — overrides `readVariableByName` and appends the
/// requested symbol path to [calls]. Throws a recoverable [UmasException]
/// so the adapter's TD-021 eager-read `catchError` handler logs + moves
/// on instead of crashing the test. The recorded call is what Test 3
/// asserts on.
///
/// Mirrors the `_RecordingUmasClient` shape established by Plan 01
/// Test 6 and Plan 02 Test 7 — the `debugSetBlockCrcs` /
/// `debugSetProjectCrc` / `debugSetSessionState` primes short-circuit
/// `readUmasVariable`'s readPlcStatus prefix so the recorded call lands
/// on `readVariableByName` directly.
class _RecordingUmasClient extends UmasClient {
  _RecordingUmasClient()
      : super(sendFn: (_) async => ModbusResponseCode.requestSucceed) {
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
}

void main() {
  group('ModbusDeviceClientAdapter — subscribe auto-register (Phase 7 Req #2)',
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

    test(
        "subscribe('foo') auto-registers 'foo' into _umasKeysByGroup when "
        'not already present', () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        // Constructor lands 'foo' in 'default'. Plan 02's removeUmasKey
        // clears the construction-time registration so the auto-register
        // path is the only thing that can put 'foo' back.
        adapter.removeUmasKey('foo');
        expect(adapter.debugUmasKeysByGroup['default'] ?? const <String>[],
            isNot(contains('foo')),
            reason: 'precondition: removeUmasKey must have cleared "foo"');

        adapter.subscribe('foo');

        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: "subscribe('foo') must auto-register the key into the "
                "'default' poll group when it isn't already registered "
                '(Phase 7 Req #2)');
      } finally {
        adapter.dispose();
      }
    });

    test(
        "subscribe('foo') auto-register honors the retained "
        'umasPollGroupByKey mapping', () async {
      final adapter = buildAdapter(
        names: {'foo': 'A.b'},
        groupByKey: {'foo': 'slow'},
        pollGroups: [
          ModbusPollGroupConfig(name: 'slow', intervalMs: 5000),
        ],
      );
      try {
        // Constructor seeds 'foo' into 'slow'. Clear it so subscribe's
        // auto-register has to repopulate the slow group via the retained
        // map (same lookup Plan 01's addUmasKey uses).
        adapter.removeUmasKey('foo');

        adapter.subscribe('foo');

        expect(adapter.debugUmasKeysByGroup['slow'], contains('foo'),
            reason: "subscribe('foo') auto-register must inherit the "
                'per-key pollGroup from the retained umasPollGroupByKey '
                'map (D-04 / SPEC Req #4 on the subscribe path)');
        expect(adapter.debugUmasKeysByGroup['default'] ?? const <String>[],
            isNot(contains('foo')),
            reason: 'auto-register must NOT fall back to "default" when '
                'the retained map names a configured group');
      } finally {
        adapter.dispose();
      }
    });

    test(
        "subscribe('foo') still fires the TD-021 eager-read on first "
        'subscribe', () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      final fake = _RecordingUmasClient();
      try {
        adapter.debugSetUmasClient(fake);

        adapter.subscribe('foo');
        // Let the unawaited TD-021 future microtask run.
        await Future<void>.delayed(Duration.zero);

        final mentionsPath = fake.calls.any(
          (c) => c.contains('A.b'),
        );
        expect(mentionsPath, isTrue,
            reason: 'after subscribe("foo") the TD-021 eager-read must '
                'still fire and call readVariableByName("A.b") on the '
                'injected UmasClient — auto-register adds a step, it '
                'does NOT replace the eager-read (Phase 7 Req #5 / '
                'D-10 / TD-021 preservation). Got: ${fake.calls}');
      } finally {
        adapter.dispose();
      }
    });

    test(
        "subscribe('foo') is a no-op for keys already in _umasKeysByGroup",
        () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        // Constructor lands 'foo' in 'default'. Don't clear it — we want
        // the auto-register path to see the already-registered state.
        final beforeCount =
            (adapter.debugUmasKeysByGroup['default'] ?? const <String>[])
                .where((k) => k == 'foo')
                .length;
        expect(beforeCount, 1,
            reason: 'precondition: constructor must seed "foo" exactly '
                'once in default');

        adapter.subscribe('foo');

        final afterCount =
            (adapter.debugUmasKeysByGroup['default'] ?? const <String>[])
                .where((k) => k == 'foo')
                .length;
        expect(afterCount, beforeCount,
            reason: "subscribe('foo') on an already-registered key must "
                'NOT duplicate the entry (addUmasKey idempotency under '
                'the auto-register path; D-05)');
      } finally {
        adapter.dispose();
      }
    });
  });
}
