import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:rxdart/rxdart.dart';
import 'state_man.dart' show ConnectionStatus;

/// Stub implementation -- connection lifecycle not yet implemented.
/// Tests should compile but fail on behavioral assertions.
class ModbusClientWrapper {
  ModbusClientWrapper(
    String host,
    int port,
    int unitId, {
    ModbusClientTcp Function(String, int, int)? clientFactory,
  });

  ConnectionStatus get connectionStatus => ConnectionStatus.disconnected;
  Stream<ConnectionStatus> get connectionStream => const Stream.empty();

  void connect() {}
  void disconnect() {}
  void dispose() {}
}
