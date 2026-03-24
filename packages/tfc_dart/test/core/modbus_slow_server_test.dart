/// Tests for ModbusClientWrapper behavior with a real TCP Modbus server
/// that introduces configurable response delays.
///
/// Validates:
/// - Poll guard prevents overlapping transactions when PLC is slow
/// - Data integrity under slow responses (correct values, no corruption)
/// - Multiple poll groups operate independently under load
/// - Write during slow poll read doesn't deadlock or corrupt
/// - Transaction ID correlation remains correct (library handles MBAP)
///
/// Run: dart test test/core/modbus_slow_server_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart' show ConnectionStatus;
import 'package:test/test.dart';

// =============================================================================
// Minimal Modbus TCP server (MBAP + PDU) with configurable response delay
// =============================================================================

/// A simple Modbus TCP server that holds register/coil state and responds
/// to FC01-04 reads and FC05/FC06/FC15/FC16 writes.
///
/// [responseDelay] is injected before each response to simulate a slow PLC.
class SlowModbusTcpServer {
  final int port;
  final Duration responseDelay;
  ServerSocket? _server;
  final List<Socket> _clients = [];

  /// Holding registers: 0-999, initialized to address value.
  final Uint16List holdingRegisters = Uint16List(1000);

  /// Coils: 0-999, packed into bytes.
  final List<bool> coils = List.filled(1000, false);

  /// Number of requests handled (for assertions).
  int requestCount = 0;

  /// Per-request delay override. If set, called with the request function code
  /// to allow variable delays (e.g. slow only for reads).
  Duration Function(int functionCode)? delayOverride;

  SlowModbusTcpServer({
    this.port = 0, // 0 = ephemeral port
    this.responseDelay = Duration.zero,
  }) {
    // Initialize holding registers to their address index
    for (var i = 0; i < holdingRegisters.length; i++) {
      holdingRegisters[i] = i;
    }
  }

