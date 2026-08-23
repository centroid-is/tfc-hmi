import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:test/test.dart';

class MockModbusClient extends ModbusClientTcp {
  bool _connected = false;
  ModbusResponseCode Function(ModbusRequest request)? onSend;

  MockModbusClient()
      : super('mock',
            serverPort: 0,
            connectionMode: ModbusConnectionMode.doNotConnect);

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<ModbusResponseCode> send(ModbusRequest request) async {
    if (!_connected) return ModbusResponseCode.connectionFailed;
    if (onSend != null) return onSend!(request);
    return ModbusResponseCode.requestSucceed;
  }
}

/// Fills a group read with [word] in every register.
ModbusResponseCode succeedWith(ModbusRequest request, int word) {
  if (request is ModbusReadGroupRequest) {
    final n = request.elementGroup.addressRange * 2;
    final bytes = Uint8List(n);
    for (var i = 0; i + 1 < n; i += 2) {
      bytes[i] = (word >> 8) & 0xFF;
      bytes[i + 1] = word & 0xFF;
    }
    request.internalSetElementData(bytes);
  }
  return ModbusResponseCode.requestSucceed;
}

void main() {
  const spec = ModbusRegisterSpec(
    key: 'temp',
    registerType: ModbusElementType.holdingRegister,
    address: 10,
    pollGroup: 'fast',
  );

  test('a failed poll must not publish a value', () async {
    final mock = MockModbusClient();
    final wrapper = ModbusClientWrapper('h', 502, 1,
        clientFactory: (_, __, ___) => mock,
        heartbeatInterval: const Duration(hours: 1));
    wrapper.addPollGroup('fast', const Duration(milliseconds: 50));

    // The device is reachable but every read times out.
    mock.onSend = (_) => ModbusResponseCode.requestTimeout;

    final seen = <Object?>[];
    wrapper.subscribe(spec).listen(seen.add);
    wrapper.connect();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(seen, isEmpty,
        reason: 'a poll that failed published something to subscribers: $seen');

    wrapper.dispose();
  });

  test('after polls start failing the stream must stop republishing the '
      'last good value', () async {
    final mock = MockModbusClient();
    final wrapper = ModbusClientWrapper('h', 502, 1,
        clientFactory: (_, __, ___) => mock,
        heartbeatInterval: const Duration(hours: 1));
    wrapper.addPollGroup('fast', const Duration(milliseconds: 50));

    mock.onSend = (r) => succeedWith(r, 42);

    final seen = <Object?>[];
    wrapper.subscribe(spec).listen(seen.add);
    wrapper.connect();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(seen, isNotEmpty, reason: 'sanity: good polls publish');
    expect(seen.last, 42);

    // Device stops answering.
    mock.onSend = (_) => ModbusResponseCode.requestTimeout;
    final countAtFailure = seen.length;
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(seen.length, countAtFailure,
        reason: 'stale value republished ${seen.length - countAtFailure} '
            'times after the device stopped answering');

    wrapper.dispose();
  });
}
