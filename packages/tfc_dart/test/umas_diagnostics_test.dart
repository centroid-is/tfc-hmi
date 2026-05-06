import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';

// ---------------------------------------------------------------------------
// Test helpers (replicated from umas_client_test.dart for isolation)
// ---------------------------------------------------------------------------

class MockUmasSender {
  final List<UmasRequest> sentRequests = [];
  final Map<int, List<Uint8List>> _responseQueues = {};

  void whenSubFunction(int subFunc, Uint8List responsePdu) {
    _responseQueues.putIfAbsent(subFunc, () => []).add(responsePdu);
  }

  Future<ModbusResponseCode> send(ModbusRequest request) async {
    if (request is UmasRequest) {
      sentRequests.add(request);
      final pdu = request.protocolDataUnit;
      final subFunc = pdu[2];
      final queue = _responseQueues[subFunc];
      if (queue != null && queue.isNotEmpty) {
        final response = queue.removeAt(0);
        if (queue.isEmpty) {
          queue.add(response);
        }
        request.setFromPduResponse(response);
        return request.responseCode;
      }
    }
    return ModbusResponseCode.requestRxFailed;
  }
}

Uint8List buildSuccessResponse(int subFunc, Uint8List payload,
    {int pairingKey = 0x00}) {
  final pdu = Uint8List(3 + payload.length);
  pdu[0] = 0x5A;
  pdu[1] = pairingKey;
  pdu[2] = 0xFE;
  pdu.setAll(3, payload);
  return pdu;
}

Uint8List buildErrorResponse(int errorCode,
    {int pairingKey = 0x00, int subFunc = 0x00}) {
  return Uint8List.fromList([0x5A, pairingKey, 0xFD, errorCode]);
}

