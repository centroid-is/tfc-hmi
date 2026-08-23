/// `_buildCoalescedGroups` splits batches on address SPAN, but
/// ModbusElementsGroup also rejects a batch on element COUNT (>125 for
/// registers). Those two limits are not the same number when several keys
/// share one register address — which is exactly what bit-masked status
/// words look like.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart' show ConnectionStatus;

class OkClient extends ModbusClientTcp {
  OkClient()
      : super('mock',
            serverPort: 0, connectionMode: ModbusConnectionMode.doNotConnect);

  bool _connected = false;
  int reads = 0;

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
    reads++;
    if (request is ModbusReadGroupRequest) {
      request.internalSetElementData(
          Uint8List(request.elementGroup.addressRange * 2));
    } else if (request is ModbusReadRequest) {
      request.element.setValueFromBytes(Uint8List(request.element.byteCount));
    }
    return ModbusResponseCode.requestSucceed;
  }
}

void main() {
  test(
      'a status word decoded into bits must not blow up the poll tick',
      () async {
      // Eight 16-bit status words at addresses 100..107, every bit bound to
      // its own key: 128 subscriptions across an address span of 8. The
      // coalescer keeps them in ONE batch because the SPAN is 8 (well under
      // 125), but the batch holds 128 ELEMENTS and ModbusElementsGroup
      // rejects anything over 125.
    final client = OkClient();
    late ModbusClientWrapper wrapper;
    final errors = <Object>[];

    // Everything inside the zone: the poll timers are created by the
    // connectionStream listener that subscribe() installs, so the wrapper has
    // to be built here for the zone to see what those timers throw.
    await runZonedGuarded(() async {
      wrapper = ModbusClientWrapper('h', 502, 1,
          clientFactory: (h, p, u) => client);
      wrapper.addPollGroup('status', const Duration(milliseconds: 50));

      for (var word = 0; word < 8; word++) {
        for (var bit = 0; bit < 16; bit++) {
          wrapper.subscribe(ModbusRegisterSpec(
            key: 'w$word.b$bit',
            registerType: ModbusElementType.holdingRegister,
            address: 100 + word,
            pollGroup: 'status',
            bitMask: 1 << bit,
            bitShift: bit,
          ));
        }
      }

      wrapper.connect();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }, (e, _) => errors.add(e));
    addTearDown(wrapper.dispose);

    expect(errors, isEmpty,
        reason: 'ModbusElementsGroup threw out of _buildCoalescedGroups. That '
            'call sits in _onPollTick\'s outer try, which has a `finally` but '
            'NO `catch`, and _onPollTick runs from an async Timer.periodic '
            'callback whose Future is discarded — so the throw becomes an '
            'uncaught async error. In the data-acquisition isolate '
            '(errorsAreFatal) that kills all acquisition for the server on '
            'the very first poll tick, forever, because the config that '
            'causes it is reloaded on every respawn. Errors: $errors');
    expect(client.reads, greaterThan(0),
        reason: 'The poll group never managed a single read.');
    expect(wrapper.connectionStatus, ConnectionStatus.connected);
  });
}
