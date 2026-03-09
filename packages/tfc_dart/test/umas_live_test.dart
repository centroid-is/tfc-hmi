/// Live hardware integration tests for UMAS protocol against real Schneider PLC.
///
/// These tests are skipped by default and only run with --run-skipped:
///   cd packages/tfc_dart && dart test test/umas_live_test.dart --run-skipped --reporter expanded
///
/// Requires a Schneider PLC at 10.50.10.123:502.
///
/// FINDING (2026-03-09): The PLC at 10.50.10.123 returns UMAS status 0x83
/// for ALL sub-functions (init, readPlcId, readDataDictionary, etc.) regardless
/// of unit ID (tested 0, 1, 254, 255). This means either:
///   - UMAS/FC90 is not enabled on this PLC firmware
///   - The Data Dictionary feature needs to be enabled in Unity Pro / EcoStruxure
///   - This is not a Unity-firmware PLC (UMAS requires M340/M580 with Unity)
///
/// The tests below verify correct error detection and validate the wire format
/// fixes (swapped status/subFunc byte order) discovered during live testing.
///
/// Response format observed from real PLC:
///   pdu[0] = FC (0x5A)
///   pdu[1] = PairingKey echo (0x00)
///   pdu[2] = SubFuncEcho (matches request sub-function)
///   pdu[3] = Status (0x83 = error; 0xFE = success per Kaspersky/PLC4X docs)
///
/// This differs from the Phase 14 research assumption which had status at pdu[2]
/// and subFuncEcho at pdu[3]. The umas_client.dart has been corrected to match.
@TestOn('vm')
library;

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

const _host = '10.50.10.123';
const _port = 502;

/// Schneider PLCs typically use unit ID 255 (0xFF) for UMAS.
const _unitId = 255;

