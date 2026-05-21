/// Reserved-surface UMAS probe (READ-ONLY).
///
/// Premise: prior named-bit probes (worktrees a7d3de2d, a10ea891) ran
/// ~30k payloads on the **unreserved** surface and found nothing. User
/// confirms Aveva reads `M_F2_RC_01.HMI.Color.red` etc. from THIS PLC
/// (192.168.112.159) — therefore the data lives behind the reservation
/// gate or behind a sub-protocol Aveva unlocks. This tool probes the
/// reserved surface to find it.
///
/// SAFETY: writes are FORBIDDEN. Reservation acquire/release is the only
/// state-changing op. All requests are diagnostic / read-only.
///
/// Phase A — Confirm reservation buys readMemoryBlock access
///   Re-issue readMemoryBlock on the blocks that returned 0x88 unreserved.
///   Tabulate which now return data.
///
/// Phase B — DD02 / DD03 with non-zero offsets while reserved
///   The `0x86` rejections from unreserved offset>0 may turn into data.
///
/// Phase C — Sub-function probe with reservation held
///   0x52 (GET_FORCED_BITS, zaltzman Black Hat EU 2024), 0x70..0x73,
///   0x80..0x8F. Unreserved these returned 0x88; reserved may return data.
///
/// Phase D — Re-dump DD02 bodies for typeIds 0x27 (HMI) and 0x28
///   (M_F2_RC_01) with reservation held. Look for additional records
///   after the WORD members — particularly classId=0x0001 (BOOL) records
///   that would represent the bit aliases.
///
/// Phase E — Try sub-function variants of DD02 fetch (0x26 with sub-fn
///   selectors in the trailer) under reservation. Specifically the trailers
///   that returned 0x88 unreserved.
///
/// Output: /tmp/named-bit-probe-reserved/
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

const _statusSuccess = 0xFE;
const _statusError = 0xFD;

