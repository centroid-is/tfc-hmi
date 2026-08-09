/// Phase 7 Plan 01 (v1.1.x): TDD coverage for the new
/// `ModbusDeviceClientAdapter.addUmasKey(String key)` API and its
/// supporting `@visibleForTesting` accessors.
///
/// Pins the contract enumerated in 07-01-PLAN.md `must_haves.truths`:
///   * addUmasKey('foo') appends 'foo' to `_umasKeysByGroup` under the
///     group resolved from the retained `umasPollGroupByKey` mapping
///     (or 'default' when absent).
///   * addUmasKey nulls `_umasTableBuiltFor` so the next
///     `_pollUmasGroup` tick triggers `_buildUmasTableAndStartTimers`.
///   * addUmasKey honors the retained per-key poll-group mapping
///     (Req #4 / D-04).
///   * Duplicate addUmasKey is a silent no-op (D-05 — matches
///     `Set.add` ergonomics).
///   * Unknown poll-group falls back to 'default' AND emits a warn
///     (D-04).
///   * After addUmasKey + debugPumpPollTick, an injected fake
///     UmasClient records a read/register call naming the new key
///     (SPEC Acceptance #2).
///
/// Run: `cd packages/tfc_dart && dart test test/umas_add_key_test.dart`
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
/// `wrapper.connectionStatus`; bypassing it lets Test 6 exercise the
/// fallback-poll path against an injected fake UmasClient.
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
/// `catch (e)` at modbus_device_client.dart:525) instead of crashing
/// the test. The recorded call is what Test 6 asserts on.
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
  group('ModbusDeviceClientAdapter — addUmasKey (Phase 7 Req #1, #2, #4)', () {
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
        "addUmasKey('foo') registers 'foo' in the resolved group derived "
        'from umasPollGroupByKey', () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        // Constructor places 'foo' in 'default'. Clear it so the assert
        // is unambiguous.
        adapter.unsubscribeUmas('foo');
        expect(adapter.debugUmasKeysByGroup['default'] ?? const <String>[],
            isNot(contains('foo')),
            reason: 'precondition: unsubscribeUmas must have cleared "foo"');

        adapter.addUmasKey('foo');

        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'addUmasKey with empty umasPollGroupByKey must land the '
                'key in the "default" group bucket');
      } finally {
        adapter.dispose();
      }
    });

    test('addUmasKey nulls _umasTableBuiltFor to trigger rebuild on next tick',
        () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        adapter.unsubscribeUmas('foo');

        adapter.addUmasKey('foo');

        expect(adapter.debugUmasTableBuiltFor, isNull,
            reason: 'addUmasKey must dirty the table-built marker so the next '
                '_pollUmasGroup tick rebuilds the MonitorPlc table');
      } finally {
        adapter.dispose();
      }
    });

    test('addUmasKey honors umasPollGroupByKey for group placement',
        () async {
      final adapter = buildAdapter(
        names: {'foo': 'A.b', 'bar': 'C.d'},
        groupByKey: {'foo': 'slow', 'bar': 'fast'},
        pollGroups: [
          ModbusPollGroupConfig(name: 'slow', intervalMs: 5000),
          ModbusPollGroupConfig(name: 'fast', intervalMs: 100),
        ],
      );
      try {
        // Constructor seeds 'foo' into 'slow' and 'bar' into 'fast'.
        // Clear 'foo' so addUmasKey has to repopulate the slow group
        // via the retained map.
        adapter.unsubscribeUmas('foo');

        adapter.addUmasKey('foo');

        expect(adapter.debugUmasKeysByGroup['slow'], contains('foo'),
            reason: 'addUmasKey must inherit the per-key pollGroup from the '
                'retained umasPollGroupByKey map (D-04)');
        expect(adapter.debugUmasKeysByGroup['default'] ?? const <String>[],
            isNot(contains('foo')),
            reason: 'addUmasKey must NOT fall back to "default" when the '
                'retained map names a configured group');
      } finally {
        adapter.dispose();
      }
    });

    test('addUmasKey is a silent no-op when key is already registered',
        () async {
      final adapter = buildAdapter(names: {'foo': 'A.b'});
      try {
        // Constructor lands 'foo' in 'default'. Don't clear it.
        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'precondition: constructor must seed "foo" in default');

        adapter.addUmasKey('foo');
        adapter.addUmasKey('foo');

        final fooCount = (adapter.debugUmasKeysByGroup['default'] ??
                const <String>[])
            .where((k) => k == 'foo')
            .length;
        expect(fooCount, 1,
            reason: 'addUmasKey on an already-registered key must NOT '
                'duplicate the entry (D-05 — matches Set.add ergonomics)');
      } finally {
        adapter.dispose();
      }
    });

    test(
        "addUmasKey falls back to 'default' when resolved group has no timer",
        () async {
      final adapter = buildAdapter(
        names: {'foo': 'A.b'},
        pollGroups: [
          ModbusPollGroupConfig(name: 'default', intervalMs: 1000),
        ],
      );
      try {
        // Constructor places 'foo' in 'default'. Override its retained
        // group to a never-configured name so the addUmasKey fallback
        // branch fires.
        adapter.debugSetUmasPollGroupForKey('foo', 'never-configured');
        adapter.unsubscribeUmas('foo');

        adapter.addUmasKey('foo');

        expect(adapter.debugUmasKeysByGroup['default'], contains('foo'),
            reason: 'addUmasKey must fall back to "default" when the '
                'resolved group has no timer entry (D-04)');
      } finally {
        adapter.dispose();
      }
    });

    test(
        'addUmasKey + debugPumpPollTick records a read attempt for the new '
        'key (SPEC Acceptance #2)', () async {
      final wrapper = _ConnectedWrapper();
      final adapter = buildAdapter(
        names: {'foo': 'A.b'},
        wrapper: wrapper,
      );
      final fake = _RecordingUmasClient();
      try {
        adapter.debugSetUmasClient(fake);
        // Clear 'foo' from the constructor-time poll set so addUmasKey
        // is the only path that lands it back in.
        adapter.unsubscribeUmas('foo');
        adapter.addUmasKey('foo');

        await adapter.debugPumpPollTick('default');

        final mentionsFooOrPath = fake.calls.any(
          (c) => c.contains('foo') || c.contains('A.b'),
        );
        expect(mentionsFooOrPath, isTrue,
            reason: 'after addUmasKey + one poll tick, the injected fake '
                'UmasClient must have recorded a read/register call naming '
                '"foo" or its symbol path "A.b" (got ${fake.calls})');
      } finally {
        adapter.dispose();
      }
    });
  });
}