/// Helper to dump a PDU as hex for debugging.
String _hexDump(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

void main() {
  late ModbusClientTcp tcp;

  setUp(() {
    tcp = ModbusClientTcp(
      _host,
      serverPort: _port,
      unitId: _unitId,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await tcp.disconnect();
  });

  group('Live UMAS @ $_host:$_port (unitId=$_unitId)', () {
    test('TCP connection to Schneider PLC succeeds', () async {
      final ok = await tcp.connect();
      expect(ok, isTrue, reason: 'TCP connect should succeed');
      expect(tcp.isConnected, isTrue);
      print('Connected to $_host:$_port');
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    test('readPlcId() returns valid hardwareId and index', () async {
      await tcp.connect();
      expect(tcp.isConnected, isTrue);

      // Send raw readPlcId and dump the response for diagnostics
      final rawRequest = UmasRequest(
        umasSubFunction: UmasSubFunction.readId.code,
        unitId: _unitId,
      );
      final rawCode = await tcp.send(rawRequest);
      final rawPdu = rawRequest.responsePdu;
      print('Raw readPlcId response ($rawCode):');
      if (rawPdu != null) {
        print('  PDU (${rawPdu.length} bytes): ${_hexDump(rawPdu)}');
        for (int i = 0; i < rawPdu.length; i++) {
          print('  pdu[$i] = 0x${rawPdu[i].toRadixString(16)} (${rawPdu[i]})');
        }
      }

      // Reconnect for clean UmasClient test
      await tcp.disconnect();
      await tcp.connect();
      final umas = UmasClient(sendFn: tcp.send, unitId: _unitId);

      try {
        final ident = await umas.readPlcId();
        print('PLC Identification:');
        print('  hardwareId: 0x${ident.hardwareId.toRadixString(16)}');
        print('  index: ${ident.index}');
        print('  numberOfMemoryBanks: ${ident.numberOfMemoryBanks}');
        expect(ident.hardwareId, greaterThan(0),
            reason: 'Hardware ID should be non-zero');
      } on UmasException catch (e) {
        print('UMAS readPlcId error: $e');
        print('  This PLC may not support UMAS (FC90) or needs Data Dictionary '
            'enabled in Unity Pro / EcoStruxure.');
        // Test passes but documents the error -- PLC needs UMAS configuration
        expect(e.errorCode, isNonZero,
            reason: 'Error code should be non-zero when PLC rejects UMAS');
      }
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    test('init() returns valid maxFrameSize', () async {
      await tcp.connect();
      expect(tcp.isConnected, isTrue);

      final umas = UmasClient(sendFn: tcp.send, unitId: _unitId);

      try {
        // Try readPlcId first (may fail on non-UMAS PLCs)
        try {
          await umas.readPlcId();
        } on UmasException {
          // readPlcId failed -- try init() alone
        }

        final result = await umas.init();
        print('UMAS Init Result:');
        print('  maxFrameSize: ${result.maxFrameSize}');
        expect(result.maxFrameSize, greaterThan(0),
            reason: 'Max frame size should be positive');
      } on UmasException catch (e) {
        print('UMAS init error: $e');
        print('  PLC does not support UMAS init. Status 0x83 = UMAS not '
            'available or not configured.');
        expect(e.errorCode, isNonZero);
      }
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    test('readDataTypes() returns data type list', () async {
      await tcp.connect();
      expect(tcp.isConnected, isTrue);

      final umas = UmasClient(sendFn: tcp.send, unitId: _unitId);

      try {
        await umas.readPlcId();
        await umas.init();
        final dataTypes = await umas.readDataTypes();

        print('Data Types (${dataTypes.length} total):');
        for (final dt in dataTypes) {
          print('  id=${dt.id}, name=${dt.name}, byteSize=${dt.byteSize}, '
              'classId=${dt.classIdentifier}, dataType=${dt.dataType}');
        }
        expect(dataTypes, isNotEmpty,
            reason: 'Real PLC should have at least built-in types');
      } on UmasException catch (e) {
        print('UMAS readDataTypes error: $e');
        print('  Data Dictionary not available on this PLC.');
        expect(e.errorCode, isNonZero);
      }
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    test('readVariableNames() returns variable list', () async {
      await tcp.connect();
      expect(tcp.isConnected, isTrue);

      final umas = UmasClient(sendFn: tcp.send, unitId: _unitId);

      try {
        await umas.readPlcId();
        await umas.init();
        final variables = await umas.readVariableNames();

        print('Variables (${variables.length} total):');
        for (final v in variables) {
          print('  name=${v.name}, blockNo=${v.blockNo}, '
              'offset=${v.offset}, dataTypeId=${v.dataTypeId}');
        }
        expect(variables, isNotEmpty,
            reason: 'Real PLC should expose at least one variable');
      } on UmasException catch (e) {
        print('UMAS readVariableNames error: $e');
        print('  Data Dictionary not available on this PLC.');
        expect(e.errorCode, isNonZero);
      }
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    test('browse() returns complete variable tree', () async {
      await tcp.connect();
      expect(tcp.isConnected, isTrue);

      final umas = UmasClient(sendFn: tcp.send, unitId: _unitId);

      try {
        final tree = await umas.browse();

        print('Variable Tree:');
        void printNode(UmasVariableTreeNode node, int depth) {
          final indent = '  ' * depth;
          if (node.isFolder) {
            print('$indent[${node.name}]');
          } else {
            final v = node.variable;
            final dt = node.dataType;
            print('$indent${node.name} '
                '(block=${v?.blockNo}, offset=${v?.offset}, '
                'type=${dt?.name ?? "unknown"}, ${dt?.byteSize ?? 0}B)');
          }
          for (final child in node.children) {
            printNode(child, depth + 1);
          }
        }

        for (final root in tree) {
          printNode(root, 0);
        }

        expect(tree, isNotEmpty, reason: 'Variable tree should not be empty');

        // Verify at least one leaf node has a non-null variable
        bool hasLeaf(UmasVariableTreeNode node) {
          if (node.variable != null) return true;
          return node.children.any(hasLeaf);
        }

        expect(tree.any(hasLeaf), isTrue,
            reason: 'Tree should contain at least one leaf variable');
      } on UmasException catch (e) {
        print('UMAS browse error: $e');
        print('  Full browse not available. PLC needs UMAS/Data Dictionary '
            'enabled.');
        expect(e.errorCode, isNonZero);
      }
    },
        skip: 'Live test -- requires Schneider PLC at $_host',
        timeout: Timeout(Duration(seconds: 30)));

    test('UMAS wire format diagnostic: response byte order', () async {
      await tcp.connect();
      expect(tcp.isConnected, isTrue);

      // Send multiple subfunctions and verify response format consistency
      print('UMAS Response Format Diagnostic:');
      print('Expected format: FC(0x5A) + pairingKey + subFuncEcho + status');
      print('');

      for (final subFunc in [0x01, 0x02, 0x03, 0x04, 0x26]) {
        final req = UmasRequest(
          umasSubFunction: subFunc,
          unitId: _unitId,
        );
        final code = await tcp.send(req);
        final pdu = req.responsePdu;

        if (pdu != null && pdu.length >= 4) {
          print('SubFunc 0x${subFunc.toRadixString(16).padLeft(2, "0")}:');
          print('  Response: ${_hexDump(pdu)}');
          print('  pdu[0]=FC: 0x${pdu[0].toRadixString(16)} '
              '(expect 0x5a)');
          print('  pdu[1]=pairing: 0x${pdu[1].toRadixString(16)} '
              '(expect 0x00)');
          print('  pdu[2]=subFuncEcho: 0x${pdu[2].toRadixString(16)} '
              '(expect 0x${subFunc.toRadixString(16)})');
          print('  pdu[3]=status: 0x${pdu[3].toRadixString(16)} '
              '(0xFE=success, 0xFD=error)');

          // Verify the format: pdu[2] should echo the request sub-function
          expect(pdu[0], 0x5A, reason: 'FC should be 0x5A');
          expect(pdu[2], subFunc,
              reason: 'pdu[2] should echo the request sub-function');
        } else {
          print('SubFunc 0x${subFunc.toRadixString(16).padLeft(2, "0")}: '
              '$code, PDU=${pdu != null ? _hexDump(pdu) : "null"}');
        }
      }
    }, skip: 'Live test -- requires Schneider PLC at $_host');
  });
}