  int get actualPort => _server?.port ?? port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleConnection);
  }

  Future<void> stop() async {
    final clients = List<Socket>.from(_clients);
    _clients.clear();
    for (final c in clients) {
      c.destroy();
    }
    await _server?.close();
    _server = null;
  }

  void _handleConnection(Socket socket) {
    _clients.add(socket);
    final buffer = BytesBuilder();

    socket.listen(
      (data) {
        buffer.add(data);
        _processBuffer(buffer, socket);
      },
      onDone: () {
        _clients.remove(socket);
      },
      onError: (_) {
        _clients.remove(socket);
      },
    );
  }

  void _processBuffer(BytesBuilder buffer, Socket socket) {
    // Process all complete MBAP frames in the buffer
    while (true) {
      final bytes = buffer.toBytes();
      if (bytes.length < 7) return; // Need at least MBAP header (7 bytes)

      // MBAP header: [transId(2), protocolId(2), length(2), unitId(1)]
      final length = (bytes[4] << 8) | bytes[5]; // bytes remaining after length
      final totalFrame = 6 + length; // 6 = transId + protocolId + length fields

      if (bytes.length < totalFrame) return; // Incomplete frame

      final frame = Uint8List.fromList(bytes.sublist(0, totalFrame));
      // Remove processed frame from buffer
      buffer.clear();
      if (bytes.length > totalFrame) {
        buffer.add(bytes.sublist(totalFrame));
      }

      // Handle asynchronously (with delay)
      _handleFrame(frame, socket);
    }
  }

  Future<void> _handleFrame(Uint8List frame, Socket socket) async {
    requestCount++;

    final transIdHi = frame[0];
    final transIdLo = frame[1];
    final unitId = frame[6];
    final fc = frame[7];

    // Determine delay
    final delay = delayOverride?.call(fc) ?? responseDelay;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }

    Uint8List? response;
    try {
      switch (fc) {
        case 0x01: // Read Coils
          response = _handleReadCoils(frame);
        case 0x02: // Read Discrete Inputs (treat same as coils)
          response = _handleReadCoils(frame);
        case 0x03: // Read Holding Registers
          response = _handleReadHoldingRegisters(frame);
        case 0x04: // Read Input Registers (treat same as holding)
          response = _handleReadHoldingRegisters(frame);
        case 0x05: // Write Single Coil
          response = _handleWriteSingleCoil(frame);
        case 0x06: // Write Single Register
          response = _handleWriteSingleRegister(frame);
        case 0x0F: // Write Multiple Coils (FC15)
          response = _handleWriteMultipleCoils(frame);
        case 0x10: // Write Multiple Registers (FC16)
          response = _handleWriteMultipleRegisters(frame);
        default:
          // Unsupported function code -> exception response
          response = _buildExceptionResponse(transIdHi, transIdLo, unitId, fc, 0x01);
      }
    } catch (e) {
      response = _buildExceptionResponse(transIdHi, transIdLo, unitId, fc, 0x04);
    }

    try {
      socket.add(response);
    } catch (_) {
      // Client disconnected
    }
  }

  Uint8List _handleReadCoils(Uint8List frame) {
    final startAddr = (frame[8] << 8) | frame[9];
    final quantity = (frame[10] << 8) | frame[11];
    final byteCount = (quantity + 7) ~/ 8;

    final data = Uint8List(byteCount);
    for (var i = 0; i < quantity; i++) {
      if (coils[startAddr + i]) {
        data[i ~/ 8] |= (1 << (i % 8));
      }
    }

    return _buildResponse(frame, [byteCount, ...data]);
  }

  Uint8List _handleReadHoldingRegisters(Uint8List frame) {
    final startAddr = (frame[8] << 8) | frame[9];
    final quantity = (frame[10] << 8) | frame[11];
    final byteCount = quantity * 2;

    final data = <int>[byteCount];
    for (var i = 0; i < quantity; i++) {
      final val = holdingRegisters[startAddr + i];
      data.add((val >> 8) & 0xFF);
      data.add(val & 0xFF);
    }

    return _buildResponse(frame, data);
  }

  Uint8List _handleWriteSingleCoil(Uint8List frame) {
    final addr = (frame[8] << 8) | frame[9];
    final value = (frame[10] << 8) | frame[11];
    coils[addr] = value == 0xFF00;
    // Echo request back
    return _buildResponse(frame, [frame[8], frame[9], frame[10], frame[11]]);
  }

  Uint8List _handleWriteSingleRegister(Uint8List frame) {
    final addr = (frame[8] << 8) | frame[9];
    final value = (frame[10] << 8) | frame[11];
    holdingRegisters[addr] = value;
    // Echo request back
    return _buildResponse(frame, [frame[8], frame[9], frame[10], frame[11]]);
  }

  Uint8List _handleWriteMultipleCoils(Uint8List frame) {
    final startAddr = (frame[8] << 8) | frame[9];
    final quantity = (frame[10] << 8) | frame[11];
    // byte count at frame[12], data starts at frame[13]
    for (var i = 0; i < quantity; i++) {
      final byteIdx = 13 + (i ~/ 8);
      coils[startAddr + i] = (frame[byteIdx] & (1 << (i % 8))) != 0;
    }
    return _buildResponse(frame, [frame[8], frame[9], frame[10], frame[11]]);
  }

  Uint8List _handleWriteMultipleRegisters(Uint8List frame) {
    final startAddr = (frame[8] << 8) | frame[9];
    final quantity = (frame[10] << 8) | frame[11];
    // byte count at frame[12], data starts at frame[13]
    for (var i = 0; i < quantity; i++) {
      final hi = frame[13 + i * 2];
      final lo = frame[14 + i * 2];
      holdingRegisters[startAddr + i] = (hi << 8) | lo;
    }
    return _buildResponse(frame, [frame[8], frame[9], frame[10], frame[11]]);
  }

  /// Builds MBAP response: echoes transId/protocolId/unitId, sets FC, appends data.
  Uint8List _buildResponse(Uint8List request, List<int> pduData) {
    final fc = request[7];
    final pduLen = 1 + pduData.length; // FC byte + data
    final totalLen = pduLen + 1; // + unitId
    return Uint8List.fromList([
      request[0], request[1], // Transaction ID
      0x00, 0x00, // Protocol ID
      (totalLen >> 8) & 0xFF, totalLen & 0xFF, // Length
      request[6], // Unit ID
      fc, // Function code
      ...pduData,
    ]);
  }

  Uint8List _buildExceptionResponse(
      int transIdHi, int transIdLo, int unitId, int fc, int exceptionCode) {
    return Uint8List.fromList([
      transIdHi, transIdLo,
      0x00, 0x00, // Protocol ID
      0x00, 0x03, // Length
      unitId,
      fc | 0x80, // Exception FC
      exceptionCode,
    ]);
  }
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  late SlowModbusTcpServer server;
  late ModbusClientWrapper wrapper;

  tearDown(() async {
    wrapper.dispose();
    await server.stop();
  });

  group('slow server - poll guard', () {
    test('poll guard skips ticks when server response exceeds poll interval',
        () async {
      // Server takes 300ms per response, poll interval is 100ms.
      // Without the guard, requests would pile up. With it, overlapping
      // ticks are skipped.
      server = SlowModbusTcpServer(responseDelay: const Duration(milliseconds: 300));
      await server.start();

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('default', const Duration(milliseconds: 100));

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Let it run for 2 seconds
      await Future.delayed(const Duration(seconds: 2));

      // With 300ms response and 100ms interval, we expect ~6 requests in 2s
      // (each takes 300ms, so ceil(2000/300) ≈ 6-7).
      // Without guard, it would be 20 (2000/100).
      expect(server.requestCount, greaterThan(3));
      expect(server.requestCount, lessThan(12),
          reason: 'Guard should prevent more than ~7 requests in 2s '
              'when each takes 300ms');
    });

    test('no data corruption when poll ticks are skipped', () async {
      // Server responds with distinct values per register.
      // Verify the wrapper delivers correct values even under slow responses.
      server = SlowModbusTcpServer(responseDelay: const Duration(milliseconds: 200));
      await server.start();

      // Set known values
      server.holdingRegisters[10] = 1234;
      server.holdingRegisters[11] = 5678;

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('default', const Duration(milliseconds: 100));

      final stream10 = wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr10',
        registerType: ModbusElementType.holdingRegister,
        address: 10,
      ));
      final stream11 = wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr11',
        registerType: ModbusElementType.holdingRegister,
        address: 11,
      ));

      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Wait for at least one successful poll
      final val10 = await stream10
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));
      final val11 = await stream11
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));

      expect(val10, equals(1234));
      expect(val11, equals(5678));
    });
  });

  group('slow server - multiple poll groups', () {
    test('fast and slow poll groups operate independently', () async {
      server = SlowModbusTcpServer(responseDelay: const Duration(milliseconds: 50));
      await server.start();

      server.holdingRegisters[0] = 100;
      server.holdingRegisters[50] = 200;

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('fast', const Duration(milliseconds: 100));
      wrapper.addPollGroup('slow', const Duration(milliseconds: 500));

      final fastStream = wrapper.subscribe(ModbusRegisterSpec(
        key: 'fast_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
        pollGroup: 'fast',
      ));
      final slowStream = wrapper.subscribe(ModbusRegisterSpec(
        key: 'slow_reg',
        registerType: ModbusElementType.holdingRegister,
        address: 50,
        pollGroup: 'slow',
      ));

      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Both should deliver correct values
      final fastVal = await fastStream
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));
      final slowVal = await slowStream
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));

      expect(fastVal, equals(100));
      expect(slowVal, equals(200));

      // After 1.5s, fast should have many more updates than slow
      await Future.delayed(const Duration(milliseconds: 1500));

      // Total requests: fast fires ~15x, slow fires ~3x, total ~18+
      expect(server.requestCount, greaterThan(10));
    });
  });

  group('slow server - write during slow read', () {
    test('write completes while poll reads are slow', () async {
      // Reads take 500ms, but writes should still go through
      server = SlowModbusTcpServer();
      server.delayOverride = (fc) {
        if (fc == 0x03 || fc == 0x04) {
          return const Duration(milliseconds: 500); // Slow reads
        }
        return Duration.zero; // Fast writes
      };
      await server.start();

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('default', const Duration(milliseconds: 200));

      wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
      ));
      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Wait for polling to start
      await Future.delayed(const Duration(milliseconds: 100));

      // Write while a slow read may be in progress
      // Note: since sends are serialized by the library, the write will
      // queue behind the current read. We verify it eventually completes.
      final writeSpec = ModbusRegisterSpec(
        key: 'hr_write',
        registerType: ModbusElementType.holdingRegister,
        address: 99,
      );

      await wrapper.write(writeSpec, 42).timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('Write timed out while reads were slow'),
          );

      expect(server.holdingRegisters[99], equals(42));
    });
  });

  group('slow server - data integrity under load', () {
    test('10 registers all deliver correct values with 100ms server delay',
        () async {
      server = SlowModbusTcpServer(responseDelay: const Duration(milliseconds: 100));
      await server.start();

      // Set distinct values for each register
      for (var i = 0; i < 10; i++) {
        server.holdingRegisters[i] = 1000 + i;
      }

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('default', const Duration(milliseconds: 200));

      // Subscribe to 10 contiguous registers (should coalesce into 1 batch)
      final streams = <Stream<Object?>>[];
      for (var i = 0; i < 10; i++) {
        streams.add(wrapper.subscribe(ModbusRegisterSpec(
          key: 'hr$i',
          registerType: ModbusElementType.holdingRegister,
          address: i,
        )));
      }

      wrapper.connect();

      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Wait for values to arrive
      for (var i = 0; i < 10; i++) {
        final value = await streams[i]
            .where((v) => v != null)
            .first
            .timeout(const Duration(seconds: 10));
        expect(value, equals(1000 + i),
            reason: 'Register $i should read ${1000 + i}');
      }
    });

    test('server value changes are picked up on subsequent polls', () async {
      server = SlowModbusTcpServer(responseDelay: const Duration(milliseconds: 50));
      await server.start();

      server.holdingRegisters[0] = 111;

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('default', const Duration(milliseconds: 100));

      final stream = wrapper.subscribe(ModbusRegisterSpec(
        key: 'hr0',
        registerType: ModbusElementType.holdingRegister,
        address: 0,
      ));

      wrapper.connect();
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      // Get initial value
      final val1 = await stream
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));
      expect(val1, equals(111));

      // Change server value
      server.holdingRegisters[0] = 222;

      // Wait for the updated value to arrive
      final val2 = await stream
          .where((v) => v == 222)
          .first
          .timeout(const Duration(seconds: 5));
      expect(val2, equals(222));
    });

    test('coil reads are correct under slow responses', () async {
      server = SlowModbusTcpServer(responseDelay: const Duration(milliseconds: 150));
      await server.start();

      server.coils[0] = true;
      server.coils[1] = false;
      server.coils[2] = true;

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('default', const Duration(milliseconds: 100));

      final s0 = wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil0',
        registerType: ModbusElementType.coil,
        address: 0,
        dataType: ModbusDataType.bit,
      ));
      final s1 = wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil1',
        registerType: ModbusElementType.coil,
        address: 1,
        dataType: ModbusDataType.bit,
      ));
      final s2 = wrapper.subscribe(ModbusRegisterSpec(
        key: 'coil2',
        registerType: ModbusElementType.coil,
        address: 2,
        dataType: ModbusDataType.bit,
      ));

      wrapper.connect();
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      final v0 = await s0
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));
      final v1 = await s1
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));
      final v2 = await s2
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));

      expect(v0, isTrue);
      expect(v1, isFalse);
      expect(v2, isTrue);
    });
  });

  group('slow server - subscribe dedup with spec change', () {
    test('resubscribe with different spec tears down old and creates new',
        () async {
      server = SlowModbusTcpServer(responseDelay: const Duration(milliseconds: 50));
      await server.start();

      server.holdingRegisters[10] = 999;

      wrapper = ModbusClientWrapper(
        '127.0.0.1',
        server.actualPort,
        1,
      );
      wrapper.addPollGroup('default', const Duration(milliseconds: 100));

      // Subscribe to address 10 as uint16
      final stream1 = wrapper.subscribe(ModbusRegisterSpec(
        key: 'mykey',
        registerType: ModbusElementType.holdingRegister,
        address: 10,
      ));

      wrapper.connect();
      await wrapper.connectionStream
          .firstWhere((s) => s == ConnectionStatus.connected)
          .timeout(const Duration(seconds: 3));

      final val1 = await stream1
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));
      expect(val1, equals(999));

      // Now resubscribe same key with different address
      server.holdingRegisters[20] = 777;
      final stream2 = wrapper.subscribe(ModbusRegisterSpec(
        key: 'mykey',
        registerType: ModbusElementType.holdingRegister,
        address: 20,
      ));

      // Should get value from address 20, not 10
      final val2 = await stream2
          .where((v) => v != null)
          .first
          .timeout(const Duration(seconds: 5));
      expect(val2, equals(777));
    });
  });
}
