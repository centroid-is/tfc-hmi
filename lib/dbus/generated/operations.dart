// This file was generated using the following command and may be overwritten.
// dart-dbus generate-remote-object operations.xml

import 'dart:io';
import 'package:dbus/dbus.dart';

/// Signal data for is.centroid.OperationMode.Update.
class IsCentroidOperationModeUpdate extends DBusSignal {
  String get new_mode => values[0].asString();
  String get old_mode => values[1].asString();

  IsCentroidOperationModeUpdate(DBusSignal signal)
      : super(
            sender: signal.sender,
            path: signal.path,
            interface: signal.interface,
            name: signal.name,
            values: signal.values);
}

/// Signal data for org.freedesktop.DBus.Properties.PropertiesChanged.
class IsCentroidOperationModePropertiesChanged extends DBusSignal {
  String get interface_name => values[0].asString();
  Map<String, DBusValue> get changed_properties =>
      values[1].asStringVariantDict();
  List<String> get invalidated_properties => values[2].asStringArray().toList();

  IsCentroidOperationModePropertiesChanged(DBusSignal signal)
      : super(
            sender: signal.sender,
            path: signal.path,
            interface: signal.interface,
            name: signal.name,
            values: signal.values);
}

class IsCentroidOperationMode extends DBusRemoteObject {
  /// Stream of is.centroid.OperationMode.Update signals.
  late final Stream<IsCentroidOperationModeUpdate> update;

  /// Stream of org.freedesktop.DBus.Properties.PropertiesChanged signals.
  late final Stream<IsCentroidOperationModePropertiesChanged>
      customPropertiesChanged;

  IsCentroidOperationMode(
      DBusClient client, String destination, DBusObjectPath path)
      : super(client, name: destination, path: path) {
    update = DBusRemoteObjectSignalStream(
            object: this,
            interface: 'is.centroid.OperationMode',
            name: 'Update',
            signature: DBusSignature('ss'))
        .asBroadcastStream()
        .map((signal) => IsCentroidOperationModeUpdate(signal));

    customPropertiesChanged = DBusRemoteObjectSignalStream(
            object: this,
            interface: 'org.freedesktop.DBus.Properties',
            name: 'PropertiesChanged',
            signature: DBusSignature('sa{sv}as'))
        .asBroadcastStream()
        .map((signal) => IsCentroidOperationModePropertiesChanged(signal));
  }

  /// Gets is.centroid.OperationMode.Mode
  Future<String> getMode() async {
    var value = await getProperty('is.centroid.OperationMode', 'Mode',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Invokes is.centroid.OperationMode.SetMode()
  Future<void> callSetMode(String mode_str,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod(
        'is.centroid.OperationMode', 'SetMode', [DBusString(mode_str)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes is.centroid.OperationMode.StopWithReason()
  Future<void> callStopWithReason(String reason,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod(
        'is.centroid.OperationMode', 'StopWithReason', [DBusString(reason)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
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
