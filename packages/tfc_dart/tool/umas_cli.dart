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
///   write  <host> <name> <value>
///                              Write a single value to a named UMAS
///                              variable. The value is parsed according
///                              to the resolved symbol's data type:
///                              BOOL accepts true/false/1/0, integer
///                              types parse as int (with the same
///                              client-side range guard as the live
///                              writer), REAL/LREAL parse as double,
///                              STRING / WSTRING pass through verbatim.
///                              Exits non-zero on any failure.
///   dump-types <host>          Dump every DD03 data-type entry.
///   dump-array <host> <typeId> Print the raw DD02 bytes returned for
///                              an array type id (the
///                              UmasArrayTypeDefinition payload). Useful
///                              when reverse-engineering a new wire
///                              variant.
///   parse-zef <path>           Parse a Schneider EcoStruxure `.ZEF` or
///                              `.XEF` project export and print the
///                              extracted variable + DDT + bit-alias map.
///                              Offline — does not touch the PLC.
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
///   --quiet         `write` only — suppress the resolved-symbol summary
///                   so the command emits a single line on success.
///                   Useful for tight write→read shell loops.
///   --out <path>    `parse-zef` only — write JSON output to <path>.
///                   When omitted, parse-zef prints a human-readable
///                   summary to stdout.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/ecostruxure_zef.dart';
import 'package:tfc_dart/core/umas_bit_alias_map.dart';
import 'package:tfc_dart/core/umas_browse_search.dart';
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
    ..addFlag('json', defaultsTo: false, negatable: false)
    ..addFlag('show-direction', defaultsTo: false, negatable: false)
    ..addFlag('quiet', defaultsTo: false, negatable: false)
    ..addOption('out')
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
  final quiet = parsed['quiet'] as bool;
  final outPath = parsed['out'] as String?;

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
    case 'write':
      _need(rest, 3, 'write <host> <name> <value>');
      return _withClient(rest[0], port, unit, timeout,
          (umas) => _writeCommand(umas, rest[1], rest[2], quiet: quiet));
    case 'dump-types':
      _need(rest, 1, 'dump-types <host>');
      return _withClient(
          rest[0], port, unit, timeout, _dumpTypesCommand);
    case 'dump-array':
      _need(rest, 2, 'dump-array <host> <typeId>');
      final typeId = _parseInt(rest[1]);
      return _withClient(rest[0], port, unit, timeout,
          (umas) => _dumpArrayCommand(umas, typeId));
    case 'bit-aliases':
      _need(rest, 1, 'bit-aliases <host>');
      return _withClient(rest[0], port, unit, timeout,
          (umas) => _bitAliasesCommand(umas, emitJson: emitJson));
    case 'parse-zef':
      _need(rest, 1, 'parse-zef <path>');
      return _parseZefCommand(rest[0], outPath);
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
  stderr.writeln(
      '  write  <host> <name> <value>  Write a single value to a named variable');
  stderr.writeln('  dump-types <host>          Dump every DD03 data type');
  stderr.writeln(
      '  dump-array <host> <typeId> Dump raw DD02 bytes for an array type id');
  stderr.writeln(
      '  bit-aliases <host>         Enumerate every located-bit / bit alias');
  stderr.writeln(
      '  parse-zef  <path>          Parse a .ZEF / .XEF project export\n');
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
  // Accept BOTH leaf-only ("p_CMD_xManFwd") and full dotted-path
  // ("M_F2_RC_01.p_CMD_xManFwd") forms. Bug 2026-05-20: dotted-path
  // queries used to fail silently because the local matcher only
  // compared against `node.name` (leaf segment) and never the path —
  // operators got "Variable not found" for symbols that
  // `readVariableByName` could resolve. See umas_browse_search.dart.
  final node = findUmasNodeByPathOrName(tree, name);
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

// ---------------------------------------------------------------------------
// write — write a single value to a named variable
// ---------------------------------------------------------------------------

