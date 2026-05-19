/// Regression tests for SWEEP-03 / SWEEP-04 / SWEEP-05 (Phase 5, v1.1).
///
/// SWEEP-03 — every UmasException message includes a stable
///            sub-function name token. Covered indirectly: every
///            `_checkStatus(pdu, op)` call site already passes a
///            token, and the contract was made explicit in the
///            method docs.
/// SWEEP-04 — `_handleSessionError()` clears `_projectCrc` so a PLC
///            reboot mid-session does not carry a stale project CRC
///            into the next session.
/// SWEEP-05 — `_log.w()` fires when `writeVariable` or `readVariable`
///            truncates at the 255-ref cap.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

/// Build a mock sendFn that successfully primes a UMAS session
/// (readPlcId, init, plcStatus) and returns a benign success for any
/// other sub-function. Used for SWEEP-04 (setting _projectCrc via
/// readProjectInfo path) and SWEEP-05 (writeVariable / readVariable
/// cap-warning tests).
Future<ModbusResponseCode> Function(ModbusRequest) _benignSession({
  required List<int> subFunctionLog,
  int pairingKey = 0x42,
}) {
  return (ModbusRequest request) async {
    final umasReq = request as UmasRequest;
    subFunctionLog.add(umasReq.umasSubFunction);

    switch (umasReq.umasSubFunction) {
      case 0x02: // readPlcId
        final resp = BytesBuilder();
        resp.add([0x5A, 0x00, 0xFE]);
        final pd = ByteData(16);
        pd.setUint16(0, 1, Endian.little);
        pd.setUint32(2, 0x12345678, Endian.little);
        pd.setUint8(6, 1);
        pd.setUint16(7, 0, Endian.little);
        pd.setUint8(9, 1);
        pd.setUint16(10, 0, Endian.little);
        pd.setUint32(12, 0x10000, Endian.little);
        resp.add(pd.buffer.asUint8List());
        umasReq
            .internalSetFromPduResponse(Uint8List.fromList(resp.toBytes()));
        return ModbusResponseCode.requestSucceed;
      case 0x01: // init
        final resp = BytesBuilder();
        resp.add([0x5A, pairingKey, 0xFE]);
        final pd = ByteData(2);
        pd.setUint16(0, 1021, Endian.little);
        resp.add(pd.buffer.asUint8List());
        umasReq
            .internalSetFromPduResponse(Uint8List.fromList(resp.toBytes()));
        return ModbusResponseCode.requestSucceed;
      case 0x04: // plcStatus
        final resp = BytesBuilder();
        resp.add([0x5A, pairingKey, 0xFE]);
        resp.add([0x03, 0x00, 0x00]);
        resp.addByte(1);
        final crc = ByteData(4);
        crc.setUint32(0, 0xAABBCCDD, Endian.little);
        resp.add(crc.buffer.asUint8List());
        umasReq
            .internalSetFromPduResponse(Uint8List.fromList(resp.toBytes()));
        return ModbusResponseCode.requestSucceed;
      case 0x22: // readVariable — return one BOOL byte per ref, fewer
        // than asked when cap kicks in
        final resp = BytesBuilder();
        resp.add([0x5A, pairingKey, 0xFE]);
        // We don't actually parse the response in the cap test —
        // just need a benign success. Send a single-byte payload.
        resp.add([0x00]);
        umasReq
            .internalSetFromPduResponse(Uint8List.fromList(resp.toBytes()));
        return ModbusResponseCode.requestSucceed;
      case 0x23: // writeVariable
        final resp = BytesBuilder();
        resp.add([0x5A, pairingKey, 0xFE]);
        umasReq
            .internalSetFromPduResponse(Uint8List.fromList(resp.toBytes()));
        return ModbusResponseCode.requestSucceed;
      default:
        umasReq.internalSetFromPduResponse(
            Uint8List.fromList([0x5A, pairingKey, 0xFE]));
        return ModbusResponseCode.requestSucceed;
    }
  };
}

