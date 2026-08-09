// Regression: the periodic keep-alive timer must NOT send UMAS
// sub-function 0x12 (umas_QueryKeepPLCReservation). M580 firmware
// rejects 0x12 from a non-reserved client with `status=0xFD errorCode=0x81
// secondary=0x80`, which previously generated a continuous warning log
// every keep-alive interval on the live HMI.
//
// Live-PLC byte evidence (192.168.112.159, captured 2026-05-20):
//
//   >>> 5a 00 12                (KeepAlive, no body)
//   <<< 5a 00 fd 81 80 c0 c6 2d 00 00 00 00 00
//
// The fix: the timer calls `readPlcStatus()` (sub-function 0x04, a
// public no-reservation-required UMAS function) instead of
// `sendKeepAlive()`. plc4j follows the same approach — its umas.mspec
// has no 0x12 typeSwitch case.
//
// These tests guard the timer-side wire choice; the low-level
// `sendKeepAlive()` API itself is kept (and tested elsewhere) for
// diagnostic tooling.

import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

class _Mock {
  final List<UmasRequest> sent = [];
  final Map<int, List<Uint8List>> _pdu = {};

  void respond(int subFunc, Uint8List pdu) {
    _pdu.putIfAbsent(subFunc, () => []).add(pdu);
  }

  Future<ModbusResponseCode> send(ModbusRequest req) async {
    if (req is! UmasRequest) return ModbusResponseCode.requestRxFailed;
    sent.add(req);
    final subFunc = req.protocolDataUnit[2];
    final q = _pdu[subFunc];
    if (q != null && q.isNotEmpty) {
      // Repeat the LAST response forever so periodic timers can fire
      // multiple times without queue exhaustion.
      final response = q.length > 1 ? q.removeAt(0) : q.first;
      req.setFromPduResponse(response);
      return req.responseCode;
    }
    return ModbusResponseCode.requestRxFailed;
  }
}

Uint8List _successPdu(Uint8List payload, {int pairingKey = 0x00}) {
  final pdu = Uint8List(3 + payload.length);
  pdu[0] = 0x5A;
  pdu[1] = pairingKey;
  pdu[2] = 0xFE;
  pdu.setAll(3, payload);
  return pdu;
}

Uint8List _le16(int v) {
  final bd = ByteData(2);
  bd.setUint16(0, v, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List _plcIdentPayload() {
  final bd = ByteData(16);
  bd.setUint16(0, 0x0001, Endian.little);
  bd.setUint32(2, 0x0000060B, Endian.little);
  bd.setUint8(6, 1);
  bd.setUint16(7, 0, Endian.little);
  bd.setUint8(9, 0x01);
  bd.setUint16(10, 0x0000, Endian.little);
  bd.setUint32(12, 0x00010000, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List _projectBlockPayload() {
  final bd = ByteData(20);
  bd.setUint8(0, 0x01);
  bd.setUint16(1, 17, Endian.little);
  bd.setUint16(3, 0x0001, Endian.little);
  bd.setUint16(5, 0x0000, Endian.little);
  bd.setUint8(7, 7);
  bd.setUint32(8, 0x10C3B4E8, Endian.little);
  bd.setUint32(12, 0x10000000, Endian.little);
  bd.setUint32(16, 0x00000000, Endian.little);
  return bd.buffer.asUint8List();
}

/// Minimal plcStatus (0x04) success response — 3-byte UMAS header +
/// notUsed(1) + notUsed2(2) + numberOfBlocks(1) + 0 blocks.
Uint8List _plcStatusOkPayload() =>
    Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);

void _seedPaired(_Mock mock) {
  mock.respond(0x02, _successPdu(_plcIdentPayload()));
  mock.respond(0x01, _successPdu(_le16(240), pairingKey: 0x42));
  mock.respond(0x20, _successPdu(_projectBlockPayload()));
}

void main() {
  group('keep-alive timer wire choice', () {
    test(
        'timer ticks send sub-function 0x04 (plcStatus), NOT 0x12 (KeepAlive)',
        () async {
      final mock = _Mock();
      _seedPaired(mock);
      // Seed a permanent plcStatus success so periodic ticks don't error.
      mock.respond(0x04, _successPdu(_plcStatusOkPayload()));

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 25),
        // Stop CRC timer from creating noise in the assertion below.
        projectCrcCheckInterval: const Duration(hours: 1),
      );
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();
      expect(client.sessionState, UmasSessionState.paired);

      final beforeTicks = mock.sent.length;
      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      client.stopKeepAlive();

      // Look at what the timer sent (everything appended since
      // startKeepAlive was called).
      final timerSent = mock.sent.skip(beforeTicks).toList();
      expect(timerSent, isNotEmpty,
          reason: 'the timer should have fired at least once');

      // No request from the timer may carry sub-function 0x12.
      final keepAliveSent = timerSent
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .toList();
      expect(keepAliveSent, isEmpty,
          reason: 'timer must NOT send 0x12 KeepAlive — M580 rejects it '
              'with 0xFD 0x81 0x80 (live byte capture, 2026-05-20)');

      // Every timer-sent request should be sub-function 0x04 plcStatus.
      for (final r in timerSent) {
        expect(r.protocolDataUnit[2], 0x04,
            reason: 'keep-alive timer should only send 0x04 plcStatus');
      }
    });

    test(
        'timer survives a transient 0x04 byte-level error without invalidating',
        () async {
      // Even with the new wire choice, a byte-level (PLC-side) error
      // from plcStatus must not trigger a session re-pair storm — same
      // contract as the old test for 0x12.
      final mock = _Mock();
      _seedPaired(mock);

      // One byte-level error on plcStatus, followed by a success — but
      // because the mock retains the LAST response, we queue two so the
      // first call gets the error, subsequent calls get the success.
      mock.respond(
          0x04, Uint8List.fromList([0x5A, 0x42, 0xFD, 0x01])); // status error
      mock.respond(0x04, _successPdu(_plcStatusOkPayload()));

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 25),
        projectCrcCheckInterval: const Duration(hours: 1),
      );
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();
      expect(client.sessionState, UmasSessionState.paired);

      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      client.stopKeepAlive();

      expect(
        client.sessionState,
        UmasSessionState.paired,
        reason: 'a byte-level error from plcStatus must NOT invalidate '
            'the session — same Fix A contract as for KeepAlive',
      );
    });
  });
}