/// Write a single value to a named UMAS variable.
///
/// Resolves the symbol via [UmasClient.lookupSymbol], parses [rawValue]
/// per the resolved data type, then issues
/// [UmasClient.writeVariableByName]. Operator-friendly errors are
/// surfaced via [mapUmasError] when the protocol returns a known code.
///
/// `--quiet` suppresses the resolved-symbol summary so the command emits
/// a single OK line on success, suitable for write→read shell loops.
Future<int> _writeCommand(
  UmasClient umas,
  String name,
  String rawValue, {
  bool quiet = false,
}) async {
  // Resolve the symbol first so we can show the operator exactly what
  // we're about to hit and which type we're encoding against. This
  // matters more for write than for read — a typo'd name or wrong type
  // could otherwise drop a value in the wrong PLC address.
  final ResolvedSymbol sym;
  try {
    sym = await umas.lookupSymbol(name);
  } on UmasException catch (e) {
    final info = mapUmasError(e);
    if (info != null) {
      stderr.writeln(info.summary);
      stderr.writeln(info.detail);
    } else {
      stderr.writeln('UMAS lookupSymbol error: ${e.message}');
    }
    return 1;
  }

  final dynamic parsed;
  try {
    parsed = _parseWriteValue(rawValue, sym.dataType);
  } on FormatException catch (e) {
    stderr.writeln('Cannot parse value "$rawValue" for '
        '${sym.path} (${sym.dataType.name}): ${e.message}');
    return 64;
  }

  if (!quiet) {
    print('write ${sym.path}  (${sym.dataType.name}) '
        '[block=0x${sym.variable.blockNo.toRadixString(16)} '
        'off=0x${sym.variable.offset.toRadixString(16)}]  =  $parsed');
  }

  try {
    await umas.writeVariableByName(sym.path, parsed);
  } on UmasException catch (e) {
    // Same operator-friendly mapping path the read command uses.
    final info = mapUmasError(e);
    final codeHex = '0x${e.errorCode.toRadixString(16)}';
    if (info != null) {
      stderr.writeln(info.summary);
      stderr.writeln(info.detail);
    } else if (e.errorCode == 0) {
      // Pure client-side errors (range guard, type mismatch, VAR_IN_OUT
      // refusal) carry the actionable signal in `e.message` rather than
      // a protocol code — surface it verbatim.
      stderr.writeln('write ${sym.path}: ${e.message}');
    } else {
      stderr.writeln('write ${sym.path}: $codeHex  ${e.message}');
    }
    return 1;
  }

  if (quiet) {
    print('ok ${sym.path} = $parsed');
  } else {
    print('ok');
  }
  return 0;
}

