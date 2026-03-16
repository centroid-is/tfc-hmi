/// Debug test: diagnose %MD520-524 (incrementing REAL counters) on Schneider PLC.
/// Tests multiple address theories and function codes.
/// Run with: dart test test/md520_debug_test.dart --run-skipped
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';

const _host = '10.50.10.123';
const _port = 502;
const _unitId = 254;

/// Read a batch of uint16 holding registers (FC03).
Future<List<int>?> readHoldingRegisters(
    ModbusClientTcp client, int start, int count) async {
  final regs = [
    for (var i = 0; i < count; i++)
      ModbusUint16Register(
        name: 'HR${start + i}',
        address: start + i,
        type: ModbusElementType.holdingRegister,
      ),
  ];
  final group = ModbusElementsGroup(regs);
  final result = await client.send(group.getReadRequest());
  if (result != ModbusResponseCode.requestSucceed) {
    print('  FC03 HR$start-${start + count - 1}: FAILED ($result)');
    return null;
  }
  return regs.map((r) => (r.value as num).toInt()).toList();
}

/// Read a batch of uint16 input registers (FC04).
Future<List<int>?> readInputRegisters(
    ModbusClientTcp client, int start, int count) async {
  final regs = [
    for (var i = 0; i < count; i++)
      ModbusUint16Register(
        name: 'IR${start + i}',
        address: start + i,
        type: ModbusElementType.inputRegister,
      ),
  ];
  final group = ModbusElementsGroup(regs);
  final result = await client.send(group.getReadRequest());
  if (result != ModbusResponseCode.requestSucceed) {
    print('  FC04 IR$start-${start + count - 1}: FAILED ($result)');
    return null;
  }
  return regs.map((r) => (r.value as num).toInt()).toList();
}

double toFloat(int w0, int w1, String endian) {
  final bd = ByteData(4);
  switch (endian) {
    case 'ABCD':
      bd.setUint16(0, w0, Endian.big);
      bd.setUint16(2, w1, Endian.big);
    case 'CDAB':
      bd.setUint16(0, w1, Endian.big);
      bd.setUint16(2, w0, Endian.big);
    case 'BADC':
      bd.setUint16(0, w0, Endian.little);
      bd.setUint16(2, w1, Endian.little);
    case 'DCBA':
      bd.setUint16(0, w1, Endian.little);
      bd.setUint16(2, w0, Endian.little);
  }
  return bd.getFloat32(0, Endian.big);
}

void printAsFloats(String label, List<int> raw, int baseAddr) {
  print('  $label raw uint16: $raw');
  for (final endian in ['ABCD', 'CDAB', 'BADC', 'DCBA']) {
    final floats = <String>[];
    for (var i = 0; i < raw.length - 1; i += 2) {
      final f = toFloat(raw[i], raw[i + 1], endian);
      floats.add('${f.toStringAsFixed(4)}');
    }
    print('  $label $endian floats: $floats');
  }
}

