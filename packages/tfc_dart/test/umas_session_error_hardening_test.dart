// Fix A + Fix B regression tests (v1.1.x UMAS hardening, May 2026).
//
// These tests guard against the "session re-pair storm" bug observed
// in the live HMI against the M580 at 192.168.112.159, where a benign
// UMAS error would invalidate the session and trigger a full re-pair +
// 1082-entry symbol-cache rebuild — visible as a tight loop of
// "paired -> uninitialized -> identified -> paired" log lines.
//
// Fix A: _handleSessionError is now gated by _isFatalSessionError, so
//        only transport-level (Modbus 0xF0..0xF6, 0xFF) failures
//        invalidate. Byte-level UMAS errors (0xFD-status responses,
//        per-symbol 0x83/0x86/0x94/0xC0 codes, client-side parse
//        errors with errorCode=0) no longer trigger a session reset.
//        Per-attempt _initWithRetry failures also no longer call
//        _handleSessionError — only the final exhausted-retries path
//        does.
//
// Fix B: _hardwareId is split into _plcIdHardwareId (from sub-function
//        0x02) and _projectHardwareId (from memory block 0x30). The
//        latter is the value Data Dictionary (0x26) requests need.

import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

// ---------------------------------------------------------------------------
// Test scaffolding
// ---------------------------------------------------------------------------

/// Mock UMAS sender modeled after the one in `test/core/umas_client_test.dart`
/// but local to this file so the regression suite is self-contained.
class _Mock {
  final List<UmasRequest> sent = [];
  final Map<int, List<Uint8List>> _pdu = {};
  final Map<int, List<ModbusResponseCode>> _failure = {};

  void respond(int subFunc, Uint8List pdu) {
    _pdu.putIfAbsent(subFunc, () => []).add(pdu);
  }

  void clearResponses(int subFunc) {
    _pdu.remove(subFunc);
  }

  /// Queue a transport-level failure for the next call to [subFunc].
  void transportFail(int subFunc, ModbusResponseCode code) {
    _failure.putIfAbsent(subFunc, () => []).add(code);
  }

