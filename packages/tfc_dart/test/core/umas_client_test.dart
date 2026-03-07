import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:tfc_dart/core/umas_client.dart';

/// Mock send function that captures requests and returns canned responses.
class MockUmasSender {
  final List<UmasRequest> sentRequests = [];
  final Map<int, Uint8List> _cannedResponses = {};

  /// Register a canned PDU response for a given sub-function code.
  void whenSubFunction(int subFunc, Uint8List responsePdu) {
    _cannedResponses[subFunc] = responsePdu;
  }

  Future<ModbusResponseCode> send(ModbusRequest request) async {
    if (request is UmasRequest) {
      sentRequests.add(request);
      final pdu = request.protocolDataUnit;
      // Sub-function is at index 2 in the PDU (FC=0, pairingKey=1, subFunc=2)
      final subFunc = pdu[2];
      final response = _cannedResponses[subFunc];
      if (response != null) {
        request.setFromPduResponse(response);
        return request.responseCode;
      }
    }
    return ModbusResponseCode.requestRxFailed;
  }
}

/// Build a UMAS success response PDU.
/// Format: FC(0x5A) + pairingKey + status(0xFE) + subFuncEcho + payload
Uint8List buildSuccessResponse(int subFunc, Uint8List payload,
    {int pairingKey = 0x00}) {
  final pdu = Uint8List(4 + payload.length);
  pdu[0] = 0x5A; // FC90
  pdu[1] = pairingKey;
  pdu[2] = 0xFE; // Success status
  pdu[3] = subFunc; // Echo sub-function
  pdu.setAll(4, payload);
  return pdu;
}

/// Build a UMAS error response PDU.
/// Format: FC(0x5A) + pairingKey + status(0xFD) + errorCode
Uint8List buildErrorResponse(int errorCode, {int pairingKey = 0x00}) {
  return Uint8List.fromList([0x5A, pairingKey, 0xFD, errorCode]);
}

/// Build little-endian uint16 bytes.
Uint8List leUint16(int value) {
  final bd = ByteData(2);
  bd.setUint16(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

/// Build a data dictionary variable names (0xDD02) response payload.
/// Each record: name_length(2 LE) + name(UTF-8) + block_no(2 LE) +
///              offset(2 LE) + data_type_id(2 LE)
Uint8List buildVariableNamesPayload(
    List<({String name, int blockNo, int offset, int typeId})> records) {
  final bytes = <int>[];
  for (final r in records) {
    final nameBytes = r.name.codeUnits;
    bytes.addAll(leUint16(nameBytes.length));
    bytes.addAll(nameBytes);
    bytes.addAll(leUint16(r.blockNo));
    bytes.addAll(leUint16(r.offset));
    bytes.addAll(leUint16(r.typeId));
  }
  return Uint8List.fromList(bytes);
}

/// Build a data dictionary data types (0xDD03) response payload.
/// Each record: type_id(2 LE) + name_length(2 LE) + name(UTF-8) +
///              byte_size(2 LE)
Uint8List buildDataTypesPayload(
    List<({int id, String name, int byteSize})> records) {
  final bytes = <int>[];
  for (final r in records) {
    bytes.addAll(leUint16(r.id));
    final nameBytes = r.name.codeUnits;
    bytes.addAll(leUint16(nameBytes.length));
    bytes.addAll(nameBytes);
    bytes.addAll(leUint16(r.byteSize));
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
    test('parses init response to extract max frame size (LE uint16)', () async {
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

  group('UmasClient.readVariableNames()', () {
    test('parses 0x26/0xDD02 response into list of UmasVariable', () async {
      final mock = MockUmasSender();
      // Set up init first
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      // Variable names payload with 2 records
      final varsPayload = buildVariableNamesPayload([
        (name: 'Application.GVL.temperature', blockNo: 1, offset: 0, typeId: 5),
        (name: 'Application.GVL.pressure', blockNo: 1, offset: 4, typeId: 5),
      ]);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, varsPayload));

      final client = UmasClient(sendFn: mock.send);
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
  });

  group('UmasClient.readDataTypes()', () {
    test('parses 0x26/0xDD03 response into data type reference list',
        () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));

      final typesPayload = buildDataTypesPayload([
        (id: 100, name: 'MY_STRUCT', byteSize: 16),
        (id: 101, name: 'VALVE_TYPE', byteSize: 8),
      ]);
      mock.whenSubFunction(0x26, buildSuccessResponse(0x26, typesPayload));

      final client = UmasClient(sendFn: mock.send);
      await client.init();
      final types = await client.readDataTypes();

      expect(types.length, 2);
      expect(types[0].id, 100);
      expect(types[0].name, 'MY_STRUCT');
      expect(types[0].byteSize, 16);
      expect(types[1].id, 101);
      expect(types[1].name, 'VALVE_TYPE');
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

      final client = UmasClient(sendFn: (_) async => ModbusResponseCode.requestSucceed);
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
      mock.whenSubFunction(0x01, buildErrorResponse(0x42));

      final client = UmasClient(sendFn: mock.send);

      expect(
        () => client.init(),
        throwsA(isA<UmasException>()
            .having((e) => e.errorCode, 'errorCode', 0x42)),
      );
    });

    test('handles Data Dictionary not enabled (0x26 failure)', () async {
      final mock = MockUmasSender();
      mock.whenSubFunction(0x01, buildSuccessResponse(0x01, leUint16(240)));
      // 0x26 returns error
      mock.whenSubFunction(0x26, buildErrorResponse(0x01));

      final client = UmasClient(sendFn: mock.send);
      await client.init();

      expect(
        () => client.readVariableNames(),
        throwsA(isA<UmasException>().having(
            (e) => e.message, 'message', contains('Data Dictionary'))),
      );
    });
  });
}
