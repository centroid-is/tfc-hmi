/// Resume-mode aggressive dump. For each enumerated section:
///   1. Read current file size if it exists.
///   2. Continue paging from end of existing data to declared cap.
///   3. Try chunks 0x100, 0x80, 0x40, 0x20 per page.
///   4. ALSO scan a few sections beyond 0xff (in case there are more).
///   5. Stop only on 30 consecutive failures.
///
/// Output: /tmp/bit-alias-final/full-dump-v5/
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
const _outDir = '/tmp/bit-alias-final/full-dump-v5';
const _interReqDelayMs = 15;

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
  await Future.delayed(const Duration(milliseconds: _interReqDelayMs));
  return _ProbeResult(pdu[2], pdu.sublist(3));
}

Future<_ProbeResult> _readMem(
  ModbusClientTcp tcp,
  UmasClient umas, {
  required int section,
  required int offset,
  required int nBytes,
}) async {
  final p = Uint8List(9);
  p[0] = 0;
  ByteData.sublistView(p).setUint16(1, section, Endian.little);
  ByteData.sublistView(p).setUint16(3, offset, Endian.little);
  ByteData.sublistView(p).setUint16(5, 0, Endian.little);
  ByteData.sublistView(p).setUint16(7, nBytes, Endian.little);
  return _sendRaw(tcp, umas, 0x20, payload: p);
}

Uint8List _extractData(Uint8List body) {
  if (body.length < 3) return Uint8List(0);
  final numBytes = body[1] | (body[2] << 8);
  if (body.length < 3 + numBytes) return body.sublist(3);
  return body.sublist(3, 3 + numBytes);
}

Future<int> _main(List<String> args) async {
  await Directory(_outDir).create(recursive: true);
  final logFile = File('$_outDir/dump.log').openWrite();

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
    logFile.writeln('Primed. maxFrameSize=${umas.maxFrameSize}\n');

    // Enumerate sections via 0x07 — include some beyond 0xff
    final descriptors = <int, int>{};
    for (var s = 0; s < 0x200; s++) {
      final p = Uint8List(8);
      p[0] = 0;
      // 16-bit section id in case there are sections beyond 0xff
      ByteData.sublistView(p).setUint16(1, s, Endian.little);
      ByteData.sublistView(p).setUint16(6, 0x40, Endian.little);
      final r = await _sendRaw(tcp, umas, 0x07, payload: p);
      if (r.status == 0xFE && r.body.length >= 6) {
        final purported = r.body[2] |
            (r.body[3] << 8) |
            (r.body[4] << 16) |
            (r.body[5] << 24);
        if (purported > 0 && purported < 16 * 1024 * 1024) {
          descriptors[s] = purported;
        }
      }
    }
    stderr.writeln('Enumerated ${descriptors.length} sections (0..0x1ff).');
    logFile.writeln('Enumerated ${descriptors.length} sections.');
    final unusual =
        descriptors.keys.where((s) => s > 0xff).map((s) => '0x${s.toRadixString(16)}').join(',');
    if (unusual.isNotEmpty) {
      stderr.writeln('Beyond 0xff: $unusual');
      logFile.writeln('Beyond 0xff: $unusual');
    }

    for (final entry in descriptors.entries) {
      final sec = entry.key;
      final declared = entry.value;
      final secHex = sec.toRadixString(16).padLeft(2, '0');
      final outFile = File('$_outDir/sec-0x$secHex.bin');

      // Resume: start from existing length
      var startOffset = 0;
      if (await outFile.exists()) {
        startOffset = await outFile.length();
        if (startOffset >= declared) {
          continue;
        }
      }

      final ras = outFile.openSync(mode: FileMode.append);
      var offset = startOffset;
      var consecutiveErr = 0;
      var bytesThisRun = 0;
      logFile.writeln('\nsec-0x$secHex declared=$declared start_off=$startOffset');

      while (offset < declared) {
        Uint8List? gotData;
        var usedChunk = 0;
        for (final chunk in [0x100, 0x80, 0x40, 0x20, 0x10]) {
          final remain = declared - offset;
          final ask = chunk > remain ? remain : chunk;
          if (ask <= 0) break;
          final r = await _readMem(tcp, umas,
              section: sec, offset: offset, nBytes: ask);
          if (r.status == 0xFE) {
            final data = _extractData(r.body);
            if (data.isNotEmpty) {
              gotData = data;
              usedChunk = ask;
              break;
            }
          }
        }
        if (gotData == null) {
          consecutiveErr++;
          if (consecutiveErr >= 30) break;
          offset += 0x10;
          continue;
        }
        consecutiveErr = 0;
        // We may be appending past file end if file currently has fewer
        // bytes than current offset. Write whatever bytes we got.
        ras.writeFromSync(gotData);
        bytesThisRun += gotData.length;
        offset += gotData.length;
        if (gotData.length < usedChunk) {
          // We can't trust that the rest of the section is reachable.
          // But keep going to declared cap.
        }
      }
      ras.closeSync();
      if (bytesThisRun > 0) {
        stderr.writeln('sec-0x$secHex: +$bytesThisRun bytes (now ${await outFile.length()}/$declared)');
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
    await logFile.close();
  }
}

Future<void> main(List<String> args) async {
  exit(await _main(args));
}
