/// readMemoryBlock parametric probe (READ-ONLY, UNRESERVED).
///
/// Hypothesis: prior probes always sent `numberOfBytes=0x40` and got
/// `ERR 0x88` on every block — but the internal `_readProjectBlock`
/// succeeds with `numberOfBytes=0x21` on block 0x0030. So the rejection
/// might be a byte-count cap, not a reservation gate.
///
/// Also tries the `range` byte at multiple values — `_readProjectBlock`
/// uses range=0x00 but the PLC4X mspec hints at other range values.
///
/// SAFETY: read-only. No reservation required, no writes.
///
/// Output: /tmp/named-bit-probe-reserved/phaseA0-readmemblock-unreserved.md
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
const _outDir = '/tmp/named-bit-probe-reserved';

Future<int> _main(List<String> args) async {
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
    final hwId = umas.projectHardwareId;
    if (hwId == null) {
      stderr.writeln('FATAL: hwId null');
      return 2;
    }
    stderr.writeln('Primed: hwId=0x${hwId.toRadixString(16)}');

    final file = File('$_outDir/phaseA0-readmemblock-unreserved.md');
    final sink = file.openWrite();
    sink.writeln('# Phase A0 — readMemoryBlock parametric, UNRESERVED\n');
    sink.writeln('Vary numberOfBytes (prior probes only used 0x40). Vary '
        'range. Try blocks of interest.\n');

    Future<String> probe(int range, int block, int offset, int nBytes) async {
      final payload = ByteData(9);
      payload.setUint8(0, range & 0xFF);
      payload.setUint16(1, block, Endian.little);
      payload.setUint16(3, offset, Endian.little);
      payload.setUint16(5, 0x0000, Endian.little);
      payload.setUint16(7, nBytes, Endian.little);
      final req = UmasRequest(
        umasSubFunction: UmasSubFunction.readMemoryBlock.code,
        pairingKey: umas.pairingKey,
        payload: payload.buffer.asUint8List(),
        unitId: _unit,
      );
      final code = await tcp.send(req);
      if (code != ModbusResponseCode.requestSucceed) {
        return 'transport-fail(${code.name})';
      }
      final pdu = req.responsePdu;
      if (pdu == null || pdu.length < 3) return 'short';
      final status = pdu[2];
      final body = pdu.sublist(3);
      if (status == 0xFE) {
        return 'OK ${body.length}B '
            '`${body.sublist(0, body.length < 32 ? body.length : 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}`';
      }
      final errByte = body.isNotEmpty ? body[0] : 0;
      return 'ERR 0x${errByte.toRadixString(16).padLeft(2, '0')}';
    }

    // Step 1: confirm canonical read works (range=0, block=0x30, off=0, n=0x21)
    sink.writeln('## Step 1: confirm canonical project-block read\n');
    sink.writeln('  block=0x30 n=0x21 → ${await probe(0, 0x0030, 0, 0x21)}\n');

    // Step 2: vary numberOfBytes on block 0x30 (which is known to be accessible)
    sink.writeln('\n## Step 2: vary nBytes on block 0x30\n');
    sink.writeln('| n | result |');
    sink.writeln('|---|--------|');
    for (final n in [
      0x01, 0x10, 0x20, 0x21, 0x22, 0x30, 0x40, 0x50, 0x80, 0x100, 0x200, 0xFFFF
    ]) {
      sink.writeln('| 0x${n.toRadixString(16)} | ${await probe(0, 0x0030, 0, n)} |');
      await Future.delayed(const Duration(milliseconds: 15));
    }

    // Step 3: vary range on block 0x30
    sink.writeln('\n## Step 3: vary range on block 0x30, n=0x21\n');
    sink.writeln('| range | result |');
    sink.writeln('|------:|--------|');
    for (final r in [0, 1, 2, 3, 4, 8, 0x10, 0x20, 0x80, 0xFF]) {
      sink.writeln('| 0x${r.toRadixString(16)} | ${await probe(r, 0x0030, 0, 0x21)} |');
      await Future.delayed(const Duration(milliseconds: 15));
    }

    // Step 4: sweep block numbers with n=0x21 (the working byte count)
    sink.writeln('\n## Step 4: block sweep with n=0x21 (canonical size)\n');
    sink.writeln('| block | result |');
    sink.writeln('|------:|--------|');
    final blocks = <int>[
      0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x20,
      0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x40, 0x50, 0x60, 0x70, 0x80,
      0x90, 0xa0, 0xb0, 0xb1, 0xb2, 0xb3, 0xc0, 0xd0, 0xe0, 0xf0,
      0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000,
    ];
    var oks = 0;
    for (final b in blocks) {
      final r = await probe(0, b, 0, 0x21);
      if (r.startsWith('OK')) oks++;
      sink.writeln('| 0x${b.toRadixString(16).padLeft(4, '0')} | $r |');
      await Future.delayed(const Duration(milliseconds: 12));
    }
    sink.writeln('\nOK count: $oks / ${blocks.length}\n');

    // Step 5: vary offset on block 0x30 (the working block)
    sink.writeln('\n## Step 5: vary offset on block 0x30, n=0x21\n');
    sink.writeln('| offset | result |');
    sink.writeln('|------:|--------|');
    for (final off in [
      0, 1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800,
      0x1000, 0x2000, 0x4000, 0x8000, 0xFFFE
    ]) {
      sink.writeln('| 0x${off.toRadixString(16)} | ${await probe(0, 0x0030, off, 0x21)} |');
      await Future.delayed(const Duration(milliseconds: 12));
    }

    // Step 6: vary unknownObject1 (the field set to 0 in _readProjectBlock)
    sink.writeln('\n## Step 6: vary unknownObject1 on block 0x30, n=0x21\n');
    sink.writeln('| obj1 | result |');
    sink.writeln('|----:|--------|');
    Future<String> probeUnknown(int unkn) async {
      final payload = ByteData(9);
      payload.setUint8(0, 0);
      payload.setUint16(1, 0x0030, Endian.little);
      payload.setUint16(3, 0, Endian.little);
      payload.setUint16(5, unkn, Endian.little);
      payload.setUint16(7, 0x21, Endian.little);
      final req = UmasRequest(
        umasSubFunction: UmasSubFunction.readMemoryBlock.code,
        pairingKey: umas.pairingKey,
        payload: payload.buffer.asUint8List(),
        unitId: _unit,
      );
      final code = await tcp.send(req);
      if (code != ModbusResponseCode.requestSucceed) {
        return 'transport-fail';
      }
      final pdu = req.responsePdu;
      if (pdu == null || pdu.length < 3) return 'short';
      final status = pdu[2];
      final body = pdu.sublist(3);
      if (status == 0xFE) {
        return 'OK ${body.length}B';
      }
      return 'ERR 0x${(body.isNotEmpty ? body[0] : 0).toRadixString(16).padLeft(2, '0')}';
    }

    for (final u in [0, 1, 0x21, 0x40, 0x100, 0xFFFF]) {
      sink.writeln('| 0x${u.toRadixString(16)} | ${await probeUnknown(u)} |');
      await Future.delayed(const Duration(milliseconds: 12));
    }

    await sink.flush();
    await sink.close();
    stderr.writeln('Probe complete. See $_outDir/phaseA0-readmemblock-unreserved.md');
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
