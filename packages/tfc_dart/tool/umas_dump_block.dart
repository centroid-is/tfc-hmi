/// Dump a single UMAS memory block (READ-ONLY, UNRESERVED).
///
/// Usage: dart run packages/tfc_dart/tool/umas_dump_block.dart \
///   --block 0x60 --bytes 0x4000 [--out /tmp/block.bin]
///
/// SAFETY: read-only. Walks `readMemoryBlock` in 0x200-byte chunks.
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

Future<int> _main(List<String> args) async {
  var block = 0x60;
  var totalBytes = 0x4000;
  var outPath = '';
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--block' && i + 1 < args.length) {
      block = int.parse(args[++i].replaceAll('0x', ''), radix: 16);
    } else if (a == '--bytes' && i + 1 < args.length) {
      totalBytes = int.parse(args[++i].replaceAll('0x', ''), radix: 16);
    } else if (a == '--out' && i + 1 < args.length) {
      outPath = args[++i];
    }
  }
  outPath = outPath.isNotEmpty
      ? outPath
      : '/tmp/named-bit-probe-reserved/block-0x${block.toRadixString(16)}.bin';
  await Directory(File(outPath).parent.path).create(recursive: true);

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
    stderr.writeln('Primed.');
    stderr.writeln('Dumping block=0x${block.toRadixString(16)} '
        'totalBytes=0x${totalBytes.toRadixString(16)} '
        'out=$outPath');

    final buf = BytesBuilder();
    // Try chunk sizes in descending order. Some blocks reject large chunks
    // (return ERR 0x94) but accept smaller. Find the working size per block.
    var chunk = 0x21;
    // Probe largest working chunk
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
      if (pdu[2] == 0xFE) {
        chunk = candidate;
        stderr.writeln('Block 0x${block.toRadixString(16)} accepts '
            'chunk=0x${candidate.toRadixString(16)}');
        break;
      }
    }
    var offset = 0;
    final stop = offset + totalBytes;
    var firstError = '';
    while (offset < stop) {
      final n = (stop - offset) > chunk ? chunk : (stop - offset);
      final payload = ByteData(9);
      payload.setUint8(0, 0);
      payload.setUint16(1, block, Endian.little);
      payload.setUint16(3, offset, Endian.little);
      payload.setUint16(5, 0, Endian.little);
      payload.setUint16(7, n, Endian.little);
      final req = UmasRequest(
        umasSubFunction: UmasSubFunction.readMemoryBlock.code,
        pairingKey: umas.pairingKey,
        payload: payload.buffer.asUint8List(),
        unitId: _unit,
      );
      final code = await tcp.send(req);
      if (code != ModbusResponseCode.requestSucceed) {
        firstError = 'transport @ 0x${offset.toRadixString(16)}';
        break;
      }
      final pdu = req.responsePdu;
      if (pdu == null || pdu.length < 3) {
        firstError = 'short @ 0x${offset.toRadixString(16)}';
        break;
      }
      final status = pdu[2];
      final body = pdu.sublist(3);
      if (status != 0xFE) {
        firstError = 'ERR 0x${(body.isNotEmpty ? body[0] : 0).toRadixString(16)} '
            '@ offset 0x${offset.toRadixString(16)}';
        break;
      }
      // Response: range(1) + numberOfBytes(2 LE) + data
      if (body.length < 3) {
        firstError = 'malformed @ 0x${offset.toRadixString(16)}';
        break;
      }
      final numBytes = body[1] | (body[2] << 8);
      final data = body.sublist(3, 3 + numBytes);
      buf.add(data);
      if (data.length < n) {
        firstError = 'short data (got ${data.length} expected $n) '
            'at offset 0x${offset.toRadixString(16)} — block end';
        break;
      }
      offset += n;
      // polite delay
      if (offset % 0x1000 == 0) {
        await Future.delayed(const Duration(milliseconds: 10));
        stderr.writeln('  ...offset=0x${offset.toRadixString(16)} '
            'accumulated=${buf.length}B');
      }
    }
    final data = buf.takeBytes();
    await File(outPath).writeAsBytes(data);
    stderr.writeln('Wrote ${data.length}B to $outPath');
    if (firstError.isNotEmpty) stderr.writeln('Stopped: $firstError');
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
