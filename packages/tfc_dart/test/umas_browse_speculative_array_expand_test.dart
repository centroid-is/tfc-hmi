/// Regression for the speculative-DD02 array-cardinality-mismatch bug.
///
/// Symptom (live fuzz, 2026-05-19): on the live M580 at
/// 192.168.112.159, a direct DD02-arrayDef-based read of
/// `BMEP58_ECPU_EXT.DIO_HEALTH[519]` succeeds, but
/// `readVariableByName(...)` of the same canonical name throws
/// "symbol not found in data dictionary". 8 of 20 strided
/// cross-checks diverged this way (all in `DIO_HEALTH[519+]` /
/// `DIO_CTRL[540+]` / `LS_HEALTH[N]`).
///
/// Root cause: `_expandVariable`'s array branch (umas_client.dart) bails
/// when `resolvedType.byteSize <= 0`, even when the cached
/// `UmasArrayTypeDefinition` IS present and the element type is a known
/// built-in. For FB-member arrays whose typeId is absent from DD03 (the
/// M580 firmware behaviour for `LS_HEALTH` / `DIO_HEALTH` / `DIO_CTRL`),
/// the speculative-DD02 path synthesizes a type with `byteSize: 0`, so
/// the children expansion is skipped. The symbol cache then walks a
/// tree that has no `[N]` leaves under those arrays — and
/// `readVariableByName("...DIO_HEALTH[519]")` fails for exactly those
/// names the cached `arrayDef` describes.
///
/// Fix: when the parent array's synthesized byteSize is 0 but the
/// element type is a built-in scalar with a known size (BOOL=1, INT=2,
/// etc.), derive `elementSize` from the built-in directly instead of
/// dividing the parent byteSize by `totalElementCount`, using the
/// `UmasArrayTypeDefinition.dimensions` bounds.
///
/// Test fixture: the Python stub now exposes `Application.GVL.health_bits`
/// referencing typeId 130 (ARRAY[1..3] OF BOOL). Type 130 is present in
/// `ARRAY_TYPES` (DD02) but ABSENT from `DATA_TYPES` (DD03) — exactly the
/// shape that crashes browse on the live M580.
///
/// Run: dart test test/umas_browse_speculative_array_expand_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_client.dart';

late int _stubPort;

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

Process? _serverProcess;
final _portPattern = RegExp(r'PORT=(\d+)');

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
  // Whether the interpreter died before it could speak. Without this a
  // start-up failure and a slow start-up look identical in the CI log.
  int? stubExit;
  unawaited(_serverProcess!.exitCode.then((code) => stubExit = code));
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
  // Two minutes, not thirty seconds. The first Python process of a `dart
  // test` run pays interpreter cold-start, and on a hosted Windows runner
  // that has been seen to take over thirty seconds while printing nothing at
  // all -- CI run 33506143133 lost this suite in setUpAll with an empty
  // stderr, then started twelve more stubs in the same job in under a second
  // each. This budget is a liveness guard, not an assertion about speed.
  _stubPort = await completer.future.timeout(const Duration(seconds: 120),
      onTimeout: () => throw StateError(
          'Stub server did not start (python=$python, '
          'script=$stubScript, '
          'exit=${stubExit ?? 'still running'}, stderr=$stderrBuf)'));
}

void _stopStub() {
  _serverProcess?.kill();
  _serverProcess = null;
}

void main() {
  late ModbusClientTcp tcp;

  setUpAll(() async {
    await _startStub();
  });

  tearDownAll(() {
    _stopStub();
  });

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

  group('Speculative-DD02 array expansion — array-cardinality-mismatch', () {
    test('browse() expands ARRAY[1..3] OF BOOL whose typeId is absent from DD03',
        () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);
      final tree = await umas.browse();

      final app = tree.firstWhere((n) => n.name == 'Application');
      final gvl = app.children.firstWhere((c) => c.name == 'GVL');
      final hb = gvl.children.firstWhere((c) => c.name == 'health_bits',
          orElse: () => throw StateError(
              'health_bits not in browse tree; children='
              '${gvl.children.map((c) => c.name).toList()}'));

      expect(hb.dataType?.classIdentifier, 4,
          reason: 'health_bits is an array (classIdentifier==4)');
      // The bug: hb.children was empty because resolvedType.byteSize==0
      // bailed out of the expansion branch. The fix MUST expand it into
      // [1], [2], [3] children whose dataTypeId is BOOL (1).
      expect(hb.children, hasLength(3),
          reason: 'array MUST expand into 3 BOOL elements');
      expect(hb.children.map((c) => c.name).toList(),
          ['[1]', '[2]', '[3]'],
          reason: '1D array uses natural [startIndex..upperBound] indexing');

      // Each element addressed at offset+i (one byte per BOOL on M580).
      final base = hb.variable!.offset;
      final addrs = hb.children.map((c) => c.variable!.offset - base).toList();
      expect(addrs, [0, 1, 2],
          reason: 'byte-per-bool layout: 1 byte per element');
      for (final child in hb.children) {
        expect(child.variable!.dataTypeId, 1,
            reason: 'element typeId is BOOL (1)');
        expect(child.dataType?.name, 'BOOL');
        expect(child.dataType?.byteSize, 1);
      }
    });

    test('readVariableByName resolves the expanded element leaves', () async {
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send);
      // readVariable requires the blockCrcs guard to be populated.
      await umas.readPlcStatus();
      // The bug: lookupSymbol threw "symbol not found in data dictionary"
      // for these paths because the symbol cache (populated by walking
      // the browse tree) never indexed them. The fix MUST produce a
      // tree where these paths resolve.
      final r1 =
          await umas.readVariableByName('Application.GVL.health_bits[1]');
      expect(r1.value, isTrue,
          reason: 'stub initialises health_bits[1] = true');

      final r2 =
          await umas.readVariableByName('Application.GVL.health_bits[2]');
      expect(r2.value, isFalse,
          reason: 'stub initialises health_bits[2] = false');

      final r3 =
          await umas.readVariableByName('Application.GVL.health_bits[3]');
      expect(r3.value, isTrue,
          reason: 'stub initialises health_bits[3] = true');
    });
  });
}
