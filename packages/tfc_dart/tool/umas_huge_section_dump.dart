/// Aggressive dump of large sections.
///
/// Prior v4 dumper bailed on short reads at low offsets, missing 98% of
/// sections 0x10 and 0x11 (which declare 150KB and 300KB respectively).
/// This tool:
///   1. Keeps paging up to the declared cap regardless of short reads
///   2. Falls back to smaller chunks per-page
///   3. Detects all-zero pages but keeps going past them up to cap
///   4. Writes one binary per section + a hex-trace log
///
/// Output: /tmp/bit-alias-final/huge-dump/
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
const _outDir = '/tmp/bit-alias-final/huge-dump';
const _interReqDelayMs = 20;

// Sections we want to fully harvest.
const _targetSections = <int, int>{
  0x10: 0x25400,
  0x11: 0x4a820,
  0x40: 0x4000,
  0xac: 0x1c9e,
  0x55: 0x12fc,
  0x78: 0x18a6,
  0x6b: 0xaa4,
  0xa8: 0xad0,
  0x83: 0xc09,
  0x84: 0xa24,
  0x7d: 0xf1b,
  0xee: 0x5a0,
  0xf5: 0x7dc,
  0xd0: 0x9fc,
  0x67: 0x420,
  0x73: 0x660,
  0x75: 0x908,
  0xcc: 0x310,
  0xce: 0x310,
  0xd1: 0x20d,
  0xe7: 0x2ce,
  0x41: 0xc2e,
  0x30: 0x20f6,
  0x33: 0x12e4,
};

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

/// Aggressively page: even if a chunk returns zero / partial, keep going
/// to next offset. Only stop when error response or full cap reached.
Future<Map<int, Uint8List>> _aggressivePage(
  ModbusClientTcp tcp,
  UmasClient umas, {
  required int sec,
  required int cap,
  required IOSink log,
}) async {
  // Build a map of offset -> bytes
  final pages = <int, Uint8List>{};
  final chunks = [0x100, 0x80, 0x40, 0x20, 0x10];
  var offset = 0;
  var consecutiveErrors = 0;
  while (offset < cap) {
    Uint8List? gotData;
    var usedChunk = 0;
    for (final chunk in chunks) {
      final r = await _readMem(tcp, umas,
          section: sec, offset: offset, nBytes: chunk);
      if (r.status == 0xFE) {
        final data = _extractData(r.body);
        if (data.isNotEmpty) {
          gotData = data;
          usedChunk = chunk;
          break;
        }
      }
    }
    if (gotData == null) {
      consecutiveErrors++;
      log.writeln('  off=0x${offset.toRadixString(16)}: NO DATA');
      if (consecutiveErrors >= 20) {
        log.writeln('  -> giving up after 20 consec errors');
        break;
      }
      // Skip ahead one minimum-chunk
      offset += 0x10;
      continue;
    }
    consecutiveErrors = 0;
    pages[offset] = gotData;
    log.writeln('  off=0x${offset.toRadixString(16)}: chunk=0x${usedChunk.toRadixString(16)} got=${gotData.length}B');
    // Advance by what we got (may be less than requested)
    offset += gotData.length;
    if (gotData.length == 0) break;
  }
  return pages;
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

    for (final entry in _targetSections.entries) {
      final sec = entry.key;
      final declared = entry.value;
      final secHex = sec.toRadixString(16).padLeft(2, '0');
      final outFile = File('$_outDir/sec-0x$secHex.bin');
      if (await outFile.exists() && (await outFile.length()) >= declared - 256) {
        stderr.writeln('Skip 0x$secHex (already have ${await outFile.length()} bytes)');
        continue;
      }
      logFile.writeln('\n=== Section 0x$secHex (declared 0x${declared.toRadixString(16)} = $declared bytes) ===');
      stderr.writeln('Dumping 0x$secHex (cap=$declared)...');
      final pages = await _aggressivePage(tcp, umas,
          sec: sec, cap: declared, log: logFile);

      // Coalesce pages into a single buffer, filling gaps with 0x00.
      // Use a bit of headroom in case the device returns more than declared.
      final bufSize = declared + 4096;
      final out = Uint8List(bufSize);
      var maxOff = 0;
      for (final off in pages.keys) {
        final data = pages[off]!;
        for (var i = 0; i < data.length && off + i < bufSize; i++) {
          out[off + i] = data[i];
        }
        final end = off + data.length;
        if (end > maxOff) maxOff = end;
      }
      // Truncate to last non-zero region + a bit
      final clip = maxOff.clamp(0, declared);
      final truncated = Uint8List.sublistView(out, 0, clip);
      await File('$_outDir/sec-0x$secHex.bin').writeAsBytes(truncated);
      logFile.writeln('  -> wrote $maxOff bytes (pages=${pages.length})');
      stderr.writeln('  -> $maxOff bytes');
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
