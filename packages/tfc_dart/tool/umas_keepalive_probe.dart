/// UMAS keep-alive probe — diagnoses the recurring 0x81/0x80 keep-alive
/// failure observed against the live M580 at 192.168.112.159.
///
/// Captures byte-level request + response for keep-alive in three
/// scenarios:
///   1. Fresh-after-pair (immediately after init).
///   2. Idle (60s with no other traffic).
///   3. After a successful readPlcStatus (touch the session).
///
/// Each request is sent both as the "empty body" form (what UmasClient
/// produces today) and the "one-byte zero" form (defensive variant).
///
/// Usage:
///   dart run packages/tfc_dart/tool/umas_keepalive_probe.dart \
///       [--host 192.168.112.159] [--idle-seconds 60]
///
/// Output goes to stdout (human report) and stderr (per-frame log).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

const _defaultHost = '192.168.112.159';
const _defaultPort = 502;
const _defaultUnit = 255;

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void _log(String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] $msg');
}

/// Wrap a real ModbusClient.send so each UMAS frame is dumped before
/// it goes out and the response is dumped before it returns to the
/// caller. Captures BOTH the wire-PDU we built AND the bytes the PLC
/// returned.
class _Capturing {
  final ModbusClientTcp tcp;
  final List<_Frame> frames = [];
  _Capturing(this.tcp);

  Future<ModbusResponseCode> send(ModbusRequest req) async {
    Uint8List? requestPdu;
    if (req is UmasRequest) {
      requestPdu = req.protocolDataUnit;
    }
    final code = await tcp.send(req);
    Uint8List? responsePdu;
    if (req is UmasRequest) {
      responsePdu = req.responsePdu;
    }
    if (requestPdu != null) {
      final f = _Frame(
        sub: requestPdu.length >= 3 ? requestPdu[2] : -1,
        pairingKey: requestPdu.length >= 2 ? requestPdu[1] : -1,
        request: requestPdu,
        response: responsePdu,
        code: code,
      );
      frames.add(f);
    }
    return code;
  }
}

class _Frame {
  final int sub;
  final int pairingKey;
  final Uint8List request;
  final Uint8List? response;
  final ModbusResponseCode code;
  _Frame({
    required this.sub,
    required this.pairingKey,
    required this.request,
    required this.response,
    required this.code,
  });

  String summarize() {
    final s = StringBuffer();
    s.writeln('  sub=0x${sub.toRadixString(16).padLeft(2, '0')} '
        'pairingKey=0x${pairingKey.toRadixString(16).padLeft(2, '0')} '
        'code=${code.name}');
    s.writeln('  >>> ${_hex(request)}');
    if (response == null) {
      s.writeln('  <<< (no response)');
    } else {
      s.writeln('  <<< ${_hex(response!)}');
      if (response!.length >= 3) {
        final status = response![2];
        if (status == 0xFE) {
          s.writeln('      status=0xFE (success)');
        } else if (status == 0xFD) {
          final err = response!.length > 3 ? response![3] : 0;
          final sec = response!.length > 4 ? response![4] : null;
          s.writeln('      status=0xFD ERROR '
              'errorCode=0x${err.toRadixString(16).padLeft(2, '0')}'
              '${sec != null ? ' secondary=0x${sec.toRadixString(16).padLeft(2, '0')}' : ''}');
        } else {
          s.writeln('      status=0x${status.toRadixString(16).padLeft(2, '0')} (unexpected)');
        }
      }
    }
    return s.toString();
  }
}

