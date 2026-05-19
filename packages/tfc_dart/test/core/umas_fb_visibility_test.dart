/// FB visibility (Bug B core, Phase 2): function-block instances whose
/// data type is absent from DD03 must still expand into their member
/// tree via the plc4j-style DD02-on-typeIndex resolution path.
///
/// Live evidence (M580 at 192.168.112.159, captured in
/// /tmp/umas-string-bug-report.md):
///   - DD03 returns 7 entries (5 arrays + 1 zero-byte UDT). No FB
///     types.
///   - 23 FB instances (`M_Elevator`, `FB_Elevator_1`, `FB_B_*`, etc.)
///     reference data-type IDs that DD03 doesn't enumerate.
///   - `_expandVariable` (current behaviour) returns a no-children
///     leaf when `type == null` ⇒ all 23 FB instances appear as `(?)`.
///
/// plc4j reference (`UmasProtocolLogic.java`):
///   - `resolveCustomType(typeIndex, ref)` L1079-1097 — issues DD02 with
///     `blockNo = typeIndex` (NOT 0xFFFF) and the same wire format as
///     the existing `_readDD02Block(blockNo: typeId, isMemberLayout: true)`.
///   - `parseCustomTypeBlock` L1130-1146 — discriminates on `block[0]`:
///     classId 0x04 ⇒ UmasArrayTypeDefinition, else ⇒
///     UmasPDUReadUmasUDTDefinitionResponse (member records).
///
/// The fixture mirroring the failing M580 case lives in
/// `test/umas_stub_server.py`:
///   - `M_Elevator` (block=5, offset=0, dataTypeId=200) is in DD02 but
///     typeId 200 is NOT in `DATA_TYPES` (DD03).
///   - `FB_TYPES[200]` provides the member layout returned by
///     DD02-on-typeIndex.
///
/// Run: `cd packages/tfc_dart && dart test test/core/umas_fb_visibility_test.dart`
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

late int _stubPort;
Process? _serverProcess;

final _portPattern = RegExp(r'PORT=(\d+)');

