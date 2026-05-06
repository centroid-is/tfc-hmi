import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:tfc_dart/core/umas_client.dart';

/// Mock send function that captures requests and returns canned responses.
/// Supports returning different responses per call to the same sub-function
/// (needed for pagination: first 0x26 returns page 1, second returns page 2).
class MockUmasSender {
  final List<UmasRequest> sentRequests = [];

  /// Queue of responses per sub-function code. Consumed in order.
  final Map<int, List<Uint8List>> _responseQueues = {};

  /// Register a canned PDU response for a given sub-function code.
  /// Multiple calls with the same sub-function add to the queue.
  void whenSubFunction(int subFunc, Uint8List responsePdu) {
    _responseQueues.putIfAbsent(subFunc, () => []).add(responsePdu);
  }

  Future<ModbusResponseCode> send(ModbusRequest request) async {
    if (request is UmasRequest) {
      sentRequests.add(request);
      final pdu = request.protocolDataUnit;
      // Sub-function is at index 2 in the PDU (FC=0, pairingKey=1, subFunc=2)
      final subFunc = pdu[2];
      final queue = _responseQueues[subFunc];
      if (queue != null && queue.isNotEmpty) {
        final response = queue.removeAt(0);
        // If queue is empty after consuming, re-add the last response
        // so that subsequent calls don't fail (single-page scenario).
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

/// Build a UMAS success response PDU.
/// Real Schneider PLC format (3-byte header): FC(0x5A) + pairingKey + status(0xFE) + payload
/// The [subFunc] parameter is kept for API compatibility but is unused in the
/// response PDU (real PLCs do not echo the sub-function).
Uint8List buildSuccessResponse(int subFunc, Uint8List payload,
    {int pairingKey = 0x00}) {
  final pdu = Uint8List(3 + payload.length);
  pdu[0] = 0x5A; // FC90
  pdu[1] = pairingKey;
  pdu[2] = 0xFE; // Success status
  pdu.setAll(3, payload);
  return pdu;
}

/// Build a UMAS error response PDU.
/// Real Schneider PLC format (3-byte header): FC(0x5A) + pairingKey + status(0xFD) + errorCode
/// The [subFunc] parameter is kept for API compatibility but is unused.
Uint8List buildErrorResponse(int errorCode,
    {int pairingKey = 0x00, int subFunc = 0x00}) {
  return Uint8List.fromList([0x5A, pairingKey, 0xFD, errorCode]);
}

/// Build little-endian uint16 bytes.
Uint8List leUint16(int value) {
  final bd = ByteData(2);
  bd.setUint16(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

/// Build little-endian uint32 bytes.
Uint8List leUint32(int value) {
  final bd = ByteData(4);
  bd.setUint32(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

/// Build a PLC Identification (0x02) response payload.
///
/// Simplified format matching what readPlcId() expects:
/// range(2) + ident/hardwareId(4 LE) + padding(to reach numBanks) +
/// numberOfMemoryBanks(1) + PlcMemoryBlockIdent entries
Uint8List buildPlcIdentResponse({
  int hardwareId = 0x12345678,
  int numberOfMemoryBanks = 1,
  int memBlockIndex = 0,
}) {
  final bytes = <int>[];
  // range: 2 bytes
  bytes.addAll(leUint16(0x0001));
  // ident / hardwareId: 4 bytes LE
  bytes.addAll(leUint32(hardwareId));
  // numberOfMemoryBanks: 1 byte
  bytes.add(numberOfMemoryBanks);
  // PlcMemoryBlockIdent entries (one per bank):
  //   address(2) + blockType(1) + unknown(2) + memoryLength(4) = 9 bytes each
  for (int i = 0; i < numberOfMemoryBanks; i++) {
    bytes.addAll(leUint16(memBlockIndex + i)); // address (used as index)
    bytes.add(0x01); // blockType
    bytes.addAll(leUint16(0x0000)); // unknown
    bytes.addAll(leUint32(0x00010000)); // memoryLength
  }
  return Uint8List.fromList(bytes);
}

/// Build a data dictionary variable names (0xDD02) top-level response payload.
///
/// Per PLC4X UmasPDUReadUnlocatedVariableNamesResponse mspec:
///   Header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE)
///   Top-level record (10-byte header):
///     dataType(2 LE) + block(2 LE) + offset(4 LE) + flags(1) + unknown4(1)
///     + null-terminated UTF-8 name
Uint8List buildVariableNamesPayload(
    List<({String name, int blockNo, int offset, int typeId})> records,
    {int nextAddress = 0x0000}) {
  final bytes = <int>[];
  bytes.add(0x00); // range
  bytes.addAll(leUint16(nextAddress));
  bytes.addAll(leUint16(0x0000)); // unknown1
  bytes.addAll(leUint16(records.length));

  for (final r in records) {
    bytes.addAll(leUint16(r.typeId)); // dataType
    bytes.addAll(leUint16(r.blockNo)); // block
    bytes.addAll(leUint32(r.offset)); // offset (uint32)
    bytes.add(0xFF); // flags (non-zero -> top-level format)
    bytes.add(0x01); // unknown4
    bytes.addAll(r.name.codeUnits);
    bytes.add(0x00); // null terminator
  }
  return Uint8List.fromList(bytes);
}

/// Build a data dictionary data types (0xDD03) response payload.
///
/// Per PLC4X UmasPDUReadDatatypeNamesResponse mspec:
///   Header: range(1) + unknown1(4) + noOfRecords(2 LE)  -- 7 bytes
///   Per record (UmasDatatypeReference):
///     dataSize(2 LE) + unknown1(2 LE) + classIdentifier(1) + dataType(1)
///     + reserved 0x00(1) + null-terminated UTF-8 name
///
/// DD03 does not paginate (single full response).
Uint8List buildDataTypesPayload(
    List<({int id, String name, int byteSize, int classId, int dataType})>
        records,
    {int nextAddress = 0x0000}) {
  final bytes = <int>[];
  bytes.add(0x00); // range
  // unknown1 (4 bytes) — historically used as nextAddress in tests; preserve
  // the low 16 bits so the legacy `nextAddress` arg still flows through.
  bytes.addAll(leUint16(nextAddress));
  bytes.addAll(leUint16(0x0000));
  bytes.addAll(leUint16(records.length));

  for (final r in records) {
    bytes.addAll(leUint16(r.byteSize)); // dataSize
    bytes.addAll(leUint16(0x0000)); // unknown1
    bytes.add(r.classId); // classIdentifier
    bytes.add(r.dataType); // dataType
    bytes.add(0x00); // reserved
    bytes.addAll(r.name.codeUnits);
    bytes.add(0x00); // null terminator
  }
  return Uint8List.fromList(bytes);
}


void main() {
  group('UmasRequest PDU construction', () {
    test('builds correct PDU with FC=0x5A, pairing key, sub-function, '
        'and payload', () {
      final payload = Uint8List.fromList([0x02, 0xDD]);
      final request = UmasRequest(
        umasSubFunction: 0x26,
        pairingKey: 0x05,
        payload: payload,
      );

      final pdu = request.protocolDataUnit;
      expect(pdu[0], 0x5A, reason: 'FC byte should be 0x5A');
      expect(pdu[1], 0x05, reason: 'Pairing key should be 0x05');
      expect(pdu[2], 0x26, reason: 'Sub-function should be 0x26');
      expect(pdu.sublist(3), [0x02, 0xDD], reason: 'Payload should follow');
      expect(request.functionCode.code, 0x5A);
      expect(request.functionCode.type, FunctionType.custom);
    });

    test('init sub-function (0x01) has empty payload and correct PDU length',
        () {
      final request = UmasRequest(umasSubFunction: 0x01);
      final pdu = request.protocolDataUnit;
      expect(pdu.length, 3, reason: 'FC + pairingKey + subFunc = 3 bytes');
      expect(pdu[0], 0x5A);
      expect(pdu[1], 0x00, reason: 'Default pairing key is 0x00');
      expect(pdu[2], 0x01);
    });
  });

  group('UmasClient.init()', () {
    test('parses init response to extract max frame size (LE uint16)',
        () async {
      final mock = MockUmasSender();
      // Init response payload: maxFrameSize(2 LE) = 0x00F0 = 240
      final payload = leUint16(240);
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, payload));

      final client = UmasClient(sendFn: mock.send);
      final result = await client.init();

      expect(result.maxFrameSize, 240);
      expect(mock.sentRequests.length, 1);
      expect(mock.sentRequests.first.protocolDataUnit[2], 0x01);
    });
  });

  group('UmasClient.readPlcId()', () {
    test('parses 0x02 response to extract hardwareId and index', () async {
      final mock = MockUmasSender();
      final plcIdentPayload = buildPlcIdentResponse(
        hardwareId: 0xAABBCCDD,
        numberOfMemoryBanks: 2,
        memBlockIndex: 3,
      );
      mock.whenSubFunction(
          0x02, buildSuccessResponse(0x02, plcIdentPayload));

      final client = UmasClient(sendFn: mock.send);
      final ident = await client.readPlcId();

      expect(ident.hardwareId, 0xAABBCCDD);
      expect(ident.index, 3);
      expect(ident.numberOfMemoryBanks, 2);
      expect(mock.sentRequests.length, 1);
      expect(mock.sentRequests.first.protocolDataUnit[2], 0x02);
    });
  });

  group('UmasClient.readVariableNames()', () {
    test('parses corrected 0x26/0xDD02 response with header and record format',
        () async {
      final mock = MockUmasSender();
      // Set up readPlcId and init first
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      // Variable names payload with 2 records (corrected format with header)
      final varsPayload = buildVariableNamesPayload([
        (
          name: 'Application.GVL.temperature',
          blockNo: 1,
          offset: 0,
          typeId: 5
        ),
        (
          name: 'Application.GVL.pressure',
          blockNo: 1,
          offset: 4,
          typeId: 5
        ),
      ]);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, varsPayload));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final variables = await client.readVariableNames();

      expect(variables.length, 2);
      expect(variables[0].name, 'Application.GVL.temperature');
      expect(variables[0].blockNo, 1);
      expect(variables[0].offset, 0);
      expect(variables[0].dataTypeId, 5);
      expect(variables[1].name, 'Application.GVL.pressure');
      expect(variables[1].offset, 4);
    });

    test('paginates when nextAddress != 0', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      // Page 1: nextAddress = 0x0050 (not zero = more pages)
      final page1 = buildVariableNamesPayload(
        [
          (name: 'App.GVL.temp', blockNo: 1, offset: 0, typeId: 5),
          (name: 'App.GVL.pressure', blockNo: 1, offset: 4, typeId: 5),
        ],
        nextAddress: 0x0050,
      );
      // Page 2: nextAddress = 0x0000 (done)
      final page2 = buildVariableNamesPayload(
        [
          (name: 'App.Motor.speed', blockNo: 2, offset: 0, typeId: 3),
        ],
        nextAddress: 0x0000,
      );

      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, page1));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, page2));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final variables = await client.readVariableNames();

      expect(variables.length, 3,
          reason: 'Should accumulate variables from both pages');
      expect(variables[0].name, 'App.GVL.temp');
      expect(variables[1].name, 'App.GVL.pressure');
      expect(variables[2].name, 'App.Motor.speed');
    });
  });

  group('UmasClient.readDataTypes()', () {
    test('parses corrected 0x26/0xDD03 response with classIdentifier and dataType',
        () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      final typesPayload = buildDataTypesPayload([
        (id: 100, name: 'MY_STRUCT', byteSize: 16, classId: 2, dataType: 27),
        (id: 101, name: 'VALVE_TYPE', byteSize: 8, classId: 0, dataType: 5),
      ]);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, typesPayload));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final types = await client.readDataTypes();

      expect(types.length, 2);
      // Per the corrected parser, `id` mirrors the PLC-assigned `dataType`
      // byte so that DD02 records can resolve to their DD03 entry directly.
      expect(types[0].id, 27);
      expect(types[0].dataType, 27);
      expect(types[0].name, 'MY_STRUCT');
      expect(types[0].byteSize, 16);
      expect(types[0].classIdentifier, 2);
      expect(types[1].id, 5);
      expect(types[1].name, 'VALVE_TYPE');
      expect(types[1].byteSize, 8);
      expect(types[1].dataType, 5);
    });

    test('DD03 returns the full type table in a single (non-paginated) call',
        () async {
      // PLC4X confirms DD03 is not paginated — the whole type table arrives
      // in one response. Verify that even if a `nextAddress` field is set in
      // the wire (legacy behaviour), the parser does not loop indefinitely.
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      final payload = buildDataTypesPayload(
        [
          (id: 100, name: 'MY_STRUCT', byteSize: 16, classId: 2, dataType: 27),
          (id: 101, name: 'VALVE_TYPE', byteSize: 8, classId: 0, dataType: 5),
        ],
        nextAddress: 0x0020, // ignored by the new parser
      );
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, payload));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final types = await client.readDataTypes();

      expect(types.length, 2);
      expect(types[0].name, 'MY_STRUCT');
      expect(types[1].name, 'VALVE_TYPE');
    });
  });

  group('UmasClient.browse()', () {
    test('calls readPlcId before init in correct sequence', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      // Empty data types and variable names responses
      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);

      // browse() calls readDataTypes (DD03) before readVariableNames (DD02)
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      final client = UmasClient(sendFn: mock.send);
      await client.browse();

      // Verify call order: 0x02 (readPlcId), 0x01 (init), 0x20 (readProjectBlock), 0x26 (DD03), 0x26 (DD02)
      expect(mock.sentRequests.length, greaterThanOrEqualTo(5));
      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(subFuncs[0], 0x02, reason: 'First call should be readPlcId');
      expect(subFuncs[1], 0x01, reason: 'Second call should be init');
      expect(subFuncs[2], 0x20, reason: 'Third call should be readProjectBlock');
      // Remaining calls are 0x26 for data dictionary reads
      expect(subFuncs.sublist(3).every((sf) => sf == 0x26), isTrue);
    });
  });

  group('0x26 request payload', () {
    test('is 13 bytes with correct fields', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(0x02,
              buildPlcIdentResponse(hardwareId: 0xAABBCCDD, memBlockIndex: 5)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      final varsPayload = buildVariableNamesPayload([
        (name: 'App.x', blockNo: 1, offset: 0, typeId: 1),
      ]);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, varsPayload));

      // Need both DD03 (empty) and DD02 for browse()
      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      // First 0x26 call gets DD03 (empty), second gets DD02
      // Reset and re-queue
      mock._responseQueues.remove(0x26);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, varsPayload));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      await client.readVariableNames();

      // Find the 0x26 request (third sent request: after 0x02 and 0x01)
      final ddRequests =
          mock.sentRequests.where((r) => r.protocolDataUnit[2] == 0x26);
      expect(ddRequests, isNotEmpty);

      final firstDdRequest = ddRequests.first;
      // Payload starts after FC(1) + pairingKey(1) + subFunc(1) = index 3
      final fullPdu = firstDdRequest.protocolDataUnit;
      final payload = fullPdu.sublist(3);

      expect(payload.length, 13,
          reason: '0x26 payload should be 13 bytes');

      final pd = ByteData.sublistView(payload);
      // recordType at offset 0 (2 bytes LE)
      final recordType = pd.getUint16(0, Endian.little);
      expect(recordType == 0xDD02 || recordType == 0xDD03, isTrue,
          reason: 'Record type should be DD02 or DD03');

      // index at offset 2 (1 byte)
      expect(pd.getUint8(2), 5, reason: 'Index should match PLC ident');

      // hardwareId at offset 3 (4 bytes LE)
      expect(pd.getUint32(3, Endian.little), 0xAABBCCDD,
          reason: 'HardwareId should match PLC ident');

      // blank at offset 11 (2 bytes LE)
      expect(pd.getUint16(11, Endian.little), 0x0000,
          reason: 'Blank field should be 0');
    });
  });

  group('UmasClient.buildVariableTree()', () {
    test('constructs hierarchical tree from flat variable list using '
        'dot-separated names', () {
      final variables = [
        const UmasVariable(
            name: 'App.GVL.temp', blockNo: 1, offset: 0, dataTypeId: 5),
        const UmasVariable(
            name: 'App.GVL.pressure', blockNo: 1, offset: 4, dataTypeId: 5),
        const UmasVariable(
            name: 'App.Motor.speed', blockNo: 2, offset: 0, dataTypeId: 3),
      ];
      final dataTypes = <UmasDataTypeRef>[];

      final client = UmasClient(
          sendFn: (_) async => ModbusResponseCode.requestSucceed);
      final tree = client.buildVariableTree(variables, dataTypes);

      // Root should have 1 node: "App"
      expect(tree.length, 1);
      expect(tree[0].name, 'App');
      expect(tree[0].isFolder, true);

      // App should have 2 children: GVL and Motor
      expect(tree[0].children.length, 2);
      final gvl = tree[0].children.firstWhere((n) => n.name == 'GVL');
      final motor = tree[0].children.firstWhere((n) => n.name == 'Motor');

      // GVL should have 2 leaf variables
      expect(gvl.children.length, 2);
      expect(gvl.children[0].variable, isNotNull);
      expect(gvl.children[0].name, 'temp');

      // Motor should have 1 leaf variable
      expect(motor.children.length, 1);
      expect(motor.children[0].name, 'speed');
      expect(motor.children[0].variable?.dataTypeId, 3);
    });
  });

  group('UmasClient error handling', () {
    test('handles 0xFD error response gracefully (throws UmasException)',
        () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x01, buildErrorResponse(0x42, subFunc: 0x01));

      final client = UmasClient(sendFn: mock.send);

      expect(
        () => client.init(),
        throwsA(isA<UmasException>()
            .having((e) => e.errorCode, 'errorCode', 0x42)),
      );
    });

    test('handles Data Dictionary not enabled (0x26 failure)', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));
      // 0x26 returns error
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      expect(
        () => client.readVariableNames(),
        throwsA(isA<UmasException>()),
      );
    });
  });

  group('UmasClient session state machine', () {
    test('starts in uninitialized state', () {
      final client = UmasClient(
          sendFn: (_) async => ModbusResponseCode.requestSucceed);
      expect(client.sessionState, UmasSessionState.uninitialized);
    });

    test('readPlcId transitions to identified', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      expect(client.sessionState, UmasSessionState.identified);
    });

    test('init transitions to paired', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      expect(client.sessionState, UmasSessionState.paired);
    });

    test('sessionStream emits state changes', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      final client = UmasClient(sendFn: mock.send);

      // Collect all emitted states
      final states = <UmasSessionState>[];
      final sub = client.sessionStream.listen(states.add);

      // Allow the seeded value to be delivered
      await Future<void>.delayed(Duration.zero);

      await client.readPlcId();
      await client.init();

      // Allow stream events to propagate
      await Future<void>.delayed(Duration.zero);

      sub.cancel();

      expect(states, [
        UmasSessionState.uninitialized,
        UmasSessionState.identified,
        UmasSessionState.paired,
      ]);
    });
  });

  group('UmasClient session invalidation', () {
    /// Helper: set up mock for a full successful init sequence (0x02 + 0x01).
    void setupInitSequence(MockUmasSender mock, {int pairingKey = 0x42}) {
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: pairingKey));
    }

    test('UMAS error resets session state to uninitialized', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      expect(client.sessionState, UmasSessionState.paired);

      // Queue an error response for readVariableNames (0x26)
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26, pairingKey: 0x42));

      await expectLater(
        client.readVariableNames(),
        throwsA(isA<UmasException>()),
      );

      // After the error, session should be reset to uninitialized
      expect(client.sessionState, UmasSessionState.uninitialized);
    });

    test('reset clears pairing key', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock, pairingKey: 0x42);

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      // Trigger error to reset session
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26, pairingKey: 0x42));
      try {
        await client.readVariableNames();
      } catch (_) {}

      // Clear stale queues and queue fresh init + DD responses for recovery
      mock._responseQueues.remove(0x02);
      mock._responseQueues.remove(0x01);
      mock._responseQueues.remove(0x26);
      setupInitSequence(mock, pairingKey: 0x55);

      // Queue a successful DD02 response for the readVariableNames call
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      // Next call should re-init; check that the 0x02 request has pairingKey == 0x00
      await client.readVariableNames();

      // Find the second 0x02 request (the re-init one)
      final readPlcIdRequests = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x02)
          .toList();
      expect(readPlcIdRequests.length, 2,
          reason: 'Should have two readPlcId calls');
      // The re-init readPlcId should use pairingKey 0x00 (reset)
      expect(readPlcIdRequests[1].protocolDataUnit[1], 0x00,
          reason: 'Pairing key should be 0x00 after reset');
    });

    test('browse recovers after session invalidation', () async {
      final mock = MockUmasSender();
      // First init sequence
      setupInitSequence(mock, pairingKey: 0x42);

      // First browse succeeds: DD03 + DD02
      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      final client = UmasClient(sendFn: mock.send);
      final tree1 = await client.browse();
      expect(tree1, isEmpty);
      expect(client.sessionState, UmasSessionState.paired);

      // Now queue an error for the next DD03 call (readDataTypes in browse)
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26, pairingKey: 0x42));

      // Second browse throws
      await expectLater(client.browse(), throwsA(isA<UmasException>()));

      // Clear stale queues and queue fresh init + browse responses for recovery
      mock._responseQueues.remove(0x02);
      mock._responseQueues.remove(0x01);
      mock._responseQueues.remove(0x26);
      setupInitSequence(mock, pairingKey: 0x55);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      // Third browse should recover (re-init from uninitialized)
      final tree3 = await client.browse();
      expect(tree3, isEmpty);
      expect(client.sessionState, UmasSessionState.paired);
    });

    test('sessionStream emits uninitialized on reset', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final client = UmasClient(sendFn: mock.send);

      final states = <UmasSessionState>[];
      final sub = client.sessionStream.listen(states.add);
      await Future<void>.delayed(Duration.zero);

      await client.readPlcId();
      await client.init();

      // Trigger error to reset
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26, pairingKey: 0x42));
      try {
        await client.readVariableNames();
      } catch (_) {}

      await Future<void>.delayed(Duration.zero);
      sub.cancel();

      // Should see: uninitialized -> identified -> paired -> uninitialized
      expect(states, [
        UmasSessionState.uninitialized,
        UmasSessionState.identified,
        UmasSessionState.paired,
        UmasSessionState.uninitialized,
      ]);
    });

    test('error during re-init propagates without infinite loop', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      // Trigger error to reset session
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26, pairingKey: 0x42));
      try {
        await client.readVariableNames();
      } catch (_) {}

      expect(client.sessionState, UmasSessionState.uninitialized);

      // Now make readPlcId also fail during re-init
      mock.whenSubFunction(
          0x02, buildErrorResponse(0x99, subFunc: 0x02));

      // browse() should throw, not loop forever
      await expectLater(client.browse(), throwsA(isA<UmasException>()));

      // Verify exactly one additional 0x02 attempt (not multiple)
      final readPlcIdAfterReset = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x02)
          .length;
      // 1 from original init + 1 from re-init attempt = 2 total
      expect(readPlcIdAfterReset, 2,
          reason: 'Should have exactly 2 readPlcId calls total');
    });

    test('all 0xFD errors reset state (conservative approach)', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      expect(client.sessionState, UmasSessionState.paired);

      // Any 0xFD error should reset state (conservative per Research Pitfall 4)
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x83, subFunc: 0x26, pairingKey: 0x42));
      try {
        await client.readVariableNames();
      } catch (_) {}

      expect(client.sessionState, UmasSessionState.uninitialized);
    });
  });

  group('UmasClient _withSession guard', () {
    /// Helper: create a MockUmasSender with readPlcId + init + empty DD responses.
    MockUmasSender _buildFullMock({int browseCallCount = 1}) {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      // Each browse/readDataTypes/readVariableNames call needs DD03 + DD02
      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      for (int i = 0; i < browseCallCount; i++) {
        mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
        mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));
      }
      return mock;
    }

    test('_withSession auto-initializes from uninitialized', () async {
      final mock = _buildFullMock();

      // Add extra DD02 response for standalone readVariableNames
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      final client = UmasClient(sendFn: mock.send);
      // Call readVariableNames directly without manual readPlcId/init
      final vars = await client.readVariableNames();

      expect(vars, isEmpty);
      expect(client.sessionState, UmasSessionState.paired);
      // Should have sent: 0x02 (readPlcId) + 0x01 (init) + 0x20 (readProjectBlock) + 0x26 (readVariableNames)
      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(subFuncs[0], 0x02);
      expect(subFuncs[1], 0x01);
      expect(subFuncs[2], 0x20);
      expect(subFuncs[3], 0x26);
    });

    test('_withSession skips init when already paired', () async {
      final mock = _buildFullMock();

      // Extra DD02 response for standalone readVariableNames after manual init
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      final client = UmasClient(sendFn: mock.send);
      // Manually initialize
      await client.readPlcId();
      await client.init();

      final requestCountBefore = mock.sentRequests.length;

      // Now call readVariableNames - should NOT re-run readPlcId/init
      await client.readVariableNames();

      // Only 0x26 requests should have been sent after manual init
      final newRequests = mock.sentRequests.sublist(requestCountBefore);
      final newSubFuncs =
          newRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(newSubFuncs.every((sf) => sf == 0x26), isTrue,
          reason: 'Should only send DD requests, no readPlcId/init');
    });

    test('browse second call skips init', () async {
      final mock = _buildFullMock(browseCallCount: 2);

      final client = UmasClient(sendFn: mock.send);
      await client.browse();

      final requestCountAfterFirst = mock.sentRequests.length;

      await client.browse();

      // Second browse should only send 0x26 requests (no 0x02 or 0x01)
      final secondCallRequests =
          mock.sentRequests.sublist(requestCountAfterFirst);
      final secondSubFuncs =
          secondCallRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(secondSubFuncs.every((sf) => sf == 0x26), isTrue,
          reason: 'Second browse should skip readPlcId and init');
    });

    test('concurrent _withSession calls do not duplicate init', () async {
      final mock = _buildFullMock(browseCallCount: 2);

      final client = UmasClient(sendFn: mock.send);

      // Run two browse() calls concurrently
      await Future.wait([client.browse(), client.browse()]);

      // Count readPlcId (0x02) and init (0x01) calls
      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      final readPlcIdCount = subFuncs.where((sf) => sf == 0x02).length;
      final initCount = subFuncs.where((sf) => sf == 0x01).length;

      expect(readPlcIdCount, 1,
          reason: 'readPlcId should be called exactly once');
      expect(initCount, 1, reason: 'init should be called exactly once');
    });
  });

  group('UmasClient keepAlive and echo', () {
    /// Helper: set up mock for a full successful init sequence (0x02 + 0x01).
    void setupInitSequence(MockUmasSender mock, {int pairingKey = 0x42}) {
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: pairingKey));
    }

    test('sendKeepAlive sends 0x12 and returns void on success', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // KeepAlive success response: no payload needed
      mock.whenSubFunction(
          0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      // Should complete without throwing
      await client.sendKeepAlive();

      // Verify a 0x12 request was sent
      final keepAliveRequests = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .toList();
      expect(keepAliveRequests.length, 1);
      expect(keepAliveRequests.first.protocolDataUnit[1], 0x42,
          reason: 'Should use current pairing key');
    });

    test('sendKeepAlive throws UmasException on 0xFD error', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // KeepAlive error response
      mock.whenSubFunction(
          0x12, buildErrorResponse(0x01, subFunc: 0x12, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      expect(
        () => client.sendKeepAlive(),
        throwsA(isA<UmasException>()),
      );
    });

    test('sendKeepAlive uses _withSession to auto-init if not paired',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock, pairingKey: 0x42);

      // KeepAlive success response
      mock.whenSubFunction(
          0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);

      // Call sendKeepAlive without manual init -- should auto-init
      await client.sendKeepAlive();

      // Verify 0x02 + 0x01 + 0x20 were sent before 0x12
      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(subFuncs[0], 0x02, reason: 'Should auto-call readPlcId');
      expect(subFuncs[1], 0x01, reason: 'Should auto-call init');
      expect(subFuncs[2], 0x20, reason: 'Should auto-call readProjectBlock');
      expect(subFuncs[3], 0x12, reason: 'Then send keepAlive');
    });

    test('sendEcho sends 0x0A with payload and returns echoed bytes',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final echoPayload = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      // Echo success response echoes the payload back
      mock.whenSubFunction(
          0x0A, buildSuccessResponse(0x0A, echoPayload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      final result = await client.sendEcho(echoPayload);

      expect(result.payload, echoPayload,
          reason: 'Echoed payload should match sent payload');

      // Verify the sent request had the payload
      final echoRequests = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x0A)
          .toList();
      expect(echoRequests.length, 1);
      // Payload starts at index 3 in PDU
      expect(echoRequests.first.protocolDataUnit.sublist(3), echoPayload);
    });

    test('sendEcho returns Duration measuring round-trip latency', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final echoPayload = Uint8List.fromList([0x01, 0x02]);
      mock.whenSubFunction(
          0x0A, buildSuccessResponse(0x0A, echoPayload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      final result = await client.sendEcho(echoPayload);

      expect(result.latency, greaterThanOrEqualTo(Duration.zero),
          reason: 'Latency should be non-negative');
    });

    test('sendEcho throws UmasException on 0xFD error', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // Echo error response
      mock.whenSubFunction(
          0x0A, buildErrorResponse(0x01, subFunc: 0x0A, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      expect(
        () => client.sendEcho(Uint8List.fromList([0x01, 0x02])),
        throwsA(isA<UmasException>()),
      );
    });
  });

  group('UmasClient keep-alive timer', () {
    /// Helper: set up mock for a full successful init sequence (0x02 + 0x01).
    void setupInitSequence(MockUmasSender mock, {int pairingKey = 0x42}) {
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: pairingKey));
    }

    test('startKeepAlive causes sendKeepAlive to be called periodically',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // Queue multiple keepAlive success responses
      for (int i = 0; i < 5; i++) {
        mock.whenSubFunction(
            0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x42));
      }

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
      );
      await client.readPlcId();
      await client.init();
      expect(client.sessionState, UmasSessionState.paired);

      client.startKeepAlive();

      // Wait long enough for at least 2 keepAlive ticks
      await Future<void>.delayed(const Duration(milliseconds: 150));

      client.stopKeepAlive();

      final keepAliveCount = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .length;
      expect(keepAliveCount, greaterThanOrEqualTo(2),
          reason: 'Timer should have fired at least twice');
    });

    test('stopKeepAlive stops the timer -- no more keepAlive calls after stop',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      for (int i = 0; i < 10; i++) {
        mock.whenSubFunction(
            0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x42));
      }

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
      );
      await client.readPlcId();
      await client.init();

      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      client.stopKeepAlive();

      final countAfterStop = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .length;

      // Wait more time -- no new keepAlives should appear
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final countLater = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .length;

      expect(countLater, countAfterStop,
          reason: 'No new keepAlive calls after stopKeepAlive');
    });

    test('failed keepAlive transitions session to uninitialized', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // First keepAlive succeeds, second fails
      mock.whenSubFunction(
          0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x42));
      mock.whenSubFunction(
          0x12, buildErrorResponse(0x01, subFunc: 0x12, pairingKey: 0x42));

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
      );
      await client.readPlcId();
      await client.init();
      expect(client.sessionState, UmasSessionState.paired);

      client.startKeepAlive();

      // Wait for the error keepAlive to fire
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(client.sessionState, UmasSessionState.uninitialized,
          reason: 'Failed keepAlive should reset session to uninitialized');

      client.stopKeepAlive();
    });

    test('dispose cancels the keep-alive timer', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      for (int i = 0; i < 10; i++) {
        mock.whenSubFunction(
            0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x42));
      }

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
      );
      await client.readPlcId();
      await client.init();

      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      client.dispose();

      final countAfterDispose = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .length;

      await Future<void>.delayed(const Duration(milliseconds: 150));

      final countLater = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .length;

      expect(countLater, countAfterDispose,
          reason: 'No keepAlive calls after dispose');
    });

    test('calling startKeepAlive twice replaces the previous timer', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      for (int i = 0; i < 20; i++) {
        mock.whenSubFunction(
            0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x42));
      }

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
      );
      await client.readPlcId();
      await client.init();

      // Start twice
      client.startKeepAlive();
      client.startKeepAlive();

      // Wait for one interval
      await Future<void>.delayed(const Duration(milliseconds: 80));

      client.stopKeepAlive();

      final keepAliveCount = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .length;

      // With one timer at 50ms, after 80ms we expect 1 tick.
      // If two timers were running, we'd see 2 ticks.
      expect(keepAliveCount, 1,
          reason: 'Only one timer should be active (not two)');
    });
  });

  group('UmasClient auto re-init and backoff', () {
    /// Helper: set up mock for a full successful init sequence (0x02 + 0x01).
    void setupInitSequence(MockUmasSender mock, {int pairingKey = 0x42}) {
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: pairingKey));
    }

    test('after session loss, browse transparently re-inits and succeeds',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock, pairingKey: 0x42);

      // First browse succeeds
      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      // KeepAlive error to trigger session loss
      mock.whenSubFunction(
          0x12, buildErrorResponse(0x01, subFunc: 0x12, pairingKey: 0x42));

      final delays = <Duration>[];
      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
        backoffDelay: (d) async => delays.add(d),
      );

      await client.browse();
      expect(client.sessionState, UmasSessionState.paired);

      // Trigger session loss via failed keepAlive
      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      client.stopKeepAlive();
      expect(client.sessionState, UmasSessionState.uninitialized);

      // Queue fresh init + browse responses for recovery
      mock._responseQueues.remove(0x02);
      mock._responseQueues.remove(0x01);
      mock._responseQueues.remove(0x26);
      setupInitSequence(mock, pairingKey: 0x55);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      // browse() should transparently re-init and succeed
      final tree = await client.browse();
      expect(tree, isEmpty);
      expect(client.sessionState, UmasSessionState.paired);

      client.dispose();
    });

    test('re-init failure retries with backoff delay', () async {
      final mock = MockUmasSender();

      // First readPlcId fails, second succeeds
      mock.whenSubFunction(
          0x02, buildErrorResponse(0x99, subFunc: 0x02));
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: 0x42));

      // DD responses for browse
      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      final delays = <Duration>[];
      final client = UmasClient(
        sendFn: mock.send,
        backoffDelay: (d) async => delays.add(d),
      );

      // browse should succeed after retry
      await client.browse();
      expect(client.sessionState, UmasSessionState.paired);

      // Should have recorded a backoff delay
      expect(delays, isNotEmpty,
          reason: 'Should have used backoff delay before retry');
    });

    test('after max retries (3), exception propagates to caller', () async {
      final mock = MockUmasSender();

      // All readPlcId calls fail
      for (int i = 0; i < 5; i++) {
        mock.whenSubFunction(
            0x02, buildErrorResponse(0x99, subFunc: 0x02));
      }

      final delays = <Duration>[];
      final client = UmasClient(
        sendFn: mock.send,
        backoffDelay: (d) async => delays.add(d),
      );

      await expectLater(
        client.browse(),
        throwsA(isA<UmasException>()),
      );

      // Should have retried exactly _maxRetries times (3 attempts total means 2 retries + 1 initial)
      // With 3 max retries: initial + 3 retries = 4 total attempts, 3 backoff delays
      expect(delays.length, lessThanOrEqualTo(3),
          reason: 'Should not exceed max retries');
    });

    test('backoff resets to initial delay after successful operation',
        () async {
      final mock = MockUmasSender();

      // First attempt: readPlcId fails, then succeeds on retry
      mock.whenSubFunction(
          0x02, buildErrorResponse(0x99, subFunc: 0x02));
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: 0x42));

      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      final delays = <Duration>[];
      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
        backoffDelay: (d) async => delays.add(d),
      );

      // First browse recovers after one retry
      await client.browse();
      expect(client.sessionState, UmasSessionState.paired);

      final firstDelay = delays.last;

      // Force session loss
      mock.whenSubFunction(
          0x12, buildErrorResponse(0x01, subFunc: 0x12, pairingKey: 0x42));
      client.startKeepAlive();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      client.stopKeepAlive();
      expect(client.sessionState, UmasSessionState.uninitialized);

      // Queue another failing then succeeding init
      mock._responseQueues.remove(0x02);
      mock._responseQueues.remove(0x01);
      mock._responseQueues.remove(0x26);
      mock.whenSubFunction(
          0x02, buildErrorResponse(0x99, subFunc: 0x02));
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: 0x55));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      delays.clear();

      // Second browse should also use initial delay (backoff was reset)
      await client.browse();
      expect(delays.last, firstDelay,
          reason: 'Backoff should reset to initial delay after success');

      client.dispose();
    });

    test('keep-alive timer restarts after successful re-init', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock, pairingKey: 0x42);

      // KeepAlive responses for after re-init
      for (int i = 0; i < 10; i++) {
        mock.whenSubFunction(
            0x12, buildSuccessResponse(0x12, Uint8List(0), pairingKey: 0x55));
      }

      // First browse succeeds
      final emptyTypes = buildDataTypesPayload([], nextAddress: 0x0000);
      final emptyVars = buildVariableNamesPayload([], nextAddress: 0x0000);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      final client = UmasClient(
        sendFn: mock.send,
        keepAliveInterval: const Duration(milliseconds: 50),
        backoffDelay: (d) async {},
      );

      await client.browse();

      // Force session loss manually
      // Queue an error for DD, triggering _withSessionAndRecovery reset
      mock._responseQueues.remove(0x26);
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26, pairingKey: 0x42));

      try {
        await client.browse();
      } catch (_) {}
      expect(client.sessionState, UmasSessionState.uninitialized);

      // Queue fresh init + browse for recovery
      mock._responseQueues.remove(0x02);
      mock._responseQueues.remove(0x01);
      mock._responseQueues.remove(0x26);
      setupInitSequence(mock, pairingKey: 0x55);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyTypes));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, emptyVars));

      // Clear sent requests to count keepAlives after re-init
      mock.sentRequests.clear();

      await client.browse();
      expect(client.sessionState, UmasSessionState.paired);

      // Wait for keep-alive timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final keepAliveCount = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x12)
          .length;
      expect(keepAliveCount, greaterThanOrEqualTo(1),
          reason: 'Keep-alive timer should restart after successful re-init');

      client.dispose();
    });
  });

  group('UmasClient.readPlcStatus()', () {
    /// Helper: set up mock for a full successful init sequence (0x02 + 0x01).
    void setupInitSequence(MockUmasSender mock, {int pairingKey = 0x42}) {
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: pairingKey));
    }

    test('sends 0x04 request and returns PlcStatusResult with run state and CRC list',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // PlcStatus response: statusByte=0x01, notUsed2=0x0000, numberOfBlocks=1,
      // one CRC: 0x12345678
      final payload = Uint8List.fromList([
        0x01, // statusByte (pdu[4])
        0x00, 0x00, // notUsed2 (pdu[5..6])
        0x01, // numberOfBlocks (pdu[7])
        ...leUint32(0x12345678), // block CRC
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final result = await client.readPlcStatus();

      expect(result.statusByte, 0x01);
      expect(result.numberOfBlocks, 1);
      expect(result.blockCrcs, [0x12345678]);
      expect(result.additionalData, isEmpty);
    });

    test('extracts correct number of CRC uint32 values from numberOfBlocks field',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // 2 blocks with known CRC values
      final payload = Uint8List.fromList([
        0x03, // statusByte
        0x00, 0x00, // notUsed2
        0x02, // numberOfBlocks = 2
        ...leUint32(0x12345678),
        ...leUint32(0xABCDEF01),
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final result = await client.readPlcStatus();

      expect(result.numberOfBlocks, 2);
      expect(result.blockCrcs, [0x12345678, 0xABCDEF01]);
    });

    test('auto-initializes session via _withSession when not paired', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock, pairingKey: 0x42);

      final payload = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x01, ...leUint32(0xDEADBEEF),
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      // Call readPlcStatus without manual init -- should auto-init
      final result = await client.readPlcStatus();

      expect(result.blockCrcs, [0xDEADBEEF]);

      // Verify 0x02 + 0x01 + 0x20 were sent before 0x04
      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(subFuncs[0], 0x02, reason: 'Should auto-call readPlcId');
      expect(subFuncs[1], 0x01, reason: 'Should auto-call init');
      expect(subFuncs[2], 0x20, reason: 'Should auto-call readProjectBlock');
      expect(subFuncs[3], 0x04, reason: 'Then send plcStatus');
    });

    test('throws UmasException on 0xFD error response', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      mock.whenSubFunction(
          0x04, buildErrorResponse(0x42, subFunc: 0x04, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      expect(
        () => client.readPlcStatus(),
        throwsA(isA<UmasException>()
            .having((e) => e.errorCode, 'errorCode', 0x42)),
      );
    });

    test('with 0 blocks returns empty CRC list', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // 0 blocks, some additional data after
      final payload = Uint8List.fromList([
        0x05, // statusByte
        0x00, 0x00, // notUsed2
        0x00, // numberOfBlocks = 0
        0xAA, 0xBB, // additional data
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final result = await client.readPlcStatus();

      expect(result.statusByte, 0x05);
      expect(result.numberOfBlocks, 0);
      expect(result.blockCrcs, isEmpty);
      expect(result.additionalData, [0xAA, 0xBB]);
    });

    test('stores CRCs on client instance via blockCrcs getter', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final payload = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x02,
        ...leUint32(0x11111111),
        ...leUint32(0x22222222),
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      expect(client.blockCrcs, isNull, reason: 'Initially null');

      await client.readPlcId();
      await client.init();
      await client.readPlcStatus();

      expect(client.blockCrcs, [0x11111111, 0x22222222]);
    });

    test('first readPlcStatus reports crcChanged = false (no previous CRCs)',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final payload = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x01,
        ...leUint32(0x12345678),
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final result = await client.readPlcStatus();

      expect(result.crcChanged, isFalse,
          reason: 'First poll has no previous CRCs to compare against');
    });

    test('second readPlcStatus with same CRCs reports crcChanged = false',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final payload = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x02,
        ...leUint32(0x11111111),
        ...leUint32(0x22222222),
      ]);
      // Queue same response twice
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      await client.readPlcStatus(); // first poll
      final result2 = await client.readPlcStatus(); // second poll, same CRCs

      expect(result2.crcChanged, isFalse,
          reason: 'CRCs did not change between polls');
    });

    test('second readPlcStatus with different CRCs reports crcChanged = true',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final payload1 = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x01,
        ...leUint32(0x11111111),
      ]);
      final payload2 = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x01,
        ...leUint32(0x99999999), // different CRC
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload1, pairingKey: 0x42));
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload2, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      await client.readPlcStatus(); // first poll
      final result2 = await client.readPlcStatus(); // second poll, different CRCs

      expect(result2.crcChanged, isTrue,
          reason: 'CRC change detected between polls');
    });

    test('CRC change detection: different number of blocks = changed',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final payload1 = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x01,
        ...leUint32(0x11111111),
      ]);
      final payload2 = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x02,
        ...leUint32(0x11111111),
        ...leUint32(0x22222222),
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload1, pairingKey: 0x42));
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload2, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      await client.readPlcStatus();
      final result2 = await client.readPlcStatus();

      expect(result2.crcChanged, isTrue,
          reason: 'Different number of blocks means CRC changed');
    });

    test('session reset clears previous CRCs so next poll reports no change',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final payload = Uint8List.fromList([
        0x01, 0x00, 0x00, 0x01,
        ...leUint32(0x11111111),
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      await client.readPlcStatus(); // stores CRCs

      // Trigger session error via failed 0x26
      mock.whenSubFunction(
          0x26, buildErrorResponse(0x01, subFunc: 0x26, pairingKey: 0x42));
      try {
        await client.readVariableNames();
      } catch (_) {}

      // Re-init and poll again -- should report no change (previous cleared)
      mock._responseQueues.remove(0x02);
      mock._responseQueues.remove(0x01);
      mock._responseQueues.remove(0x04);
      setupInitSequence(mock, pairingKey: 0x55);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x55));

      final result = await client.readPlcStatus();
      expect(result.crcChanged, isFalse,
          reason: 'After session reset, no previous CRCs to compare');
    });

    test('caps numberOfBlocks at 256 to prevent memory exhaustion', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // Malformed response claiming 255+ blocks but with minimal data
      // The response has numberOfBlocks=255 but only enough bytes for 0 blocks
      final payload = Uint8List.fromList([
        0x01, 0x00, 0x00,
        0xFF, // numberOfBlocks = 255 (but no actual block data follows)
      ]);
      mock.whenSubFunction(
          0x04, buildSuccessResponse(0x04, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      // Should not crash or allocate huge memory -- just parse what's available
      final result = await client.readPlcStatus();
      expect(result.blockCrcs.length, lessThanOrEqualTo(256));
    });
  });

  group('UmasClient.readProjectInfo()', () {
    /// Helper: set up mock for a full successful init sequence (0x02 + 0x01).
    void setupInitSequence(MockUmasSender mock, {int pairingKey = 0x42}) {
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(
          0x01,
          buildSuccessResponse(0x01, leUint16(240), pairingKey: pairingKey));
    }

    test('sends 0x03 with subcode and returns ProjectInfoResult with raw bytes',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // ProjectInfo response: some opaque bytes
      final payload = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]);
      mock.whenSubFunction(
          0x03, buildSuccessResponse(0x03, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final result = await client.readProjectInfo();

      expect(result.rawData, payload);

      // Verify the request had subcode byte in payload
      final projRequests = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x03)
          .toList();
      expect(projRequests.length, 1);
      // Payload is at index 3+: should contain subcode byte 0x00 (default)
      expect(projRequests.first.protocolDataUnit[3], 0x00);
    });

    test('extracts project name from response bytes (null-terminated string)',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // Response with a null-terminated project name embedded
      final nameBytes = 'MyPLCProject'.codeUnits;
      final payload = Uint8List.fromList([
        0x00, 0x00, // some prefix bytes
        ...nameBytes,
        0x00, // null terminator
        0xFF, 0xFF, // trailing junk
      ]);
      mock.whenSubFunction(
          0x03, buildSuccessResponse(0x03, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final result = await client.readProjectInfo();

      expect(result.projectName, 'MyPLCProject');
    });

    test('auto-initializes session via _withSession', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock, pairingKey: 0x42);

      final payload = Uint8List.fromList([0x01, 0x02]);
      mock.whenSubFunction(
          0x03, buildSuccessResponse(0x03, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      // Call without manual init
      final result = await client.readProjectInfo();

      expect(result.rawData, payload);

      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(subFuncs[0], 0x02, reason: 'Should auto-call readPlcId');
      expect(subFuncs[1], 0x01, reason: 'Should auto-call init');
      expect(subFuncs[2], 0x20, reason: 'Should auto-call readProjectBlock');
      expect(subFuncs[3], 0x03, reason: 'Then send projectInfo');
    });

    test('throws UmasException on error', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      mock.whenSubFunction(
          0x03, buildErrorResponse(0x55, subFunc: 0x03, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();

      expect(
        () => client.readProjectInfo(),
        throwsA(isA<UmasException>()
            .having((e) => e.errorCode, 'errorCode', 0x55)),
      );
    });

    test('handles response with no printable ASCII (projectName is null)',
        () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      // All non-printable bytes
      final payload = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04]);
      mock.whenSubFunction(
          0x03, buildSuccessResponse(0x03, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final result = await client.readProjectInfo();

      expect(result.projectName, isNull);
    });

    test('accepts custom subcode parameter', () async {
      final mock = MockUmasSender();
      setupInitSequence(mock);

      final payload = Uint8List.fromList([0x01]);
      mock.whenSubFunction(
          0x03, buildSuccessResponse(0x03, payload, pairingKey: 0x42));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      await client.readProjectInfo(subcode: 0x05);

      final projRequests = mock.sentRequests
          .where((r) => r.protocolDataUnit[2] == 0x03)
          .toList();
      expect(projRequests.first.protocolDataUnit[3], 0x05,
          reason: 'Should use custom subcode');
    });
  });
}
