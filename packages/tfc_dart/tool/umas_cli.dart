/// UMAS CLI — ad-hoc diagnostic tool for Schneider PLCs (M340, M580).
///
/// Connects to a PLC over Modbus TCP, primes the UMAS session, and runs
/// one of a handful of inspection commands. Useful for verifying wire-
/// format changes, regression-checking a deployment, or debugging a
/// specific variable layout that the browser surfaces oddly.
///
/// Usage:
///   dart run packages/tfc_dart/tool/umas_cli.dart <command> [args] [options]
///
/// Commands:
///   browse <host>              Print the full variable tree.
///   check  <host>              Pass/fail gate over every scalar leaf
///                              and a sample of every array's elements.
///                              Exits non-zero on any real failure (FB
///                              VAR_IN_OUT 0x94 errors counted separately).
///   read   <host> <name>       Read every leaf under a named variable
///                              (e.g. `astColorScanner_Colors_B`) and
///                              print value, type and address. Exits
///                              non-zero on any read failure.
///   dump-types <host>          Dump every DD03 data-type entry.
///   dump-array <host> <typeId> Print the raw DD02 bytes returned for
///                              an array type id (the
///                              UmasArrayTypeDefinition payload). Useful
///                              when reverse-engineering a new wire
///                              variant.
///   bitalias-probe <host>      Read-only protocol exploration of the
///                              0x26 (DATA_DICTIONARY) sub-opcode space,
///                              attempting to find the hidden bit-alias
///                              enumeration entry-point. Sweeps single-
///                              byte payloads, args under sub-op 0x04,
///                              and neighbouring opcodes 0x27 / 0x28
///                              while holding the PLC reservation
///                              (best-effort — falls back to unreserved
///                              if reservation is denied). Captures every
///                              response and writes a structured JSON log
///                              plus a markdown summary. NEVER writes to
///                              the PLC.
///
/// Options:
///   --port <N>      Modbus TCP port (default 502).
///   --unit <N>      Modbus unit identifier (default 255).
///   --timeout <s>   TCP connect timeout (default 5 seconds).
///   --elements <N>  `check` only — elements per array sampled (default 5;
///                   pass 0 for "every element of every array", which is
///                   slow but exhaustive).
///   --json          `check` only — emit machine-readable JSON summary
///                   instead of the human report.
///   --show-direction `browse` only — print the function-block member
///                   direction (input / output / publicVar / inOut / unknown)
///                   alongside each leaf that has one. Nodes without a
///                   direction (top-level vars, array elements) are
///                   printed as before.
///   --out <path>    `bitalias-probe` only — JSON output path
///                   (default /tmp/bitalias-p2-output.json).
///   --no-reserve    `bitalias-probe` only — skip the reservation
///                   attempt entirely (run unreserved baseline only).
///                   Useful for differential comparison.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_error_messages.dart';
import 'package:tfc_dart/core/umas_types.dart';

const _defaultPort = 502;
const _defaultUnit = 255;
const _defaultTimeoutSeconds = 5;

// FB VAR_IN_OUT pointer-backed paths cannot be read by direct memory
// access — the PLC returns 0x94 regardless of client. plc4j's symbol
// resolver also drops them. Categorise them so they don't muddy the
// pass/fail gate.
final _fbInOutRegex = RegExp(r'\.(iq_|io_)');

Future<void> main(List<String> args) async {
  // Wrap the real entry in an explicit exit() because the underlying
  // Modbus client keeps a heartbeat / listener alive after disconnect,
  // and the Dart VM otherwise waits for that timer to settle (which
  // never happens). This caused `v1.1-verify.sh` to hang after the
  // command had already printed its full result.
  final code = await _main(args);
  exit(code);
}

Future<int> _main(List<String> args) async {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addOption('port', defaultsTo: '$_defaultPort')
    ..addOption('unit', defaultsTo: '$_defaultUnit')
    ..addOption('timeout', defaultsTo: '$_defaultTimeoutSeconds')
    ..addOption('elements', defaultsTo: '5')
    ..addOption('out', defaultsTo: '/tmp/bitalias-p2-output.json')
    ..addFlag('json', defaultsTo: false, negatable: false)
    ..addFlag('show-direction', defaultsTo: false, negatable: false)
    ..addFlag('no-reserve', defaultsTo: false, negatable: false)
    ..addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Argument error: ${e.message}\n');
    _printUsage(parser);
    return 64;
  }

  if (parsed['help'] == true || parsed.rest.isEmpty) {
    _printUsage(parser);
    return parsed['help'] == true ? 0 : 64;
  }

  final command = parsed.rest.first;
  final rest = parsed.rest.skip(1).toList();
  final port = int.parse(parsed['port'] as String);
  final unit = int.parse(parsed['unit'] as String);
  final timeout =
      Duration(seconds: int.parse(parsed['timeout'] as String));
  final elementsPerArray = int.parse(parsed['elements'] as String);
  final emitJson = parsed['json'] as bool;
  final showDirection = parsed['show-direction'] as bool;
  final outPath = parsed['out'] as String;
  final noReserve = parsed['no-reserve'] as bool;

  switch (command) {
    case 'browse':
      _need(rest, 1, 'browse <host>');
      return _withClient(rest[0], port, unit, timeout,
          (umas) => _browseCommand(umas, showDirection: showDirection));
    case 'check':
      _need(rest, 1, 'check <host>');
      return _withClient(rest[0], port, unit, timeout,
          (umas) => _checkCommand(umas, elementsPerArray, emitJson));
    case 'read':
      _need(rest, 2, 'read <host> <name>');
      return _withClient(
          rest[0], port, unit, timeout, (umas) => _readCommand(umas, rest[1]));
    case 'dump-types':
      _need(rest, 1, 'dump-types <host>');
      return _withClient(
          rest[0], port, unit, timeout, _dumpTypesCommand);
    case 'dump-array':
      _need(rest, 2, 'dump-array <host> <typeId>');
      final typeId = _parseInt(rest[1]);
      return _withClient(rest[0], port, unit, timeout,
          (umas) => _dumpArrayCommand(umas, typeId));
    case 'bitalias-probe':
      _need(rest, 1, 'bitalias-probe <host>');
      return _withClient(
          rest[0],
          port,
          unit,
          timeout,
          (umas) => _bitaliasProbeCommand(
                umas,
                host: rest[0],
                outPath: outPath,
                noReserve: noReserve,
              ));
    default:
      stderr.writeln('Unknown command: $command\n');
      _printUsage(parser);
      return 64;
  }
}

