/// Named-bit alias probe v3 (READ-ONLY).
///
/// Two phases the prior probes did NOT exhaustively cover:
///
/// Phase A — DD02 full IDX sweep 0x0000..0xFFFF
///   Prior agent (a7d3de2d) only swept 0x00..0xFF. Sweep the full u16 range
///   to find any DD02 records hiding at higher IDX.
///
/// Phase B — DD02 with non-zero offset (per-member sub-records)
///   The 0x26 wire format has both `blockNo` and `offset` fields. All prior
///   probes set offset=0 (since DD02 pagination uses offset as nextAddress).
///   But for the FIRST request of a typeId, what does offset=<byte_off> do?
///   Hypothesis: at IDX=<parent_typeId> + offset=<byte_off_of_WORD_member>,
///   the firmware returns the bit children of that specific WORD member.
///
/// Phase C — DD02 with non-zero offset on FB-root, scanning every member offset
///   Belt-and-braces version of Phase B: hit every word-aligned offset.
///
/// Phase D — DD02 first-page raw dump of all real type bodies (0x1a..0x2b)
///   The prior dumps showed the parsed records but only at offset=0. Verify
///   that no second-page exists with named bits.
///
/// Output: /tmp/named-bit-probe-v2/jb-probe/
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

const _statusSuccess = 0xFE;
const _statusError = 0xFD;