void main() {
  late ModbusClientTcp client;

  setUp(() async {
    client = ModbusClientTcp(
      _host,
      serverPort: _port,
      unitId: _unitId,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 5),
    );
    final ok = await client.connect();
    expect(ok, isTrue, reason: 'TCP connect to $_host should succeed');
  });

  tearDown(() async {
    await client.disconnect();
  });

  test('diagnose MD520-524 — all address theories', () async {
    print('\n=== Diagnosing %MD520-524 on $_host (unit $_unitId) ===\n');

    // --- Sanity check: MW1000 counters should still be working ---
    print('--- Sanity: %MW1000-1005 (HR1000-1005) ---');
    final sanity = await readHoldingRegisters(client, 1000, 6);
    if (sanity != null) {
      print('  HR1000-1005 = $sanity');
    }

    // --- Theory 1: %MD520 = HR520+HR521 (direct word-based) ---
    // %MD520 occupies %MW520 and %MW521
    print('\n--- Theory 1: %MDn = HR(n) + HR(n+1) [direct] ---');
    print('  Reading HR520-529 (FC03)...');
    final t1 = await readHoldingRegisters(client, 520, 10);
    if (t1 != null) printAsFloats('HR520-529', t1, 520);

    // --- Theory 2: %MD520 = HR1040+HR1041 (double-word indexed) ---
    // %MDn = %MW(2n) + %MW(2n+1)
    print('\n--- Theory 2: %MDn = HR(2n) + HR(2n+1) [dword index] ---');
    print('  Reading HR1040-1049 (FC03)...');
    final t2 = await readHoldingRegisters(client, 1040, 10);
    if (t2 != null) printAsFloats('HR1040-1049', t2, 1040);

    // --- Theory 3: Input registers instead of holding (FC04) ---
    print('\n--- Theory 3: Input registers (FC04) ---');
    print('  Reading IR520-529...');
    final t3a = await readInputRegisters(client, 520, 10);
    if (t3a != null) printAsFloats('IR520-529', t3a, 520);

    print('  Reading IR1040-1049...');
    final t3b = await readInputRegisters(client, 1040, 10);
    if (t3b != null) printAsFloats('IR1040-1049', t3b, 1040);

    // --- Try different unit IDs ---
    print('\n--- Trying unit ID 1 (common default) ---');
    await client.disconnect();
    client = ModbusClientTcp(
      _host,
      serverPort: _port,
      unitId: 1,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 5),
    );
    await client.connect();
    final uid1 = await readHoldingRegisters(client, 520, 10);
    if (uid1 != null) {
      printAsFloats('HR520-529 (unitId=1)', uid1, 520);
    }
    final uid1b = await readHoldingRegisters(client, 1040, 10);
    if (uid1b != null) {
      printAsFloats('HR1040-1049 (unitId=1)', uid1b, 1040);
    }

    // --- Try unit ID 255 ---
    print('\n--- Trying unit ID 255 ---');
    await client.disconnect();
    client = ModbusClientTcp(
      _host,
      serverPort: _port,
      unitId: 255,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 5),
    );
    await client.connect();
    final uid255 = await readHoldingRegisters(client, 520, 10);
    if (uid255 != null) {
      printAsFloats('HR520-529 (unitId=255)', uid255, 520);
    }
    final uid255b = await readHoldingRegisters(client, 1040, 10);
    if (uid255b != null) {
      printAsFloats('HR1040-1049 (unitId=255)', uid255b, 1040);
    }

    // --- Read twice with delay to detect incrementing ---
    print('\n--- Increment detection (reading twice, 2s apart) ---');
    await client.disconnect();
    client = ModbusClientTcp(
      _host,
      serverPort: _port,
      unitId: _unitId,
      connectionMode: ModbusConnectionMode.doNotConnect,
      connectionTimeout: const Duration(seconds: 5),
    );
    await client.connect();

    print('  Read 1:');
    final r1_520 = await readHoldingRegisters(client, 520, 10);
    final r1_1040 = await readHoldingRegisters(client, 1040, 10);
    if (r1_520 != null) print('    HR520-529  = $r1_520');
    if (r1_1040 != null) print('    HR1040-1049 = $r1_1040');

    await Future.delayed(const Duration(seconds: 2));

    print('  Read 2 (after 2s):');
    final r2_520 = await readHoldingRegisters(client, 520, 10);
    final r2_1040 = await readHoldingRegisters(client, 1040, 10);
    if (r2_520 != null) print('    HR520-529  = $r2_520');
    if (r2_1040 != null) print('    HR1040-1049 = $r2_1040');

    // Show deltas
    if (r1_520 != null && r2_520 != null) {
      final deltas = List.generate(10, (i) => r2_520[i] - r1_520[i]);
      print('    Delta HR520-529: $deltas');
    }
    if (r1_1040 != null && r2_1040 != null) {
      final deltas = List.generate(10, (i) => r2_1040[i] - r1_1040[i]);
      print('    Delta HR1040-1049: $deltas');
    }

    // --- Also try reading as float32 directly using modbus_client ---
    print('\n--- Direct float32 read (CDAB endianness) at HR520 ---');
    final floatRegs = [
      for (var i = 0; i < 5; i++)
        ModbusFloatRegister(
          name: 'MD${520 + i}',
          address: 520 + (i * 2),
          type: ModbusElementType.holdingRegister,
          endianness: ModbusEndianness.CDAB,
        ),
    ];
    for (final reg in floatRegs) {
      final result = await client.send(reg.getReadRequest());
      print('  ${reg.name} @ HR${reg.address}: result=$result, value=${reg.value}');
    }

    print('\n--- Direct float32 read (CDAB endianness) at HR1040 ---');
    final floatRegs2 = [
      for (var i = 0; i < 5; i++)
        ModbusFloatRegister(
          name: 'MD${520 + i}_t2',
          address: 1040 + (i * 2),
          type: ModbusElementType.holdingRegister,
          endianness: ModbusEndianness.CDAB,
        ),
    ];
    for (final reg in floatRegs2) {
      final result = await client.send(reg.getReadRequest());
      print('  ${reg.name} @ HR${reg.address}: result=$result, value=${reg.value}');
    }

    print('\n=== Done ===');
  }, skip: 'Live test — run with --run-skipped',
     timeout: const Timeout(Duration(minutes: 2)));
}