void _printUsage(ArgParser parser) {
  stderr.writeln('UMAS CLI — Schneider PLC diagnostic tool\n');
  stderr.writeln(
      'Usage: dart run tool/umas_cli.dart <command> [args] [options]\n');
  stderr.writeln('Commands:');
  stderr.writeln('  browse <host>              Print the full variable tree');
  stderr.writeln(
      '  check  <host>              Read scalars + sampled array elements');
  stderr.writeln(
      '  read   <host> <name>       Read every leaf under a named variable');
  stderr.writeln('  dump-types <host>          Dump every DD03 data type');
  stderr.writeln(
      '  dump-array <host> <typeId> Dump raw DD02 bytes for an array type id');
  stderr.writeln(
      '  bitalias-probe <host>      Read-only 0x26 sub-opcode protocol probe\n');
  stderr.writeln('Options:\n${parser.usage}');
}

void _need(List<String> rest, int n, String example) {
  if (rest.length < n) {
    stderr.writeln('Missing argument(s). Expected: $example');
    exit(64);
  }
}

int _parseInt(String s) {
  final lower = s.toLowerCase();
  if (lower.startsWith('0x')) return int.parse(lower.substring(2), radix: 16);
  return int.parse(s);
}

Future<int> _withClient(
  String host,
  int port,
  int unit,
  Duration timeout,
  Future<int> Function(UmasClient) body,
) async {
  final tcp = ModbusClientTcp(
    host,
    serverPort: port,
    unitId: unit,
    connectionMode: ModbusConnectionMode.doNotConnect,
    connectionTimeout: timeout,
  );
  await tcp.connect();
  final umas = UmasClient(sendFn: tcp.send, unitId: unit);
  try {
    await umas.readPlcStatus();
    return await body(umas);
  } on UmasException catch (e) {
    // TD-018 (v1.1.x): translate raw UMAS hex into operator-grade
    // guidance instead of letting the unhandled exception trace
    // surface in the verify-script gating loop. Same mapping the
    // Flutter Browse dialog uses.
    final info = mapUmasError(e);
    if (info != null) {
      stderr.writeln(info.summary);
      stderr.writeln('');
      stderr.writeln(info.detail);
    } else {
      stderr.writeln('UMAS error: $e');
    }
    return 1;
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// browse — print the full tree
// ---------------------------------------------------------------------------

Future<int> _browseCommand(UmasClient umas,
    {bool showDirection = false}) async {
  final tree = await umas.browse();
  final leafCount = _countLeaves(tree);
  print('${tree.length} root(s), $leafCount leaves\n');
  for (final root in tree) {
    _printTree(root, '', showDirection: showDirection);
  }
  return 0;
}

void _printTree(UmasVariableTreeNode n, String indent,
    {bool showDirection = false}) {
  final type = n.dataType?.name ?? '?';
  final addr = n.variable == null
      ? ''
      : ' [block=0x${n.variable!.blockNo.toRadixString(16)} '
          'off=0x${n.variable!.offset.toRadixString(16)}]';
  // Phase 3 (v1.1): --show-direction surfaces the FB-member direction
  // when the node carries one. Suppress entirely when no direction is
  // attached so legacy top-level / array-element output is unchanged.
  final dirSuffix = (showDirection && n.direction != null)
      ? ' dir=${n.direction!.name}'
      : '';
  print('$indent${n.name}  ($type)$addr$dirSuffix');
  for (final c in n.children) {
    _printTree(c, '$indent  ', showDirection: showDirection);
  }
}

int _countLeaves(List<UmasVariableTreeNode> roots) {
  var total = 0;
  void walk(UmasVariableTreeNode n) {
    if (n.children.isEmpty && n.variable != null) total++;
    for (final c in n.children) {
      walk(c);
    }
  }

  for (final r in roots) {
    walk(r);
  }
  return total;
}

// ---------------------------------------------------------------------------
// check — pass/fail gate
// ---------------------------------------------------------------------------

Future<int> _checkCommand(
    UmasClient umas, int elementsPerArray, bool emitJson) async {
  final tree = await umas.browse();

  // Scalars: first three leaves of every memory block (catches per-block
  // addressing regressions cheaply).
  final scalarLeaves = <UmasVariableTreeNode>[];
  void gatherScalars(UmasVariableTreeNode n) {
    if (n.children.isEmpty && n.variable != null) scalarLeaves.add(n);
    for (final c in n.children) {
      gatherScalars(c);
    }
  }

  for (final r in tree) {
    gatherScalars(r);
  }

  final byBlock = <int, List<UmasVariableTreeNode>>{};
  for (final n in scalarLeaves) {
    byBlock.putIfAbsent(n.variable!.blockNo, () => []).add(n);
  }

  int scalarOk = 0, scalarFail = 0;
  final failures = <_Failure>[];
  for (final entry in byBlock.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key))) {
    for (final n in entry.value.take(3)) {
      final v = n.variable!;
      final dt = n.dataType ??
          UmasDataTypeRef(id: v.dataTypeId, name: '?', byteSize: 2);
      try {
        await umas.readVariables([(v, dt)]);
        scalarOk++;
      } on UmasException catch (e) {
        scalarFail++;
        failures.add(_Failure(n.path, v, dt, e.errorCode));
      }
    }
  }

  // Arrays: first N elements per array — N=0 means exhaustive.
  final arrayNodes = <UmasVariableTreeNode>[];
  void gatherArrays(UmasVariableTreeNode n) {
    if (n.dataType?.classIdentifier == 4 && n.children.isNotEmpty) {
      arrayNodes.add(n);
    }
    for (final c in n.children) {
      gatherArrays(c);
    }
  }

  for (final r in tree) {
    gatherArrays(r);
  }

  int arrayOk = 0, arrayFail = 0, arrayFbInOut = 0;
  final arrayElementCounts = <int>[];
  for (final arr in arrayNodes) {
    final elementLeaves = <UmasVariableTreeNode>[];
    void gather(UmasVariableTreeNode n) {
      if (n.children.isEmpty && n.variable != null && n.dataType != null) {
        elementLeaves.add(n);
      }
      for (final c in n.children) {
        gather(c);
      }
    }

    gather(arr);
    arrayElementCounts.add(elementLeaves.length);

    final sample = elementsPerArray <= 0
        ? elementLeaves
        : elementLeaves.take(elementsPerArray);
    for (final elem in sample) {
      try {
        await umas.readVariables([(elem.variable!, elem.dataType!)]);
        arrayOk++;
      } on UmasException catch (e) {
        if (_fbInOutRegex.hasMatch(elem.path)) {
          arrayFbInOut++;
          continue;
        }
        arrayFail++;
        failures
            .add(_Failure(elem.path, elem.variable!, elem.dataType!, e.errorCode));
      }
    }
  }

  arrayElementCounts.sort();
  final maxLeaves =
      arrayElementCounts.isEmpty ? 0 : arrayElementCounts.last;
  final medLeaves = arrayElementCounts.isEmpty
      ? 0
      : arrayElementCounts[arrayElementCounts.length ~/ 2];
  final realFails = scalarFail + arrayFail;

  if (emitJson) {
    final summary = {
      'roots': tree.length,
      'leaves': _countLeaves(tree),
      'scalars': {'ok': scalarOk, 'fail': scalarFail},
      'arrays': {
        'ok': arrayOk,
        'fail': arrayFail,
        'fb_in_out': arrayFbInOut,
        'count': arrayNodes.length,
        'leaves_median': medLeaves,
        'leaves_max': maxLeaves,
      },
      'failures': failures.map((f) => f.toJson()).toList(),
    };
    print(const JsonEncoder.withIndent('  ').convert(summary));
  } else {
    print('${tree.length} roots, ${_countLeaves(tree)} leaves\n');
    print('Scalars (first 3 per block): $scalarOk ok / $scalarFail fail');
    print('Arrays: $arrayOk ok / $arrayFail fail / $arrayFbInOut FB-in/out '
        '(unreadable by design) (${arrayNodes.length} array vars, '
        'leaves median=$medLeaves max=$maxLeaves)');
    if (failures.isNotEmpty) {
      print('\nFailures (${failures.length}):');
      for (final f in failures.take(50)) {
        print('  ${f.format()}');
      }
      if (failures.length > 50) {
        print('  ... ${failures.length - 50} more');
      }
    }
  }

  return realFails == 0 ? 0 : 1;
}