String get _projectRoot {
  var dir = Directory.current;
  while (dir.path != dir.parent.path) {
    if (File('${dir.path}/test/umas_stub_server.py').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  return '${Directory.current.path}/../..';
}

Future<void> _startStub() async {
  final stubScript = '$_projectRoot/test/umas_stub_server.py';

  String python;
  try {
    final r = await Process.run('python3', ['--version']);
    python = r.exitCode == 0 ? 'python3' : 'python';
  } catch (_) {
    python = 'python';
  }

  _serverProcess = await Process.start(
    python,
    ['-u', stubScript, '--port', '0'],
  );

  final stderrBuf = StringBuffer();
  _serverProcess!.stderr
      .transform(const SystemEncoding().decoder)
      .listen((line) {
    stderr.write('[STUB ERR] $line');
    stderrBuf.write(line);
  });

  final completer = Completer<int>();
  _serverProcess!.stdout
      .transform(const SystemEncoding().decoder)
      .listen((line) {
    stdout.write('[STUB] $line');
    if (!completer.isCompleted) {
      final match = _portPattern.firstMatch(line);
      if (match != null) {
        completer.complete(int.parse(match.group(1)!));
      }
    }
  });

  _stubPort = await completer.future.timeout(const Duration(seconds: 5),
      onTimeout: () => throw StateError(
          'Stub server did not start (python=$python, '
          'script=$stubScript, stderr=$stderrBuf)'));
}

void _stopStub() {
  _serverProcess?.kill();
  _serverProcess = null;
}

UmasVariableTreeNode? _findByName(
    List<UmasVariableTreeNode> nodes, String name) {
  for (final n in nodes) {
    if (n.name == name) return n;
    final hit = _findByName(n.children, name);
    if (hit != null) return hit;
  }
  return null;
}

void main() {
  late ModbusClientTcp tcp;

  setUpAll(_startStub);
  tearDownAll(_stopStub);

  setUp(() {
    tcp = ModbusClientTcp(
      '127.0.0.1',
      serverPort: _stubPort,
      connectionTimeout: const Duration(seconds: 3),
    );
  });

  tearDown(() async {
    await tcp.disconnect();
  });

  test('FB instance with type missing from DD03 expands into members',
      () async {
    await tcp.connect();
    expect(tcp.isConnected, isTrue);
    final umas = UmasClient(sendFn: tcp.send);

    final tree = await umas.browse();
    // Should still parse the rest of the symbol table without throwing.
    expect(tree, isNotEmpty);

    final mElevator = _findByName(tree, 'M_Elevator');
    expect(mElevator, isNotNull,
        reason: 'M_Elevator must appear under Application.Motors');
    expect(mElevator!.children, hasLength(3),
        reason: 'FB typeId 200 is absent from DD03; plc4j-style '
            'speculative DD02-on-typeIndex (FB_TYPES[200] = 3 members) '
            'must surface speed/torque/enabled');

    final names = mElevator.children.map((c) => c.name).toList();
    expect(names, ['speed', 'torque', 'enabled']);
  });

  test('FB member offsets and types match the FB_TYPES layout', () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);

    final tree = await umas.browse();
    final mElevator = _findByName(tree, 'M_Elevator')!;
    expect(mElevator.variable, isNotNull);
    expect(mElevator.variable!.blockNo, 5);
    expect(mElevator.variable!.offset, 0);

    final speed = mElevator.children.firstWhere((c) => c.name == 'speed');
    expect(speed.variable, isNotNull);
    expect(speed.variable!.blockNo, 5,
        reason: 'inherits parent FB block_no');
    expect(speed.variable!.offset, 0,
        reason: 'member offset 0 within FB at offset 0');
    expect(speed.variable!.dataTypeId, 8, reason: 'REAL');
    expect(speed.dataType?.name, 'REAL');
    expect(speed.dataType?.byteSize, 4);

    final torque = mElevator.children.firstWhere((c) => c.name == 'torque');
    expect(torque.variable!.offset, 4,
        reason: 'member offset 4 within FB at offset 0');
    expect(torque.variable!.dataTypeId, 8); // REAL
    expect(torque.dataType?.name, 'REAL');

    final enabled = mElevator.children.firstWhere((c) => c.name == 'enabled');
    expect(enabled.variable!.offset, 8,
        reason: 'member offset 8 within FB at offset 0');
    expect(enabled.variable!.dataTypeId, 1); // BOOL
    expect(enabled.dataType?.name, 'BOOL');
  });

  test('FB members read back their seeded values via readVariables',
      () async {
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);
    // readVariables (0x22 path) needs block CRCs from readPlcStatus.
    await umas.readPlcStatus();

    final tree = await umas.browse();
    final mElevator = _findByName(tree, 'M_Elevator')!;
    final speed = mElevator.children.firstWhere((c) => c.name == 'speed');
    final torque = mElevator.children.firstWhere((c) => c.name == 'torque');
    final enabled = mElevator.children.firstWhere((c) => c.name == 'enabled');

    final values = await umas.readVariables([
      (speed.variable!, speed.dataType!),
      (torque.variable!, torque.dataType!),
      (enabled.variable!, enabled.dataType!),
    ]);

    // Stub seeds (5, 0)=1450.0f, (5, 4)=92.5f, (5, 8)=0x01.
    expect(values, hasLength(3));
    expect(values[0].value, isA<double>());
    expect(values[0].value as double, closeTo(1450.0, 0.01));
    expect(values[1].value, isA<double>());
    expect(values[1].value as double, closeTo(92.5, 0.01));
    // BOOL decodes via the existing scalar parser. The exact runtime
    // representation (bool vs int) depends on the type; the value
    // should be truthy.
    final enabledVal = values[2].value;
    expect(enabledVal == true || enabledVal == 1,
        isTrue,
        reason: 'enabled (BOOL @ +8) was seeded with 0x01');
  });

  test('Existing non-FB tree (GVL/Motor/Counters) still expands correctly',
      () async {
    // Regression guard: the speculative-DD02 branch must not perturb
    // already-working struct or array expansion.
    await tcp.connect();
    final umas = UmasClient(sendFn: tcp.send);

    final tree = await umas.browse();
    final app = tree.firstWhere((n) => n.name == 'Application');

    // GVL with the array still expands per umas_e2e_test.dart assertions.
    final gvl = app.children.firstWhere((c) => c.name == 'GVL');
    final colors = gvl.children.firstWhere((c) => c.name == 'colors');
    expect(colors.dataType?.classIdentifier, 4,
        reason: 'array DD03 type unchanged');
    expect(colors.children, hasLength(4),
        reason: 'ARRAY[1..4] OF UINT still expands to 4 elements');

    // Motor scalar leaves untouched.
    final motor = app.children.firstWhere((c) => c.name == 'Motor');
    final speed = motor.children.firstWhere((c) => c.name == 'speed');
    expect(speed.children, isEmpty,
        reason: 'REAL scalar must NOT pick up the speculative branch');
    expect(speed.dataType?.name, 'REAL');
  });
}
