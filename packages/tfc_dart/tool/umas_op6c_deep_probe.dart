/// Deep probe of opcode 0x6c — found to respond with non-error payloads
/// in initial sweep. Iterate sub-selectors 0..ff with different trailing
/// payloads to map the response space.
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
const _outDir = '/tmp/bit-alias-final/op6c-deep';

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
  await Future.delayed(const Duration(milliseconds: 20));
  return _ProbeResult(pdu[2], pdu.sublist(3));
}

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
    final results = <String>[];
    results.add('# op 0x6c deep probe ${DateTime.now().toIso8601String()}\n');
    results.add('| sel | extra | status | len | first48 | ascii |');
    results.add('|----:|-------|-------:|----:|---------|-------|');

    for (var sel = 0; sel < 0x100; sel++) {
      final payload = Uint8List.fromList([sel]);
      final r = await _sendRaw(tcp, umas, 0x6c, payload: payload);
      if (r.status == 0xFE && r.body.length > 4) {
        final hex = r.body.take(48).map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ');
        final ascii = r.body.take(48).map((b) => (b >= 0x20 && b < 0x7f) ? String.fromCharCode(b) : '.').join();
        results.add('| 0x${sel.toRadixString(16)} | (none) | OK | ${r.body.length} | `$hex` | `$ascii` |');
        final fname = '$_outDir/sel_0x${sel.toRadixString(16).padLeft(2,'0')}.bin';
        await File(fname).writeAsBytes(r.body);
      } else if (r.status == 0xFD && r.body.isNotEmpty && ![0x83,0x86,0x88,0x90,0xff,0xfe].contains(r.body[0])) {
        results.add('| 0x${sel.toRadixString(16)} | (none) | ERR 0x${r.body[0].toRadixString(16)} | ${r.body.length} | | |');
      }
    }

    // Also try 2-byte selectors that match section IDs
    for (final secId in [0x7d, 0xce, 0xcd, 0xa8, 0x40, 0x10, 0x11, 0x30]) {
      for (final payload in [
        Uint8List.fromList([0x01, secId & 0xff]),
        Uint8List.fromList([0x00, secId & 0xff]),
        Uint8List.fromList([0x01, secId & 0xff, 0x00]),
        Uint8List.fromList([0x01, secId & 0xff, 0x00, 0x00]),
        Uint8List.fromList([secId & 0xff, 0x00, 0x00, 0x00]),
      ]) {
        final r = await _sendRaw(tcp, umas, 0x6c, payload: payload);
        if (r.status == 0xFE && r.body.length > 4) {
          final hex = r.body.take(48).map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ');
          final ascii = r.body.take(48).map((b) => (b >= 0x20 && b < 0x7f) ? String.fromCharCode(b) : '.').join();
          final shapeName = payload.map((b) => b.toRadixString(16).padLeft(2,'0')).join('-');
          results.add('| - | $shapeName | OK | ${r.body.length} | `$hex` | `$ascii` |');
          await File('$_outDir/2byte_$shapeName.bin').writeAsBytes(r.body);
        }
      }
    }

    await File('$_outDir/REPORT.md').writeAsString(results.join('\n'));
    stderr.writeln('Wrote $_outDir/REPORT.md (${results.length-3} entries)');
    return 0;
  } catch (e, st) {
    stderr.writeln('FATAL: $e\n$st');
    return 2;
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
  }
}

Future<void> main(List<String> args) async {
  exit(await _main(args));
}
