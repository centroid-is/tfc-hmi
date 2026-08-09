// ignore_for_file: invalid_use_of_visible_for_testing_member

/// Comprehensive probe for named bit-of-WORD aliases in UMAS.
///
/// The user's HMI sub-FB (typeId 0x27, instance member of M_F2_RC_01) has
/// WORD members (`Status`, `CMD`, `Mode`, `Color`) that Aveva displays with
/// named-bit children (`p_Stat_xAuto` bit 0, `red`, `grey`, ...). The prior
/// probe in worktree a7d3de2d concluded the aliases were "not in UMAS".
/// We refuse to accept that — Aveva reads them over UMAS, so they MUST be
/// reachable through some opcode / record-type combination we haven't tried.
///
/// This probe runs four phases, each writing its raw bytes to
/// `/tmp/named-bit-probe-v2/` so we can post-mortem if something subtle
/// is being missed:
///
///   Phase 1: Decode the FB body record FLAGS field byte-by-byte (the prior
///            probe glossed over this).  Look for non-zero flags on WORDs.
///   Phase 2: DD02 IDX sweep extended to 0x100..0xFFFF (prior probe stopped
///            at 0xFF).  Polite 10ms between requests.
///   Phase 3: DD02 keyed on the FB-INSTANCE blockNo (0xb2 for M_F2_RC_01),
///            NOT the typeId.  Maybe aliases are per-instance not per-type.
///   Phase 4: Sibling recordType sweep: 0xDD00..0xDD0F, 0xDD10..0xDD1F, also
///            0xDExx and 0xDFxx, plus DD02 with a different sub-op trailer.
///            And 0x52 (GET_FORCED_BITS) per zaltzman BHEU 2024.
///
/// READ-ONLY.  No writes, no reservation attempts.  Polite pacing throughout.
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
const _outDir = '/tmp/named-bit-probe-v2';

// Strings we expect to find if a probe lands on the right record set.
const _aliasNeedles = <String>[
  'p_Stat_xAuto',
  'p_Stat_xParentConvFault',
  'p_CMD_xManRev',
  'p_CMD_xResetRuntime',
  'p_Mode_xAuto',
  'p_Mode_xMan',
  'red',
  'grey',
  'green',
  'blue',
  'yellow',
  'pink',
];

Future<void> main(List<String> args) async {
  // Args: a comma-separated list of phases to run, e.g. "1,3,4" or "all".
  // Phase 2 is the 10-minute IDX sweep — run only when explicitly requested.
  final phaseArg = args.isNotEmpty ? args[0] : '1,3,4';
  final phases = phaseArg == 'all'
      ? <int>{1, 2, 3, 4}
      : phaseArg.split(',').map(int.parse).toSet();
  print('running phases: ${phases.toList()..sort()}');

  await Directory(_outDir).create(recursive: true);

  final tcp = ModbusClientTcp(
    _host,
    serverPort: _port,
    unitId: _unit,
    connectionMode: ModbusConnectionMode.doNotConnect,
  );
  await tcp.connect();
  final umas = UmasClient(sendFn: tcp.send, unitId: _unit);

  try {
    print('== Named-bit-of-WORD probe v2 ==');
    print('host: $_host  out: $_outDir\n');

    await umas.readPlcStatus(); // primes session

    // Step 0: find M_F2_RC_01 and HMI sub-FB.
    final vars = await umas.readVariableNames();
    final root = vars.firstWhere((v) => v.name == 'M_F2_RC_01');
    print('M_F2_RC_01: typeId=0x${root.dataTypeId.toRadixString(16)} '
        'blockNo=0x${root.blockNo.toRadixString(16)}');

    final rootRaw = await umas.readDD02Raw(root.dataTypeId);
    await _writeFile('00-fb-body-raw.bin', rootRaw);

    final rootMembers =
        await umas.readStructMembers(root.dataTypeId, parentClassId: 7);
    final hmi = rootMembers.firstWhere((m) => m.name == 'HMI');
    print('HMI sub-FB: typeId=0x${hmi.dataTypeId.toRadixString(16)} '
        'byteOff=0x${hmi.blockNo.toRadixString(16)}');

    final hmiRaw = await umas.readDD02Raw(hmi.dataTypeId);
    await _writeFile('00-hmi-body-raw.bin', hmiRaw);

    final hmiMembers =
        await umas.readStructMembers(hmi.dataTypeId, parentClassId: 7);

    if (phases.contains(1)) {
      await _phase1DecodeFlags(rootRaw, hmiRaw, rootMembers, hmiMembers);
    }
    if (phases.contains(2)) {
      await _phase2DdSweep(umas);
    }
    if (phases.contains(3)) {
      await _phase3InstanceBlockProbe(umas, root, hmi);
    }
    if (phases.contains(4)) {
      await _phase4SiblingOpcodes(umas, root, hmi);
    }

    print('\n== probe done — see $_outDir for raw captures ==');
    exit(0);
  } catch (e, st) {
    stderr.writeln('probe error: $e\n$st');
    exit(1);
  } finally {
    await tcp.disconnect();
  }
}

