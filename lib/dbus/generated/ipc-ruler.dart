// This file was generated using the following command and may be overwritten.
// dart-dbus generate-remote-object ipc-ruler.xml

import 'dart:io';
import 'package:dbus/dbus.dart';

/// Signal data for org.freedesktop.DBus.Properties.PropertiesChanged.
class OrgFreedesktopDBusPropertiesPropertiesChanged extends DBusSignal {
  String get interface_name => values[0].asString();
  Map<String, DBusValue> get changed_properties =>
      values[1].asStringVariantDict();
  List<String> get invalidated_properties => values[2].asStringArray().toList();

  OrgFreedesktopDBusPropertiesPropertiesChanged(DBusSignal signal)
      : super(
            sender: signal.sender,
            path: signal.path,
            interface: signal.interface,
            name: signal.name,
            values: signal.values);
}

/// Signal data for is.centroid.manager.ConnectionChange.
class OrgFreedesktopDBusPropertiesConnectionChange extends DBusSignal {
  String get slot_name => values[0].asString();
  String get signal_name => values[1].asString();

  OrgFreedesktopDBusPropertiesConnectionChange(DBusSignal signal)
      : super(
            sender: signal.sender,
            path: signal.path,
            interface: signal.interface,
            name: signal.name,
            values: signal.values);
}

class OrgFreedesktopDBusProperties extends DBusRemoteObject {
  /// Stream of org.freedesktop.DBus.Properties.PropertiesChanged signals.
  late final Stream<OrgFreedesktopDBusPropertiesPropertiesChanged>
      customPropertiesChanged;

  /// Stream of is.centroid.manager.ConnectionChange signals.
  late final Stream<OrgFreedesktopDBusPropertiesConnectionChange>
      connectionChange;

  OrgFreedesktopDBusProperties(
      DBusClient client, String destination, DBusObjectPath path)
      : super(client, name: destination, path: path) {
    customPropertiesChanged = DBusRemoteObjectSignalStream(
            object: this,
            interface: 'org.freedesktop.DBus.Properties',
            name: 'PropertiesChanged',
            signature: DBusSignature('sa{sv}as'))
        .asBroadcastStream()
        .map((signal) => OrgFreedesktopDBusPropertiesPropertiesChanged(signal));

    connectionChange = DBusRemoteObjectSignalStream(
            object: this,
            interface: 'is.centroid.manager',
            name: 'ConnectionChange',
            signature: DBusSignature('ss'))
        .asBroadcastStream()
        .map((signal) => OrgFreedesktopDBusPropertiesConnectionChange(signal));
  }

  /// Invokes org.freedesktop.DBus.Properties.Get()
  Future<DBusValue> callGet(String interface_name, String property_name,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.DBus.Properties', 'Get',
        [DBusString(interface_name), DBusString(property_name)],
        replySignature: DBusSignature('v'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asVariant();
  }

  /// Invokes org.freedesktop.DBus.Properties.Set()
  Future<void> callSet(
      String interface_name, String property_name, DBusValue value,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod(
        'org.freedesktop.DBus.Properties',
        'Set',
        [
          DBusString(interface_name),
          DBusString(property_name),
          DBusVariant(value)
        ],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.DBus.Properties.GetAll()
  Future<Map<String, DBusValue>> callGetAll(String interface_name,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.DBus.Properties', 'GetAll',
        [DBusString(interface_name)],
        replySignature: DBusSignature('a{sv}'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asStringVariantDict();
  }

  /// Gets is.centroid.manager.Connections
  Future<String> getConnections() async {
    var value = await getProperty('is.centroid.manager', 'Connections',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets is.centroid.manager.Signals
  Future<String> getSignals() async {
    var value = await getProperty('is.centroid.manager', 'Signals',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets is.centroid.manager.Slots
  Future<String> getSlots() async {
    var value = await getProperty('is.centroid.manager', 'Slots',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Invokes is.centroid.manager.Connect()
  Future<void> callConnect(String slot_name, String signal_name,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('is.centroid.manager', 'Connect',
        [DBusString(slot_name), DBusString(signal_name)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes is.centroid.manager.Disconnect()
  Future<void> callDisconnect(String slot_name,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod(
        'is.centroid.manager', 'Disconnect', [DBusString(slot_name)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes is.centroid.manager.RegisterSignal()
  Future<void> callRegisterSignal(String name, String description, int type_id,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('is.centroid.manager', 'RegisterSignal',
        [DBusString(name), DBusString(description), DBusByte(type_id)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes is.centroid.manager.RegisterSlot()
  Future<void> callRegisterSlot(String name, String description, int type_id,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('is.centroid.manager', 'RegisterSlot',
        [DBusString(name), DBusString(description), DBusByte(type_id)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.DBus.Peer.Ping()
  Future<void> callPing(
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.DBus.Peer', 'Ping', [],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.DBus.Peer.GetMachineId()
  Future<String> callGetMachineId(
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod(
        'org.freedesktop.DBus.Peer', 'GetMachineId', [],
        replySignature: DBusSignature('s'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asString();
  }

  /// Invokes org.freedesktop.DBus.Introspectable.Introspect()
  Future<String> callIntrospect(
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod(
        'org.freedesktop.DBus.Introspectable', 'Introspect', [],
        replySignature: DBusSignature('s'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asString();
  }
}