// ---------------------------------------------------------------------------
// read — every leaf under one named variable
// ---------------------------------------------------------------------------

Future<int> _readCommand(UmasClient umas, String name) async {
  final tree = await umas.browse();
  final node = _findByName(tree, name);
  if (node == null) {
    stderr.writeln('Variable not found: $name');
    return 1;
  }

  final leaves = <UmasVariableTreeNode>[];
  void gather(UmasVariableTreeNode n) {
    if (n.children.isEmpty && n.variable != null && n.dataType != null) {
      leaves.add(n);
    }
    for (final c in n.children) {
      gather(c);
    }
  }

  gather(node);

  print('${node.path}: ${leaves.length} leaf/leaves');

  int ok = 0, fail = 0;
  for (final leaf in leaves) {
    final v = leaf.variable!;
    final dt = leaf.dataType!;
    try {
      final result = await umas.readVariables([(v, dt)]);
      final val = result.first.value;
      print('  ${leaf.path}  ${dt.name} '
          '[block=0x${v.blockNo.toRadixString(16)} '
          'off=0x${v.offset.toRadixString(16)}]  =  $val');
      ok++;
    } on UmasException catch (e) {
      fail++;
      // CRIT-1: when errorCode == 0 the failure is a parse / decode
      // condition (e.g. "Buffer underflow") and the actionable
      // signal is in `e.message`. Print it to stderr so operators
      // and `v1.1-verify.sh` greps surface the real cause rather
      // than a misleading `0x0`.
      //
      // TD-018 (v1.1.x): for protocol error codes (0x83, 0xC0, 0x86,
      // etc.) print the shared operator-friendly summary so the verify
      // loop produces actionable output without the operator having
      // to look up hex codes.
      final info = mapUmasError(e);
      final codeHex = '0x${e.errorCode.toRadixString(16)}';
      final summary = info?.summary ?? codeHex;
      if (e.errorCode == 0) {
        stderr.writeln('  ${leaf.path}  ${dt.name} '
            '[block=0x${v.blockNo.toRadixString(16)} '
            'off=0x${v.offset.toRadixString(16)}]  -> '
            '$codeHex  ${e.message}');
      }
      print('  ${leaf.path}  ${dt.name} '
          '[block=0x${v.blockNo.toRadixString(16)} '
          'off=0x${v.offset.toRadixString(16)}]  -> '
          '$summary'
          '${e.errorCode == 0 ? '  ${e.message}' : ''}');
    }
  }

  print('\n$ok ok / $fail fail');
  return fail == 0 ? 0 : 1;
}