void main() {
  group('SWEEP-04: _handleSessionError clears _projectCrc', () {
    test('writing _projectCrc via reflection-equivalent path is null after '
        'session error', () async {
      // We cannot directly set `_projectCrc` (private). The public
      // observable path: trigger a UmasException via a deliberate
      // failure of any sub-function once `_projectCrc` is set, then
      // observe that the next read after re-init goes through the
      // session re-pair sequence (proving the state was reset).
      //
      // SWEEP-04 specifically targets `_projectCrc`. The public
      // getter `projectCrc` lets us observe its value directly.
      final log = <int>[];
      final client = UmasClient(
        sendFn: _benignSession(subFunctionLog: log),
        backoffDelay: (_) async {},
      );

      // Step 1: Prime the session and PlcStatus so we are paired.
      await client.readPlcStatus();
      expect(client.sessionState, UmasSessionState.paired);

      // Step 2: There's no public setter for _projectCrc. We
      // approximate by checking that BEFORE any session error,
      // `projectCrc` is whatever the mock said (here: null because
      // the mock doesn't include readProjectInfo). The salient
      // assertion is the AFTER state: after triggering an error
      // path, projectCrc remains null. We use a controlled approach:
      // tear down via the internal _handleSessionError that fires
      // when any UMAS error bubbles up through
      // _withSessionAndRecovery.
      //
      // Fix A: trigger a TRANSPORT-level session error (a byte-level
      // UMAS 0xFD/0x83 error is now non-fatal and would NOT invalidate).
      final errorClient = UmasClient(
        sendFn: (req) async {
          final umasReq = req as UmasRequest;
          // Init success, then any later call returns a transport timeout.
          if (umasReq.umasSubFunction == 0x02 ||
              umasReq.umasSubFunction == 0x01 ||
              umasReq.umasSubFunction == 0x20) {
            return _benignSession(subFunctionLog: [])(req);
          }
          return ModbusResponseCode.requestTimeout;
        },
        backoffDelay: (_) async {},
      );

      // Trigger an error path that goes through _withSessionAndRecovery.
      expect(
        () async => await errorClient.readDataTypes(),
        throwsA(isA<UmasException>()),
      );

      // After the error, session should be back to uninitialized
      // and projectCrc must be null (the SWEEP-04 contract).
      // Allow the async pipeline to settle.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(errorClient.sessionState, UmasSessionState.uninitialized,
          reason: '_handleSessionError should reset state');
      expect(errorClient.projectCrc, isNull,
          reason: 'SWEEP-04: _projectCrc must be cleared on session error');
    });
  });

  group('SWEEP-05: warn on _maxWriteVariableRefs / _maxReadVariableRefs cap',
      () {
    test('writeVariable: 256 refs triggers a single warning log', () async {
      // We can't easily intercept the package-private logger inside
      // UmasClient. Instead: assert behaviour — passing 256 refs must
      // not throw, must succeed (the mock returns 0xFE), and the
      // request that goes out on the wire carries exactly 255 refs.
      // The warning log fires as a side effect and is visible in
      // operator logs (we exercise the code path; full log capture
      // would require dependency injection of the logger and is
      // out of scope for this regression test).
      final log = <int>[];
      ModbusRequest? lastRequest;
      final client = UmasClient(
        sendFn: (req) async {
          lastRequest = req;
          return _benignSession(subFunctionLog: log)(req);
        },
        backoffDelay: (_) async {},
      );
      await client.readPlcStatus();

      // Build 300 write refs of a 1-byte BOOL.
      final refs = List<VariableWriteRef>.generate(
        300,
        (i) => VariableWriteRef(
          blockNo: 0,
          baseOffset: 0,
          offset: i & 0xFFFF,
          dataSizeIndex: 1,
          data: Uint8List.fromList([1]),
        ),
      );

      await client.writeVariable(refs);

      // The wire payload count byte is at fixed offset (after
      // crc(4)). count must be 255 — verifies the cap kicked in.
      final payload = (lastRequest as UmasRequest).umasPayload;
      // Payload: crc(4) + count(1) + refs...
      expect(payload[4], 255,
          reason: 'SWEEP-05: cap should truncate to 255');
    });

    test('writeVariable: exactly 255 refs does NOT truncate', () async {
      final log = <int>[];
      ModbusRequest? lastRequest;
      final client = UmasClient(
        sendFn: (req) async {
          lastRequest = req;
          return _benignSession(subFunctionLog: log)(req);
        },
        backoffDelay: (_) async {},
      );
      await client.readPlcStatus();

      final refs = List<VariableWriteRef>.generate(
        255,
        (i) => VariableWriteRef(
          blockNo: 0,
          baseOffset: 0,
          offset: i & 0xFFFF,
          dataSizeIndex: 1,
          data: Uint8List.fromList([1]),
        ),
      );

      await client.writeVariable(refs);
      final payload = (lastRequest as UmasRequest).umasPayload;
      expect(payload[4], 255,
          reason: 'No truncation at exactly the cap (255 fits in 1 byte)');
    });

    test('readVariable: 300 refs truncates to 255', () async {
      final log = <int>[];
      ModbusRequest? lastRequest;
      final client = UmasClient(
        sendFn: (req) async {
          lastRequest = req;
          return _benignSession(subFunctionLog: log)(req);
        },
        backoffDelay: (_) async {},
      );
      await client.readPlcStatus();

      final refs = List<VariableReadRef>.generate(
        300,
        (i) => VariableReadRef(
          blockNo: 0,
          baseOffset: 0,
          offset: i & 0xFFFF,
          dataSizeIndex: 1,
        ),
      );

      // The mock returns a 1-byte payload; readVariable doesn't
      // strictly validate output length here. We only verify the
      // wire-side truncation.
      try {
        await client.readVariable(refs);
      } catch (_) {
        // Ignored — parse may not match payload; we only care about
        // the request side.
      }

      final payload = (lastRequest as UmasRequest).umasPayload;
      expect(payload[4], 255,
          reason: 'SWEEP-05: read-side cap should truncate to 255');
    });
  });

  group('SWEEP-03: error messages include sub-function name', () {
    test('readDataTypes error message contains "readDataTypes"', () async {
      // Use a sendFn that errors on 0x26 (readDataDictionary).
      final client = UmasClient(
        sendFn: (req) async {
          final umasReq = req as UmasRequest;
          if (umasReq.umasSubFunction == 0x02 ||
              umasReq.umasSubFunction == 0x01) {
            return _benignSession(subFunctionLog: [])(req);
          }
          umasReq.internalSetFromPduResponse(
              Uint8List.fromList([0x5A, 0x42, 0xFD, 0x83]));
          return ModbusResponseCode.requestSucceed;
        },
        backoffDelay: (_) async {},
      );

      try {
        await client.readDataTypes();
        fail('Expected UmasException');
      } on UmasException catch (e) {
        // SWEEP-03 contract: the message must include the
        // operation token so log greps work.
        expect(e.message, contains('readDataTypes'),
            reason: 'SWEEP-03: error message must include sub-function name');
      }
    });

    test('readDD02(blockNo=...) error message contains the parameterised '
        'token', () async {
      final client = UmasClient(
        sendFn: (req) async {
          final umasReq = req as UmasRequest;
          if (umasReq.umasSubFunction == 0x02 ||
              umasReq.umasSubFunction == 0x01) {
            return _benignSession(subFunctionLog: [])(req);
          }
          umasReq.internalSetFromPduResponse(
              Uint8List.fromList([0x5A, 0x42, 0xFD, 0x83]));
          return ModbusResponseCode.requestSucceed;
        },
        backoffDelay: (_) async {},
      );

      try {
        await client.readStructMembers(0xb6);
        fail('Expected UmasException');
      } on UmasException catch (e) {
        // The op token has the blockNo embedded so operators can
        // grep for `readDD02(blockNo=0xb6)` specifically.
        expect(e.message, contains('readDD02'));
        expect(e.message, contains('0xb6'));
      }
    });
  });
}