// ----- Phase 1 ---------------------------------------------------------------
// Decode the FLAGS field of every member record carefully.  The prior probe's
// parsed table dropped this byte.  If non-built-in WORDs encode a bit position
// in the flags, the prior table-driven parse would have missed it.
Future<void> _phase1DecodeFlags(
  Uint8List fbBody,
  Uint8List hmiBody,
  List<UmasVariable> fbMembers,
  List<UmasVariable> hmiMembers,
) async {
  final sb = StringBuffer();
  sb.writeln('## Phase 1 — Flags field decode\n');
  sb.writeln('### M_F2_RC_01 FB body raw');
  sb.writeln(_hex16(fbBody));
  sb.writeln('\n### M_F2_RC_01 FB body member records (manual byte-walk)');
  _walkRecords(sb, fbBody, isMemberLayout: true, fbHeader: 7);
  sb.writeln('\n### HMI sub-FB body raw');
  sb.writeln(_hex16(hmiBody));
  sb.writeln('\n### HMI sub-FB member records (manual byte-walk)');
  _walkRecords(sb, hmiBody, isMemberLayout: true, fbHeader: 7);

  await _writeText('01-flags-decoded.md', sb.toString());
  print('phase 1: see 01-flags-decoded.md');
}

// Manual byte walk that prints EVERY byte (not the parser-stripped view).
// In member-layout (called for both rootBody and hmiBody) the per-record
// schema in the prior probe was inferred to be:
//   dataType(2 LE) + byteOff(2 LE) + flags(4) + name<NUL>
// We print the 4 flag bytes per record so non-zero patterns scream out.
void _walkRecords(StringBuffer sb, Uint8List body,
    {required bool isMemberLayout, required int fbHeader}) {
  if (body.length < fbHeader + 1) {
    sb.writeln('(body too short — ${body.length} bytes)');
    return;
  }
  final hd = ByteData.sublistView(body);
  // The prior probe saw the FB body start with: classByte(1) + 6 bytes of
  // header before the first record at offset 7.  (For HMI body, header is
  // 7 bytes too.)  Use that.
  sb.writeln('  classByte(0)=0x${body[0].toRadixString(16)}');
  sb.writeln('  header[1..7]: ${_hex(body.sublist(1, fbHeader.clamp(1, body.length)))}');

  int pos = fbHeader;
  int idx = 0;
  while (pos + 8 < body.length) {
    final start = pos;
    if (pos + 8 > body.length) break;
    final dt = hd.getUint16(pos, Endian.little);
    final byteOff = hd.getUint16(pos + 2, Endian.little);
    final flag0 = body[pos + 4];
    final flag1 = body[pos + 5];
    final flag2 = body[pos + 6];
    final flag3 = body[pos + 7];
    pos += 8;
    int end = pos;
    while (end < body.length && body[end] != 0x00) {
      end++;
    }
    if (end >= body.length) break;
    final name = String.fromCharCodes(body.sublist(pos, end));
    pos = end + 1;
    sb.writeln('  [$idx] @0x${start.toRadixString(16).padLeft(3, '0')} '
        'dt=0x${dt.toRadixString(16).padLeft(4, '0')} '
        'byteOff=0x${byteOff.toRadixString(16).padLeft(4, '0')} '
        'flags=${flag0.toRadixString(16).padLeft(2, '0')} '
        '${flag1.toRadixString(16).padLeft(2, '0')} '
        '${flag2.toRadixString(16).padLeft(2, '0')} '
        '${flag3.toRadixString(16).padLeft(2, '0')}  '
        'name=$name');
    idx++;
  }
}

