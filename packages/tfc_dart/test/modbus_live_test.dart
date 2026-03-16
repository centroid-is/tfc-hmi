/// Quick manual test to verify Modbus TCP connectivity.
/// Run with: dart test test/modbus_live_test.dart --run-skipped
///
/// Tests basic TCP connection, register read, and connection stability.
import 'dart:async';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart' show ConnectionStatus;
import 'package:test/test.dart';

const _host = '10.50.10.152';
const _port = 502;
const _unitId = 1;

void main() {
  group('Live Modbus TCP @ $_host:$_port', () {
    test('raw TCP connect + read holding register 0', () async {
      final client = ModbusClientTcp(
        _host,
        serverPort: _port,
        unitId: _unitId,
        connectionMode: ModbusConnectionMode.doNotConnect,
        connectionTimeout: const Duration(seconds: 5),
      );

      final ok = await client.connect();
      expect(ok, isTrue, reason: 'TCP connect should succeed');
      expect(client.isConnected, isTrue);

      // Try reading holding register 0
      final element = ModbusUint16Register(
        name: 'test',
        address: 0,
        type: ModbusElementType.holdingRegister,
      );
      final request = element.getReadRequest();
      final result = await client.send(request);
      print('Read HR0: result=$result, value=${element.value}');

      await client.disconnect();
    }, skip: 'Manual test — run with --run-skipped');

    test('wrapper connects and stays connected for 30s', () async {
      final wrapper = ModbusClientWrapper(_host, _port, _unitId);
      final statuses = <ConnectionStatus>[];
      final sub = wrapper.connectionStream.listen(statuses.add);

      wrapper.connect();

      // Wait for connection
      await Future.delayed(const Duration(seconds: 5));
      print('Status after 5s: ${wrapper.connectionStatus}');
      print('Status history: $statuses');
      expect(wrapper.connectionStatus, ConnectionStatus.connected);

      // Hold for 30s to see if it stays connected (heartbeat should keep it alive)
      for (var i = 0; i < 6; i++) {
        await Future.delayed(const Duration(seconds: 5));
        print('  ${(i + 2) * 5}s: ${wrapper.connectionStatus}');
      }

      expect(wrapper.connectionStatus, ConnectionStatus.connected,
          reason: 'Should stay connected for 30s with heartbeat');
      print('Final status history: $statuses');

      await sub.cancel();
      wrapper.dispose();
    }, skip: 'Manual test — run with --run-skipped', timeout: Timeout(Duration(seconds: 60)));
  });
}
