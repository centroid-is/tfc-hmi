/// M2400 DeviceClient adapter — native-only.
///
/// Wraps jbtm's [M2400ClientWrapper] and presents the protocol-agnostic
/// [DeviceClient] interface used by [StateMan].
///
/// This file is NEVER imported on web.
import 'package:jbtm/src/m2400_client_wrapper.dart' show M2400ClientWrapper;
import 'package:jbtm/src/msocket.dart' as jbtm show ConnectionStatus;
import 'dynamic_value.dart' as tfc;
import 'opcua_device_client.dart' show fromOpcUaDynamicValue;
import 'state_man.dart' show ConnectionStatus, DeviceClient, M2400Config;

/// Adapter that wraps [M2400ClientWrapper] from the jbtm package as a
/// [DeviceClient] for use in [StateMan].
///
/// Maps jbtm's [jbtm.ConnectionStatus] to state_man's [ConnectionStatus] and
/// delegates subscribe/connect/dispose to the underlying wrapper.
/// Converts between open62541's DynamicValue and tfc_dart's DynamicValue.
class M2400DeviceClientAdapter implements DeviceClient {
  /// The underlying M2400ClientWrapper from jbtm.
  final M2400ClientWrapper wrapper;

  /// The server alias for this device (from M2400Config).
  final String? serverAlias;

  static const _validKeys = {'BATCH', 'STAT', 'INTRO', 'LUA'};

  M2400DeviceClientAdapter(this.wrapper, {this.serverAlias});

  @override
  Set<String> get subscribableKeys => _validKeys;

  @override
  bool canSubscribe(String key) => _validKeys.contains(key.split('.').first);

  @override
  Stream<tfc.DynamicValue> subscribe(String key) =>
      wrapper.subscribe(key).map((v) => fromOpcUaDynamicValue(v));

  @override
  tfc.DynamicValue? read(String key) {
    final v = wrapper.lastValue(key);
    if (v == null) return null;
    return fromOpcUaDynamicValue(v);
  }

  @override
  ConnectionStatus get connectionStatus => _mapStatus(wrapper.status);

  @override
  Stream<ConnectionStatus> get connectionStream =>
      wrapper.statusStream.map(_mapStatus);

  @override
  Future<void> write(String key, tfc.DynamicValue value) {
    throw UnsupportedError('M2400 does not support writes');
  }

  @override
  void connect() => wrapper.connect();

  @override
  void dispose() => wrapper.dispose();

  /// Map jbtm's ConnectionStatus to state_man's ConnectionStatus.
  static ConnectionStatus _mapStatus(jbtm.ConnectionStatus s) {
    switch (s) {
      case jbtm.ConnectionStatus.connected:
        return ConnectionStatus.connected;
      case jbtm.ConnectionStatus.connecting:
        return ConnectionStatus.connecting;
      case jbtm.ConnectionStatus.disconnected:
        return ConnectionStatus.disconnected;
    }
  }
}

/// Create [DeviceClient] instances for each [M2400Config] in the list.
///
/// Each M2400Config produces one [M2400DeviceClientAdapter] wrapping an
/// [M2400ClientWrapper]. The caller is responsible for calling [connect()]
/// and [dispose()] on the returned clients.
List<DeviceClient> createM2400DeviceClients(List<M2400Config> configs) {
  return configs.map((config) {
    final wrapper = M2400ClientWrapper(config.host, config.port);
    return M2400DeviceClientAdapter(wrapper, serverAlias: config.serverAlias);
  }).toList();
}