Future<void> main(List<String> argv) async {
  var host = _defaultHost;
  var port = _defaultPort;
  var unit = _defaultUnit;
  var idleSeconds = 5; // fast default for CI / quick probes
  var iterations = 5;
  var timerSeconds = 30;
  for (var i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--host':
        host = argv[++i];
      case '--port':
        port = int.parse(argv[++i]);
      case '--unit':
        unit = int.parse(argv[++i]);
      case '--idle-seconds':
        idleSeconds = int.parse(argv[++i]);
      case '--iterations':
        iterations = int.parse(argv[++i]);
      case '--timer-seconds':
        timerSeconds = int.parse(argv[++i]);
    }
  }

  stdout.writeln('=== UMAS keep-alive probe ===');
  stdout.writeln('Target: $host:$port unit=$unit '
      'idle=${idleSeconds}s iterations=$iterations');
  stdout.writeln('');

  final tcp = ModbusClientTcp(
    host,
    serverPort: port,
    unitId: unit,
    connectionMode: ModbusConnectionMode.doNotConnect,
    connectionTimeout: const Duration(seconds: 5),
  );
  _log('TCP connect...');
  final ok = await tcp.connect();
  if (!ok) {
    stderr.writeln('TCP connect failed');
    exit(2);
  }
  _log('TCP connected');

  final cap = _Capturing(tcp);

  // Build a UmasClient that uses the capturing wrapper as its sendFn.
  final umas = UmasClient(
    sendFn: cap.send,
    unitId: unit,
    // Disable keep-alive timer — we drive keep-alive manually.
    keepAliveInterval: const Duration(hours: 1),
  );

  try {
    // Phase 1: pair
    _log('readPlcStatus (drives readPlcId + init + readProjectBlock)');
    await umas.readPlcStatus();
    _log('Session state: ${umas.sessionState}');
    _log('Pairing key: 0x${umas.pairingKey.toRadixString(16)}');

    // Capture the post-init frame list — print just init + project block
    // for record.
    stdout.writeln('--- Init sequence ---');
    for (final f in cap.frames) {
      stdout.write(f.summarize());
    }
    cap.frames.clear();

    // Phase 2: manual keep-alive immediately
    stdout.writeln('');
    stdout.writeln('--- Scenario A: keep-alive immediately after pair (UmasClient.sendKeepAlive, empty body) ---');
    await _tryKeepAlive(umas, 'A1: immediate');
    for (final f in cap.frames) {
      stdout.write(f.summarize());
    }
    cap.frames.clear();

    // Phase 3: send a raw keep-alive with a one-byte payload, comparing
    // shapes that some Schneider clients use.
    stdout.writeln('');
    stdout.writeln('--- Scenario B: keep-alive with payload=[0x00] (raw frame) ---');
    await _tryRawKeepAlive(cap, umas, unit, payload: Uint8List.fromList([0x00]), label: 'B1: payload=[0x00]');
    for (final f in cap.frames) {
      stdout.write(f.summarize());
    }
    cap.frames.clear();

    // Phase 4: another empty-body keep-alive (does the previous one
    // disturb session?)
    stdout.writeln('');
    stdout.writeln('--- Scenario C: keep-alive empty body again ---');
    await _tryKeepAlive(umas, 'C1: empty body second try');
    for (final f in cap.frames) {
      stdout.write(f.summarize());
    }
    cap.frames.clear();

    // Phase 5: idle for N seconds then keep-alive
    stdout.writeln('');
    stdout.writeln('--- Scenario D: idle for ${idleSeconds}s then keep-alive ---');
    _log('idle ${idleSeconds}s...');
    await Future<void>.delayed(Duration(seconds: idleSeconds));
    await _tryKeepAlive(umas, 'D1: after idle');
    for (final f in cap.frames) {
      stdout.write(f.summarize());
    }
    cap.frames.clear();

    // Phase 6: do a successful round-trip (readPlcStatus) then keep-alive
    stdout.writeln('');
    stdout.writeln('--- Scenario E: readPlcStatus → keep-alive ---');
    try {
      await umas.readPlcStatus();
      _log('readPlcStatus OK');
    } catch (e) {
      _log('readPlcStatus FAILED: $e');
    }
    cap.frames.clear();
    await _tryKeepAlive(umas, 'E1: after readPlcStatus');
    for (final f in cap.frames) {
      stdout.write(f.summarize());
    }
    cap.frames.clear();

    // Phase 7: spin keep-alive $iterations times rapid-fire to see if
    // it ever recovers / changes behavior
    stdout.writeln('');
    stdout.writeln('--- Scenario F: ${iterations} consecutive keep-alives ---');
    for (var i = 0; i < iterations; i++) {
      try {
        await umas.sendKeepAlive();
        _log('F${i + 1}: SUCCESS');
      } catch (e) {
        _log('F${i + 1}: FAILED: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    for (final f in cap.frames) {
      stdout.write(f.summarize());
    }
    cap.frames.clear();

    // Phase 8: exercise the production keep-alive TIMER (which post
    // 2026-05-20 sends 0x04 plcStatus instead of 0x12 KeepAlive).
    // This is the after-fix regression check: 30s of timer ticks must
    // produce ZERO 0xFD status responses.
    stdout.writeln('');
    stdout.writeln('--- Scenario G: production timer ticks (${timerSeconds}s, 2s interval) ---');
    final timerClient = UmasClient(
      sendFn: cap.send,
      unitId: unit,
      keepAliveInterval: const Duration(seconds: 2),
      projectCrcCheckInterval: const Duration(hours: 1),
    );
    await timerClient.readPlcStatus();
    cap.frames.clear();
    timerClient.startKeepAlive();
    await Future<void>.delayed(Duration(seconds: timerSeconds));
    timerClient.stopKeepAlive();

    var errCount = 0;
    var okCount = 0;
    var subCounts = <int, int>{};
    for (final f in cap.frames) {
      subCounts[f.sub] = (subCounts[f.sub] ?? 0) + 1;
      if (f.response != null && f.response!.length >= 3) {
        if (f.response![2] == 0xFD) errCount++;
        if (f.response![2] == 0xFE) okCount++;
      }
    }
    stdout.writeln('  timer-triggered frames: ${cap.frames.length}');
    stdout.writeln('  by sub-function: ${subCounts.entries.map((e) =>
        "0x${e.key.toRadixString(16).padLeft(2, "0")}=${e.value}").join(", ")}');
    stdout.writeln('  status 0xFE (success): $okCount');
    stdout.writeln('  status 0xFD (error)  : $errCount');
    if (errCount == 0) {
      stdout.writeln(
          '  >>> ZERO 0xFD errors over ${timerSeconds}s of ticks — FIX VERIFIED');
    } else {
      stdout.writeln('  >>> $errCount errors observed — fix may be incomplete');
    }
    cap.frames.clear();
  } finally {
    try {
      await tcp.disconnect();
    } catch (_) {}
  }
}

