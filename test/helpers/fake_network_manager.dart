/// Structural fakes for the `nm` package, for IP settings widget tests.
///
/// The nm classes are concrete with private constructors, but the page only
/// touches their public getters, so `implements` + a throwing [noSuchMethod]
/// gives an honest fake: anything the page starts using without a fake
/// implementation fails loudly in tests instead of silently returning null.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';
import 'package:nm/nm.dart';

class _Unstubbed {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not stubbed');
}

class FakeNetworkManagerClient extends _Unstubbed
    implements NetworkManagerClient {
  @override
  List<NetworkManagerDevice> devices;

  final FakeNetworkManagerSettings fakeSettings;

  /// `(interface, connection id)` per [activateConnection] call.
  final List<(String, String?)> activations = [];

  /// Active connections passed to [deactivateConnection].
  final List<NetworkManagerActiveConnection> deactivations = [];

  /// Settings maps passed to [addAndActivateConnection].
  final List<Map<String, Map<String, DBusValue>>> addAndActivated = [];

  FakeNetworkManagerClient({
    this.devices = const [],
    FakeNetworkManagerSettings? settings,
  }) : fakeSettings = settings ?? FakeNetworkManagerSettings();

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {}

  @override
  Stream<NetworkManagerDevice> get deviceAdded => const Stream.empty();

  @override
  Stream<NetworkManagerDevice> get deviceRemoved => const Stream.empty();

  @override
  Stream<List<String>> get propertiesChanged => const Stream.empty();

  @override
  NetworkManagerSettings get settings => fakeSettings;

  @override
  Future<NetworkManagerActiveConnection> activateConnection(
      {required NetworkManagerDevice device,
      NetworkManagerSettingsConnection? connection,
      NetworkManagerAccessPoint? accessPoint}) async {
    activations.add((
      device.interface,
      connection is FakeSettingsConnection ? connection.id : null,
    ));
    return FakeActiveConnection();
  }

  @override
  Future<void> deactivateConnection(
      NetworkManagerActiveConnection connection) async {
    deactivations.add(connection);
  }

  @override
  Future<NetworkManagerActiveConnection> addAndActivateConnection(
      {Map<String, Map<String, DBusValue>> connection = const {},
      required NetworkManagerDevice device,
      NetworkManagerAccessPoint? accessPoint}) async {
    addAndActivated.add(connection);
    return FakeActiveConnection();
  }
}

class FakeNetworkManagerSettings extends _Unstubbed
    implements NetworkManagerSettings {
  @override
  List<NetworkManagerSettingsConnection> connections;

  /// Settings maps passed to [addConnection], in call order.
  final List<Map<String, Map<String, DBusValue>>> addedConnections = [];

  FakeNetworkManagerSettings({this.connections = const []});

  @override
  Future<NetworkManagerSettingsConnection> addConnection(
      Map<String, Map<String, DBusValue>> connection) async {
    addedConnections.add(connection);
    return FakeSettingsConnection(
        id: connection['connection']?['id']?.asString() ?? '');
  }
}

class FakeSettingsConnection extends _Unstubbed
    implements NetworkManagerSettingsConnection {
  final String id;
  Map<String, Map<String, DBusValue>> settings;

  /// Settings maps passed to [update], in call order.
  final List<Map<String, Map<String, DBusValue>>> updates = [];
  bool deleted = false;

  FakeSettingsConnection({this.id = '', this.settings = const {}});

  @override
  Future<Map<String, Map<String, DBusValue>>> getSettings() async =>
      settings;

  @override
  Future<void> update(Map<String, Map<String, DBusValue>> properties) async {
    updates.add(properties);
    settings = properties;
  }

  @override
  Future<void> delete() async {
    deleted = true;
  }
}

class FakeActiveConnection extends _Unstubbed
    implements NetworkManagerActiveConnection {
  @override
  final String id;

  @override
  final NetworkManagerSettingsConnection? connection;

  @override
  final NetworkManagerIP4Config? ip4Config;

  @override
  final NetworkManagerDevice? master;

  FakeActiveConnection({
    this.id = '',
    this.connection,
    this.ip4Config,
    this.master,
  });
}

class FakeIp4Config extends _Unstubbed implements NetworkManagerIP4Config {
  @override
  final List<Map<String, dynamic>> addressData;

  @override
  final String gateway;

  @override
  final List<Map<String, dynamic>> nameserverData;

  FakeIp4Config({
    this.addressData = const [],
    this.gateway = '',
    this.nameserverData = const [],
  });
}

class FakeDhcp4Config extends _Unstubbed
    implements NetworkManagerDHCP4Config {}

class FakeDeviceStatistics extends _Unstubbed
    implements NetworkManagerDeviceStatistics {
  @override
  int rxBytes;

  @override
  int txBytes;

  /// Values passed to [setRefreshRateMs].
  final List<int> refreshRates = [];

  final _controller = StreamController<List<String>>.broadcast();

  FakeDeviceStatistics({this.rxBytes = 0, this.txBytes = 0});

  @override
  Stream<List<String>> get propertiesChanged => _controller.stream;

  @override
  Future<void> setRefreshRateMs(int value) async {
    refreshRates.add(value);
  }

  /// Announces new counter values, like NM does on a refresh tick.
  void emit() => _controller.add(['RxBytes', 'TxBytes']);
}

class FakeDeviceWired extends _Unstubbed implements NetworkManagerDeviceWired {
  @override
  final int speed;

  FakeDeviceWired({this.speed = 0});
}

class FakeAccessPoint extends _Unstubbed implements NetworkManagerAccessPoint {
  @override
  final List<int> ssid;

  @override
  final int strength;

  FakeAccessPoint({String ssidText = '', this.strength = 0})
      : ssid = utf8.encode(ssidText);
}

class FakeDeviceWireless extends _Unstubbed
    implements NetworkManagerDeviceWireless {
  @override
  final NetworkManagerAccessPoint? activeAccessPoint;

  FakeDeviceWireless({this.activeAccessPoint});
}

class FakeNetworkManagerDevice extends _Unstubbed
    implements NetworkManagerDevice {
  @override
  final NetworkManagerDeviceType deviceType;

  @override
  final String interface;

  @override
  final NetworkManagerDeviceState state;

  @override
  final NetworkManagerActiveConnection? activeConnection;

  @override
  final NetworkManagerIP4Config? ip4Config;

  @override
  final NetworkManagerDHCP4Config? dhcp4Config;

  @override
  final String hwAddress;

  @override
  final int mtu;

  @override
  final NetworkManagerDeviceWired? wired;

  @override
  final NetworkManagerDeviceWireless? wireless;

  @override
  final NetworkManagerDeviceStatistics? statistics;

  FakeNetworkManagerDevice({
    this.deviceType = NetworkManagerDeviceType.ethernet,
    this.interface = 'eth0',
    this.state = NetworkManagerDeviceState.activated,
    this.activeConnection,
    this.ip4Config,
    this.dhcp4Config,
    this.hwAddress = '',
    this.mtu = 0,
    this.wired,
    this.wireless,
    this.statistics,
  });

  @override
  Stream<List<String>> get propertiesChanged => const Stream.empty();
}