UmasVariableTreeNode? _findByName(
    List<UmasVariableTreeNode> roots, String name) {
  UmasVariableTreeNode? hit;
  void walk(UmasVariableTreeNode n) {
    if (hit != null) return;
    if (n.name == name) {
      hit = n;
      return;
    }
    for (final c in n.children) {
      walk(c);
    }
  }

  // TD-019 (v1.1.x): break out as soon as a root walk finds the
  // target. Previously the outer loop kept iterating roots even after
  // `hit` was set — on PLCs with many roots this wasted up to N
  // traversals worth of work per lookup.
  for (final r in roots) {
    walk(r);
    if (hit != null) break;
  }
  return hit;
}

// ---------------------------------------------------------------------------
// dump-types — DD03 data type listing
// ---------------------------------------------------------------------------

Future<int> _dumpTypesCommand(UmasClient umas) async {
  final types = await umas.readDataTypes();
  print('${types.length} data type(s)');
  for (final t in types) {
    print('  id=0x${t.id.toRadixString(16).padLeft(2, '0')} '
        'classId=${t.classIdentifier} '
        'dataType=0x${t.dataType.toRadixString(16).padLeft(2, '0')} '
        'byteSize=${t.byteSize}  ${t.name}');
  }
  return 0;
}

// ---------------------------------------------------------------------------
// dump-array — raw DD02 payload for an array type id
// ---------------------------------------------------------------------------

Future<int> _dumpArrayCommand(UmasClient umas, int typeId) async {
  final raw = await umas.readDD02Raw(typeId);
  print('typeId=0x${typeId.toRadixString(16)}  '
      '${raw.length} byte(s)');
  print('  raw:    ${_hex(raw)}');
  final arr = UmasArrayTypeDefinition.tryParse(raw);
  if (arr == null) {
    print('  parse:  not a UmasArrayTypeDefinition (classId != 0x04)');
    return 0;
  }
  print('  parse:  classId=0x${arr.classId.toRadixString(16)} '
      'elementTypeId=0x${arr.elementTypeId.toRadixString(16)} '
      'dimensions=${arr.dimensions.length}');
  for (var i = 0; i < arr.dimensions.length; i++) {
    final d = arr.dimensions[i];
    print('    dim[$i]: [${d.startIndex}..${d.upperBound}] '
        '(${d.count} elements)');
  }
  print('  total elements: ${arr.totalElementCount}');
  return 0;
}