// ----- Phase 2 ---------------------------------------------------------------
// Sweep DD02 IDX 0x0100..0xFFFF.  Polite 5ms gap.  Persist any non-empty
// response.  Search for alias-name needles in the bytes.
Future<void> _phase2DdSweep(UmasClient umas) async {
  final sb = StringBuffer();
  sb.writeln('## Phase 2 — DD02 IDX sweep 0x0100..0xFFFF (extended range)\n');
  print('phase 2: sweeping DD02 IDX 0x100..0xFFFF (this takes ~10 min)');
  int hits = 0;
  int needleHits = 0;
  final firstByteCounts = <int, int>{};
  for (int idx = 0x0100; idx <= 0xFFFF; idx++) {
    if (idx % 0x1000 == 0) {
      print('  ... at IDX 0x${idx.toRadixString(16).padLeft(4, '0')} '
          'hits=$hits needleHits=$needleHits');
    }
    try {
      final raw = await umas.readDD02Raw(idx);
      if (raw.length > 1) {
        hits++;
        final fb = raw[0];
        firstByteCounts[fb] = (firstByteCounts[fb] ?? 0) + 1;
        if (_containsNeedle(raw)) {
          needleHits++;
          sb.writeln(
              'IDX 0x${idx.toRadixString(16).padLeft(4, '0')}  '
              'len=${raw.length}  classByte=0x${fb.toRadixString(16)}  '
              '*** NEEDLE HIT ***');
          sb.writeln(_hex16(raw));
          sb.writeln();
        } else if (raw.length >= 8) {
          // Save anything substantial for offline review.
          sb.writeln(
              'IDX 0x${idx.toRadixString(16).padLeft(4, '0')}  '
              'len=${raw.length}  classByte=0x${fb.toRadixString(16)}');
        }
      }
    } on UmasException catch (_) {
      // Errors expected for most IDXs; skip silently.
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  sb.writeln('\n### Summary');
  sb.writeln('total non-empty hits: $hits');
  sb.writeln('needle hits: $needleHits');
  sb.writeln('first-byte distribution:');
  final keys = firstByteCounts.keys.toList()..sort();
  for (final k in keys) {
    sb.writeln('  0x${k.toRadixString(16).padLeft(2, '0')}: ${firstByteCounts[k]}');
  }
  await _writeText('02-dd-sweep-extended.md', sb.toString());
  print('phase 2 done: $hits non-empty hits, $needleHits needle hits');
}

// ----- Phase 3 ---------------------------------------------------------------
// DD02 keyed on the FB-INSTANCE blockNo (0xb2 for M_F2_RC_01).  The
// blockNo field of the M_F2_RC_01 top-level record is 0xb2 — try issuing
// DD02 with that as the lookup key (we normally use 0xFFFF for top-level
// or typeId for members).  Also try the byteOff (offset) field.
Future<void> _phase3InstanceBlockProbe(
    UmasClient umas, UmasVariable root, UmasVariable hmi) async {
  final sb = StringBuffer();
  sb.writeln('## Phase 3 — DD02 keyed on FB-INSTANCE block / offset\n');
  final blocks = <int>{
    root.blockNo,
    hmi.blockNo,
    root.offset & 0xFFFF,
    (root.offset >> 16) & 0xFFFF,
    hmi.offset & 0xFFFF,
    (hmi.offset >> 16) & 0xFFFF,
  };
  for (final b in blocks) {
    sb.writeln('### DD02 blockNo=0x${b.toRadixString(16)}');
    try {
      final raw = await umas.readDD02Raw(b);
      sb.writeln('len=${raw.length}  classByte=0x${raw[0].toRadixString(16)}');
      sb.writeln(_hex16(raw));
      if (_containsNeedle(raw)) sb.writeln('*** NEEDLE HIT ***');
    } on UmasException catch (e) {
      sb.writeln('error: ${e.message}');
    }
    sb.writeln();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await _writeText('03-instance-block-probe.md', sb.toString());
  print('phase 3: see 03-instance-block-probe.md');
}

// ----- Phase 4 ---------------------------------------------------------------
// Sibling recordType / opcode probing.
//
// 0x26 (readDataDictionary) takes a recordType u16 LE.  We've tried
// 0xDD02 and 0xDD03.  Try every value in {0xDD00..0xDD20, 0xDE00..0xDE10,
// 0xDF00..0xDF10}.
//
// Also probe sub-functions that might return alias info directly:
//   0x52 = GET_FORCED_BITS (zaltzman, no published format)
//   0x21 = ?  (gap in the documented codes)
//   0x27 = ?  (just past readDataDictionary)
//   0x70 = readIoObject — explicit IO objects
Future<void> _phase4SiblingOpcodes(
    UmasClient umas, UmasVariable root, UmasVariable hmi) async {
  final sb = StringBuffer();
  sb.writeln('## Phase 4 — Sibling recordType + sub-function probe\n');

  // 4a: recordType variants via 0x26
  sb.writeln('### 4a: sibling recordType values via 0x26 (FC=readDataDictionary)\n');
  final hwId = umas.projectHardwareId ?? 0;
  print('phase 4a: trying sibling recordTypes (hwId=0x${hwId.toRadixString(16)})');
  for (final rt in [
    // Around DD02/DD03
    0xDD00, 0xDD01, 0xDD04, 0xDD05, 0xDD06, 0xDD07, 0xDD08, 0xDD09,
    0xDD0A, 0xDD0B, 0xDD0C, 0xDD0D, 0xDD0E, 0xDD0F, 0xDD10, 0xDD11,
    0xDD12, 0xDD20, 0xDD30, 0xDD40, 0xDDF0, 0xDDFF,
    // Sibling families
    0xDE00, 0xDE02, 0xDE03, 0xDF00, 0xDF02, 0xDF03,
    0xDC00, 0xDC02, 0xDC03, 0xDB00, 0xDB02, 0xDB03,
  ]) {
    for (final blk in [0xFFFF, hmi.dataTypeId, hmi.blockNo, root.dataTypeId]) {
      final resp = await _sendRaw26(
          umas, recordType: rt, blockNo: blk, hwId: hwId);
      if (resp == null) continue;
      final ok = resp.status == 0xFE;
      final note = '';
      sb.writeln('  rt=0x${rt.toRadixString(16)} blk=0x${blk.toRadixString(16)} '
          '${ok ? "OK" : "ERR(0x${resp.errorCode.toRadixString(16)})"}'
          ' len=${resp.payload.length}$note');
      if (ok && resp.payload.length > 4) {
        if (_containsNeedle(resp.payload)) {
          sb.writeln('    *** NEEDLE HIT ***');
        }
        sb.writeln('    ${_hex(resp.payload.length > 96 ? resp.payload.sublist(0, 96) : resp.payload)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  // 4b: sub-function 0x52 — GET_FORCED_BITS
  sb.writeln('\n### 4b: sub-function 0x52 (GET_FORCED_BITS)\n');
  print('phase 4b: probing 0x52 GET_FORCED_BITS with various payload shapes');
  for (final payload in <List<int>>[
    [], // empty
    [0x00, 0x00],
    [0x00, 0x00, 0x00, 0x00],
    [hwId & 0xFF, (hwId >> 8) & 0xFF, (hwId >> 16) & 0xFF, (hwId >> 24) & 0xFF],
    [hmi.blockNo & 0xFF, (hmi.blockNo >> 8) & 0xFF],
    [root.blockNo & 0xFF, (root.blockNo >> 8) & 0xFF],
  ]) {
    final resp = await _sendRawSubFunction(umas,
        subFn: 0x52, payload: Uint8List.fromList(payload));
    final pHex = payload.map((b) => b.toRadixString(16)).join(' ');
    final desc = _describeResp(resp);
    sb.writeln('  payload=$pHex -> $desc');
    if (resp != null && resp.status == 0xFE && resp.payload.length > 2) {
      sb.writeln('    ${_hex(resp.payload)}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  // 4c: other near-by sub-functions
  sb.writeln('\n### 4c: other under-documented sub-functions\n');
  print('phase 4c: probing 0x21,0x27,0x28,0x29,0x70,0x71,0x72,0x73');
  for (final fn in [0x21, 0x27, 0x28, 0x29, 0x70, 0x71, 0x72, 0x73]) {
    final resp = await _sendRawSubFunction(umas, subFn: fn,
        payload: Uint8List(0));
    final desc = _describeResp(resp);
    sb.writeln('  fn=0x${fn.toRadixString(16)} -> $desc');
    if (resp != null && resp.payload.length > 2) {
      sb.writeln('    ${_hex(resp.payload.length > 64 ? resp.payload.sublist(0, 64) : resp.payload)}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  await _writeText('04-sibling-opcodes.md', sb.toString());
  print('phase 4: see 04-sibling-opcodes.md');
}

// ----- Helpers ---------------------------------------------------------------

class _Resp {
  final int status; // 0xFE = success, 0xFD = error
  final int errorCode;
  final Uint8List payload;
  _Resp(this.status, this.errorCode, this.payload);
}

// Send a hand-built 0x26 PDU with a custom recordType.  Returns null if the
// transport itself fails (timeout, no PDU).  status=0xFE on success.
Future<_Resp?> _sendRaw26(UmasClient umas,
    {required int recordType, required int blockNo, required int hwId}) async {
  final includeBlank = recordType == 0xDD02;
  final bd = ByteData(includeBlank ? 13 : 11);
  bd.setUint16(0, recordType, Endian.little);
  bd.setUint8(2, 0); // index byte — placeholder; the live client uses _index
  bd.setUint32(3, hwId, Endian.little);
  bd.setUint16(7, blockNo, Endian.little);
  bd.setUint16(9, 0x0000, Endian.little);
  if (includeBlank) bd.setUint16(11, 0x0000, Endian.little);
  return _sendRawSubFunction(umas,
      subFn: 0x26, payload: bd.buffer.asUint8List());
}

Future<_Resp?> _sendRawSubFunction(UmasClient umas,
    {required int subFn, required Uint8List payload}) async {
  final req = UmasRequest(
    umasSubFunction: subFn,
    pairingKey: umas.pairingKey,
    payload: payload,
    unitId: _unit,
  );
  try {
    final code = await umas.sendFn(req);
    if (code != ModbusResponseCode.requestSucceed) return null;
    final pdu = req.responsePdu;
    if (pdu == null || pdu.length < 3) return null;
    final status = pdu[2];
    final errorCode = pdu.length > 3 ? pdu[3] : 0;
    return _Resp(status, errorCode, pdu.sublist(3));
  } catch (_) {
    return null;
  }
}

String _describeResp(_Resp? resp) {
  if (resp == null) return 'no_resp';
  final st = resp.status.toRadixString(16);
  final ec = resp.errorCode.toRadixString(16);
  return 'len=${resp.payload.length} status=0x$st err=0x$ec';
}

bool _containsNeedle(Uint8List body) {
  // Search ASCII names inside the raw payload (case-sensitive — Schneider
  // preserves case in DD02/DD03).
  if (body.isEmpty) return false;
  final s = String.fromCharCodes(body, 0, body.length);
  for (final n in _aliasNeedles) {
    if (s.contains(n)) return true;
  }
  return false;
}

String _hex(Uint8List b) {
  final sb = StringBuffer();
  for (int i = 0; i < b.length; i++) {
    sb.write(b[i].toRadixString(16).padLeft(2, '0'));
    sb.write(' ');
  }
  return sb.toString().trimRight();
}

String _hex16(Uint8List b) {
  final sb = StringBuffer();
  for (int i = 0; i < b.length; i++) {
    if (i > 0 && i % 16 == 0) sb.write('\n  ');
    if (i == 0) sb.write('  ');
    sb.write(b[i].toRadixString(16).padLeft(2, '0'));
    sb.write(' ');
  }
  return sb.toString();
}

Future<void> _writeFile(String name, Uint8List body) async {
  await File('$_outDir/$name').writeAsBytes(body);
}

Future<void> _writeText(String name, String body) async {
  await File('$_outDir/$name').writeAsString(body);
}
