/// Sweep readProjectInfo (sub-function 0x03) subcodes 0x00..0xFF.
/// Hypothesis: an undocumented subcode returns the symbol/comment/alias
/// table containing named-bit-of-WORD aliases.
///
/// Also tries readMemoryBlock for various blockNumber values not in our
/// known set (we know 0x30=project, but there may be a symbol-table block).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

const _host = '192.168.112.159';
const _port = 502;
const _unit = 255;
const _outDir = '/tmp/named-bit-probe-v2/jb-probe';

Future<void> main(List<String> args) async {
  await Directory(_outDir).create(recursive: true);
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
    stderr.writeln('Session primed: pairingKey=0x'
        '${umas.pairingKey.toRadixString(16).padLeft(2, '0')}');

    final f = File('$_outDir/phaseE-project-info.md').openWrite();
    f.writeln('# Phase E — readProjectInfo subcode sweep + readMemoryBlock\n');

    // Phase E1: readProjectInfo subcode 0x00..0xFF
    f.writeln('## readProjectInfo subcode sweep (sub-function 0x03)\n');
    f.writeln('| subcode | status | len | first48 | ASCII (printable) |');
    f.writeln('|--------:|--------|----:|---------|--------------------|');
    final hits = <int, Uint8List>{};
    for (var sc = 0; sc <= 0xFF; sc++) {
      final request = UmasRequest(
        umasSubFunction: 0x03,
        pairingKey: umas.pairingKey,
        payload: Uint8List.fromList([sc]),
        unitId: _unit,
      );
      try {
        final code = await tcp.send(request);
        if (code != ModbusResponseCode.requestSucceed) {
          continue;
        }
        final pdu = request.responsePdu;
        if (pdu == null || pdu.length < 3) continue;
        final status = pdu[2];
        final body = pdu.sublist(3);
        if (status == 0xFE && body.length > 1) {
          // Show every reply that is non-trivial.
          final hex = _hex(body, 48);
          final asc = _ascii(body, 64);
          f.writeln('| 0x${sc.toRadixString(16).padLeft(2, '0')} | OK | '
              '${body.length} | `$hex` | `$asc` |');
          hits[sc] = body;
        } else if (status == 0xFD && body.isNotEmpty) {
          // Errors are less interesting but log if errcode varies.
          if (body[0] != 0x86 && body[0] != 0x83 && body[0] != 0x88) {
            f.writeln('| 0x${sc.toRadixString(16).padLeft(2, '0')} | '
                'ERR 0x${body[0].toRadixString(16)} | ${body.length} | '
                '`${_hex(body, 16)}` | |');
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 15));
    }
    f.writeln('\n${hits.length} distinct subcodes returned OK.');

    // Phase E2: For each successful subcode that returned something large
    // (>50 bytes), dump the full payload for closer inspection.
    f.writeln('\n## Full payload dumps of large readProjectInfo replies\n');
    for (final entry in hits.entries) {
      if (entry.value.length < 50) continue;
      f.writeln('### subcode=0x${entry.key.toRadixString(16).padLeft(2, '0')} '
          '(${entry.value.length} bytes)\n');
      f.writeln('```');
      _hexdump(f, entry.value);
      f.writeln('```\n');
    }

    // Phase E3: readMemoryBlock sweep for unknown block IDs.
    // Known: 0x30=project. Try 0x00..0x40, 0x100..0x110, 0x200..0x210, etc.
    f.writeln('\n## readMemoryBlock sweep\n');
    f.writeln('Hypothesis: an unenumerated memory block contains the symbol '
        'table or comment/alias table.\n');
    f.writeln('| block | offset | nBytes | status | len | first32 |');
    f.writeln('|------:|------:|------:|--------|----:|---------|');
    final memBlocks = <int>[
      // Known good
      0x0030,
      // Sweep around the known block
      0x0000, 0x0001, 0x0002, 0x0008, 0x0010, 0x0020,
      0x0031, 0x0032, 0x0033, 0x0034, 0x0040, 0x0050, 0x0060,
      0x0080, 0x0100, 0x0200, 0x0300, 0x0400, 0x0500, 0x0600,
      0x0800, 0x0a00, 0x0c00,
      // The wireshark-published "symbol table" base for M340
      0x1000, 0x1100, 0x1200,
      // 0xab..0xb2 are the actual blocks containing our FB instances!
      0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4,
    ];
    for (final block in memBlocks) {
      // Build readMemoryBlock payload: range(1) + blockNumber(2 LE) +
      // offset(2 LE) + numberOfBytes(2 LE) = 7 bytes
      final bd = ByteData(7);
      bd.setUint8(0, 0);
      bd.setUint16(1, block, Endian.little);
      bd.setUint16(3, 0, Endian.little);
      bd.setUint16(5, 0x40, Endian.little);
      final request = UmasRequest(
        umasSubFunction: 0x20,
        pairingKey: umas.pairingKey,
        payload: bd.buffer.asUint8List(),
        unitId: _unit,
      );
      try {
        final code = await tcp.send(request);
        if (code != ModbusResponseCode.requestSucceed) continue;
        final pdu = request.responsePdu;
        if (pdu == null || pdu.length < 3) continue;
        final status = pdu[2];
        final body = pdu.sublist(3);
        final classify = status == 0xFE
            ? 'OK'
            : (status == 0xFD ? 'ERR 0x${body[0].toRadixString(16)}' : '?');
        f.writeln('| 0x${block.toRadixString(16).padLeft(4, '0')} | 0x0 | '
            '0x40 | $classify | ${body.length} | `${_hex(body, 32)}` |');
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 15));
    }

    await f.flush();
    await f.close();
    stderr.writeln('Phase E complete.');
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
  }
}

String _hex(Uint8List b, int max) {
  final n = b.length < max ? b.length : max;
  return [
    for (var i = 0; i < n; i++) b[i].toRadixString(16).padLeft(2, '0')
  ].join(' ');
}

String _ascii(Uint8List b, int max) {
  final n = b.length < max ? b.length : max;
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    final v = b[i];
    sb.write((v >= 0x20 && v < 0x7f) ? String.fromCharCode(v) : '.');
  }
  return sb.toString();
}

void _hexdump(IOSink sink, Uint8List b) {
  for (var i = 0; i < b.length; i += 16) {
    final end = (i + 16 < b.length) ? i + 16 : b.length;
    final hex = b
        .sublist(i, end)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    final asc = String.fromCharCodes(b.sublist(i, end).map(
        (v) => (v >= 0x20 && v < 0x7f) ? v : 0x2e));
    sink.writeln('${i.toRadixString(16).padLeft(4, '0')}  '
        '${hex.padRight(48)}  $asc');
  }
}