String _hex(Uint8List bytes) {
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    if (i > 0) buf.write(' ');
    buf.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------
// bitalias-probe — 0x26 sub-opcode protocol exploration
// ---------------------------------------------------------------------------
//
// Read-only, no writes. Builds raw UMAS frames for FC 0x26
// (DATA_DICTIONARY) and neighbours, captures every response, writes a
// structured JSON log + markdown report. Best-effort reservation: tries
// `takePlcReservation` once; on denial logs the error and continues with
// an unreserved sweep so we still capture a reservation/no-reservation
// differential.
//
// Background (see /tmp/bitalias-swarm/LEADS.md + p2-stuck.md):
//   - `0x26 + [0x00]`  → 28-byte directory record (count=17, root FBs=63)
//   - `0x26 + [0x04]`  → 46-byte extended record (adds count 1438 — likely
//                        the located-bit / bit-alias table size)
//   - `0x26 + [0x04, *]` → identical 46 bytes regardless of trailing args
//                          (unreserved). Hypothesis: reservation unlocks
//                          a real enumeration semantics for [0x04, X].
//
// The probe matrix is intentionally narrow but exhaustive in the most
// promising directions. ~800 probes total at ~5ms each is < 5s.

Future<int> _bitaliasProbeCommand(
  UmasClient umas, {
  required String host,
  required String outPath,
  required bool noReserve,
}) async {
  final startedAt = DateTime.now().toUtc();
  final probes = <Map<String, Object?>>[];
  String? reservationStatus;
  Map<String, Object?>? reservationError;

  // ----- 0a. Baseline (no reservation): capture 0x26+[0x00] and 0x26+[0x04]
  //          so we have a stable "unreserved fingerprint" to diff against.
  await _runOneProbe(
    umas,
    subFn: 0x26,
    payload: const [0x00],
    label: 'baseline:0x26+[0x00]:unreserved',
    reserved: false,
    out: probes,
  );
  await _runOneProbe(
    umas,
    subFn: 0x26,
    payload: const [0x04],
    label: 'baseline:0x26+[0x04]:unreserved',
    reserved: false,
    out: probes,
  );

  // ----- 0b. Attempt reservation (once, no retry storm).
  bool reservationHeld = false;
  if (noReserve) {
    reservationStatus = 'skipped (--no-reserve)';
    stderr.writeln('[probe] --no-reserve set; running unreserved baseline');
  } else {
    try {
      await umas.takePlcReservation();
      reservationHeld = true;
      reservationStatus = 'held';
      stderr.writeln('[probe] reservation TAKEN');
    } on UmasException catch (e) {
      reservationStatus = 'denied';
      reservationError = {
        'errorCode': e.errorCode,
        'errorCodeHex':
            '0x${e.errorCode.toRadixString(16).padLeft(2, '0')}',
        'message': e.message,
      };
      stderr.writeln(
          '[probe] reservation DENIED: 0x${e.errorCode.toRadixString(16)} '
          '— continuing with unreserved sweep for completeness');
    } catch (e) {
      reservationStatus = 'error';
      reservationError = {'message': e.toString()};
      stderr.writeln('[probe] reservation ERROR: $e — continuing unreserved');
    }
  }

  try {
    // ----- Phase A: 0x26 + [N] single byte, N=0..255.
    stderr.writeln(
        '[probe] phase A: 0x26 + [N] for N=0..255 (reserved=$reservationHeld)');
    for (var n = 0; n <= 0xFF; n++) {
      await _runOneProbe(
        umas,
        subFn: 0x26,
        payload: [n],
        label: 'A:0x26+[0x${n.toRadixString(16).padLeft(2, '0')}]',
        reserved: reservationHeld,
        out: probes,
      );
    }

    // ----- Phase B: 0x26 + [0x04, X] single trailing byte, X=0..255.
    stderr.writeln('[probe] phase B: 0x26 + [0x04, X] for X=0..255');
    for (var x = 0; x <= 0xFF; x++) {
      await _runOneProbe(
        umas,
        subFn: 0x26,
        payload: [0x04, x],
        label: 'B:0x26+[0x04,0x${x.toRadixString(16).padLeft(2, '0')}]',
        reserved: reservationHeld,
        out: probes,
      );
    }

    // ----- Phase C: structured trailing args under sub-op 0x04.
    // From LEAD-C5-A and p2-stuck.md, candidate shapes worth a focused
    // re-test under reservation:
    stderr.writeln('[probe] phase C: structured args under 0x26+[0x04, ...]');
    final hwId = umas.hardwareId ?? 0;
    final hwIdBytes = _u32le(hwId);
    final memIdx = umas.memoryIndex ?? 0;

    // Tested idx values — the 1438 count from the 46-byte response is the
    // strongest lead, plus boundaries.
    final idxCandidates = <int>[0, 1, 2, 10, 50, 100, 500, 1000, 1437, 1438,
      1439, 0xFFFF];

    for (final idx in idxCandidates) {
      // 16-bit idx
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [0x04, ..._u16le(idx)],
          label: 'C:[0x04,idxLE16=$idx]',
          reserved: reservationHeld,
          out: probes);
      // 32-bit idx
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [0x04, ..._u32le(idx)],
          label: 'C:[0x04,idxLE32=$idx]',
          reserved: reservationHeld,
          out: probes);
      // recordType-like prefix + idx (mimics 0x26 standard DD02/DD03 shape)
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [0x04, ..._u16le(0xDD04), memIdx, ...hwIdBytes,
            ..._u16le(idx), 0x00, 0x00],
          label: 'C:[0x04,DD04,memIdx,hwId,idxLE16=$idx,00 00]',
          reserved: reservationHeld,
          out: probes);
      // hwId + idx
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [0x04, ...hwIdBytes, ..._u16le(idx)],
          label: 'C:[0x04,hwId,idxLE16=$idx]',
          reserved: reservationHeld,
          out: probes);
    }

    // Full DD02/DD03-style payload but under 0x04 prefix
    for (final rt in [0xDD00, 0xDD01, 0xDD04, 0xDD05, 0xDD10, 0xDD20]) {
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [
            0x04,
            ..._u16le(rt),
            memIdx,
            ...hwIdBytes,
            0xFF, 0xFF,
            0x00, 0x00,
            0x00, 0x00,
          ],
          label: 'C:[0x04,recordType=0x${rt.toRadixString(16)},dd02-shape]',
          reserved: reservationHeld,
          out: probes);
    }

    // ----- Phase D: revisit siblings 0x01/0x02/0x03/0x05/0x06/0x07
    //                under reservation. Unreserved they returned 0x88 / 0x83
    //                errors; reservation may unlock a structured request shape.
    stderr.writeln('[probe] phase D: siblings 0x01..0x07 with structured args');
    final siblingSubOps = [0x01, 0x02, 0x03, 0x05, 0x06, 0x07];
    for (final sub in siblingSubOps) {
      // bare
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [sub],
          label: 'D:[$sub bare]',
          reserved: reservationHeld,
          out: probes);
      // sub + hwId
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [sub, ...hwIdBytes],
          label: 'D:[$sub,hwId]',
          reserved: reservationHeld,
          out: probes);
      // sub + full DD02-shape body
      await _runOneProbe(umas,
          subFn: 0x26,
          payload: [
            sub,
            ..._u16le(0xDD02),
            memIdx,
            ...hwIdBytes,
            0xFF, 0xFF,
            0x00, 0x00,
            0x00, 0x00,
          ],
          label: 'D:[$sub,DD02-shape]',
          reserved: reservationHeld,
          out: probes);
      // sub + idx16
      for (final idx in [0, 1, 1437, 1438]) {
        await _runOneProbe(umas,
            subFn: 0x26,
            payload: [sub, ..._u16le(idx)],
            label: 'D:[$sub,idxLE16=$idx]',
            reserved: reservationHeld,
            out: probes);
      }
    }

    // ----- Phase E: neighbouring opcodes 0x27 (PRELOAD per Zaltzman) +
    //                0x28 single-byte sweep.
    stderr.writeln('[probe] phase E: neighbour opcodes 0x27 / 0x28');
    for (final sub in [0x27, 0x28]) {
      // Bare
      await _runOneProbe(umas,
          subFn: sub,
          payload: const [],
          label: 'E:0x${sub.toRadixString(16)}+[]',
          reserved: reservationHeld,
          out: probes);
      // Sub-byte sweep
      for (var x = 0; x <= 0xFF; x++) {
        await _runOneProbe(umas,
            subFn: sub,
            payload: [x],
            label: 'E:0x${sub.toRadixString(16)}+'
                '[0x${x.toRadixString(16).padLeft(2, '0')}]',
            reserved: reservationHeld,
            out: probes);
      }
      // DD02-shape (mirrors what 0x26 expects)
      await _runOneProbe(umas,
          subFn: sub,
          payload: [
            ..._u16le(0xDD02),
            memIdx,
            ...hwIdBytes,
            0xFF, 0xFF,
            0x00, 0x00,
            0x00, 0x00,
          ],
          label: 'E:0x${sub.toRadixString(16)}+DD02-shape',
          reserved: reservationHeld,
          out: probes);
    }
  } finally {
    if (reservationHeld) {
      try {
        await umas.releasePlcReservation();
        stderr.writeln('[probe] reservation released');
      } catch (e) {
        stderr.writeln('[probe] reservation release error (ignored): $e');
      }
    }
  }

  // ----- Analysis: classify probes, compute response signatures.
  final analysis = _analyseProbes(probes);

  // ----- Write JSON output.
  final output = {
    'tool': 'umas_cli bitalias-probe',
    'started_at_utc': startedAt.toIso8601String(),
    'finished_at_utc': DateTime.now().toUtc().toIso8601String(),
    'host': host,
    'reservation': {
      'requested': !noReserve,
      'status': reservationStatus,
      'error': reservationError,
      'note': 'errorCode 0x06 = another client holds reservation (per '
          'codebase); 0x81 was observed previously by /tmp/p2-reserved.log '
          'and is NOT one of the documented conflict codes — likely '
          'firmware/auth-level denial.',
    },
    'session': {
      'hardwareIdHex': hwIdHexOrNull(umas.hardwareId),
      'memoryIndex': umas.memoryIndex,
      'pairingKey': umas.pairingKey,
    },
    'baseline_signatures': analysis.baselineSignatures,
    'probe_count': probes.length,
    'classification': analysis.classification,
    'novel_signatures': analysis.novelSignatures,
    'probes': probes,
  };
  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(output));
  stderr.writeln('[probe] wrote ${probes.length} probes -> $outPath');

  // ----- Markdown report next to it (sibling path).
  final mdPath = outPath.endsWith('.json')
      ? outPath.replaceFirst(RegExp(r'\.json$'), '.md')
      : '$outPath.md';
  File(mdPath).writeAsStringSync(_renderMarkdownReport(
    host: host,
    reservationStatus: reservationStatus,
    reservationError: reservationError,
    analysis: analysis,
    probeCount: probes.length,
    startedAt: startedAt,
  ));
  stderr.writeln('[probe] wrote report -> $mdPath');

  // ----- Stdout summary.
  print('bitalias-probe complete: ${probes.length} probes');
  print('  reservation: $reservationStatus');
  print('  baseline signatures:');
  analysis.baselineSignatures.forEach((k, v) {
    print('    $k: $v');
  });
  print('  classification:');
  analysis.classification.forEach((k, v) {
    print('    $k: $v');
  });
  if (analysis.novelSignatures.isNotEmpty) {
    print('  NOVEL signatures (not seen unreserved):');
    for (final sig in analysis.novelSignatures.entries.take(20)) {
      print('    ${sig.key} (${(sig.value as List).length} probes hit it)');
    }
  } else {
    print('  no novel signatures detected.');
  }
  print('Outputs:\n  $outPath\n  $mdPath');
  return 0;
}

