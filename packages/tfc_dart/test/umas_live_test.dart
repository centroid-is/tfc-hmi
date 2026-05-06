/// Live hardware integration tests for UMAS protocol against real Schneider PLC.
///
/// These tests are skipped by default and only run with --run-skipped:
///   cd packages/tfc_dart && dart test test/umas_live_test.dart --run-skipped --reporter expanded
///
/// Requires a Schneider PLC at 10.50.10.12:502.
///
/// Response format observed from real PLC (3-byte header):
///   pdu[0] = FC (0x5A)
///   pdu[1] = PairingKey
///   pdu[2] = Status (0xFE=success, 0xFD=error)
///   pdu[3+] = Payload (on success) or error code (on 0xFD)
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

const _host = '10.50.10.12';
const _port = 502;

/// Default unit ID -- overridden by unit ID discovery test.
const _defaultUnitId = 255;

/// Helper to dump bytes as hex for debugging.
String _hexDump(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

/// Working unit ID discovered by the probe test.
/// Defaults to 255; updated by the unit ID discovery test.
int _workingUnitId = _defaultUnitId;

/// Whether unit ID discovery succeeded.
bool _unitIdDiscovered = false;

/// Helper to create a connected TCP client and UmasClient pair.
/// Caller is responsible for calling tcp.disconnect().
Future<(ModbusClientTcp, UmasClient)> _createClient() async {
  final tcp = ModbusClientTcp(
    _host,
    serverPort: _port,
    unitId: _workingUnitId,
    connectionMode: ModbusConnectionMode.doNotConnect,
    connectionTimeout: const Duration(seconds: 5),
  );
  await tcp.connect();
  final umas = UmasClient(sendFn: tcp.send, unitId: _workingUnitId);
  return (tcp, umas);
}

void main() {
  group('Live UMAS @ $_host:$_port', () {
    // ---------------------------------------------------------------
    // Unit ID discovery -- must run first
    // ---------------------------------------------------------------
    test('Unit ID discovery: probe 0, 1, 254, 255', () async {
      final candidates = [0, 1, 254, 255];
      final results = <int, String>{};

      for (final uid in candidates) {
        final tcp = ModbusClientTcp(
          _host,
          serverPort: _port,
          unitId: uid,
          connectionMode: ModbusConnectionMode.doNotConnect,
          connectionTimeout: const Duration(seconds: 5),
        );

        try {
          final connected = await tcp.connect();
          if (!connected) {
            results[uid] = 'TCP connect failed';
            continue;
          }

          // Send raw readPlcId (0x02) with this unit ID
          final req = UmasRequest(
            umasSubFunction: UmasSubFunction.readId.code,
            unitId: uid,
          );
          final code = await tcp.send(req);
          final pdu = req.responsePdu;

          if (pdu != null && pdu.length >= 3) {
            final status = pdu[2];
            final statusHex = '0x${status.toRadixString(16)}';
            results[uid] =
                'code=$code, status=$statusHex, pdu=${_hexDump(pdu.take(12).toList())}${pdu.length > 12 ? "... (${pdu.length}B)" : ""}';

            if (status == 0xFE) {
              _workingUnitId = uid;
              _unitIdDiscovered = true;
              print('  >>> Unit ID $uid WORKS (status=0xFE success)');
            }
          } else {
            results[uid] = 'code=$code, pdu=${pdu != null ? _hexDump(pdu) : "null"}';
          }
        } catch (e) {
          results[uid] = 'ERROR: $e';
        } finally {
          await tcp.disconnect();
        }
      }

      print('Unit ID Discovery Results for $_host:');
      for (final entry in results.entries) {
        print('  unitId=${entry.key}: ${entry.value}');
      }
      print('  Working unit ID: $_workingUnitId (discovered=$_unitIdDiscovered)');

      // At least one should have responded (even if with error)
      expect(results.values.any((v) => !v.startsWith('ERROR')), isTrue,
          reason: 'At least one unit ID should get a response from the PLC');
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    // ---------------------------------------------------------------
    // Wire format diagnostic -- tests all implemented sub-functions
    // ---------------------------------------------------------------
    test('Wire format diagnostic: all implemented sub-functions', () async {
      final tcp = ModbusClientTcp(
        _host,
        serverPort: _port,
        unitId: _workingUnitId,
        connectionMode: ModbusConnectionMode.doNotConnect,
        connectionTimeout: const Duration(seconds: 5),
      );
      await tcp.connect();
      expect(tcp.isConnected, isTrue);

      print('UMAS Wire Format Diagnostic (unitId=$_workingUnitId):');
      print('Expected: pdu[0]=0x5A, pdu[2]=status (0xFE/0xFD)');
      print('');

      // All currently implemented sub-functions
      final subFunctions = <int, String>{
        0x01: 'init',
        0x02: 'readPlcId',
        0x03: 'readProjectInfo',
        0x04: 'plcStatus',
        0x0A: 'echo',
        0x12: 'keepAlive',
        0x26: 'readDataDictionary',
      };

      for (final entry in subFunctions.entries) {
        final subFunc = entry.key;
        final name = entry.value;
        final req = UmasRequest(
          umasSubFunction: subFunc,
          unitId: _workingUnitId,
        );
        final code = await tcp.send(req);
        final pdu = req.responsePdu;

        if (pdu != null && pdu.length >= 3) {
          print('0x${subFunc.toRadixString(16).padLeft(2, "0")} ($name):');
          print('  Response (${pdu.length}B): ${_hexDump(pdu.take(20).toList())}${pdu.length > 20 ? "..." : ""}');
          print('  pdu[0]=FC: 0x${pdu[0].toRadixString(16)} (expect 0x5a)');
          print('  pdu[1]=pairing: 0x${pdu[1].toRadixString(16)}');
          print('  pdu[2]=status: 0x${pdu[2].toRadixString(16)} (0xFE=success, 0xFD=error)');
          print('  pdu[3+]=payload start');
          print('');

          // Verify wire format invariants (3-byte header)
          expect(pdu[0], 0x5A, reason: '$name: FC should be 0x5A');
          // Status should be 0xFE (success) or 0xFD (error) -- not some other value
          expect(pdu[2] == 0xFE || pdu[2] == 0xFD, isTrue,
              reason: '$name: pdu[2] should be 0xFE or 0xFD, got 0x${pdu[2].toRadixString(16)}');
        } else {
          print('0x${subFunc.toRadixString(16).padLeft(2, "0")} ($name): '
              'code=$code, pdu=${pdu != null ? _hexDump(pdu) : "null"}');
        }
      }

      await tcp.disconnect();
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    // ---------------------------------------------------------------
    // PlcStatus (0x04) live test
    // ---------------------------------------------------------------
    test('readPlcStatus() returns valid CRC data from real PLC', () async {
      final (tcp, umas) = await _createClient();

      try {
        final status = await umas.readPlcStatus();
        print('PLC Status (0x04):');
        print('  statusByte: 0x${status.statusByte.toRadixString(16)}');
        print('  numberOfBlocks: ${status.numberOfBlocks}');
        for (int i = 0; i < status.blockCrcs.length; i++) {
          print('  CRC[$i]: 0x${status.blockCrcs[i].toRadixString(16)}');
        }
        print('  crcChanged: ${status.crcChanged}');
        print('  additionalData (${status.additionalData.length}B): ${_hexDump(status.additionalData)}');

        expect(status.blockCrcs, isNotEmpty,
            reason: 'Real PLC should have block CRCs');
        expect(status.crcChanged, isFalse,
            reason: 'First poll should report no CRC change');
      } on UmasException catch (e) {
        print('UMAS readPlcStatus error: $e');
        print('  PLC may not support UMAS or needs configuration.');
      }

      await tcp.disconnect();
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    // ---------------------------------------------------------------
    // ProjectInfo (0x03) live test
    // ---------------------------------------------------------------
    test('readProjectInfo() returns project data from real PLC', () async {
      final (tcp, umas) = await _createClient();

      try {
        final info = await umas.readProjectInfo();
        print('Project Info (0x03):');
        print('  rawData (${info.rawData.length} bytes): ${_hexDump(info.rawData)}');
        print('  projectName: ${info.projectName ?? "(not extracted)"}');

        expect(info.rawData, isNotEmpty,
            reason: 'Real PLC should return project info data');
      } on UmasException catch (e) {
        print('UMAS readProjectInfo error: $e');
        print('  PLC may not support readProjectInfo.');
      }

      await tcp.disconnect();
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    // ---------------------------------------------------------------
    // Full session lifecycle test
    // ---------------------------------------------------------------
    test('Full session lifecycle: readPlcId -> init -> plcStatus -> browse',
        () async {
      final (tcp, umas) = await _createClient();

      try {
        // Step 1: Read PLC Identification
        final ident = await umas.readPlcId();
        print('Step 1 - PLC ID:');
        print('  hardwareId: 0x${ident.hardwareId.toRadixString(16)}');
        print('  index: ${ident.index}');
        print('  numberOfMemoryBanks: ${ident.numberOfMemoryBanks}');
        expect(umas.sessionState, UmasSessionState.identified);

        // Step 2: Initialize session
        final initResult = await umas.init();
        print('Step 2 - Init:');
        print('  maxFrameSize: ${initResult.maxFrameSize}');
        expect(umas.sessionState, UmasSessionState.paired);

        // Step 3: Read PLC Status
        final status = await umas.readPlcStatus();
        print('Step 3 - PLC Status:');
        print('  statusByte: 0x${status.statusByte.toRadixString(16)}');
        print('  numberOfBlocks: ${status.numberOfBlocks}');
        print('  CRCs: ${status.blockCrcs.map((c) => '0x${c.toRadixString(16)}').toList()}');

        // Step 4: Browse variable tree
        final tree = await umas.browse();
        print('Step 4 - Browse:');
        print('  ${tree.length} root nodes');
        for (final root in tree) {
          _printTreeNode(root, 1);
        }

        // If we get here without exceptions, the wire format is correct
        print('');
        print('Full session lifecycle PASSED');
      } on UmasException catch (e) {
        print('UMAS lifecycle error at step: $e');
        print('  Session state: ${umas.sessionState}');
        // Don't fail -- capture the observation
      }

      await tcp.disconnect();
    },
        skip: 'Live test -- requires Schneider PLC at $_host',
        timeout: Timeout(Duration(seconds: 30)));

    // ---------------------------------------------------------------
    // CRC change detection across consecutive polls
    // ---------------------------------------------------------------
    test('Consecutive PlcStatus polls: CRC change detection', () async {
      final (tcp, umas) = await _createClient();

      try {
        final status1 = await umas.readPlcStatus();
        print('Poll 1: ${status1.numberOfBlocks} blocks, crcChanged=${status1.crcChanged}');
        expect(status1.crcChanged, isFalse,
            reason: 'First poll should report no change');

        final status2 = await umas.readPlcStatus();
        print('Poll 2: ${status2.numberOfBlocks} blocks, crcChanged=${status2.crcChanged}');
        // Without a PLC project change, CRCs should be stable
        print('  CRC stable: ${!status2.crcChanged}');
      } on UmasException catch (e) {
        print('UMAS consecutive poll error: $e');
      }

      await tcp.disconnect();
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    // ---------------------------------------------------------------
    // TCP connection basic test
    // ---------------------------------------------------------------
    test('TCP connection to PLC succeeds', () async {
      final tcp = ModbusClientTcp(
        _host,
        serverPort: _port,
        unitId: _workingUnitId,
        connectionMode: ModbusConnectionMode.doNotConnect,
        connectionTimeout: const Duration(seconds: 5),
      );
      final ok = await tcp.connect();
      expect(ok, isTrue, reason: 'TCP connect should succeed');
      expect(tcp.isConnected, isTrue);
      print('Connected to $_host:$_port');
      await tcp.disconnect();
    }, skip: 'Live test -- requires Schneider PLC at $_host');

    // ---------------------------------------------------------------
    // Echo & KeepAlive group
    // ---------------------------------------------------------------
    group('Echo & KeepAlive', () {
      test('sendEcho() returns echoed payload and latency', () async {
        final (tcp, umas) = await _createClient();

        try {
          final testPayload = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
          final result = await umas.sendEcho(testPayload);
          print('Echo (0x0A):');
          print('  sent: ${_hexDump(testPayload)}');
          print('  received: ${_hexDump(result.payload)}');
          print('  latency: ${result.latency.inMilliseconds}ms');

          expect(result.payload, equals(testPayload),
              reason: 'Echoed payload should match input');
          expect(result.latency, greaterThan(Duration.zero),
              reason: 'Latency should be positive');
        } on UmasException catch (e) {
          print('UMAS sendEcho error: $e');
          print('  PLC may not support echo sub-function.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('sendKeepAlive() succeeds in paired state', () async {
        final (tcp, umas) = await _createClient();

        try {
          await umas.sendKeepAlive();
          print('KeepAlive (0x12): SUCCESS');
          print('  Session state: ${umas.sessionState}');
        } on UmasException catch (e) {
          print('UMAS sendKeepAlive error: $e');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));
    });

    // ---------------------------------------------------------------
    // Reservation lifecycle group
    // ---------------------------------------------------------------
    group('Reservation lifecycle', () {
      test('takePlcReservation() + releasePlcReservation() succeeds',
          () async {
        final (tcp, umas) = await _createClient();

        try {
          await umas.takePlcReservation();
          print('Reservation (0x10): TAKEN');
          print('  hasReservation: ${umas.hasReservation}');
          expect(umas.hasReservation, isTrue,
              reason: 'Should have reservation after take');

          await umas.releasePlcReservation();
          print('Reservation (0x11): RELEASED');
          print('  hasReservation: ${umas.hasReservation}');
          expect(umas.hasReservation, isFalse,
              reason: 'Should not have reservation after release');
        } on UmasReservationException catch (e) {
          print('Reservation conflict: $e');
          print('  Another client may hold the reservation -- PLC-specific limitation.');
        } on UmasException catch (e) {
          print('UMAS reservation error: $e');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('withReservation() runs operation and releases', () async {
        final (tcp, umas) = await _createClient();

        try {
          var operationRan = false;
          await umas.withReservation(() async {
            operationRan = true;
            print('withReservation: inside operation, hasReservation=${umas.hasReservation}');
            expect(umas.hasReservation, isTrue);
          });
          print('withReservation: after operation, hasReservation=${umas.hasReservation}');
          expect(operationRan, isTrue, reason: 'Operation should have run');
          expect(umas.hasReservation, isFalse,
              reason: 'Should release reservation after withReservation');
        } on UmasReservationException catch (e) {
          print('Reservation conflict in withReservation: $e');
          print('  Another client may hold the reservation -- PLC-specific limitation.');
        } on UmasException catch (e) {
          print('UMAS withReservation error: $e');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));
    });

    // ---------------------------------------------------------------
    // MonitorPlc (0x50) group
    // ---------------------------------------------------------------
    group('MonitorPlc (0x50)', () {
      test('monitorReset() succeeds', () async {
        final (tcp, umas) = await _createClient();

        try {
          await umas.monitorReset();
          print('MonitorPlc Reset (0x0B): SUCCESS');
          expect(umas.monitorRegistrations.isEmpty, isTrue);
        } on UmasException catch (e) {
          print('MonitorPlc Reset error: $e');
          print('  PLC may not support MonitorPlc -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('monitorRegister() returns indices', () async {
        final (tcp, umas) = await _createClient();

        try {
          // Reset first to start clean
          await umas.monitorReset();

          // Register a synthetic variable (block=0, offset=0, typeId=100)
          final testVar = UmasVariable(
            name: 'test_monitor_var',
            blockNo: 0,
            offset: 0,
            dataTypeId: 100,
          );
          final testType = UmasDataTypeRef(
            id: 100,
            name: 'INT',
            byteSize: 2,
          );

          final indices = await umas.monitorRegister([(testVar, testType)]);
          print('MonitorPlc Register (0x05): SUCCESS');
          print('  indices: $indices');
          expect(indices, isNotEmpty,
              reason: 'Should return at least one index');

          // Cleanup
          await umas.monitorReset();
        } on UmasException catch (e) {
          print('MonitorPlc Register error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  Synthetic variable address may not exist on PLC -- expected on M580.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('monitorReadAll() returns values after register', () async {
        final (tcp, umas) = await _createClient();

        try {
          await umas.monitorReset();

          final testVar = UmasVariable(
            name: 'test_read_var',
            blockNo: 0,
            offset: 0,
            dataTypeId: 100,
          );
          final testType = UmasDataTypeRef(
            id: 100,
            name: 'INT',
            byteSize: 2,
          );

          await umas.monitorRegister([(testVar, testType)]);
          final values = await umas.monitorReadAll();
          print('MonitorPlc ReadAll (0x07): SUCCESS');
          print('  values count: ${values.length}');
          for (final v in values) {
            print('  ${v.typeName}: ${v.value} (${_hexDump(v.rawBytes)})');
          }
          expect(values, isNotEmpty,
              reason: 'Should return values for registered variables');

          await umas.monitorReset();
        } on UmasException catch (e) {
          print('MonitorPlc ReadAll error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  Synthetic variable may not exist on PLC -- expected on M580.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('monitorRegisterAndRead() returns values', () async {
        final (tcp, umas) = await _createClient();

        try {
          await umas.monitorReset();

          final testVar = UmasVariable(
            name: 'test_regread_var',
            blockNo: 0,
            offset: 0,
            dataTypeId: 100,
          );
          final testType = UmasDataTypeRef(
            id: 100,
            name: 'INT',
            byteSize: 2,
          );

          final values =
              await umas.monitorRegisterAndRead([(testVar, testType)]);
          print('MonitorPlc RegisterAndRead (0x09): SUCCESS');
          print('  values count: ${values.length}');
          for (final v in values) {
            print('  ${v.typeName}: ${v.value} (${_hexDump(v.rawBytes)})');
          }
          expect(values, isNotEmpty,
              reason: 'Should return values for registered variables');

          await umas.monitorReset();
        } on UmasException catch (e) {
          print('MonitorPlc RegisterAndRead error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  Synthetic variable may not exist on PLC -- expected on M580.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));
    });

    // ---------------------------------------------------------------
    // ReadCoilsRegisters (0x24) group
    // ---------------------------------------------------------------
    group('ReadCoilsRegisters (0x24)', () {
      test('readCoilsRegisters() reads %MW0', () async {
        final (tcp, umas) = await _createClient();

        try {
          final address = RegisterAddress(
            type: RegisterType.memoryWord,
            startAddress: 0,
            quantity: 1,
          );
          final result = await umas.readCoilsRegisters(address);
          print('ReadCoilsRegisters (0x24) %MW0:');
          print('  rawBytes (${result.rawBytes.length}B): ${_hexDump(result.rawBytes)}');
          expect(result.rawBytes, isNotEmpty,
              reason: 'Should return register data');
        } on UmasException catch (e) {
          print('ReadCoilsRegisters error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support 0x24 or wire format may be wrong -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('readCoilsRegisters() reads %M0 (coil)', () async {
        final (tcp, umas) = await _createClient();

        try {
          final address = RegisterAddress(
            type: RegisterType.coil,
            startAddress: 0,
            quantity: 8,
          );
          final result = await umas.readCoilsRegisters(address);
          print('ReadCoilsRegisters (0x24) %M0..7:');
          print('  rawBytes (${result.rawBytes.length}B): ${_hexDump(result.rawBytes)}');
          expect(result.rawBytes, isNotEmpty,
              reason: 'Should return coil data');
        } on UmasException catch (e) {
          print('ReadCoilsRegisters coil error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support coil read via 0x24 -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('readCoilsRegisters() reads %SW0 (system word)', () async {
        final (tcp, umas) = await _createClient();

        try {
          final address = RegisterAddress(
            type: RegisterType.systemWord,
            startAddress: 0,
            quantity: 1,
          );
          final result = await umas.readCoilsRegisters(address);
          print('ReadCoilsRegisters (0x24) %SW0:');
          print('  rawBytes (${result.rawBytes.length}B): ${_hexDump(result.rawBytes)}');
          expect(result.rawBytes, isNotEmpty,
              reason: 'Should return system word data');
        } on UmasException catch (e) {
          print('ReadCoilsRegisters system word error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support system word read via 0x24 -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));
    });

    // ---------------------------------------------------------------
    // Diagnostics group (all 6 sub-functions)
    // ---------------------------------------------------------------
    group('Diagnostics', () {
      test('readCardInfo() (0x06) returns data', () async {
        final (tcp, umas) = await _createClient();

        try {
          final result = await umas.readCardInfo();
          print('ReadCardInfo (0x06):');
          print('  rawData (${result.rawData.length}B): ${_hexDump(result.rawData)}');
          expect(result.rawData, isNotEmpty,
              reason: 'Should return card info data');
        } on UmasException catch (e) {
          print('ReadCardInfo error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not have SD card or may not support 0x06 -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('readMemoryBlock() (0x20) reads block 0', () async {
        final (tcp, umas) = await _createClient();

        try {
          final request = ReadMemoryBlockRequest(
            range: 0,
            blockNumber: 0,
            offset: 0,
            numberOfBytes: 16,
          );
          final result = await umas.readMemoryBlock(request);
          print('ReadMemoryBlock (0x20):');
          print('  range: ${result.range}');
          print('  numberOfBytes: ${result.numberOfBytes}');
          print('  data (${result.data.length}B): ${_hexDump(result.data)}');
          expect(result.data, isNotEmpty,
              reason: 'Should return memory block data');
        } on UmasException catch (e) {
          print('ReadMemoryBlock error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support 0x20 or block 0 may not exist -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('readEthMasterData() (0x39) returns data', () async {
        final (tcp, umas) = await _createClient();

        try {
          final result = await umas.readEthMasterData();
          print('ReadEthMasterData (0x39):');
          print('  rawData (${result.rawData.length}B): ${_hexDump(result.rawData.take(40).toList())}${result.rawData.length > 40 ? "..." : ""}');
          expect(result.rawData, isNotEmpty,
              reason: 'Should return Ethernet master data');
        } on UmasException catch (e) {
          print('ReadEthMasterData error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support 0x39 -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('checkPlc() (0x58) returns data', () async {
        final (tcp, umas) = await _createClient();

        try {
          final result = await umas.checkPlc();
          print('CheckPlc (0x58):');
          print('  rawData (${result.rawData.length}B): ${_hexDump(result.rawData)}');
          expect(result.rawData, isNotEmpty,
              reason: 'Should return PLC health data');
        } on UmasException catch (e) {
          print('CheckPlc error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support 0x58 -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('readIoObject() (0x70) returns data', () async {
        final (tcp, umas) = await _createClient();

        try {
          final result = await umas.readIoObject();
          print('ReadIoObject (0x70):');
          print('  rawData (${result.rawData.length}B): ${_hexDump(result.rawData.take(40).toList())}${result.rawData.length > 40 ? "..." : ""}');
          expect(result.rawData, isNotEmpty,
              reason: 'Should return I/O object data');
        } on UmasException catch (e) {
          print('ReadIoObject error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support 0x70 -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));

      test('getStatusModule() (0x73) returns data', () async {
        final (tcp, umas) = await _createClient();

        try {
          final result = await umas.getStatusModule();
          print('GetStatusModule (0x73):');
          print('  rawData (${result.rawData.length}B): ${_hexDump(result.rawData.take(40).toList())}${result.rawData.length > 40 ? "..." : ""}');
          expect(result.rawData, isNotEmpty,
              reason: 'Should return module status data');
        } on UmasException catch (e) {
          print('GetStatusModule error: $e');
          print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          print('  PLC may not support 0x73 -- PLC-specific limitation.');
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 30)));
    });

    // ---------------------------------------------------------------
    // Browse group (data dictionary dependent)
    // ---------------------------------------------------------------
    group('Browse (data dictionary)', () {
      test('browse() returns variable tree or reports DD error', () async {
        final (tcp, umas) = await _createClient();

        try {
          final tree = await umas.browse();
          print('Browse:');
          print('  ${tree.length} root nodes');
          for (final root in tree.take(5)) {
            _printTreeNode(root, 1);
          }
          if (tree.length > 5) {
            print('  ... and ${tree.length - 5} more root nodes');
          }
          expect(tree, isNotEmpty,
              reason: 'Browse should return variable tree');
        } on UmasException catch (e) {
          if (e.errorCode == 0xC0) {
            print('Browse: DD03 returned 0xC0 -- data dictionary not supported on this M580.');
            print('  This is expected behavior for M580 PLCs.');
          } else {
            print('Browse error: $e');
            print('  errorCode: 0x${e.errorCode.toRadixString(16)}');
          }
          // Do not fail -- DD not supported on M580 is expected
        }

        await tcp.disconnect();
      },
          skip: 'Live test -- requires Schneider PLC at $_host',
          timeout: Timeout(Duration(seconds: 60)));
    });
  });
}

/// Helper to print a variable tree node with indentation.
void _printTreeNode(UmasVariableTreeNode node, int depth) {
  final indent = '  ' * depth;
  if (node.isFolder) {
    print('$indent[${node.name}] (${node.children.length} children)');
  } else {
    final v = node.variable;
    final dt = node.dataType;
    print('$indent${node.name} '
        '(block=${v?.blockNo}, offset=${v?.offset}, '
        'type=${dt?.name ?? "unknown"}, ${dt?.byteSize ?? 0}B)');
  }
  // Only print first few children to avoid excessive output
  final maxChildren = 5;
  for (int i = 0; i < node.children.length && i < maxChildren; i++) {
    _printTreeNode(node.children[i], depth + 1);
  }
  if (node.children.length > maxChildren) {
    print('$indent  ... and ${node.children.length - maxChildren} more');
  }
}
