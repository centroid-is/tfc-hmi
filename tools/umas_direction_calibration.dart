/// UMAS direction-classifier calibration harness.
///
/// One-off reverse-engineering tool: connects to a live Schneider PLC,
/// enumerates every FB member visible in the data dictionary, classifies
/// each member's expected direction from its Schneider naming convention
/// (`i_` / `q_` / `p_` / `iq_` / `io_`), captures the raw DD02 record
/// header bytes (specifically the two opaque uint16 fields `unknown5` and
/// `unknown4` at positions 4-5 and 6-7), and prints a truth table.
///
/// Names are the GROUND-TRUTH ORACLE; bytes are the SIGNAL we want to
/// learn. The production classifier in
/// `packages/tfc_dart/lib/core/umas_fb_direction.dart` runs on bytes
/// alone. This harness verifies the byte mapping shipped in production
/// against the naming convention used in the user's PLC, and surfaces
/// any disagreement so a wrong table is caught before it ships.
///
/// Usage:
///   dart run tools/umas_direction_calibration.dart <host>
///       [--port N] [--unit N] [--timeout S]
///
/// Output: a per-direction summary plus a row-per-member dump showing
/// (FB type, member name, unknown5, unknown4, name-oracle direction,
/// current byte-classifier direction, agreement flag).
///
/// This file lives at tools/ (not packages/tfc_dart/tool/) because it
/// is a one-off harness for the v1.1 hardening milestone, not a
/// shipping CLI.
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_fb_direction.dart';
import 'package:tfc_dart/core/umas_types.dart';

const _defaultPort = 502;
const _defaultUnit = 255;
const _defaultTimeoutSeconds = 5;

// Schneider IEC 61131-3 naming convention used by the user's PLC code.
// The PREFIX is parsed off the leading underscore-suffixed token. The
// classifier is name-INDEPENDENT in production; this is only for the
// calibration harness to compare against.
UmasFbMemberDirection _directionFromName(String memberName) {
  final lower = memberName.toLowerCase();
  if (lower.startsWith('iq_') || lower.startsWith('io_')) {
    return UmasFbMemberDirection.inOut;
  }
  if (lower.startsWith('i_')) return UmasFbMemberDirection.input;
  if (lower.startsWith('q_')) return UmasFbMemberDirection.output;
  if (lower.startsWith('p_')) return UmasFbMemberDirection.publicVar;
  return UmasFbMemberDirection.unknown;
}

class _MemberSample {
  final String fbTypeName;
  final int fbTypeId;
  final String memberName;
  final int unknown5;
  final int unknown4;
  final UmasFbMemberDirection nameOracle;
  final UmasFbMemberDirection byteClassifier;

  _MemberSample({
    required this.fbTypeName,
    required this.fbTypeId,
    required this.memberName,
    required this.unknown5,
    required this.unknown4,
    required this.nameOracle,
    required this.byteClassifier,
  });

  bool get nameHasConvention =>
      nameOracle != UmasFbMemberDirection.unknown;
  bool get agrees => nameOracle == byteClassifier;
}

