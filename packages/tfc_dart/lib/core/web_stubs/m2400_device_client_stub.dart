/// Web stub for m2400_device_client.dart
///
/// On web, M2400 is not available. This stub provides the type for
/// conditional import resolution.
import '../dynamic_value.dart';
import '../state_man.dart' show DeviceClient, ConnectionStatus, M2400Config;

/// Stub for M2400ClientWrapper — provides the `.host` / `.port` fields
/// accessed by server_config.dart for display purposes.
class _StubM2400Wrapper {
  final String host;
  final int port;
  _StubM2400Wrapper(this.host, this.port);
}

class M2400DeviceClientAdapter implements DeviceClient {
  final String? serverAlias;
  final _StubM2400Wrapper wrapper;

  M2400DeviceClientAdapter(dynamic w, {this.serverAlias})
      : wrapper = _StubM2400Wrapper('', 0) {
    throw UnsupportedError('M2400 not available on web');
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

List<DeviceClient> createM2400DeviceClients(List<M2400Config> configs) => [];
