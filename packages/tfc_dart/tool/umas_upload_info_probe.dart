/// Probe candidate opcodes that may implement "Upload Info" — the
/// EcoStruxure operation that fetches FB type definitions including
/// VAR_PUBLIC bit aliases like `p_Stat_xFault := Status.0`.
///
/// Targets:
///   - 0x37 (zaltzman: untouched)
///   - 0x39, 0x3A, 0x3B (gap after 0x33-0x38)
///   - 0x46, 0x48, 0x49
///   - 0x57 (info family)
///   - 0x6A..0x6F (sweep)
///   - 0x3C..0x40 (sweep)
///
/// Each opcode is tested with multiple payload shapes:
///   - empty
///   - 1-byte sub-selector (0x00, 0x01, 0x02, 0xff)
///   - DD trailer with project hwId
///   - DD trailer with FB type idx (0, 1, 2, 0x7d)
///
/// Output: /tmp/bit-alias-final/upload-info/
library;

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';

const _host = '192.168.112.159';
const _port = 502;
const _unit = 255;
const _outDir = '/tmp/bit-alias-final/upload-info';

final _targetOpcodes = <int>[
  0x37, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, // gap after 0x33-0x38
  0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, // upper-40s
  0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, // lower-40s wrap
  0x57, // info family hint from task
  0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, // 60s
];

class _ProbeResult {
  final int status;
  final Uint8List body;
  _ProbeResult(this.status, this.body);
}

Future<_ProbeResult> _sendRaw(
  ModbusClientTcp tcp,
  UmasClient umas,
  int opcode, {
  required Uint8List payload,
}) async {
  final req = UmasRequest(
    umasSubFunction: opcode,
    pairingKey: umas.pairingKey,
    payload: payload,
    unitId: _unit,
  );
  final code = await tcp.send(req);
  if (code != ModbusResponseCode.requestSucceed) {
    return _ProbeResult(-1, Uint8List(0));
  }
  final pdu = req.responsePdu;
  if (pdu == null || pdu.length < 3) {
    return _ProbeResult(-1, Uint8List(0));
  }
  await Future.delayed(const Duration(milliseconds: 25));
  return _ProbeResult(pdu[2], pdu.sublist(3));
}

String _hex(Uint8List b, int maxLen) {
  final n = b.length < maxLen ? b.length : maxLen;
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    if (i > 0) sb.write(' ');
    sb.write(b[i].toRadixString(16).padLeft(2, '0'));
  }
  if (b.length > maxLen) sb.write('...');
  return sb.toString();
}

String _ascii(Uint8List b, int maxLen) {
  final n = b.length < maxLen ? b.length : maxLen;
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    sb.write((b[i] >= 0x20 && b[i] < 0x7f) ? String.fromCharCode(b[i]) : '.');
  }
  return sb.toString();
}

Future<int> _main(List<String> args) async {
  await Directory(_outDir).create(recursive: true);
  final out = File('$_outDir/upload_info_probe.md').openWrite();
  out.writeln('# UMAS Upload-Info opcode probe — ${DateTime.now().toIso8601String()}\n');

  final tcp = ModbusClientTcp(
    _host,
    serverPort: _port,
    unitId: _unit,
    connectionMode: ModbusConnectionMode.doNotConnect,
    connectionTimeout: const Duration(seconds: 5),
  );
  await tcp.connect();
  final umas = UmasClient(sendFn: tcp.send, unitId: _unit);

  try {
    await umas.readPlcStatus();
    out.writeln('Primed. pairingKey=0x${umas.pairingKey.toRadixString(16)}\n');

    // Get project hwId (from descriptor — try 0x07 for section 0x01)
    final p07 = Uint8List(8);
    p07[1] = 0x01; // section 0x01
    ByteData.sublistView(p07).setUint16(6, 0x40, Endian.little);
    final r07 = await _sendRaw(tcp, umas, 0x07, payload: p07);
    Uint8List? projectHwId;
    if (r07.status == 0xFE && r07.body.length >= 16) {
      // hwId is usually 8 bytes inside the descriptor
      projectHwId = r07.body.sublist(6, 14);
      out.writeln('Project hwId (from sec-0x01 descriptor): `${_hex(projectHwId, 8)}`\n');
    }

    final payloadShapes = <String, Uint8List>{
      'empty': Uint8List(0),
      'sel=0x00': Uint8List.fromList([0x00]),
      'sel=0x01': Uint8List.fromList([0x01]),
      'sel=0x02': Uint8List.fromList([0x02]),
      'sel=0xff': Uint8List.fromList([0xff]),
      'DD typId=0 idx=0': Uint8List.fromList([0x00, 0xdd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      'DD typId=1 idx=0': Uint8List.fromList([0x00, 0xdd, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      'DD typId=7d idx=0': Uint8List.fromList([0x00, 0xdd, 0x00, 0x7d, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      'DD typId=ce idx=0': Uint8List.fromList([0x00, 0xdd, 0x00, 0xce, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
      'idx=0 LE 4B': Uint8List.fromList([0x00, 0x00, 0x00, 0x00]),
      'idx=1 LE 4B': Uint8List.fromList([0x01, 0x00, 0x00, 0x00]),
      'idx=ce LE 4B': Uint8List.fromList([0xce, 0x00, 0x00, 0x00]),
    };
    if (projectHwId != null) {
      // hwId-only
      payloadShapes['hwId only'] = projectHwId;
      // hwId + idx=0
      final hi = BytesBuilder();
      hi.add(projectHwId);
      hi.add([0x00, 0x00]);
      payloadShapes['hwId + idx=0'] = hi.takeBytes();
    }

    for (final op in _targetOpcodes) {
      out.writeln('## opcode 0x${op.toRadixString(16).padLeft(2, '0')}\n');
      out.writeln('| shape | status | err | len | body[0..32] | ascii |');
      out.writeln('|-------|-------:|----:|----:|-------------|-------|');
      var anyInteresting = false;
      for (final entry in payloadShapes.entries) {
        final r = await _sendRaw(tcp, umas, op, payload: entry.value);
        final status = r.status;
        final err = (status == 0xFD && r.body.isNotEmpty) ? r.body[0] : 0;
        final hex = _hex(r.body, 32);
        final ascii = _ascii(r.body, 32);
        final interesting = status == 0xFE && r.body.length > 4;
        if (interesting) anyInteresting = true;
        // Filter out the boring 0x86/0x83/0x88 errors to keep the report short
        if (!interesting && err != 0x86 && err != 0x83 && err != 0x88 && err != 0x90 && err != 0xff) {
          out.writeln('| ${entry.key} | 0x${status.toRadixString(16)} | '
              '0x${err.toRadixString(16)} | ${r.body.length} | `$hex` | `$ascii` |');
        } else if (interesting) {
          out.writeln('| ${entry.key} | **0x${status.toRadixString(16)}** | '
              '0x${err.toRadixString(16)} | **${r.body.length}** | `$hex` | `$ascii` |');
          // Save the body
          final fname = '$_outDir/op${op.toRadixString(16).padLeft(2, '0')}-${entry.key.replaceAll(' ', '_').replaceAll('=', '').replaceAll('+', '_')}.bin';
          await File(fname).writeAsBytes(r.body);
        }
      }
      out.writeln('');
      if (anyInteresting) {
        stderr.writeln('opcode 0x${op.toRadixString(16)}: HIT(s) found');
      }
    }

    return 0;
  } catch (e, st) {
    stderr.writeln('FATAL: $e\n$st');
    return 2;
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
    await out.close();
  }
}

Future<void> main(List<String> args) async {
  exit(await _main(args));
}