String? hwIdHexOrNull(int? id) =>
    id == null ? null : '0x${id.toRadixString(16).padLeft(8, '0')}';

List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> _u32le(int v) => [
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];

/// Execute a single raw UMAS probe and append its result to [out].
///
/// Best-effort: any send / transport / decode failure is recorded inside the
/// probe map rather than thrown, so the sweep continues past odd responses.
Future<void> _runOneProbe(
  UmasClient umas, {
  required int subFn,
  required List<int> payload,
  required String label,
  required bool reserved,
  required List<Map<String, Object?>> out,
}) async {
  final t0 = DateTime.now();
  final entry = <String, Object?>{
    'label': label,
    'subFn': subFn,
    'subFnHex': '0x${subFn.toRadixString(16).padLeft(2, '0')}',
    'payloadHex': _hex(Uint8List.fromList(payload)),
    'payloadLen': payload.length,
    'reserved': reserved,
    'sentAtUtc': t0.toUtc().toIso8601String(),
  };
  try {
    final request = UmasRequest(
      umasSubFunction: subFn,
      pairingKey: umas.pairingKey,
      payload: Uint8List.fromList(payload),
      unitId: 255,
    );
    final code = await umas.sendFn(request);
    final elapsedMs = DateTime.now().difference(t0).inMilliseconds;
    entry['elapsedMs'] = elapsedMs;
    entry['transport'] = code.name;
    if (code != ModbusResponseCode.requestSucceed) {
      entry['ok'] = false;
      entry['transportError'] = code.name;
    } else {
      final pdu = request.responsePdu;
      if (pdu == null || pdu.length < 3) {
        entry['ok'] = false;
        entry['note'] = 'empty PDU';
      } else {
        // pdu[0] = 0x5A, pdu[1] = pairing, pdu[2] = status (0xFE / 0xFD)
        final status = pdu[2];
        final body = pdu.length > 3 ? pdu.sublist(3) : Uint8List(0);
        entry['status'] = status;
        entry['statusHex'] = '0x${status.toRadixString(16).padLeft(2, '0')}';
        entry['statusName'] = status == 0xFE
            ? 'OK'
            : status == 0xFD
                ? 'ERROR'
                : 'OTHER';
        entry['responseLen'] = body.length;
        entry['responseHex'] = _hex(body);
        entry['ok'] = status == 0xFE;
      }
    }
  } catch (e) {
    entry['ok'] = false;
    entry['exception'] = e.toString();
  }
  out.add(entry);
}

