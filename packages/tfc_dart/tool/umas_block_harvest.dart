/// Harvest every accessible memory block (READ-ONLY, UNRESERVED).
///
/// Sweeps blocks 0..0x300 with adaptive chunk size, writes each non-empty
/// block to /tmp/named-bit-probe-reserved/harvest/block-0xNN.bin.
///
/// SAFETY: read-only.
library;

// ignore_for_file: invalid_use_of_visible_for_testing_member

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
const _outDir = '/tmp/named-bit-probe-reserved/harvest';

Future<int> _main(List<String> args) async {
  final fromArg = args.isNotEmpty ? args[0] : '0';
  final toArg = args.length >= 2 ? args[1] : '0x300';
  final from = int.parse(fromArg.replaceAll('0x', ''), radix: 16);
  final to = int.parse(toArg.replaceAll('0x', ''), radix: 16);
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
    stderr.writeln('Primed. Harvesting blocks 0x${from.toRadixString(16)}'
        '..0x${to.toRadixString(16)}.');

    Future<int> probeChunk(int block) async {
      for (final candidate in [0x200, 0x100, 0x80, 0x40, 0x21, 0x10, 0x08, 0x01]) {
        final payload = ByteData(9);
        payload.setUint8(0, 0);
        payload.setUint16(1, block, Endian.little);
        payload.setUint16(3, 0, Endian.little);
        payload.setUint16(5, 0, Endian.little);
        payload.setUint16(7, candidate, Endian.little);
        final req = UmasRequest(
          umasSubFunction: UmasSubFunction.readMemoryBlock.code,
          pairingKey: umas.pairingKey,
          payload: payload.buffer.asUint8List(),
          unitId: _unit,
        );
        final code = await tcp.send(req);
        if (code != ModbusResponseCode.requestSucceed) continue;
        final pdu = req.responsePdu;
        if (pdu == null || pdu.length < 4) continue;
        if (pdu[2] == 0xFE) return candidate;
      }
      return 0;
    }

    Future<int> dumpBlock(int block, int chunk) async {
      final buf = BytesBuilder();
      var offset = 0;
      while (true) {
        final payload = ByteData(9);
        payload.setUint8(0, 0);
        payload.setUint16(1, block, Endian.little);
        payload.setUint16(3, offset, Endian.little);
        payload.setUint16(5, 0, Endian.little);
        payload.setUint16(7, chunk, Endian.little);
        final req = UmasRequest(
          umasSubFunction: UmasSubFunction.readMemoryBlock.code,
          pairingKey: umas.pairingKey,
          payload: payload.buffer.asUint8List(),
          unitId: _unit,
        );
        final code = await tcp.send(req);
        if (code != ModbusResponseCode.requestSucceed) break;
        final pdu = req.responsePdu;
        if (pdu == null || pdu.length < 4) break;
        if (pdu[2] != 0xFE) break;
        final body = pdu.sublist(3);
        if (body.length < 3) break;
        final numBytes = body[1] | (body[2] << 8);
        if (body.length < 3 + numBytes) break;
        final data = body.sublist(3, 3 + numBytes);
        buf.add(data);
        if (data.length < chunk) break;
        offset += chunk;
        if (buf.length > 0x80000) break; // 512KB cap per block
      }
      final out = buf.takeBytes();
      if (out.isNotEmpty) {
        await File('$_outDir/block-0x${block.toRadixString(16)}.bin')
            .writeAsBytes(out);
      }
      return out.length;
    }

    final summary = StringBuffer();
    summary.writeln('# Block harvest summary\n');
    summary.writeln('| block | chunk | total | first16 |');
    summary.writeln('|------:|-----:|------:|---------|');

    var hits = 0;
    var totalBytes = 0;
    for (var b = from; b <= to; b++) {
      final chunk = await probeChunk(b);
      if (chunk == 0) continue;
      final n = await dumpBlock(b, chunk);
      if (n == 0) continue;
      hits++;
      totalBytes += n;
      final f = File('$_outDir/block-0x${b.toRadixString(16)}.bin');
      final bytes = await f.readAsBytes();
      final first = bytes.sublist(0, bytes.length < 16 ? bytes.length : 16);
      summary.writeln('| 0x${b.toRadixString(16).padLeft(4, '0')} | '
          '0x${chunk.toRadixString(16)} | $n | '
          '`${first.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ')}` |');
      if (hits % 10 == 0) {
        stderr.writeln('  ...$hits blocks dumped, ${totalBytes}B total');
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }

    summary.writeln('\nHits: $hits, total bytes: $totalBytes\n');
    await File('$_outDir/SUMMARY.md').writeAsString(summary.toString());
    stderr.writeln('Harvest complete: $hits blocks, $totalBytes bytes.');
    return 0;
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
  }
}

Future<void> main(List<String> args) async {
  exit(await _main(args));
}