Uint8List leUint16(int value) {
  final bd = ByteData(2);
  bd.setUint16(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List leUint32(int value) {
  final bd = ByteData(4);
  bd.setUint32(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List buildPlcIdentResponse({
  int hardwareId = 0x12345678,
  int numberOfMemoryBanks = 1,
  int memBlockIndex = 0,
}) {
  final bytes = <int>[];
  bytes.addAll(leUint16(0x0001));
  bytes.addAll(leUint32(hardwareId));
  bytes.add(numberOfMemoryBanks);
  for (int i = 0; i < numberOfMemoryBanks; i++) {
    bytes.addAll(leUint16(memBlockIndex + i));
    bytes.add(0x01);
    bytes.addAll(leUint16(0x0000));
    bytes.addAll(leUint32(0x00010000));
  }
  return Uint8List.fromList(bytes);
}

/// Queue readPlcId + init responses so _withSession can auto-initialize.
void queueSessionInit(MockUmasSender mock, {int pairingKey = 0x42}) {
  mock.whenSubFunction(
      0x02, buildSuccessResponse(0x02, buildPlcIdentResponse()));
  mock.whenSubFunction(
      0x01, buildSuccessResponse(0x01, leUint16(240), pairingKey: pairingKey));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Diagnostic UmasSubFunction enum entries', () {
    test('readCardInfo has code 0x06', () {
      expect(UmasSubFunction.readCardInfo.code, 0x06);
    });

    test('readMemoryBlock has code 0x20', () {
      expect(UmasSubFunction.readMemoryBlock.code, 0x20);
    });

    test('readEthMasterData has code 0x39', () {
      expect(UmasSubFunction.readEthMasterData.code, 0x39);
    });

    test('checkPlc has code 0x58', () {
      expect(UmasSubFunction.checkPlc.code, 0x58);
    });

    test('readIoObject has code 0x70', () {
      expect(UmasSubFunction.readIoObject.code, 0x70);
    });

    test('getStatusModule has code 0x73', () {
      expect(UmasSubFunction.getStatusModule.code, 0x73);
    });
  });

  group('ReadMemoryBlockRequest', () {
    test('toBytes() produces 9-byte LE payload', () {
      final req = ReadMemoryBlockRequest(
        range: 0x01,
        blockNumber: 0x0002,
        offset: 0x0003,
        numberOfBytes: 16,
      );
      final bytes = req.toBytes();
      expect(bytes.length, 9);

      expect(bytes[0], 0x01);
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint16(1, Endian.little), 0x0002);
      expect(bd.getUint16(3, Endian.little), 0x0003);
      expect(bd.getUint16(5, Endian.little), 0x0000);
      expect(bd.getUint16(7, Endian.little), 16);
    });

    test('toBytes() with custom unknownObj', () {
      final req = ReadMemoryBlockRequest(
        range: 0,
        blockNumber: 1,
        offset: 0,
        numberOfBytes: 8,
        unknownObj: 0x1234,
      );
      final bytes = req.toBytes();
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint16(5, Endian.little), 0x1234);
    });
  });

  group('ReadMemoryBlockResult', () {
    test('fromPayload() parses range + numberOfBytes + data', () {
      final payload = Uint8List(7);
      payload[0] = 0x02;
      final bd = ByteData.sublistView(payload);
      bd.setUint16(1, 4, Endian.little);
      payload[3] = 0xAA;
      payload[4] = 0xBB;
      payload[5] = 0xCC;
      payload[6] = 0xDD;

      final result = ReadMemoryBlockResult.fromPayload(payload);
      expect(result.range, 0x02);
      expect(result.numberOfBytes, 4);
      expect(result.data, Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD]));
    });

    test('fromPayload() throws on short payload', () {
      expect(
        () => ReadMemoryBlockResult.fromPayload(Uint8List(2)),
        throwsA(isA<UmasException>()),
      );
    });

    test('fromPayload() validates numberOfBytes against data length', () {
      final payload = Uint8List(5);
      payload[0] = 0x00;
      final bd = ByteData.sublistView(payload);
      bd.setUint16(1, 100, Endian.little);

      expect(
        () => ReadMemoryBlockResult.fromPayload(payload),
        throwsA(isA<UmasException>()),
      );
    });
  });

  group('Simple diagnostic result types', () {
    test('CardInfoResult holds rawData', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final result = CardInfoResult(rawData: data);
      expect(result.rawData, data);
    });

    test('EthMasterDataResult holds rawData', () {
      final data = Uint8List.fromList([4, 5, 6]);
      final result = EthMasterDataResult(rawData: data);
      expect(result.rawData, data);
    });

    test('CheckPlcResult holds rawData', () {
      final data = Uint8List.fromList([7, 8, 9]);
      final result = CheckPlcResult(rawData: data);
      expect(result.rawData, data);
    });

    test('StatusModuleResult holds rawData', () {
      final data = Uint8List.fromList([10, 11, 12]);
      final result = StatusModuleResult(rawData: data);
      expect(result.rawData, data);
    });

    test('IoObjectResult holds rawData', () {
      final data = Uint8List.fromList([13, 14, 15]);
      final result = IoObjectResult(rawData: data);
      expect(result.rawData, data);
    });
  });

  // -------------------------------------------------------------------------
  // Task 2: Client method tests
  // -------------------------------------------------------------------------

  group('UmasClient.readCardInfo()', () {
    test('sends 0x06 request and returns CardInfoResult', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      final cardData = Uint8List.fromList([0x01, 0x00, 0x00, 0x00, 0xAA, 0xBB]);
      mock.whenSubFunction(0x06, buildSuccessResponse(0x06, cardData));

      final client = UmasClient(sendFn: mock.send);
      final result = await client.readCardInfo();

      expect(result.rawData, cardData);
    });

    test('throws UmasException on error response', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      mock.whenSubFunction(0x06, buildErrorResponse(0x42));

      final client = UmasClient(sendFn: mock.send);
      expect(() => client.readCardInfo(), throwsA(isA<UmasException>()));
    });
  });

  group('UmasClient.readMemoryBlock()', () {
    test('sends 0x20 with request payload and returns parsed result', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      // Build response: range(1) + numberOfBytes(2 LE) + data[4]
      final respPayload = Uint8List(7);
      respPayload[0] = 0x01; // range
      final bd = ByteData.sublistView(respPayload);
      bd.setUint16(1, 4, Endian.little);
      respPayload[3] = 0x11;
      respPayload[4] = 0x22;
      respPayload[5] = 0x33;
      respPayload[6] = 0x44;

      mock.whenSubFunction(0x20, buildSuccessResponse(0x20, respPayload));

      final client = UmasClient(sendFn: mock.send);
      final request = ReadMemoryBlockRequest(
        range: 0x01,
        blockNumber: 1,
        offset: 0,
        numberOfBytes: 4,
      );
      final result = await client.readMemoryBlock(request);

      expect(result.range, 0x01);
      expect(result.numberOfBytes, 4);
      expect(result.data, Uint8List.fromList([0x11, 0x22, 0x33, 0x44]));
    });

    test('throws on error response', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      mock.whenSubFunction(0x20, buildErrorResponse(0x02));

      final client = UmasClient(sendFn: mock.send);
      final request = ReadMemoryBlockRequest(
        range: 0,
        blockNumber: 1,
        offset: 0,
        numberOfBytes: 16,
      );
      expect(
          () => client.readMemoryBlock(request), throwsA(isA<UmasException>()));
    });

    test('sends 9-byte request payload from ReadMemoryBlockRequest', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      // Minimal valid response
      final respPayload = Uint8List(3);
      respPayload[0] = 0x00;
      final bd = ByteData.sublistView(respPayload);
      bd.setUint16(1, 0, Endian.little);

      mock.whenSubFunction(0x20, buildSuccessResponse(0x20, respPayload));

      final client = UmasClient(sendFn: mock.send);
      final request = ReadMemoryBlockRequest(
        range: 0x05,
        blockNumber: 0x0A,
        offset: 0x0B,
        numberOfBytes: 0,
      );
      await client.readMemoryBlock(request);

      // _initWithRetry() also sends a 0x20 request via _readProjectBlock to
      // read the project memory block at 0x30 — so we expect at least two
      // 0x20 requests in sentRequests. The user-issued request is the last
      // one (range=0x05, blockNumber=0x0A).
      final sent0x20 = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x20)
          .toList();
      expect(sent0x20, isNotEmpty);
      // Payload is in protocolDataUnit after 3-byte header (FC+pairing+subfunc)
      final sentPayload = sent0x20.last.protocolDataUnit.sublist(3);
      expect(sentPayload.length, 9);
      expect(sentPayload[0], 0x05); // range
    });
  });

  group('UmasClient.readEthMasterData()', () {
    test('sends 0x39 and returns EthMasterDataResult', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      final ethData = Uint8List.fromList([0x01, 0x02, 192, 168, 1, 1]);
      mock.whenSubFunction(0x39, buildSuccessResponse(0x39, ethData));

      final client = UmasClient(sendFn: mock.send);
      final result = await client.readEthMasterData();

      expect(result.rawData, ethData);
    });
  });

  group('UmasClient.checkPlc()', () {
    test('sends 0x58 and returns CheckPlcResult', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      final plcData = Uint8List.fromList([0x00, 0x00, 0x00, 0x00]);
      mock.whenSubFunction(0x58, buildSuccessResponse(0x58, plcData));

      final client = UmasClient(sendFn: mock.send);
      final result = await client.checkPlc();

      expect(result.rawData, plcData);
    });
  });

  group('UmasClient.getStatusModule()', () {
    test('sends 0x73 and returns StatusModuleResult', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      final statusData = Uint8List.fromList([0x01, 0x00, 0x03]);
      mock.whenSubFunction(0x73, buildSuccessResponse(0x73, statusData));

      final client = UmasClient(sendFn: mock.send);
      final result = await client.getStatusModule();

      expect(result.rawData, statusData);
    });
  });

  group('UmasClient.readIoObject()', () {
    test('sends 0x70 and returns IoObjectResult', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      final ioData = Uint8List.fromList([0x01, 0x00, 0xFF, 0xAA]);
      mock.whenSubFunction(0x70, buildSuccessResponse(0x70, ioData));

      final client = UmasClient(sendFn: mock.send);
      final result = await client.readIoObject();

      expect(result.rawData, ioData);
    });
  });

  group('Diagnostic methods auto-initialize session', () {
    test('readCardInfo auto-initializes via _withSession', () async {
      final mock = MockUmasSender();
      queueSessionInit(mock);

      final cardData = Uint8List.fromList([0x01]);
      mock.whenSubFunction(0x06, buildSuccessResponse(0x06, cardData));

      final client = UmasClient(sendFn: mock.send);
      // Client starts uninitialized -- readCardInfo should auto-init
      expect(client.sessionState, UmasSessionState.uninitialized);
      await client.readCardInfo();
      expect(client.sessionState, UmasSessionState.paired);

      // Should have sent: readPlcId (0x02), init (0x01), readCardInfo (0x06)
      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(subFuncs, contains(0x02));
      expect(subFuncs, contains(0x01));
      expect(subFuncs, contains(0x06));
    });
  });
}