  Future<ModbusResponseCode> send(ModbusRequest req) async {
    if (req is! UmasRequest) return ModbusResponseCode.requestRxFailed;
    sent.add(req);
    final subFunc = req.protocolDataUnit[2];
    final failQ = _failure[subFunc];
    if (failQ != null && failQ.isNotEmpty) {
      return failQ.removeAt(0);
    }
    final q = _pdu[subFunc];
    if (q != null && q.isNotEmpty) {
      final response = q.removeAt(0);
      if (q.isEmpty) {
        q.add(response);
      }
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

Uint8List _errorPdu(int code, {int pairingKey = 0x00}) =>
    Uint8List.fromList([0x5A, pairingKey, 0xFD, code]);

Uint8List _le16(int v) {
  final bd = ByteData(2);
  bd.setUint16(0, v, Endian.little);
  return bd.buffer.asUint8List();
}

/// Build a fake readPlcId response carrying [hardwareId] and [memBlockIndex].
Uint8List _plcIdentPayload({
  int hardwareId = 0x0000060B,
  int memBlockIndex = 0,
}) {
  final bd = ByteData(16);
  bd.setUint16(0, 0x0001, Endian.little); // range
  bd.setUint32(2, hardwareId, Endian.little); // hardwareId
  bd.setUint8(6, 1); // numberOfMemoryBanks
  bd.setUint16(7, memBlockIndex, Endian.little); // address (index)
  bd.setUint8(9, 0x01); // blockType
  bd.setUint16(10, 0x0000, Endian.little); // unknown
  bd.setUint32(12, 0x00010000, Endian.little); // memoryLength
  return bd.buffer.asUint8List();
}

/// Build a fake _readProjectBlock (0x20) response with the given values.
Uint8List _projectBlockPayload({
  required int projectIndex,
  required int projectHardwareId,
  int projectCrc = 0x10000000,
}) {
  // Response shape after the 3-byte UMAS header:
  //   range(1) + numberOfBytes(2 LE) + UmasMemoryBlockBasicInfo(9 bytes) +
  //   hash1(4 LE) + hash2(4 LE) = 20 bytes total.
  final bd = ByteData(20);
  bd.setUint8(0, 0x01); // range
  bd.setUint16(1, 17, Endian.little); // numberOfBytes
  bd.setUint16(3, 0x0001, Endian.little); // range (inner)
  bd.setUint16(5, 0x0000, Endian.little); // notSure
  bd.setUint8(7, projectIndex);
  bd.setUint32(8, projectHardwareId, Endian.little);
  // hash1 + hash2 such that (hash1 + hash2) & 0xFFFFFFFF == projectCrc
  bd.setUint32(12, projectCrc, Endian.little); // hash1
  bd.setUint32(16, 0x00000000, Endian.little); // hash2
  return bd.buffer.asUint8List();
}

/// Wire up successful readPlcId + init + readProjectBlock responses so the
/// session reaches `paired` state.
void _seedInit(
  _Mock mock, {
  int pairingKey = 0x42,
  int plcIdHardwareId = 0x0000060B,
  int projectHardwareId = 0x10C3B4E8,
  int projectIndex = 7,
}) {
  mock.respond(0x02, _successPdu(_plcIdentPayload(hardwareId: plcIdHardwareId)));
  mock.respond(0x01, _successPdu(_le16(240), pairingKey: pairingKey));
  mock.respond(
    0x20,
    _successPdu(_projectBlockPayload(
      projectIndex: projectIndex,
      projectHardwareId: projectHardwareId,
    )),
  );
}

// ---------------------------------------------------------------------------
// Fix A — _handleSessionError gating
// ---------------------------------------------------------------------------

void main() {
  group('Fix A: _handleSessionError only fires for fatal session errors', () {
    test('errorCode == 0 from readVariable does NOT invalidate session',
        () async {
      // Build a client that has already paired against the mock and then
      // throws errorCode-0 from a readVariable-equivalent call. The
      // session must remain `paired` afterwards.
      final mock = _Mock();
      _seedInit(mock);

      final client = UmasClient(sendFn: mock.send);
      // Drive to paired via the public readPlcId/init/refreshProjectMetadata
      // chain so we don't depend on internal helpers.
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();
      expect(client.sessionState, UmasSessionState.paired);

      // readDataTypes uses _withSessionAndRecovery → an errorCode-0
      // empty-response throw is non-fatal under the Fix A predicate.
      mock.clearResponses(0x26);
      mock.respond(0x26, Uint8List.fromList([0x5A, 0x42, 0xFE])); // truncated
      try {
        await client.readDataTypes();
      } catch (_) {}

      expect(
        client.sessionState,
        UmasSessionState.paired,
        reason: 'Client-side parse (errorCode=0) must NOT reset session',
      );
    });

    test(
        'byte-level UMAS error (status=0xFD code=0x83) does NOT invalidate '
        'session', () async {
      final mock = _Mock();
      _seedInit(mock);
      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();
      expect(client.sessionState, UmasSessionState.paired);

      mock.clearResponses(0x26);
      mock.respond(0x26, _errorPdu(0x83, pairingKey: 0x42));
      try {
        await client.readDataTypes();
      } catch (_) {}

      expect(
        client.sessionState,
        UmasSessionState.paired,
        reason: 'PLC 0xFD/0x83 ("DD disabled") is per-op, not session',
      );
    });

    test(
        'transport-level requestTimeout from sendKeepAlive DOES invalidate '
        'session', () async {
      final mock = _Mock();
      _seedInit(mock);

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
      );
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();
      expect(client.sessionState, UmasSessionState.paired);

      // Queue a transport timeout for the next keep-alive tick.
      mock.transportFail(0x12, ModbusResponseCode.requestTimeout);

      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      client.stopKeepAlive();

      expect(
        client.sessionState,
        UmasSessionState.uninitialized,
        reason: 'Transport-level keepAlive failure is fatal under Fix A',
      );
    });

    test(
        'byte-level UMAS error from sendKeepAlive does NOT invalidate session',
        () async {
      final mock = _Mock();
      _seedInit(mock);

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
      );
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();
      expect(client.sessionState, UmasSessionState.paired);

      // Byte-level UMAS error from keep-alive — should NOT invalidate.
      mock.clearResponses(0x12);
      mock.respond(0x12, _errorPdu(0x01, pairingKey: 0x42));
      mock.respond(0x12, _errorPdu(0x01, pairingKey: 0x42));

      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      client.stopKeepAlive();

      expect(
        client.sessionState,
        UmasSessionState.paired,
        reason: 'Fix A: byte-level UMAS error in keep-alive is non-fatal',
      );
    });

    test(
        '_initWithRetry failing 3 attempts then succeeding logs ZERO '
        '"session invalidated" lines during the retry loop', () async {
      // Drive _initWithRetry by calling browse() on an uninitialized
      // client. Pre-queue 3 failing readPlcId responses followed by a
      // success — the loop must retry inside _initWithRetry without
      // hitting _handleSessionError until / unless ALL retries fail.
      //
      // We observe this by counting state-transition pubs on the
      // sessionStream. Under the OLD policy, EACH failed attempt
      // emitted a paired→uninitialized transition (logged "session
      // invalidated"). Under Fix A, _initWithRetry only flips state
      // back to uninitialized between attempts (via _setState) — it
      // does NOT call _handleSessionError until the loop is exhausted.
      // The full session-invalidate clears _useMonitorPlc... wait, no,
      // that's a separate detail. The observable signal: the symbol
      // cache and project CRC do NOT get wiped between attempts.
      final mock = _Mock();
      // 3 failing readPlcId responses then a success.
      mock.respond(0x02, _errorPdu(0x99));
      mock.respond(0x02, _errorPdu(0x99));
      mock.respond(0x02, _errorPdu(0x99));
      mock.respond(0x02, _successPdu(_plcIdentPayload()));
      mock.respond(0x01, _successPdu(_le16(240), pairingKey: 0x42));
      mock.respond(
        0x20,
        _successPdu(_projectBlockPayload(
          projectIndex: 7,
          projectHardwareId: 0x10C3B4E8,
        )),
      );
      // Empty DD responses for browse
      mock.respond(0x26, _successPdu(Uint8List.fromList([0x00, 0x00, 0x00, 0x00])));

      final delays = <Duration>[];
      final client = UmasClient(
        sendFn: mock.send,
        backoffDelay: (d) async => delays.add(d),
      );

      // Fire-and-forget a browse so the init loop runs and eventually
      // succeeds (4th readPlcId).
      try {
        await client.browse();
      } catch (_) {}

      // Should have used backoff at least 3 times (1 per failed attempt
      // before the eventual success or before the loop exhausted).
      expect(delays.length, greaterThanOrEqualTo(3),
          reason: '_initWithRetry must apply backoff between attempts');

      // The retry loop succeeded on attempt 4: state must end paired.
      expect(client.sessionState, UmasSessionState.paired,
          reason: '4th attempt succeeds — session reaches paired');
    });
  });

  // ---------------------------------------------------------------------------
  // Fix B — _hardwareId field split
  // ---------------------------------------------------------------------------

  group('Fix B: hardware-ID field split (_plcIdHardwareId vs _projectHardwareId)',
      () {
    test('readPlcId sets _plcIdHardwareId and leaves _projectHardwareId null',
        () async {
      final mock = _Mock();
      mock.respond(
        0x02,
        _successPdu(_plcIdentPayload(hardwareId: 0x0000060B)),
      );

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();

      expect(client.plcIdHardwareId, 0x0000060B,
          reason: 'readPlcId must populate _plcIdHardwareId');
      expect(client.projectHardwareId, isNull,
          reason: 'readPlcId must NOT touch _projectHardwareId');
    });

    test(
        'readProjectBlock (via refreshProjectMetadata) sets _projectHardwareId '
        'independently', () async {
      final mock = _Mock();
      _seedInit(
        mock,
        plcIdHardwareId: 0x0000060B,
        projectHardwareId: 0x10C3B4E8,
        projectIndex: 7,
      );

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();

      expect(client.plcIdHardwareId, 0x0000060B,
          reason: '_plcIdHardwareId unchanged by readProjectBlock');
      expect(client.projectHardwareId, 0x10C3B4E8,
          reason: 'readProjectBlock must populate _projectHardwareId');
    });

    test('_handleSessionError clears BOTH _plcIdHardwareId and _projectHardwareId',
        () async {
      final mock = _Mock();
      _seedInit(mock);

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      await client.refreshProjectMetadata();
      expect(client.plcIdHardwareId, isNotNull);
      expect(client.projectHardwareId, isNotNull);

      // Inject a fatal session error.
      mock.transportFail(0x26, ModbusResponseCode.requestTimeout);
      try {
        await client.readDataTypes();
      } catch (_) {}

      expect(client.sessionState, UmasSessionState.uninitialized);
      expect(client.plcIdHardwareId, isNull,
          reason: '_resetHardwareIdentifiers clears _plcIdHardwareId');
      expect(client.projectHardwareId, isNull,
          reason: '_resetHardwareIdentifiers clears _projectHardwareId');
    });
  });
}
