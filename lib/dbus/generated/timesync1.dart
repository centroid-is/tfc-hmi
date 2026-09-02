// This file was generated using the following command and may be overwritten.
// dart-dbus generate-remote-object /private/tmp/claude-501/-Users-jonb-Projects-tfc-hmi-svn/bd2a89cd-85f8-4102-94be-ec851490f4cd/scratchpad/dbusxml/timesync1.xml

import 'dart:io';
import 'package:dbus/dbus.dart';

/// Signal data for org.freedesktop.DBus.Properties.PropertiesChanged.
class OrgFreedesktopDBusPeerPropertiesChanged extends DBusSignal {
  String get interface_name => values[0].asString();
  Map<String, DBusValue> get changed_properties => values[1].asStringVariantDict();
  List<String> get invalidated_properties => values[2].asStringArray().toList();

  OrgFreedesktopDBusPeerPropertiesChanged(DBusSignal signal) : super(sender: signal.sender, path: signal.path, interface: signal.interface, name: signal.name, values: signal.values);
}

class OrgFreedesktopDBusPeer extends DBusRemoteObject {
  /// Stream of org.freedesktop.DBus.Properties.PropertiesChanged signals.
  late final Stream<OrgFreedesktopDBusPeerPropertiesChanged> customPropertiesChanged;

  OrgFreedesktopDBusPeer(DBusClient client, String destination, DBusObjectPath path) : super(client, name: destination, path: path) {
    customPropertiesChanged = DBusRemoteObjectSignalStream(object: this, interface: 'org.freedesktop.DBus.Properties', name: 'PropertiesChanged', signature: DBusSignature('sa{sv}as')).asBroadcastStream().map((signal) => OrgFreedesktopDBusPeerPropertiesChanged(signal));
  }

  /// Invokes org.freedesktop.DBus.Peer.Ping()
  Future<void> callPing({bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.DBus.Peer', 'Ping', [], replySignature: DBusSignature(''), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.DBus.Peer.GetMachineId()
  Future<String> callGetMachineId({bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.DBus.Peer', 'GetMachineId', [], replySignature: DBusSignature('s'), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asString();
  }

  /// Invokes org.freedesktop.DBus.Introspectable.Introspect()
  Future<String> callIntrospect({bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.DBus.Introspectable', 'Introspect', [], replySignature: DBusSignature('s'), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asString();
  }

  /// Invokes org.freedesktop.DBus.Properties.Get()
  Future<DBusValue> callGet(String interface_name, String property_name, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.DBus.Properties', 'Get', [DBusString(interface_name), DBusString(property_name)], replySignature: DBusSignature('v'), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asVariant();
  }

  /// Invokes org.freedesktop.DBus.Properties.GetAll()
  Future<Map<String, DBusValue>> callGetAll(String interface_name, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.DBus.Properties', 'GetAll', [DBusString(interface_name)], replySignature: DBusSignature('a{sv}'), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asStringVariantDict();
  }

  /// Invokes org.freedesktop.DBus.Properties.Set()
  Future<void> callSet(String interface_name, String property_name, DBusValue value, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.DBus.Properties', 'Set', [DBusString(interface_name), DBusString(property_name), DBusVariant(value)], replySignature: DBusSignature(''), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Gets org.freedesktop.timesync1.Manager.LinkNTPServers
  Future<List<String>> getLinkNTPServers() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'LinkNTPServers', signature: DBusSignature('as'));
    return value.asStringArray().toList();
  }

  /// Gets org.freedesktop.timesync1.Manager.SystemNTPServers
  Future<List<String>> getSystemNTPServers() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'SystemNTPServers', signature: DBusSignature('as'));
    return value.asStringArray().toList();
  }

  /// Gets org.freedesktop.timesync1.Manager.RuntimeNTPServers
  Future<List<String>> getRuntimeNTPServers() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'RuntimeNTPServers', signature: DBusSignature('as'));
    return value.asStringArray().toList();
  }

  /// Gets org.freedesktop.timesync1.Manager.FallbackNTPServers
  Future<List<String>> getFallbackNTPServers() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'FallbackNTPServers', signature: DBusSignature('as'));
    return value.asStringArray().toList();
  }

  /// Gets org.freedesktop.timesync1.Manager.ServerName
  Future<String> getServerName() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'ServerName', signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.timesync1.Manager.ServerAddress
  Future<List<DBusValue>> getServerAddress() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'ServerAddress', signature: DBusSignature('(iay)'));
    return value.asStruct();
  }

  /// Gets org.freedesktop.timesync1.Manager.RootDistanceMaxUSec
  Future<int> getRootDistanceMaxUSec() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'RootDistanceMaxUSec', signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Gets org.freedesktop.timesync1.Manager.PollIntervalMinUSec
  Future<int> getPollIntervalMinUSec() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'PollIntervalMinUSec', signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Gets org.freedesktop.timesync1.Manager.PollIntervalMaxUSec
  Future<int> getPollIntervalMaxUSec() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'PollIntervalMaxUSec', signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Gets org.freedesktop.timesync1.Manager.PollIntervalUSec
  Future<int> getPollIntervalUSec() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'PollIntervalUSec', signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Gets org.freedesktop.timesync1.Manager.NTPMessage
  Future<List<DBusValue>> getNTPMessage() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'NTPMessage', signature: DBusSignature('(uuuuittayttttbtt)'));
    return value.asStruct();
  }

  /// Gets org.freedesktop.timesync1.Manager.Frequency
  Future<int> getFrequency() async {
    var value = await getProperty('org.freedesktop.timesync1.Manager', 'Frequency', signature: DBusSignature('x'));
    return value.asInt64();
  }

  /// Invokes org.freedesktop.timesync1.Manager.SetRuntimeNTPServers()
  Future<void> callSetRuntimeNTPServers(List<String> runtime_servers, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.timesync1.Manager', 'SetRuntimeNTPServers', [DBusArray.string(runtime_servers)], replySignature: DBusSignature(''), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
  }
}