class _ProbeAnalysis {
  final Map<String, String> baselineSignatures; // label -> sig
  final Map<String, int> classification; // category -> count
  final Map<String, List<String>> novelSignatures; // sig -> [labels]
  _ProbeAnalysis({
    required this.baselineSignatures,
    required this.classification,
    required this.novelSignatures,
  });
}

_ProbeAnalysis _analyseProbes(List<Map<String, Object?>> probes) {
  // Signature = "status:responseHex". Lets us detect "novel" responses that
  // never appeared in the known unreserved baseline corpus.
  String sigOf(Map<String, Object?> p) {
    final st = p['statusHex'] ?? '?';
    final body = p['responseHex'] ?? '';
    return '$st:$body';
  }

  // Known unreserved fingerprints from p2-stuck.md + p2-reserved-null.md:
  //   - 0xFE 28B for 0x26+[0x00]
  //   - 0xFE 46B for 0x26+[0x04, *]  (any args; ignored)
  //   - 0xFD 0x88 for 0x26+[0x01..0x03] (sibling sub-op errors)
  //   - 0xFD 0x83 for 0x26+[0x05..0xFF] (unknown sub-op error)
  final knownSignatures = <String>{};
  final baselineSignatures = <String, String>{};
  for (final p in probes) {
    final label = p['label'] as String? ?? '';
    if (label.startsWith('baseline:')) {
      final sig = sigOf(p);
      baselineSignatures[label] = sig;
      knownSignatures.add(sig);
    }
  }
  // Mark known error-family templates as "known" so we don't spam novelty
  // alerts on documented "unknown sub-op" / "bad payload" envelopes.
  //
  // Known 10-byte 0xFD error templates (from prior swarm analysis):
  //   "83 80 82 1a 23 00 XX 00 00 00"  — unknown sub-op, byte 6 = echoed
  //                                       sub-op id
  //   "88 80 ?? ?? 23 00 XX 00 00 00"  — recognised sub-op, bad payload
  //   "c0 c1 9d 1a 23 00 ..."          — access denied (0x27 family)
  //   "c0 c3 .. .. 23 00 .. .. .. .."  — access denied (0x26 sibling family)
  //
  // Anything else — different first-byte family, body that echoes session
  // values (hwId / pairing) in unexpected slots, or fewer/more trailing
  // zero bytes — counts as novel and surfaces in the report.
  bool isKnownErrorTemplate(String body) {
    final parts = body.split(' ');
    if (parts.length < 10) return false;
    bool b(int i, String want) => parts[i].toLowerCase() == want.toLowerCase();
    // 83 80 ?? 1a 23 00 XX 00 00 00
    if (b(0, '83') && b(1, '80') && b(3, '1a') && b(4, '23') && b(5, '00') &&
        b(7, '00') && b(8, '00') && b(9, '00')) {
      return true;
    }
    // 88 80 ?? ?? 23 00 XX 00 00 00  (FC-0x26 sibling "bad payload" family)
    if (b(0, '88') && b(1, '80') && b(4, '23') && b(5, '00') &&
        b(7, '00') && b(8, '00') && b(9, '00')) {
      return true;
    }
    // 88 80 ?? ?? 12 00 00 00 00 00  (FC-0x28 "bad payload" family —
    // saw this 257x in the 0x28 sweep; bytes 4-5 = 12 00 instead of 23 00)
    if (b(0, '88') && b(1, '80') && b(4, '12') && b(5, '00') &&
        b(6, '00') && b(7, '00') && b(8, '00') && b(9, '00')) {
      return true;
    }
    // c0 c1 / c0 c3 access-denied family
    if (b(0, 'c0') && (b(1, 'c1') || b(1, 'c3'))) return true;
    return false;
  }

  for (final p in probes) {
    if (p['status'] == 0xFD) {
      final body = p['responseHex'] as String? ?? '';
      if (isKnownErrorTemplate(body)) {
        knownSignatures.add(sigOf(p));
      }
    }
  }

  // Classification.
  int okCount = 0;
  int errCount = 0;
  int transportErr = 0;
  final byStatus = <int, int>{};
  for (final p in probes) {
    if (p['ok'] == true) okCount++;
    if (p['ok'] == false) {
      if (p['status'] != null) errCount++;
      if (p['transportError'] != null) transportErr++;
    }
    final st = p['status'];
    if (st is int) {
      byStatus[st] = (byStatus[st] ?? 0) + 1;
    }
  }
  final classification = <String, int>{
    'total': probes.length,
    'ok (0xFE)': okCount,
    'err (0xFD)': errCount,
    'transport_errors': transportErr,
    'status_0xFE_count': byStatus[0xFE] ?? 0,
    'status_0xFD_count': byStatus[0xFD] ?? 0,
  };

  // Novelty detection — responses whose signature is not in the known
  // unreserved corpus or the generic 0xFD error templates.
  final novel = <String, List<String>>{};
  for (final p in probes) {
    final label = p['label'] as String? ?? '';
    if (label.startsWith('baseline:')) continue;
    final sig = sigOf(p);
    if (knownSignatures.contains(sig)) continue;
    // Persistent baseline echoes (28B / 46B 0xFE) are already covered by
    // knownSignatures via the baseline probes — but as a defensive
    // backstop also skip 0xFE bodies that start with the documented
    // directory header prefix.
    final body = p['responseHex'] as String? ?? '';
    if (p['status'] == 0xFE &&
        (body.startsWith('f0 6c 60 00') || body.startsWith('03 f0 6c 60'))) {
      continue;
    }
    novel.putIfAbsent(sig, () => []).add(label);
  }
  return _ProbeAnalysis(
    baselineSignatures: baselineSignatures,
    classification: classification,
    novelSignatures: novel,
  );
}