Future<int> _main(List<String> args) async {
  final phasesArg = args.isNotEmpty ? args[0] : 'ABCDE';
  final phases = phasesArg.toUpperCase().split('');
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
    // Prime: sets _projectHardwareId and _index, enables DD02 calls.
    await umas.readPlcStatus();
    final hwId = umas.projectHardwareId;
    if (hwId == null) {
      stderr.writeln('FATAL: projectHardwareId still null after prime');
      return 2;
    }
    stderr.writeln('Session primed: pairingKey=0x'
        '${umas.pairingKey.toRadixString(16).padLeft(2, '0')} '
        'hwId=0x${hwId.toRadixString(16).padLeft(8, '0')}');

    // Try to acquire reservation. If refused, retry up to 3 times with 5s wait.
    var reserved = false;
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await umas.takePlcReservation();
        reserved = true;
        stderr.writeln('Reservation acquired (attempt $attempt). '
            'hasReservation=${umas.hasReservation}');
        break;
      } catch (e) {
        lastError = e;
        stderr.writeln('Reservation refused on attempt $attempt: $e');
        if (attempt < 3) {
          stderr.writeln('Waiting 5s before retry...');
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
    }
    if (!reserved) {
      stderr.writeln('FATAL: could not acquire reservation: $lastError');
      // Document refusal and exit cleanly.
      await File('$_outDir/RESERVATION-REFUSED.md').writeAsString(
          '# Reservation refused after 3 attempts\n\nLast error: $lastError\n');
      return 3;
    }

    final reservationStart = DateTime.now();

    try {
      // CRITICAL: bound reservation window to ≤60s. If we exceed,
      // release and bail to avoid hogging the PLC.
      Future<bool> _windowOk() async {
        final elapsed = DateTime.now().difference(reservationStart).inSeconds;
        if (elapsed > 55) {
          stderr.writeln('Reservation window approaching 60s '
              '(${elapsed}s elapsed) — stopping further probes.');
          return false;
        }
        return true;
      }

      if (phases.contains('A') && await _windowOk()) {
        await _phaseA(tcp, umas);
      }
      if (phases.contains('B') && await _windowOk()) {
        await _phaseB(tcp, umas);
      }
      if (phases.contains('C') && await _windowOk()) {
        await _phaseC(tcp, umas);
      }
      if (phases.contains('D') && await _windowOk()) {
        await _phaseD(tcp, umas);
      }
      if (phases.contains('E') && await _windowOk()) {
        await _phaseE(tcp, umas);
      }
    } finally {
      try {
        await umas.releasePlcReservation();
        final elapsed =
            DateTime.now().difference(reservationStart).inSeconds;
        stderr.writeln('Reservation released after ${elapsed}s.');
      } catch (e) {
        stderr.writeln('WARN: reservation release failed: $e');
      }
    }
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

class _Reply {
  final int status; // -1=transport fail
  final int errByte;
  final Uint8List body;
  _Reply(this.status, this.errByte, this.body);

  bool get ok => status == _statusSuccess;
  bool get err => status == _statusError;
  String classify() {
    if (status == -1) return 'transport';
    if (err) return 'ERR(0x${errByte.toRadixString(16).padLeft(2, '0')})';
    if (ok && body.isEmpty) return 'OK empty';
    if (ok && body.length >= 7) {
      final kind = body[0];
      if (kind == 0x00) return 'OK kind=00';
      if (kind == 0x02) return 'OK kind=02 (UDT)';
      if (kind == 0x04) return 'OK kind=04 (ARRAY)';
      if (kind == 0x07) return 'OK kind=07 (FB)';
      if (kind == 0x08) return 'OK kind=08 (sentinel)';
      return 'OK kind=0x${kind.toRadixString(16)}';
    }
    return 'OK len=${body.length}';
  }
}

/// Send a raw UMAS request via the underlying ModbusClientTcp transport.
Future<_Reply> _send(
  ModbusClientTcp tcp,
  UmasClient umas,
  int subFn,
  Uint8List payload,
) async {
  final request = UmasRequest(
    umasSubFunction: subFn,
    pairingKey: umas.pairingKey,
    payload: payload,
    unitId: _unit,
  );
  final code = await tcp.send(request);
  if (code != ModbusResponseCode.requestSucceed) {
    return _Reply(-1, code.code, Uint8List(0));
  }
  final pdu = request.responsePdu;
  if (pdu == null || pdu.length < 3) return _Reply(-1, 0, Uint8List(0));
  final status = pdu[2];
  final body = pdu.sublist(3);
  final errByte = (status == _statusError && body.isNotEmpty) ? body[0] : 0;
  return _Reply(status, errByte, body);
}

String _hex(Uint8List b, [int? max]) {
  final n = max == null ? b.length : (b.length < max ? b.length : max);
  return [
    for (var i = 0; i < n; i++) b[i].toRadixString(16).padLeft(2, '0')
  ].join(' ');
}

Uint8List _buildDD02Payload({
  required UmasClient umas,
  required int recordType,
  required int blockNo,
  required int offset,
  bool includeBlank = true,
}) {
  final hwId = umas.projectHardwareId ?? 0;
  const idx = 0;
  final bd = ByteData(includeBlank ? 13 : 11);
  bd.setUint16(0, recordType, Endian.little);
  bd.setUint8(2, idx);
  bd.setUint32(3, hwId, Endian.little);
  bd.setUint16(7, blockNo, Endian.little);
  bd.setUint16(9, offset, Endian.little);
  if (includeBlank) {
    bd.setUint16(11, 0, Endian.little);
  }
  return bd.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Phase A — readMemoryBlock under reservation
// ---------------------------------------------------------------------------
Future<void> _phaseA(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase A: readMemoryBlock under reservation ===');
  final file = File('$_outDir/phaseA-readMemoryBlock-reserved.md');
  final sink = file.openWrite();
  sink.writeln('# Phase A — readMemoryBlock with reservation held\n');
  sink.writeln(
      'Unreserved, every block returned `ERR 0x88`. Re-probe under reservation.\n');
  sink.writeln('| block | offset | nBytes | result | first48 |');
  sink.writeln('|------:|------:|------:|--------|---------|');

  // The blocks we know about + a wide sweep.
  // FB instance block 0xb2 (M_F2_RC_01) and 0x30 (project block we already use).
  final blocks = <int>[
    0x0000, 0x0001, 0x0002, 0x0008, 0x0010, 0x0020, 0x0030, 0x0031, 0x0032,
    0x0033, 0x0034, 0x0040, 0x0050, 0x0060, 0x0080, 0x0100, 0x0200, 0x0300,
    0x0400, 0x0500, 0x0600, 0x0800, 0x0a00, 0x0c00,
    0x00b2, // M_F2_RC_01 FB instance block
    0x008c, // HMI sub-FB offset within parent (used as block by some probes)
    // Hardware-id derived range — try low blocks too
    0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0009, 0x000a, 0x000b,
    // High blocks
    0x1000, 0x2000, 0x4000,
  ];

  var successCount = 0;
  for (final blk in blocks) {
    final req = ReadMemoryBlockRequest(
      range: 0x00,
      blockNumber: blk,
      offset: 0,
      numberOfBytes: 0x40,
    );
    final reply = await _send(
        tcp, umas, UmasSubFunction.readMemoryBlock.code, req.toBytes());
    final tag = reply.classify();
    if (reply.ok) successCount++;
    sink.writeln('| 0x${blk.toRadixString(16).padLeft(4, '0')} | 0 | 0x40 | '
        '$tag | `${_hex(reply.body, 48)}` |');
    await Future.delayed(const Duration(milliseconds: 15));
  }
  sink.writeln('\nSuccess count: $successCount / ${blocks.length}\n');
  await sink.flush();
  await sink.close();
  stderr.writeln('Phase A complete. $successCount/${blocks.length} blocks '
      'unlocked.');
}

// ---------------------------------------------------------------------------
// Phase B — DD02 with offset!=0 under reservation
// ---------------------------------------------------------------------------
Future<void> _phaseB(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase B: DD02 offset!=0 under reservation ===');
  final file = File('$_outDir/phaseB-dd02-offset-reserved.md');
  final sink = file.openWrite();
  sink.writeln('# Phase B — DD02(typeId, offset!=0) under reservation\n');
  sink.writeln(
      'Hypothesis: with reservation, offset!=0 may reveal bit-child records.\n');
  sink.writeln('| typeId | offset | len | result | first48 |');
  sink.writeln('|------:|------:|----:|--------|---------|');

  // HMI sub-FB members + Status WORD bit positions
  final offsets = <int>[
    0x00, 0x02, 0x04, 0x06, 0x08, 0x0c, 0x10,
    for (var b = 0; b < 16; b++) b,
    0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x1000,
  ];

  for (final typeId in [0x27, 0x28, 0x29, 0x2a, 0x2b, 0x25, 0x26]) {
    sink.writeln('\n### typeId=0x${typeId.toRadixString(16)}\n');
    sink.writeln('| offset | len | result | first48 |');
    sink.writeln('|------:|----:|--------|---------|');
    for (final off in offsets) {
      final payload = _buildDD02Payload(
          umas: umas, recordType: 0xDD02, blockNo: typeId, offset: off);
      final reply = await _send(
          tcp, umas, UmasSubFunction.readDataDictionary.code, payload);
      sink.writeln('| 0x${off.toRadixString(16)} | ${reply.body.length} | '
          '${reply.classify()} | `${_hex(reply.body, 48)}` |');
      await Future.delayed(const Duration(milliseconds: 15));
    }
  }
  await sink.flush();
  await sink.close();
  stderr.writeln('Phase B complete.');
}

// ---------------------------------------------------------------------------
// Phase C — Sub-function probe with reservation
// ---------------------------------------------------------------------------
Future<void> _phaseC(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase C: sub-function probe under reservation ===');
  final file = File('$_outDir/phaseC-subfunction-reserved.md');
  final sink = file.openWrite();
  sink.writeln('# Phase C — Sub-function probe under reservation\n');
  sink.writeln('Unreserved, these returned 0x88. Re-probe under reservation.\n');
  sink.writeln('| subFn | payload | len | result | first48 |');
  sink.writeln('|------:|---------|----:|--------|---------|');

  // 0x52 GET_FORCED_BITS — try several payload shapes
  // 0x70..0x73 — under-documented
  // 0x80..0x8F — undocumented (Aveva might use one of these)
  // 0x21, 0x27, 0x28, 0x29 — payload shape variants

  final probes = <_SubFnProbe>[
    _SubFnProbe(0x52, Uint8List(0), 'empty'),
    _SubFnProbe(0x52, Uint8List.fromList([0x00, 0x00]), '0000'),
    _SubFnProbe(0x52, Uint8List.fromList([0x00, 0x00, 0x00, 0x00]), '00000000'),
    _SubFnProbe(0x52, Uint8List.fromList([0xb2, 0x00]), 'block=0xb2'),
    _SubFnProbe(0x52, Uint8List.fromList([0x8c, 0x00]), 'block=0x8c'),
    // hwid-based form
    _SubFnProbe(
        0x52,
        () {
          final hwId = umas.projectHardwareId ?? 0;
          final bd = ByteData(4);
          bd.setUint32(0, hwId, Endian.little);
          return bd.buffer.asUint8List();
        }(),
        'hwid'),
    // 0x70 readIoObject — already implemented but probe variants
    for (var fn in [0x21, 0x27, 0x28, 0x29, 0x70, 0x71, 0x72, 0x73])
      _SubFnProbe(fn, Uint8List(0), 'empty'),
    // 0x80..0x8F
    for (var fn = 0x80; fn <= 0x8F; fn++)
      _SubFnProbe(fn, Uint8List(0), 'empty'),
    // 0x60..0x6F
    for (var fn = 0x60; fn <= 0x6F; fn++)
      _SubFnProbe(fn, Uint8List(0), 'empty'),
    // 0x40..0x4F
    for (var fn = 0x40; fn <= 0x4F; fn++)
      _SubFnProbe(fn, Uint8List(0), 'empty'),
    // 0x90..0x9F
    for (var fn = 0x90; fn <= 0x9F; fn++)
      _SubFnProbe(fn, Uint8List(0), 'empty'),
  ];

  for (final p in probes) {
    final reply = await _send(tcp, umas, p.fn, p.payload);
    sink.writeln('| 0x${p.fn.toRadixString(16).padLeft(2, '0')} | '
        '${p.label} | ${reply.body.length} | ${reply.classify()} | '
        '`${_hex(reply.body, 48)}` |');
    await Future.delayed(const Duration(milliseconds: 15));
  }
  await sink.flush();
  await sink.close();
  stderr.writeln('Phase C complete.');
}

class _SubFnProbe {
  final int fn;
  final Uint8List payload;
  final String label;
  _SubFnProbe(this.fn, this.payload, this.label);
}

// ---------------------------------------------------------------------------
// Phase D — Re-dump DD02 bodies for typeIds 0x27, 0x28 with full paging
// ---------------------------------------------------------------------------
Future<void> _phaseD(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase D: full-paged DD02 dump under reservation ===');
  final file = File('$_outDir/phaseD-dd02-paged-reserved.md');
  final sink = file.openWrite();
  sink.writeln('# Phase D — Multi-page DD02 dump under reservation\n');
  sink.writeln('If reservation unlocks paginated continuation, '
      'subsequent pages should reveal trailing bit records.\n');

  for (final typeId in [0x27, 0x28, 0x29, 0x2a, 0x2b, 0x1a, 0x24, 0x25, 0x26]) {
    sink.writeln('\n### typeId=0x${typeId.toRadixString(16)}\n');
    var offset = 0;
    var pageNum = 0;
    while (true) {
      final payload = _buildDD02Payload(
          umas: umas, recordType: 0xDD02, blockNo: typeId, offset: offset);
      final reply = await _send(
          tcp, umas, UmasSubFunction.readDataDictionary.code, payload);
      if (!reply.ok) {
        sink.writeln('Page $pageNum offset=0x${offset.toRadixString(16)} '
            '${reply.classify()}\n');
        break;
      }
      final body = reply.body;
      sink.writeln('Page $pageNum (offset=0x${offset.toRadixString(16)}, '
          'len=${body.length}):\n');
      sink.writeln('```');
      for (var i = 0; i < body.length; i += 16) {
        final end = (i + 16 < body.length) ? i + 16 : body.length;
        final hex = body
            .sublist(i, end)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        final ascii = String.fromCharCodes(body.sublist(i, end).map(
            (b) => (b >= 0x20 && b < 0x7f) ? b : 0x2e));
        sink.writeln('${i.toRadixString(16).padLeft(4, '0')}  '
            '${hex.padRight(48)}  $ascii');
      }
      sink.writeln('```\n');
      if (body.length < 7) break;
      final nextAddr = body[1] | (body[2] << 8);
      if (nextAddr == 0) break;
      offset = nextAddr;
      pageNum++;
      if (pageNum > 10) {
        sink.writeln('(stopped at page 10)\n');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 15));
    }
  }
  await sink.flush();
  await sink.close();
  stderr.writeln('Phase D complete.');
}

// ---------------------------------------------------------------------------
// Phase E — DD02 with sub-function selector trailers
// ---------------------------------------------------------------------------
Future<void> _phaseE(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase E: DD02 trailer variants under reservation ===');
  final file = File('$_outDir/phaseE-dd02-trailer-reserved.md');
  final sink = file.openWrite();
  sink.writeln('# Phase E — DD02 trailer variants under reservation\n');
  sink.writeln(
      'Probe 0xDD02 with variant trailers that returned 0x88 unreserved.\n');
  sink.writeln('| trailer | typeId | len | result | first48 |');
  sink.writeln('|---------|------:|----:|--------|---------|');

  // Variant payload: standard 13-byte but with non-zero trailer
  Uint8List buildVariant({
    required int recordType,
    required int blockNo,
    required int offset,
    required int trailer,
  }) {
    final hwId = umas.projectHardwareId ?? 0;
    const idx = 0;
    final bd = ByteData(13);
    bd.setUint16(0, recordType, Endian.little);
    bd.setUint8(2, idx);
    bd.setUint32(3, hwId, Endian.little);
    bd.setUint16(7, blockNo, Endian.little);
    bd.setUint16(9, offset, Endian.little);
    bd.setUint16(11, trailer, Endian.little);
    return bd.buffer.asUint8List();
  }

  for (final typeId in [0x27, 0x28]) {
    for (final tr in [
      0x0001, 0x0002, 0x0003, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040,
      0x0080, 0x00FF, 0x0100, 0x1000, 0xFFFE, 0xFFFF
    ]) {
      final payload = buildVariant(
          recordType: 0xDD02, blockNo: typeId, offset: 0, trailer: tr);
      final reply = await _send(
          tcp, umas, UmasSubFunction.readDataDictionary.code, payload);
      sink.writeln('| 0x${tr.toRadixString(16).padLeft(4, '0')} | '
          '0x${typeId.toRadixString(16)} | ${reply.body.length} | '
          '${reply.classify()} | `${_hex(reply.body, 48)}` |');
      await Future.delayed(const Duration(milliseconds: 15));
    }
  }

  // Also try recordType values 0xDD05..0xDD10 under reservation
  sink.writeln('\n## recordType variants under reservation\n');
  sink.writeln('| recordType | typeId | len | result | first48 |');
  sink.writeln('|----------:|------:|----:|--------|---------|');
  for (final rt in [
    0xDD05, 0xDD06, 0xDD07, 0xDD08, 0xDD09, 0xDD0A, 0xDD0B,
    0xDD0C, 0xDD0D, 0xDD0E, 0xDD0F, 0xDD10, 0xDD11, 0xDD12,
    0xDD20, 0xDD30, 0xDE02, 0xDE03, 0xDF02, 0xDF03, 0xDC02, 0xDC03, 0xDB02,
  ]) {
    for (final typeId in [0xFFFF, 0x27, 0x28, 0x8c, 0xb2]) {
      final payload = _buildDD02Payload(
          umas: umas, recordType: rt, blockNo: typeId, offset: 0);
      final reply = await _send(
          tcp, umas, UmasSubFunction.readDataDictionary.code, payload);
      sink.writeln('| 0x${rt.toRadixString(16)} | '
          '0x${typeId.toRadixString(16)} | ${reply.body.length} | '
          '${reply.classify()} | `${_hex(reply.body, 48)}` |');
      await Future.delayed(const Duration(milliseconds: 12));
    }
  }

  await sink.flush();
  await sink.close();
  stderr.writeln('Phase E complete.');
}
