/// Tests for ReadCoilsRegisters (0x24) and WriteCoilsRegisters (0x25) support.
///
/// Run: dart test test/umas_coils_registers_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // UmasSubFunction enum entries
  // ---------------------------------------------------------------------------

  group('UmasSubFunction enum', () {
    test('readCoilsRegisters exists with code 0x24', () {
      expect(UmasSubFunction.readCoilsRegisters.code, 0x24);
    });

    test('writeCoilsRegisters exists with code 0x25', () {
      expect(UmasSubFunction.writeCoilsRegisters.code, 0x25);
    });
  });

  // ---------------------------------------------------------------------------
  // RegisterType enum
  // ---------------------------------------------------------------------------

  group('RegisterType enum', () {
    test('coil (%M) has area code 0x00', () {
      expect(RegisterType.coil.areaCode, 0x00);
    });

    test('memoryWord (%MW) has area code 0x04', () {
      expect(RegisterType.memoryWord.areaCode, 0x04);
    });

    test('systemBit (%S) has area code 0x06', () {
      expect(RegisterType.systemBit.areaCode, 0x06);
    });

    test('systemWord (%SW) has area code 0x07', () {
      expect(RegisterType.systemWord.areaCode, 0x07);
    });
  });

  // ---------------------------------------------------------------------------
  // RegisterAddress model
  // ---------------------------------------------------------------------------

  group('RegisterAddress', () {
    test('%MW 100 x10 serializes to 5 bytes (area=0x04, addr=100 LE, qty=10 LE)', () {
      final addr = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 100,
        quantity: 10,
      );
      final bytes = addr.toBytes();
      expect(bytes.length, 5);
      expect(bytes[0], 0x04); // memoryWord area code
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint16(1, Endian.little), 100);
      expect(bd.getUint16(3, Endian.little), 10);
    });

    test('%M 0 x16 serializes correctly for coils', () {
      final addr = RegisterAddress(
        type: RegisterType.coil,
        startAddress: 0,
        quantity: 16,
      );
      final bytes = addr.toBytes();
      expect(bytes.length, 5);
      expect(bytes[0], 0x00); // coil area code
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint16(1, Endian.little), 0);
      expect(bd.getUint16(3, Endian.little), 16);
    });

    test('%S 50 x1 serializes correctly for system bits', () {
      final addr = RegisterAddress(
        type: RegisterType.systemBit,
        startAddress: 50,
        quantity: 1,
      );
      final bytes = addr.toBytes();
      expect(bytes.length, 5);
      expect(bytes[0], 0x06); // systemBit area code
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint16(1, Endian.little), 50);
      expect(bd.getUint16(3, Endian.little), 1);
    });

    test('expectedDataBytes: coils are bit-packed (16 coils = 2 bytes)', () {
      final addr = RegisterAddress(
        type: RegisterType.coil,
        startAddress: 0,
        quantity: 16,
      );
      expect(addr.expectedDataBytes, 2);
    });

    test('expectedDataBytes: 10 memory words = 20 bytes', () {
      final addr = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 0,
        quantity: 10,
      );
      expect(addr.expectedDataBytes, 20);
    });

    test('expectedDataBytes: 9 system bits = 2 bytes (ceil(9/8))', () {
      final addr = RegisterAddress(
        type: RegisterType.systemBit,
        startAddress: 0,
        quantity: 9,
      );
      expect(addr.expectedDataBytes, 2);
    });

    test('expectedDataBytes: 5 system words = 10 bytes', () {
      final addr = RegisterAddress(
        type: RegisterType.systemWord,
        startAddress: 0,
        quantity: 5,
      );
      expect(addr.expectedDataBytes, 10);
    });
  });

  // ---------------------------------------------------------------------------
  // readCoilsRegisters (mock sendFn)
  // ---------------------------------------------------------------------------

  group('readCoilsRegisters (mock)', () {
    test('sends 0x24 sub-function with correct payload', () async {
      UmasRequest? capturedRequest;

      // Build a mock sendFn that captures the request and returns a valid PDU
      Future<ModbusResponseCode> mockSend(ModbusRequest req) async {
        capturedRequest = req as UmasRequest;
        // Simulate response: FC(0x5A) + pairingKey(0x42) + status(0xFE) + 20 bytes data
        final responsePdu = Uint8List(3 + 20);
        responsePdu[0] = 0x5A;
        responsePdu[1] = 0x42;
        responsePdu[2] = 0xFE;
        // Fill data with pattern
        for (int i = 0; i < 20; i++) {
          responsePdu[3 + i] = i;
        }
        req.internalSetFromPduResponse(responsePdu);
        return ModbusResponseCode.requestSucceed;
      }

      // First set up a paired client (mock init + readPlcId)
      int callCount = 0;
      Future<ModbusResponseCode> fullMockSend(ModbusRequest req) async {
        final umasReq = req as UmasRequest;
        callCount++;

        if (umasReq.umasSubFunction == 0x02) {
          // readPlcId response
          final payload = Uint8List(16);
          final bd = ByteData.sublistView(payload);
          bd.setUint16(0, 0x0001, Endian.little); // range
          bd.setUint32(2, 0x12345678, Endian.little); // hardwareId
          payload[6] = 1; // numberOfMemoryBanks
          bd.setUint16(7, 0, Endian.little); // index
          final pdu = Uint8List(3 + payload.length);
          pdu[0] = 0x5A;
          pdu[1] = 0x00;
          pdu[2] = 0xFE;
          pdu.setAll(3, payload);
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        } else if (umasReq.umasSubFunction == 0x01) {
          // init response
          final pdu = Uint8List(5);
          pdu[0] = 0x5A;
          pdu[1] = 0x42; // pairing key
          pdu[2] = 0xFE;
          pdu[3] = 0xFD; // max frame LE low
          pdu[4] = 0x03; // max frame LE high = 1021
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        } else if (umasReq.umasSubFunction == 0x24) {
          return mockSend(req);
        }
        return ModbusResponseCode.requestSucceed;
      }

      final client = UmasClient(
        sendFn: fullMockSend,
        backoffDelay: (_) async {},
      );

      final address = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 100,
        quantity: 10,
      );

      final result = await client.readCoilsRegisters(address);

      // Verify the captured request
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.umasSubFunction, 0x24);

      // Verify payload is the serialized RegisterAddress
      final expectedPayload = address.toBytes();
      expect(capturedRequest!.umasPayload, expectedPayload);

      // Verify result contains the response data
      expect(result.rawBytes.length, 20);
    });

    test('returns raw response bytes from PDU', () async {
      Future<ModbusResponseCode> mockSend(ModbusRequest req) async {
        // Return a response with specific data bytes
        final responsePdu = Uint8List(3 + 4);
        responsePdu[0] = 0x5A;
        responsePdu[1] = 0x00;
        responsePdu[2] = 0xFE;
        responsePdu[3] = 0xAA;
        responsePdu[4] = 0xBB;
        responsePdu[5] = 0xCC;
        responsePdu[6] = 0xDD;
        req.internalSetFromPduResponse(responsePdu);
        return ModbusResponseCode.requestSucceed;
      }

      int callCount = 0;
      Future<ModbusResponseCode> fullMockSend(ModbusRequest req) async {
        final umasReq = req as UmasRequest;
        callCount++;
        if (umasReq.umasSubFunction == 0x02) {
          final payload = Uint8List(16);
          final bd = ByteData.sublistView(payload);
          bd.setUint16(0, 0x0001, Endian.little);
          bd.setUint32(2, 0x12345678, Endian.little);
          payload[6] = 1;
          bd.setUint16(7, 0, Endian.little);
          final pdu = Uint8List(3 + payload.length);
          pdu[0] = 0x5A; pdu[1] = 0x00; pdu[2] = 0xFE;
          pdu.setAll(3, payload);
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        } else if (umasReq.umasSubFunction == 0x01) {
          final pdu = Uint8List(5);
          pdu[0] = 0x5A; pdu[1] = 0x00; pdu[2] = 0xFE;
          pdu[3] = 0xFD; pdu[4] = 0x03;
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        } else if (umasReq.umasSubFunction == 0x24) {
          return mockSend(req);
        }
        return ModbusResponseCode.requestSucceed;
      }

      final client = UmasClient(
        sendFn: fullMockSend,
        backoffDelay: (_) async {},
      );

      final address = RegisterAddress(
        type: RegisterType.coil,
        startAddress: 0,
        quantity: 8,
      );

      final result = await client.readCoilsRegisters(address);
      expect(result.rawBytes, equals([0xAA, 0xBB, 0xCC, 0xDD]));
    });
  });

  // ---------------------------------------------------------------------------
  // writeCoilsRegisters (mock sendFn)
  // ---------------------------------------------------------------------------

  group('writeCoilsRegisters (mock)', () {
    /// Helper to build a mock that handles init handshake + target sub-function.
    Future<ModbusResponseCode> Function(ModbusRequest) buildMock({
      required Future<ModbusResponseCode> Function(ModbusRequest) onTarget,
    }) {
      return (ModbusRequest req) async {
        final umasReq = req as UmasRequest;
        if (umasReq.umasSubFunction == 0x02) {
          final payload = Uint8List(16);
          final bd = ByteData.sublistView(payload);
          bd.setUint16(0, 0x0001, Endian.little);
          bd.setUint32(2, 0x12345678, Endian.little);
          payload[6] = 1;
          bd.setUint16(7, 0, Endian.little);
          final pdu = Uint8List(3 + payload.length);
          pdu[0] = 0x5A; pdu[1] = 0x00; pdu[2] = 0xFE;
          pdu.setAll(3, payload);
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        } else if (umasReq.umasSubFunction == 0x01) {
          final pdu = Uint8List(5);
          pdu[0] = 0x5A; pdu[1] = 0x00; pdu[2] = 0xFE;
          pdu[3] = 0xFD; pdu[4] = 0x03;
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        } else if (umasReq.umasSubFunction == 0x25) {
          return onTarget(req);
        }
        // Default success for other sub-functions
        final pdu = Uint8List(3);
        pdu[0] = 0x5A; pdu[1] = 0x00; pdu[2] = 0xFE;
        req.internalSetFromPduResponse(pdu);
        return ModbusResponseCode.requestSucceed;
      };
    }

    test('sends 0x25 sub-function with payload = address + data', () async {
      UmasRequest? capturedRequest;

      final mockSend = buildMock(
        onTarget: (req) async {
          capturedRequest = req as UmasRequest;
          final pdu = Uint8List(3);
          pdu[0] = 0x5A; pdu[1] = 0x00; pdu[2] = 0xFE;
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        },
      );

      final client = UmasClient(sendFn: mockSend, backoffDelay: (_) async {});

      final address = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 100,
        quantity: 5,
      );
      final data = Uint8List(10); // 5 words = 10 bytes
      for (int i = 0; i < 10; i++) data[i] = i;

      await client.writeCoilsRegisters(address, data);

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.umasSubFunction, 0x25);

      // Payload should be address bytes (5) + data bytes (10) = 15
      expect(capturedRequest!.umasPayload.length, 15);

      // First 5 bytes = RegisterAddress
      final addrBytes = address.toBytes();
      expect(capturedRequest!.umasPayload.sublist(0, 5), addrBytes);

      // Remaining 10 bytes = data
      expect(capturedRequest!.umasPayload.sublist(5), data);
    });

    test('validates data length matches expected size (T-07-01)', () async {
      final mockSend = buildMock(
        onTarget: (req) async {
          final pdu = Uint8List(3);
          pdu[0] = 0x5A; pdu[1] = 0x00; pdu[2] = 0xFE;
          req.internalSetFromPduResponse(pdu);
          return ModbusResponseCode.requestSucceed;
        },
      );

      final client = UmasClient(sendFn: mockSend, backoffDelay: (_) async {});

      final address = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 0,
        quantity: 5,
      );
      // Wrong data length: 5 words need 10 bytes, but providing 8
      final wrongData = Uint8List(8);

      expect(
        () => client.writeCoilsRegisters(address, wrongData),
        throwsA(isA<UmasException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // E2E tests against Python stub server
  // ---------------------------------------------------------------------------

  group('E2E CoilsRegisters (0x24/0x25) via stub', () {
    late int stubPort;
    Process? serverProcess;

    String findProjectRoot() {
      var dir = Directory.current;
      while (dir.path != dir.parent.path) {
        if (File('${dir.path}/test/umas_stub_server.py').existsSync()) {
          return dir.path;
        }
        dir = dir.parent;
      }
      return '${Directory.current.path}/../..';
    }

    setUp(() async {
      final stubScript = '${findProjectRoot()}/test/umas_stub_server.py';

      String python;
      try {
        final r = await Process.run('python3', ['--version']);
        python = r.exitCode == 0 ? 'python3' : 'python';
      } catch (_) {
        python = 'python';
      }

      serverProcess = await Process.start(
        python,
        ['-u', stubScript, '--port', '0'],
      );

      serverProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((line) => stderr.write('[STUB ERR] $line'));

      final portPattern = RegExp(r'PORT=(\d+)');
      final completer = Completer<int>();
      serverProcess!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        final m = portPattern.firstMatch(line);
        if (m != null && !completer.isCompleted) {
          completer.complete(int.parse(m.group(1)!));
        }
      });

      stubPort = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw StateError('Stub server did not start'),
      );
    });

    tearDown(() {
      serverProcess?.kill();
      serverProcess = null;
    });

    Future<UmasClient> createConnectedClient() async {
      final modbus = ModbusClientTcp(
        '127.0.0.1',
        serverPort: stubPort,
        connectionTimeout: const Duration(seconds: 3),
      );
      await modbus.connect();
      final client = UmasClient(
        sendFn: modbus.send,
        backoffDelay: (_) async {},
      );
      // Initialize session
      await client.readPlcId();
      await client.init();
      return client;
    }

    test('read 10 memory words from %MW0', () async {
      final client = await createConnectedClient();

      final address = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 0,
        quantity: 10,
      );

      final result = await client.readCoilsRegisters(address);
      // 10 words = 20 bytes
      expect(result.rawBytes.length, 20);
    });

    test('write 5 memory words to %MW100', () async {
      final client = await createConnectedClient();

      final address = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 100,
        quantity: 5,
      );
      final data = Uint8List(10);
      for (int i = 0; i < 10; i++) data[i] = i + 1;

      // Should not throw
      await client.writeCoilsRegisters(address, data);
    });

    test('read 16 coils from %M0', () async {
      final client = await createConnectedClient();

      final address = RegisterAddress(
        type: RegisterType.coil,
        startAddress: 0,
        quantity: 16,
      );

      final result = await client.readCoilsRegisters(address);
      // 16 coils = 2 bytes (bit-packed)
      expect(result.rawBytes.length, 2);
    });

    test('write-then-read round-trip for %MW registers', () async {
      final client = await createConnectedClient();

      final address = RegisterAddress(
        type: RegisterType.memoryWord,
        startAddress: 200,
        quantity: 3,
      );

      // Write 3 words: [0x1234, 0x5678, 0x9ABC]
      final writeData = Uint8List(6);
      final wbd = ByteData.sublistView(writeData);
      wbd.setUint16(0, 0x1234, Endian.little);
      wbd.setUint16(2, 0x5678, Endian.little);
      wbd.setUint16(4, 0x9ABC, Endian.little);

      await client.writeCoilsRegisters(address, writeData);

      // Read back
      final result = await client.readCoilsRegisters(address);
      expect(result.rawBytes.length, 6);
      final rbd = ByteData.sublistView(result.rawBytes);
      expect(rbd.getUint16(0, Endian.little), 0x1234);
      expect(rbd.getUint16(2, Endian.little), 0x5678);
      expect(rbd.getUint16(4, Endian.little), 0x9ABC);
    });

    test('readCoilsRegistersRaw works with manual payload', () async {
      final client = await createConnectedClient();

      // Manually construct the same payload as RegisterAddress(%MW, 0, 10)
      final payload = Uint8List(5);
      final bd = ByteData.sublistView(payload);
      payload[0] = 0x04; // memoryWord
      bd.setUint16(1, 0, Endian.little);
      bd.setUint16(3, 10, Endian.little);

      final result = await client.readCoilsRegistersRaw(payload);
      expect(result.rawBytes.length, 20); // 10 words = 20 bytes
    });

    test('writeCoilsRegistersRaw works with manual payload', () async {
      final client = await createConnectedClient();

      // Manually construct payload: address(5) + data(4)
      final payload = Uint8List(5 + 4);
      final bd = ByteData.sublistView(payload);
      payload[0] = 0x04; // memoryWord
      bd.setUint16(1, 300, Endian.little); // startAddress
      bd.setUint16(3, 2, Endian.little); // quantity = 2 words
      // data: 2 words
      bd.setUint16(5, 0xAAAA, Endian.little);
      bd.setUint16(7, 0xBBBB, Endian.little);

      // Should not throw
      await client.writeCoilsRegistersRaw(payload);
    });
  });
}