String _renderMarkdownReport({
  required String host,
  required String? reservationStatus,
  required Map<String, Object?>? reservationError,
  required _ProbeAnalysis analysis,
  required int probeCount,
  required DateTime startedAt,
}) {
  final buf = StringBuffer();
  buf.writeln(
      '# bitalias-probe report ($host, ${startedAt.toUtc().toIso8601String()})');
  buf.writeln();
  buf.writeln('## Reservation');
  buf.writeln('- Status: $reservationStatus');
  if (reservationError != null) {
    buf.writeln('- Error: ${reservationError['errorCodeHex'] ?? '-'} '
        '(${reservationError['message'] ?? ''})');
  }
  buf.writeln();
  buf.writeln('## Baseline signatures');
  analysis.baselineSignatures.forEach((label, sig) {
    final tail = sig.length > 200 ? '${sig.substring(0, 200)}…' : sig;
    buf.writeln('- $label → `$tail`');
  });
  buf.writeln();
  buf.writeln('## Classification');
  analysis.classification.forEach((k, v) {
    buf.writeln('- $k: $v');
  });
  buf.writeln();
  buf.writeln('## Novel signatures');
  if (analysis.novelSignatures.isEmpty) {
    buf.writeln(
        '(none — every probe response matched a known unreserved fingerprint '
        'or generic 0xFD envelope. The reservation differential, if any, '
        'did not unlock new wire shapes on this firmware.)');
  } else {
    buf.writeln(
        'Each entry below is a (status, body) tuple that does NOT appear '
        'in the unreserved baseline or the generic 0xFD error envelope set. '
        'These are the highest-EV leads — inspect each one against the '
        'plc4j sources at `/tmp/bitalias-swarm/plc4j-sources/` and the '
        'C5-A directory decode in LEADS.md before claiming a decoder.');
    buf.writeln();
    final entries = analysis.novelSignatures.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in entries.take(50)) {
      final tail =
          e.key.length > 200 ? '${e.key.substring(0, 200)}…' : e.key;
      buf.writeln('### `$tail`');
      buf.writeln('Probes producing this signature (${e.value.length}):');
      for (final lbl in e.value.take(20)) {
        buf.writeln('- `$lbl`');
      }
      if (e.value.length > 20) {
        buf.writeln('- … ${e.value.length - 20} more (see JSON)');
      }
      buf.writeln();
    }
  }
  buf.writeln();
  buf.writeln('## Total probes: $probeCount');
  buf.writeln();
  buf.writeln('## Source files for follow-up cross-reference');
  buf.writeln('- /tmp/bitalias-swarm/LEADS.md (esp. LEAD-7, LEAD-C5-A)');
  buf.writeln('- /tmp/bitalias-swarm/p2-stuck.md');
  buf.writeln('- /tmp/bitalias-swarm/p2-reserved-null.md');
  buf.writeln('- /tmp/bitalias-swarm/plc4j-sources/');
  buf.writeln('- packages/tfc_dart/lib/core/umas_client.dart');
  buf.writeln(
      '  (`_build0x26Payload`, `takePlcReservation`, `withReservation`)');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// failure record
// ---------------------------------------------------------------------------

class _Failure {
  final String path;
  final UmasVariable variable;
  final UmasDataTypeRef dataType;
  final int errorCode;

  const _Failure(this.path, this.variable, this.dataType, this.errorCode);

  String format() => '$path  '
      'block=0x${variable.blockNo.toRadixString(16)} '
      'off=0x${variable.offset.toRadixString(16)} '
      '${dataType.name} classId=${dataType.classIdentifier} '
      '-> 0x${errorCode.toRadixString(16)}';

  Map<String, Object?> toJson() => {
        'path': path,
        'block': variable.blockNo,
        'offset': variable.offset,
        'dataType': dataType.name,
        'classId': dataType.classIdentifier,
        'errorCode': errorCode,
      };
}
