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
/// Real Schneider PLC format: FC(0x5A) + pairingKey + subFuncEcho + status(0xFE) + payload
Uint8List buildSuccessResponse(int subFunc, Uint8List payload,
    {int pairingKey = 0x00}) {
  final pdu = Uint8List(4 + payload.length);
  pdu[0] = 0x5A; // FC90
  pdu[1] = pairingKey;
  pdu[2] = subFunc; // Echo sub-function
  pdu[3] = 0xFE; // Success status
  pdu.setAll(4, payload);
  return pdu;
}

/// Build a UMAS error response PDU.
/// Real Schneider PLC format: FC(0x5A) + pairingKey + subFuncEcho + status(0xFD) + errorCode
Uint8List buildErrorResponse(int errorCode,
    {int pairingKey = 0x00, int subFunc = 0x00}) {
  return Uint8List.fromList([0x5A, pairingKey, subFunc, 0xFD, errorCode]);
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

/// Build a data dictionary variable names (0xDD02) response payload
/// in the CORRECTED format matching PLC4X mspec.
///
/// Header: range(1) + nextAddress(2 LE) + unknown1(2 LE) + noOfRecords(2 LE)
/// Records: dataType(2 LE) + block(2 LE) + offset(2 LE) + unknown4(2 LE) +
///          stringLength(2 LE) + name(N bytes, null-terminated)
Uint8List buildVariableNamesPayload(
    List<({String name, int blockNo, int offset, int typeId})> records,
    {int nextAddress = 0x0000}) {
  final bytes = <int>[];
  // Header
  bytes.add(0x00); // range
  bytes.addAll(leUint16(nextAddress)); // nextAddress
  bytes.addAll(leUint16(0x0000)); // unknown1
  bytes.addAll(leUint16(records.length)); // noOfRecords

  // Records
  for (final r in records) {
    bytes.addAll(leUint16(r.typeId)); // dataType
    bytes.addAll(leUint16(r.blockNo)); // block
    bytes.addAll(leUint16(r.offset)); // offset
    bytes.addAll(leUint16(0x0000)); // unknown4
    final nameBytes = r.name.codeUnits;
    bytes.addAll(leUint16(nameBytes.length + 1)); // stringLength (incl null)
    bytes.addAll(nameBytes);
    bytes.add(0x00); // null terminator
  }
  return Uint8List.fromList(bytes);
}

/// Build a data dictionary data types (0xDD03) response payload
/// in the CORRECTED format matching PLC4X mspec.
///
/// Header: range(1) + nextAddress(2 LE) + unknown1(1) + noOfRecords(2 LE)
/// Records: dataSize(2 LE) + unknown1(2 LE) + classIdentifier(1) +
///          dataType(1) + stringLength(1) + name(N bytes, null-terminated)
Uint8List buildDataTypesPayload(
    List<({int id, String name, int byteSize, int classId, int dataType})>
        records,
    {int nextAddress = 0x0000}) {
  final bytes = <int>[];
  // Header
  bytes.add(0x00); // range
  bytes.addAll(leUint16(nextAddress)); // nextAddress
  bytes.add(0x00); // unknown1
  bytes.addAll(leUint16(records.length)); // noOfRecords

  // Records
  for (final r in records) {
    bytes.addAll(leUint16(r.byteSize)); // dataSize
    bytes.addAll(leUint16(0x0000)); // unknown1
    bytes.add(r.classId); // classIdentifier
    bytes.add(r.dataType); // dataType
    final nameBytes = r.name.codeUnits;
    bytes.add(nameBytes.length + 1); // stringLength (incl null)
    bytes.addAll(nameBytes);
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
        (id: 100, name: 'MY_STRUCT', byteSize: 16, classId: 2, dataType: 0),
        (id: 101, name: 'VALVE_TYPE', byteSize: 8, classId: 0, dataType: 5),
      ]);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, typesPayload));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final types = await client.readDataTypes();

      expect(types.length, 2);
      expect(types[0].id, 100);
      expect(types[0].name, 'MY_STRUCT');
      expect(types[0].byteSize, 16);
      expect(types[0].classIdentifier, 2);
      expect(types[1].id, 101);
      expect(types[1].name, 'VALVE_TYPE');
      expect(types[1].byteSize, 8);
      expect(types[1].dataType, 5);
    });

    test('paginates when nextAddress != 0', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(
          0x02,
          buildSuccessResponse(
              0x02, buildPlcIdentResponse(hardwareId: 0x12345678)));
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      // Page 1: nextAddress = 0x0020 (more data)
      final page1 = buildDataTypesPayload(
        [
          (id: 100, name: 'MY_STRUCT', byteSize: 16, classId: 2, dataType: 0),
        ],
        nextAddress: 0x0020,
      );
      // Page 2: nextAddress = 0 (done)
      final page2 = buildDataTypesPayload(
        [
          (
            id: 101,
            name: 'VALVE_TYPE',
            byteSize: 8,
            classId: 0,
            dataType: 5
          ),
        ],
        nextAddress: 0x0000,
      );

      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, page1));
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, page2));

      final client = UmasClient(sendFn: mock.send);
      await client.readPlcId();
      await client.init();
      final types = await client.readDataTypes();

      expect(types.length, 2,
          reason: 'Should accumulate types from both pages');
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

      // Verify call order: 0x02 (readPlcId), 0x01 (init), 0x26 (DD03), 0x26 (DD02)
      expect(mock.sentRequests.length, greaterThanOrEqualTo(4));
      final subFuncs =
          mock.sentRequests.map((r) => r.protocolDataUnit[2]).toList();
      expect(subFuncs[0], 0x02, reason: 'First call should be readPlcId');
      expect(subFuncs[1], 0x01, reason: 'Second call should be init');
      // Remaining calls are 0x26 for data dictionary reads
      expect(subFuncs.sublist(2).every((sf) => sf == 0x26), isTrue);
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
}