Future<void> _tryKeepAlive(UmasClient umas, String label) async {
  try {
    await umas.sendKeepAlive();
    _log('$label: SUCCESS');
  } catch (e) {
    _log('$label: FAILED: $e');
  }
}

/// Send a raw KeepAlive frame with caller-provided payload (bypasses
/// UmasClient.sendKeepAlive which always sends empty payload).
Future<void> _tryRawKeepAlive(
  _Capturing cap,
  UmasClient umas,
  int unit, {
  required Uint8List payload,
  required String label,
}) async {
  final req = UmasRequest(
    umasSubFunction: UmasSubFunction.keepAlive.code,
    pairingKey: umas.pairingKey,
    payload: payload,
    unitId: unit,
  );
  try {
    final code = await cap.send(req);
    if (code != ModbusResponseCode.requestSucceed) {
      _log('$label: transport ${code.name}');
      return;
    }
    final pdu = req.responsePdu;
    if (pdu == null || pdu.length < 3) {
      _log('$label: empty response');
      return;
    }
    if (pdu[2] == 0xFE) {
      _log('$label: SUCCESS');
    } else if (pdu[2] == 0xFD) {
      final err = pdu.length > 3 ? pdu[3] : 0;
      final sec = pdu.length > 4 ? pdu[4] : null;
      _log('$label: ERROR 0x${err.toRadixString(16)}'
          '${sec != null ? '/0x${sec.toRadixString(16)}' : ''}');
    } else {
      _log('$label: unexpected status 0x${pdu[2].toRadixString(16)}');
    }
  } catch (e) {
    _log('$label: EXCEPTION $e');
  }
}
