/// Debug test: brute-force scan Schneider PLC for known float values.
/// Run with: dart test test/schneider_debug_test.dart --run-skipped
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';

const _host = '10.50.10.123';
const _port = 502;
const _unitId = 254;

/// Read a batch of uint16 holding registers. Returns list of int values.
Future<List<int>> readBatch(ModbusClientTcp client, int start, int count) async {
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
  if (result != ModbusResponseCode.requestSucceed) return [];
  return regs.map((r) => (r.value as num).toInt()).toList();
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
    expect(ok, isTrue, reason: 'TCP connect should succeed');
  });

  tearDown(() async {
    await client.disconnect();
  });

  test('scan HR0-6000 for floats matching rReal values', () async {
    // rReal1~25.3, rReal2~886.6, rReal3~567.6, rReal4~1328.8, rReal5~550
    // Values may have changed, so just look for "plausible" floats in 10-2000 range
    final found = <String>[];

    for (var start = 0; start < 6000; start += 100) {
      final vals = await readBatch(client, start, 100);
      if (vals.isEmpty) {
        // Try smaller batch if 100 fails
        continue;
      }

      for (var i = 0; i < 99; i++) {
        if (vals[i] == 0 && vals[i + 1] == 0) continue;
        for (final endian in ['ABCD', 'CDAB']) {
          final f = _toFloat(vals[i], vals[i + 1], endian);
          if (f.isFinite && f > 10 && f < 2000) {
            final addr = start + i;
            final msg = 'HR$addr-${addr + 1}: 0x${vals[i].toRadixString(16).padLeft(4, '0')} '
                '0x${vals[i + 1].toRadixString(16).padLeft(4, '0')} -> $endian = ${f.toStringAsFixed(4)}';
            found.add(msg);
          }
        }
      }
    }

    print('=== Found ${found.length} plausible floats (10-2000 range) ===');
    for (final f in found) {
      print('  $f');
    }
  }, skip: 'Live test — run with --run-skipped',
     timeout: const Timeout(Duration(minutes: 5)));
}

double _toFloat(int w0, int w1, String endian) {
  final bd = ByteData(4);
  switch (endian) {
    case 'ABCD':
      bd.setUint16(0, w0, Endian.big);
      bd.setUint16(2, w1, Endian.big);
    case 'CDAB':
      bd.setUint16(0, w1, Endian.big);
      bd.setUint16(2, w0, Endian.big);
  }
  return bd.getFloat32(0, Endian.big);
}
