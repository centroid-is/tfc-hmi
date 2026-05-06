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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

const _defaultPort = 502;
const _defaultUnit = 255;
const _defaultTimeoutSeconds = 5;

// FB VAR_IN_OUT pointer-backed paths cannot be read by direct memory
// access — the PLC returns 0x94 regardless of client. plc4j's symbol
// resolver also drops them. Categorise them so they don't muddy the
// pass/fail gate.
final _fbInOutRegex = RegExp(r'\.(iq_|io_)');

Future<int> main(List<String> args) async {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addOption('port', defaultsTo: '$_defaultPort')
    ..addOption('unit', defaultsTo: '$_defaultUnit')
    ..addOption('timeout', defaultsTo: '$_defaultTimeoutSeconds')
    ..addOption('elements', defaultsTo: '5')
    ..addFlag('json', defaultsTo: false, negatable: false)
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

  switch (command) {
    case 'browse':
      _need(rest, 1, 'browse <host>');
      return _withClient(rest[0], port, unit, timeout, _browseCommand);
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
      '  dump-array <host> <typeId> Dump raw DD02 bytes for an array type id\n');
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
  await umas.readPlcStatus();
  try {
    return await body(umas);
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// browse — print the full tree
// ---------------------------------------------------------------------------

Future<int> _browseCommand(UmasClient umas) async {
  final tree = await umas.browse();
  final leafCount = _countLeaves(tree);
  print('${tree.length} root(s), $leafCount leaves\n');
  for (final root in tree) {
    _printTree(root, '');
  }
  return 0;
}

void _printTree(UmasVariableTreeNode n, String indent) {
  final type = n.dataType?.name ?? '?';
  final addr = n.variable == null
      ? ''
      : ' [block=0x${n.variable!.blockNo.toRadixString(16)} '
          'off=0x${n.variable!.offset.toRadixString(16)}]';
  print('$indent${n.name}  ($type)$addr');
  for (final c in n.children) {
    _printTree(c, '$indent  ');
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
      print('  ${leaf.path}  ${dt.name} '
          '[block=0x${v.blockNo.toRadixString(16)} '
          'off=0x${v.offset.toRadixString(16)}]  -> '
          '0x${e.errorCode.toRadixString(16)}');
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

  for (final r in roots) {
    walk(r);
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
