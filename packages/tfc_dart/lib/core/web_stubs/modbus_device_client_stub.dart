/// Web stub for modbus_device_client.dart
///
/// On native, the real modbus_device_client.dart is used instead (via
/// conditional import in state_man.dart). This stub is only resolved on web.

import '../dynamic_value.dart' show DynamicValue;
import '../state_man.dart' show DeviceClient, ConnectionStatus, KeyMappings, ModbusConfig;
import 'modbus_client_wrapper_stub.dart' show ModbusClientWrapper;

class ModbusDeviceClientAdapter implements DeviceClient {
  final String? serverAlias;
  final ModbusClientWrapper wrapper;

  ModbusDeviceClientAdapter(ModbusClientWrapper w,
      {required Map<String, dynamic> specs, this.serverAlias})
      : wrapper = w {
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

List<DeviceClient> buildModbusDeviceClients(
  List<ModbusConfig> modbusConfigs,
  KeyMappings keyMappings,
) => [];