Future<int> _main(List<String> args) async {
  final phasesArg = args.isNotEmpty ? args[0] : 'ABCD';
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
    // Prime: this triggers readPlcId + project block, so _projectHardwareId
    // and _index are set, and DD02 calls work normally.
    await umas.readPlcStatus();
    final hwId = umas.projectHardwareId;
    if (hwId == null) {
      stderr.writeln('FATAL: projectHardwareId still null after prime');
      return 2;
    }
    stderr.writeln('Session primed: pairingKey=0x'
        '${umas.pairingKey.toRadixString(16).padLeft(2, '0')} '
        'hwId=0x${hwId.toRadixString(16).padLeft(8, '0')}');

    if (phases.contains('A')) {
      await _phaseA(tcp, umas);
    }
    if (phases.contains('B')) {
      await _phaseB(tcp, umas);
    }
    if (phases.contains('C')) {
      await _phaseC(tcp, umas);
    }
    if (phases.contains('D')) {
      await _phaseD(tcp, umas);
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

Uint8List _buildDD02Payload({
  required UmasClient umas,
  required int recordType,
  required int blockNo,
  required int offset,
  bool includeBlank = true,
}) {
  final hwId = umas.projectHardwareId ?? 0;
  // Use umas's own field. We can't access the private _index, so we read it
  // back via the public readPlcStatus-derived state. The session-prime
  // sequence set _index on the umas client; for our purposes index=0 is
  // ALSO accepted by the M580 firmware (verified in the trailer probe).
  // We'll hard-code 0 here because we can't access _index directly.
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

class _Reply {
  final int status; // -1=transport fail
  final int errByte;
  final Uint8List body;
  _Reply(this.status, this.errByte, this.body);

  bool get ok => status == _statusSuccess;
  bool get err => status == _statusError;
  String get classify {
    if (status == -1) return 'transport';
    if (err) return 'ERR(0x${errByte.toRadixString(16).padLeft(2, '0')})';
    if (ok && body.isEmpty) return 'OK empty';
    if (ok && body.length >= 7) {
      final kind = body[0];
      if (kind == 0x00) return 'OK kind=00';
      if (kind == 0x02) return 'OK kind=02 (UDT)';
      if (kind == 0x04) return 'OK kind=04 (ARRAY)';
      if (kind == 0x07) return 'OK kind=07 (FB)';
      if (kind == 0x08) return 'OK kind=08 (empty/sentinel)';
      return 'OK kind=0x${kind.toRadixString(16)}';
    }
    return 'OK len=${body.length}';
  }
}

Future<_Reply> _probe(ModbusClientTcp tcp, Uint8List payload, UmasClient umas,
    {int subFn = 0x26}) async {
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
    for (var i = 0; i < n; i++)
      b[i].toRadixString(16).padLeft(2, '0')
  ].join(' ');
}

/// Phase A: Full DD02 IDX sweep 0x0000..0xFFFF.
Future<void> _phaseA(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase A: DD02 IDX sweep 0x0000..0xFFFF ===');
  final file = File('$_outDir/phaseA-dd02-full-sweep.md');
  final sink = file.openWrite();
  sink.writeln('# Phase A — DD02 full IDX sweep 0x0000..0xFFFF\n');
  sink.writeln(
      'recordType=0xDD02, offset=0. Reports every IDX whose first-page reply '
      'is **not** the trivial `[0x00]` or `[0x08]` sentinel.\n');
  sink.writeln('| IDX | len | classify | first16 |');
  sink.writeln('|----:|----:|----------|---------|');

  var nontrivial = 0;
  var lastLog = DateTime.now();
  for (var idx = 0; idx <= 0xFFFF; idx++) {
    final payload = _buildDD02Payload(
        umas: umas, recordType: 0xDD02, blockNo: idx, offset: 0);
    final reply = await _probe(tcp, payload, umas);
    final body = reply.body;
    final trivial = (body.length == 1 && (body[0] == 0x00 || body[0] == 0x08)) ||
        (reply.err && (reply.errByte == 0x86 || reply.errByte == 0x83));
    if (!trivial) {
      nontrivial++;
      sink.writeln('| 0x${idx.toRadixString(16).padLeft(4, '0')} | '
          '${body.length} | ${reply.classify} | `${_hex(body, 16)}` |');
    }
    if (DateTime.now().difference(lastLog).inSeconds >= 5) {
      stderr.writeln(
          '  ... idx=0x${idx.toRadixString(16).padLeft(4, '0')} '
              'nontrivial=$nontrivial');
      lastLog = DateTime.now();
    }
    // 5ms polite delay
    if (idx % 200 == 0) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
  sink.writeln('\nTotal nontrivial IDX: $nontrivial');
  await sink.flush();
  await sink.close();
  stderr.writeln('Phase A complete. $nontrivial nontrivial IDX values found.');
}

/// Phase B: DD02 with non-zero offset, keyed on parent typeId.
///
/// For the HMI sub-FB (typeId=0x27), Status @ byteOff=0, CMD @ byteOff=2,
/// Mode @ 4, Cfg @ 6, Color @ 0x10. Probe DD02(blockNo=0x27, offset=<byteOff>)
/// AND DD02(blockNo=0x28, offset=<byteOff_of_HMI_in_parent>=0x8c).
Future<void> _phaseB(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase B: DD02 with non-zero offset ===');
  final file = File('$_outDir/phaseB-dd02-with-offset.md');
  final sink = file.openWrite();
  sink.writeln('# Phase B — DD02(blockNo, offset!=0)\n');
  sink.writeln(
      'Hypothesis: the firmware re-uses offset as a sub-record selector. '
      'At offset=<byte_off_of_member>, perhaps it returns bit children of '
      'that member.\n');
  sink.writeln('| IDX | offset | len | classify | first32 |');
  sink.writeln('|----:|------:|----:|----------|---------|');

  // Probe HMI sub-FB (typeId=0x27) with offsets matching its members.
  final hmiOffsets = <int>[
    0x00, // Status (WORD)
    0x02, // CMD (WORD)
    0x04, // Mode (WORD)
    0x06, // Cfg (WORD)
    0x08, // p_Stat_iThermalFaults (INT)
    0x0c, // p_Stat_diRuntime (DINT)
    0x10, // Color (WORD)
    // Bit positions within Status (0..15)
    for (var b = 0; b < 16; b++) b,
    // Some odd offsets to find boundaries
    0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x1000,
  ];

  for (final typeId in [0x27, 0x28, 0x29, 0x2a, 0x2b, 0x25, 0x26]) {
    sink.writeln('\n### typeId=0x${typeId.toRadixString(16)}\n');
    for (final off in hmiOffsets) {
      final payload = _buildDD02Payload(
          umas: umas, recordType: 0xDD02, blockNo: typeId, offset: off);
      final reply = await _probe(tcp, payload, umas);
      sink.writeln('| 0x${typeId.toRadixString(16)} | '
          '0x${off.toRadixString(16)} | ${reply.body.length} | '
          '${reply.classify} | `${_hex(reply.body, 32)}` |');
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }
  await sink.flush();
  await sink.close();
  stderr.writeln('Phase B complete.');
}

/// Phase C: DD03 / DD04 IDX sweep with non-zero offsets.
Future<void> _phaseC(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase C: DD03/DD04 with various blocks/offsets ===');
  final file = File('$_outDir/phaseC-dd03-dd04-variations.md');
  final sink = file.openWrite();
  sink.writeln('# Phase C — DD03/DD04 with blockNo and offset variations\n');

  // The prior agent (04-sibling-opcodes.md) found rt=0xDD04 returns 46-byte
  // extended-header regardless of blockNo. But it always sent offset=0. Try
  // offset=1..0xFFFF.
  sink.writeln(
      '## DD04 (recordType=0xDD04) — sweep offset at fixed blockNo=0\n');
  sink.writeln('| offset | len | classify | first32 |');
  sink.writeln('|------:|----:|----------|---------|');
  final dd04offsets = <int>[
    0, 1, 2, 3, 4, 5, 6, 7, 8, 0x10, 0x20, 0x40, 0x80,
    0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x8000, 0xFFFF,
  ];
  for (final off in dd04offsets) {
    final payload = _buildDD02Payload(
        umas: umas, recordType: 0xDD04, blockNo: 0, offset: off);
    final reply = await _probe(tcp, payload, umas);
    sink.writeln('| 0x${off.toRadixString(16)} | ${reply.body.length} | '
        '${reply.classify} | `${_hex(reply.body, 32)}` |');
    await Future.delayed(const Duration(milliseconds: 25));
  }

  // DD04 with non-blank trailer
  sink.writeln(
      '\n## DD04 without 2-byte blank trailer (11-byte payload)\n');
  for (final off in [0, 1, 0x100]) {
    final payload = _buildDD02Payload(
        umas: umas,
        recordType: 0xDD04,
        blockNo: 0,
        offset: off,
        includeBlank: false);
    final reply = await _probe(tcp, payload, umas);
    sink.writeln('  offset=0x${off.toRadixString(16)} → '
        'len=${reply.body.length} ${reply.classify} '
        '`${_hex(reply.body, 32)}`\n');
  }

  await sink.flush();
  await sink.close();
  stderr.writeln('Phase C complete.');
}

/// Phase D: First-page raw dump of every real type body (0x1a..0x2b).
/// Also dump SECOND PAGE (offset = nextAddress from first page) — the prior
/// dumps only showed first-page records and might have missed bit-child
/// records hidden in continuation pages.
Future<void> _phaseD(ModbusClientTcp tcp, UmasClient umas) async {
  stderr.writeln('\n=== Phase D: Multi-page dump of all real type bodies ===');
  final file = File('$_outDir/phaseD-multipage-dump.md');
  final sink = file.openWrite();
  sink.writeln('# Phase D — Full multi-page dump of every UDT/FB body\n');
  sink.writeln('Hypothesis: the prior probe used `readDD02Raw` which returns '
      'ONE page. The HMI body claimed nextAddr=0, but verify against every '
      'type and check ALL pages.\n');

  for (final typeId in [0x1a, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b]) {
    sink.writeln('\n### typeId=0x${typeId.toRadixString(16)}\n');
    var offset = 0;
    var pageNum = 0;
    while (true) {
      final payload = _buildDD02Payload(
          umas: umas, recordType: 0xDD02, blockNo: typeId, offset: offset);
      final reply = await _probe(tcp, payload, umas);
      if (!reply.ok) {
        sink.writeln('Page $pageNum offset=0x${offset.toRadixString(16)} '
            '${reply.classify}\n');
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
      // Parse header: range(1) + nextAddress(2 LE)
      final nextAddr = body[1] | (body[2] << 8);
      if (nextAddr == 0) break;
      offset = nextAddr;
      pageNum++;
      if (pageNum > 10) {
        sink.writeln('(stopped at page 10)\n');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }
  await sink.flush();
  await sink.close();
  stderr.writeln('Phase D complete.');
}
