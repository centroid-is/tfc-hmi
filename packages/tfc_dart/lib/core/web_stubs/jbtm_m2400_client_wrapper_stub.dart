/// Web stub for package:jbtm/src/m2400_client_wrapper.dart

import 'open62541_stub.dart' show DynamicValue;
import 'jbtm_msocket_stub.dart' show ConnectionStatus;

class M2400ClientWrapper {
  static const String batchKey = 'batch';
  static const String statKey = 'stat';
  static const String introKey = 'intro';
  static const String luaKey = 'lua';

  M2400ClientWrapper(String host, int port) {
    throw UnsupportedError('M2400 not available on web');
  }

  void connect() => throw UnsupportedError('M2400 not available on web');
  void disconnect() {}
  void dispose() {}

  Stream<DynamicValue> subscribe(String key) => const Stream.empty();
  DynamicValue? lastValue(String key) => null;

  Stream<ConnectionStatus> get statusStream => const Stream.empty();
  ConnectionStatus get status => ConnectionStatus.disconnected;
}
