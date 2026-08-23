/// Regression guard for the UMAS MonitorPlc demux ordering invariant.
///
/// `_demuxUmasReadAll` maps `monitorReadAll()` results onto `_umasKeyOrder`
/// BY POSITION, so two independently-maintained orderings have to stay in
/// lockstep: the PLC's MonitorPlc registration, and the adapter's local key
/// list. If a key is spliced out of one but not the other, every key after it
/// silently reads its neighbour's tag — the same shape as a ragged-batch
/// column shuffle, but on the operator's screen.
///
/// `unsubscribeUmas` removes from `_umasKeyOrder` immediately and only marks
/// the PLC-side table dirty, which reads like exactly that hazard (and its
/// own comment claims "the order list is unchanged", which is false). It is
/// nevertheless SAFE: `_pollUmasGroup` re-checks the dirty flag on every
/// tick, so the tick after a removal rebuilds and re-registers rather than
/// reading, and no shifted response is ever demuxed. This test pins that.
///
/// The trigger it exercises is the live key-mapping edit path:
/// StateMan.updateKeyMappings -> updateVariableNames -> unsubscribeUmas.
///
/// Note: before the `_umasClientFor` line in `debugSetUmasClient`, an
/// injected client could never get past the early return in
/// `_buildUmasTableAndStartTimers`, so this whole path — MonitorPlc
/// registration and demux, the primary data path on M580 — had no test
/// coverage at all.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/modbus_device_client.dart';
import 'package:tfc_dart/core/state_man.dart'
    show ConnectionStatus, ModbusPollGroupConfig;
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

class _ConnectedWrapper extends ModbusClientWrapper {
  _ConnectedWrapper()
      : super('mock', 0, 1,
            clientFactory: (h, p, u) => ModbusClientTcp(h,
                serverPort: p,
                unitId: u,
                connectionMode: ModbusConnectionMode.doNotConnect));

  /// A stable non-null socket identity. The adapter keys its MonitorPlc
  /// table off this object, so it has to exist for the table to be built.
  final ModbusClientTcp _tcp = ModbusClientTcp('mock',
      serverPort: 0, unitId: 1, connectionMode: ModbusConnectionMode.doNotConnect);

  @override
  ModbusClientTcp? get client => _tcp;

  @override
  ConnectionStatus get connectionStatus => ConnectionStatus.connected;
}

TypedVariableValue _val(int v) => TypedVariableValue(
    value: v, typeName: 'INT', rawBytes: Uint8List.fromList([v, 0]));

/// A PLC that keeps answering for the variable set it was told to register,
/// in registration order, regardless of what the adapter later decided
/// locally — which is exactly what a real PLC does until it is re-registered.
class _StickyPlc extends UmasClient {
  _StickyPlc()
      : super(sendFn: (_) async => ModbusResponseCode.requestSucceed) {
    debugSetBlockCrcs(const <int>[0xDEADBEEF]);
    debugSetProjectCrc(0xCAFEBABE);
    debugSetSessionState(UmasSessionState.paired);
  }

  /// Variables the PLC currently holds registered, in order.
  final List<String> registered = <String>[];

  /// Value the PLC reports for each variable name.
  final Map<String, int> values = <String, int>{};

  @override
  Future<PlcStatusResult> readPlcStatus() async => PlcStatusResult(
        statusByte: 1,
        numberOfBlocks: 1,
        blockCrcs: const [0xDEADBEEF],
        additionalData: Uint8List(0),
      );

  @override
  Future<ResolvedSymbol> lookupSymbol(String path) async => ResolvedSymbol(
        path: path,
        variable: UmasVariable(
            name: path, blockNo: 1, offset: values.keys.toList().indexOf(path),
            dataTypeId: 4),
        dataType: const UmasDataTypeRef(id: 4, name: 'INT', byteSize: 2),
        readable: true,
      );

  @override
  Future<List<int>> monitorRegister(
      List<(UmasVariable, UmasDataTypeRef)> refs) async {
    registered
      ..clear()
      ..addAll(refs.map((r) => r.$1.name));
    return List<int>.generate(refs.length, (i) => i);
  }

  @override
  Future<List<TypedVariableValue>> monitorReadAll() async =>
      [for (final name in registered) _val(values[name] ?? -1)];

  @override
  Future<void> monitorReset() async {}

  @override
  Future<TypedVariableValue> readVariableByName(String path) async =>
      _val(values[path] ?? -1);
}

void main() {
  test(
      'removing one UMAS key live must not shift the remaining keys onto '
      "their neighbours' values", () async {
    final wrapper = _ConnectedWrapper();
    addTearDown(wrapper.dispose);

    // Three UMAS-by-name keys. Distinct values so a shift is unmistakable.
    final plc = _StickyPlc()
      ..values.addAll({'V_a': 10, 'V_b': 20, 'V_c': 30});

    final adapter = ModbusDeviceClientAdapter(
      wrapper,
      specs: const {},
      serverAlias: 'plc',
      umasEnabled: true,
      variableNames: const {'a': 'V_a', 'b': 'V_b', 'c': 'V_c'},
      umasPollGroupByKey: const {'a': 'g', 'b': 'g', 'c': 'g'},
      pollGroups: [ModbusPollGroupConfig(name: 'g', intervalMs: 1000)],
    );
    addTearDown(adapter.dispose);
    adapter.debugSetUmasClient(plc);

    final seen = <String, int>{};
    for (final key in ['a', 'b', 'c']) {
      final sub = adapter
          .subscribe(key)
          .listen((dv) => seen[key] = dv.asInt);
      addTearDown(sub.cancel);
    }

    // The first tick only kicks off the (unawaited) MonitorPlc table build
    // and returns; the second actually reads.
    await adapter.debugPumpPollTick('g');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await adapter.debugPumpPollTick('g');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen, {'a': 10, 'b': 20, 'c': 30},
        reason: 'sanity: each key reads its own variable');

    // The operator deletes key 'a' in the key-mapping editor. StateMan
    // applies it live via updateVariableNames -> unsubscribeUmas('a'). The
    // PLC has NOT been re-registered: it still holds V_a, V_b, V_c.
    adapter.updateVariableNames(
      const {'b': 'V_b', 'c': 'V_c'},
      umasPollGroupByKey: const {'b': 'g', 'c': 'g'},
    );
    expect(plc.registered, ['V_a', 'V_b', 'V_c'],
        reason: 'sanity: the PLC-side table is only marked dirty, not rebuilt');

    seen.clear();
    // Same two-tick dance: removal dirtied the table, so the first tick
    // rebuilds (re-registering the PLC without V_a) and skips reading.
    await adapter.debugPumpPollTick('g');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await adapter.debugPumpPollTick('g');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(plc.registered, ['V_b', 'V_c'],
        reason: 'the rebuild must re-register the PLC without the removed '
            'variable before any further read is demuxed');

    expect(seen['b'], 20,
        reason: 'Key "b" is showing V_a\'s value. _demuxUmasReadAll pairs '
            'monitorReadAll()[i] with _umasKeyOrder[i], and unsubscribeUmas '
            'spliced "a" out of the local list while the PLC still returns '
            'three values in the original order — so every key after the '
            'removed one reads its neighbour\'s tag. Silent, wrong numbers '
            'on the operator\'s screen until the next reconnect re-registers '
            'the table. Saw: $seen');
    expect(seen['c'], 30,
        reason: 'Key "c" must still read V_c, not V_b. Saw: \$seen');
  });
}
