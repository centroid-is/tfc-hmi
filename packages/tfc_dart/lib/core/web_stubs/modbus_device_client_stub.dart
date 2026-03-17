/// Web stub for modbus_device_client.dart
///
/// On native, the real modbus_device_client.dart is used instead (via
/// conditional import in state_man.dart). This stub is only resolved on web.

import 'package:open62541/open62541.dart'
    if (dart.library.js_interop) 'open62541_stub.dart' show DynamicValue;
import '../state_man.dart' show DeviceClient, ConnectionStatus;

class ModbusDeviceClientAdapter implements DeviceClient {
  final String? serverAlias;

  ModbusDeviceClientAdapter(dynamic wrapper,
      {required Map<String, dynamic> specs, this.serverAlias}) {
    throw UnsupportedError('Modbus not available on web');
  }

  @override
  Set<String> get subscribableKeys => {};
  @override
  bool canSubscribe(String key) => false;
  @override
  Stream<DynamicValue> subscribe(String key) => const Stream.empty();
  @override
  DynamicValue? read(String key) => null;
  @override
  ConnectionStatus get connectionStatus => ConnectionStatus.disconnected;
  @override
  Stream<ConnectionStatus> get connectionStream => const Stream.empty();
  @override
  void connect() {}
  @override
  Future<void> write(String key, DynamicValue value) async {}
  @override
  void dispose() {}
}
