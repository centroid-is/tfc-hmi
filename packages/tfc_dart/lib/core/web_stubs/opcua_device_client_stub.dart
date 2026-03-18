/// Web stub for opcua_device_client.dart
///
/// OPC UA is not available on web. This stub provides type definitions
/// so that conditional imports compile.

import 'dart:async';

import '../dynamic_value.dart';
import '../state_man.dart' show ConnectionStatus, DeviceClient, OpcUAConfig,
    KeyMappings, AutoDisposingStream;
import 'open62541_stub.dart' show ClientApi;

// ---------------------------------------------------------------------------
// ClientWrapper stub
// ---------------------------------------------------------------------------

class ClientWrapper {
  final ClientApi client;
  final OpcUAConfig config;
  int? subscriptionId;
  bool sessionLost = false;
  bool resendOnRecovery;
  final Set<AutoDisposingStream> streams = {};

  ClientWrapper(this.client, this.config, {this.resendOnRecovery = true}) {
    throw UnsupportedError('OPC UA ClientWrapper not available on web');
  }

  ConnectionStatus get connectionStatus => ConnectionStatus.disconnected;
  Stream<ConnectionStatus> get connectionStream => const Stream.empty();
}

// ---------------------------------------------------------------------------
// OpcUaDeviceClientAdapter stub
// ---------------------------------------------------------------------------

class OpcUaDeviceClientAdapter implements DeviceClient {
  final List<ClientWrapper> clients;
  final KeyMappings keyMappings;
  final String alias;

  OpcUaDeviceClientAdapter._({
    required this.clients,
    required this.keyMappings,
    required this.alias,
  });

  static Future<OpcUaDeviceClientAdapter> create({
    required List<OpcUAConfig> opcuaConfigs,
    required KeyMappings keyMappings,
    bool useIsolate = true,
    String alias = '',
    bool resendOnRecovery = true,
  }) async {
    throw UnsupportedError('OPC UA not available on web');
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