Future<int> _main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', defaultsTo: '$_defaultPort')
    ..addOption('unit', defaultsTo: '$_defaultUnit')
    ..addOption('timeout', defaultsTo: '$_defaultTimeoutSeconds')
    ..addFlag('json', defaultsTo: false, negatable: false)
    ..addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
  final parsed = parser.parse(args);
  if (parsed['help'] as bool || parsed.rest.isEmpty) {
    stderr.writeln(
        'Usage: dart run tools/umas_direction_calibration.dart <host> [opts]');
    stderr.writeln(parser.usage);
    return 64;
  }
  final host = parsed.rest.first;
  final port = int.parse(parsed['port'] as String);
  final unit = int.parse(parsed['unit'] as String);
  final timeout =
      Duration(seconds: int.parse(parsed['timeout'] as String));

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
    final tree = await umas.browse();
    final dataTypes = await umas.readDataTypes();

    // Walk the tree exhaustively. For the calibration we want every
    // variable whose type appears to be a struct/FB so we can fetch the
    // member-layout bytes — that's classId==2 (struct) OR ==7 (FB) OR
    // the speculative-resolved synthetic "FB" name (byteSize=0). We
    // also walk children that are nodes WITH children themselves: the
    // tree-builder won't have given them member-records, but it has
    // already resolved them — we just want the type id.
    final fbTypeIds = <int, String>{};
    void walk(dynamic node) {
      final dt = node.dataType;
      if (dt != null) {
        final cls = dt.classIdentifier;
        if ((cls == 2 || cls == 7) && node.variable != null) {
          final id = node.variable!.dataTypeId;
          if (id != 0) {
            fbTypeIds[id] = dt.name == '?' || dt.name.isEmpty
                ? 'typeId=0x${id.toRadixString(16)}'
                : dt.name;
          }
        }
      }
      for (final c in node.children) {
        walk(c);
      }
    }

    for (final r in tree) {
      walk(r);
    }
    stderr.writeln(
        '[calibration] found ${fbTypeIds.length} distinct FB/struct type id(s) in tree');

    // For each FB type, fetch the raw DD02 member-layout bytes via
    // readDD02Raw (block=typeId). Walk the records to extract
    // (memberName, unknown5, unknown4) per member. The wire layout for
    // member-layout records is documented in
    // packages/tfc_dart/lib/core/umas_client.dart:737 (_parseVariableRecords):
    //   header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE) = 7 bytes
    //   per member record (8-byte header + null-terminated name):
    //     dataType(2 LE) + block(2 LE) + unknown5(2 LE) + unknown4(2 LE)
    //     + name\0
    final samples = <_MemberSample>[];
    for (final entry in fbTypeIds.entries) {
      final typeId = entry.key;
      final typeName = entry.value;
      Uint8List raw;
      try {
        raw = await umas.readDD02Raw(typeId);
      } catch (e) {
        stderr.writeln('[calibration] skip FB typeId=0x${typeId.toRadixString(16)} '
            '($typeName): readDD02Raw failed — $e');
        continue;
      }
      if (raw.length < 7) {
        stderr.writeln('[calibration] skip FB typeId=0x${typeId.toRadixString(16)} '
            '($typeName): raw response too short (${raw.length} bytes)');
        continue;
      }
      final hd = ByteData.sublistView(raw);
      final noOfRecords = hd.getUint16(5, Endian.little);
      int pos = 7;
      const headerSize = 8;
      for (int i = 0; i < noOfRecords && pos + headerSize <= raw.length; i++) {
        final view = ByteData.sublistView(raw, pos);
        // dataType=getUint16(0), block=getUint16(2), unknown5=getUint16(4),
        // unknown4=getUint16(6). Production reads bytes 4-7 also as a single
        // uint32 `offset` — for direction we look at them as two halves.
        final unknown5 = view.getUint16(4, Endian.little);
        final unknown4 = view.getUint16(6, Endian.little);
        pos += headerSize;
        int end = pos;
        while (end < raw.length && raw[end] != 0x00) {
          end++;
        }
        if (end >= raw.length) break;
        final name = String.fromCharCodes(raw.sublist(pos, end));
        pos = end + 1;
        if (name.isEmpty) continue;
        samples.add(_MemberSample(
          fbTypeName: typeName,
          fbTypeId: typeId,
          memberName: name,
          unknown5: unknown5,
          unknown4: unknown4,
          nameOracle: _directionFromName(name),
          byteClassifier: classifyFbMemberDirection(unknown5, unknown4),
        ));
      }
    }

    stderr.writeln('[calibration] collected ${samples.length} FB-member sample(s)');

    // ─── Per-direction byte-pattern histogram ──────────────────────────
    final histogramByName = <UmasFbMemberDirection, Map<String, int>>{};
    for (final s in samples) {
      if (!s.nameHasConvention) continue;
      final key = '0x${s.unknown5.toRadixString(16).padLeft(4, '0')}'
          ',0x${s.unknown4.toRadixString(16).padLeft(4, '0')}';
      histogramByName
          .putIfAbsent(s.nameOracle, () => <String, int>{})
          .update(key, (v) => v + 1, ifAbsent: () => 1);
    }

    print('\n=== Byte pattern histogram, keyed by NAME-ORACLE direction ===');
    for (final dir in [
      UmasFbMemberDirection.input,
      UmasFbMemberDirection.output,
      UmasFbMemberDirection.inOut,
      UmasFbMemberDirection.publicVar,
    ]) {
      final h = histogramByName[dir];
      print('\n  ${dir.name.toUpperCase()} (oracle ${dir.name}):');
      if (h == null || h.isEmpty) {
        print('    (no samples)');
        continue;
      }
      final entries = h.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        print('    ${e.key.padRight(20)} ${e.value.toString().padLeft(4)} sample(s)');
      }
    }

    // ─── Agreement matrix ──────────────────────────────────────────────
    final agreement = <(UmasFbMemberDirection, UmasFbMemberDirection), int>{};
    for (final s in samples) {
      if (!s.nameHasConvention) continue;
      agreement.update((s.nameOracle, s.byteClassifier), (v) => v + 1,
          ifAbsent: () => 1);
    }
    print('\n=== Agreement matrix: oracle (name) → byte classifier output ===');
    for (final entry in agreement.entries) {
      final flag = entry.key.$1 == entry.key.$2 ? 'OK ' : 'MISMATCH';
      print('  $flag  ${entry.key.$1.name.padRight(10)} -> '
          '${entry.key.$2.name.padRight(10)}  ${entry.value} sample(s)');
    }

    // ─── Per-sample dump (truncated for readability) ───────────────────
    print('\n=== Sample table (first 30 mismatches, then 10 agreements) ===');
    final mismatches = samples
        .where((s) => s.nameHasConvention && !s.agrees)
        .toList();
    final agreements = samples
        .where((s) => s.nameHasConvention && s.agrees)
        .toList();
    print('  total mismatches: ${mismatches.length}');
    print('  total agreements: ${agreements.length}');
    for (final s in mismatches.take(30)) {
      print('  MISMATCH ${s.fbTypeName.padRight(20)} '
          '${s.memberName.padRight(28)} '
          'unk5=0x${s.unknown5.toRadixString(16).padLeft(4, '0')} '
          'unk4=0x${s.unknown4.toRadixString(16).padLeft(4, '0')} '
          'name=${s.nameOracle.name.padRight(10)} '
          'bytes=${s.byteClassifier.name}');
    }
    for (final s in agreements.take(10)) {
      print('  OK       ${s.fbTypeName.padRight(20)} '
          '${s.memberName.padRight(28)} '
          'unk5=0x${s.unknown5.toRadixString(16).padLeft(4, '0')} '
          'unk4=0x${s.unknown4.toRadixString(16).padLeft(4, '0')} '
          'name=${s.nameOracle.name.padRight(10)} '
          'bytes=${s.byteClassifier.name}');
    }

    // ─── No-convention samples (informational) ────────────────────────
    final noConv = samples.where((s) => !s.nameHasConvention).toList();
    print('\n=== Members without naming-convention prefix '
        '(name-oracle = unknown, informational) ===');
    print('  count: ${noConv.length}');
    final noConvHistogram = <String, int>{};
    for (final s in noConv) {
      final key = '0x${s.unknown5.toRadixString(16).padLeft(4, '0')}'
          ',0x${s.unknown4.toRadixString(16).padLeft(4, '0')}';
      noConvHistogram.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    final noConvEntries = noConvHistogram.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in noConvEntries.take(20)) {
      print('    ${e.key.padRight(20)} ${e.value.toString().padLeft(4)} sample(s)');
    }

    // Show names without convention for context
    print('\n  Sample names without convention (first 20):');
    for (final s in noConv.take(20)) {
      print('    ${s.fbTypeName.padRight(20)} '
          '${s.memberName.padRight(28)} '
          'unk5=0x${s.unknown5.toRadixString(16).padLeft(4, '0')} '
          'unk4=0x${s.unknown4.toRadixString(16).padLeft(4, '0')}');
    }
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
  }
  return 0;
}

Future<void> main(List<String> args) async {
  // Explicit exit() because the modbus client keeps a heartbeat alive
  // post-disconnect; mirrors umas_cli.dart's pattern.
  final code = await _main(args);
  exit(code);
}