/// Parse a CLI-supplied string into the Dart value expected by
/// [encodeVariableValue] for the resolved [dataType].
///
/// Throws [FormatException] for unparseable inputs. The actual range
/// check (e.g. INT [-32768..32767]) is left to [encodeVariableValue] so
/// the CLI surface and the live HMI writer share exactly one guard.
dynamic _parseWriteValue(String raw, UmasDataTypeRef dataType) {
  final upper = dataType.name.toUpperCase();
  switch (upper) {
    case 'BOOL':
    case 'EBOOL':
      switch (raw.toLowerCase()) {
        case 'true':
        case '1':
          return true;
        case 'false':
        case '0':
          return false;
        default:
          throw FormatException(
              'expected true/false/1/0 for $upper, got "$raw"');
      }

    case 'INT':
    case 'UINT':
    case 'WORD':
    case 'DINT':
    case 'UDINT':
    case 'DWORD':
    case 'TIME':
    case 'DATE':
    case 'TIME_OF_DAY':
    case 'DATE_AND_TIME':
    case 'LINT':
    case 'ULINT':
    case 'BYTE':
      final lower = raw.toLowerCase();
      final radix = lower.startsWith('0x') ? 16 : 10;
      final value = int.tryParse(radix == 16 ? lower.substring(2) : raw,
          radix: radix);
      if (value == null) {
        throw FormatException(
            'expected integer (decimal or 0x-prefixed hex) for $upper');
      }
      return value;

    case 'REAL':
    case 'LREAL':
      final value = double.tryParse(raw);
      if (value == null) {
        throw FormatException('expected floating-point value for $upper');
      }
      return value;

    case 'STRING':
    case 'WSTRING':
    case 'BYTE_STRING':
      return raw;

    default:
      // Fall back to integer parsing for unknown types — encodeVariableValue
      // will surface a precise "unknown type" UmasException downstream if
      // the type really isn't supported.
      final asInt = int.tryParse(raw);
      if (asInt != null) return asInt;
      final asDouble = double.tryParse(raw);
      if (asDouble != null) return asDouble;
      return raw;
  }
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

// ---------------------------------------------------------------------------
// bit-aliases — enumerate every located-bit / bit alias on the PLC
// ---------------------------------------------------------------------------

Future<int> _bitAliasesCommand(UmasClient umas,
    {bool emitJson = false}) async {
  final UmasBitAliasMap map;
  try {
    map = await umas.ensureBitAliasMap();
  } on UmasException catch (e) {
    final info = mapUmasError(e);
    if (info != null) {
      stderr.writeln(info.summary);
      stderr.writeln(info.detail);
    } else {
      stderr.writeln('UMAS bit-alias enumeration error: ${e.message}');
    }
    return 1;
  }

  if (emitJson) {
    final out = {
      'count': map.length,
      'entries': [
        for (final e in map.entries)
          {
            'alias': e.aliasName,
            'parent': e.parentVariableName,
            'parentBlock': e.parentBlock,
            'parentByteOffset': e.parentByteOffset,
            'bitOffset': e.bitOffset,
          },
      ],
    };
    print(const JsonEncoder.withIndent('  ').convert(out));
    return 0;
  }

  print('${map.length} bit-alias(es)\n');
  // Header
  print('  alias                                                 '
      'parent                                            '
      '   block  byteOff  bit');
  print('  ${'-' * 116}');
  for (final e in map.entries) {
    final alias = e.aliasName.padRight(52).substring(
        0, e.aliasName.length > 52 ? 52 : e.aliasName.length).padRight(52);
    final parent = (e.parentVariableName ?? '').padRight(48).substring(
        0,
        (e.parentVariableName ?? '').length > 48
            ? 48
            : (e.parentVariableName ?? '').length).padRight(48);
    final block = '0x${e.parentBlock.toRadixString(16).padLeft(4, '0')}';
    final byteOff =
        '0x${e.parentByteOffset.toRadixString(16).padLeft(4, '0')}';
    final bit = e.bitOffset.toString().padLeft(3);
    print('  $alias  $parent  $block   $byteOff   $bit');
  }
  print('');
  // Per-parent summary so the operator can see the array-bound layout.
  final byParent = <String, int>{};
  for (final e in map.entries) {
    final k = e.parentVariableName ?? '?';
    byParent[k] = (byParent[k] ?? 0) + 1;
  }
  if (byParent.isNotEmpty) {
    print('Summary (per parent variable):');
    final keys = byParent.keys.toList()..sort();
    for (final k in keys) {
      print('  $k: ${byParent[k]} bit(s)');
    }
  }
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
// parse-zef — offline .ZEF / .XEF parser
// ---------------------------------------------------------------------------

Future<int> _parseZefCommand(String inputPath, String? outPath) async {
  final f = File(inputPath);
  if (!f.existsSync()) {
    stderr.writeln('parse-zef: file not found: $inputPath');
    return 1;
  }

  final ZefProject project;
  try {
    if (inputPath.toLowerCase().endsWith('.xef')) {
      project = parseXef(f.readAsStringSync());
    } else {
      // Default to .zef (ZIP) for anything else. parseZef will also
      // fall back to picking up `.xml` entries inside the archive.
      project = parseZef(f);
    }
  } on FormatException catch (e) {
    stderr.writeln('parse-zef: ${e.message}');
    return 1;
  } catch (e) {
    stderr.writeln('parse-zef: unexpected error: $e');
    return 1;
  }

  final aliases = project.resolveBitAliases();

  if (outPath != null) {
    final json = const JsonEncoder.withIndent('  ').convert({
      'project': project.toJson(),
      'resolvedBitAliases': aliases.map((a) => a.toJson()).toList(),
    });
    File(outPath).writeAsStringSync(json);
    print('parse-zef: wrote ${project.variables.length} variable(s), '
        '${project.ddts.length} DDT(s), ${aliases.length} resolved bit '
        'alias(es) → $outPath');
  } else {
    print('Variables: ${project.variables.length}');
    for (final v in project.variables.values) {
      final addr = v.rawAddress ?? '<unlocated>';
      final type = v.typeName ?? '<no type>';
      print('  ${v.name}  $type  $addr');
    }
    print('\nDDTs: ${project.ddts.length}');
    for (final d in project.ddts) {
      print('  ${d.name}  (${d.members.length} member(s))');
      for (final m in d.members) {
        final bitInfo = m.bitOffset != null
            ? '  ← bit ${m.bitOffset} of ${m.parentMemberName}'
            : '';
        print('    ${m.name}  ${m.typeName ?? '<no type>'}$bitInfo');
      }
    }
    print('\nResolved bit aliases: ${aliases.length}');
    for (final a in aliases) {
      print('  ${a.aliasFullName}  '
          '→ parent=${a.parentVariableName}.${a.parentMemberName}  '
          'bit=${a.bitOffset}  '
          'addr=${a.parentRawAddress ?? '<unlocated>'}');
    }
  }

  return 0;
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
