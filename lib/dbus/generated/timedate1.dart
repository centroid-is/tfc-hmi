// This file was generated using the following command and may be overwritten.
// dart-dbus generate-remote-object /private/tmp/claude-501/-Users-jonb-Projects-tfc-hmi-svn/bd2a89cd-85f8-4102-94be-ec851490f4cd/scratchpad/dbusxml/timedate1.xml

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

  /// Gets org.freedesktop.timedate1.Timezone
  Future<String> getTimezone() async {
    var value = await getProperty('org.freedesktop.timedate1', 'Timezone', signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.timedate1.LocalRTC
  Future<bool> getLocalRTC() async {
    var value = await getProperty('org.freedesktop.timedate1', 'LocalRTC', signature: DBusSignature('b'));
    return value.asBoolean();
  }

  /// Gets org.freedesktop.timedate1.CanNTP
  Future<bool> getCanNTP() async {
    var value = await getProperty('org.freedesktop.timedate1', 'CanNTP', signature: DBusSignature('b'));
    return value.asBoolean();
  }

  /// Gets org.freedesktop.timedate1.NTP
  Future<bool> getNTP() async {
    var value = await getProperty('org.freedesktop.timedate1', 'NTP', signature: DBusSignature('b'));
    return value.asBoolean();
  }

  /// Gets org.freedesktop.timedate1.NTPSynchronized
  Future<bool> getNTPSynchronized() async {
    var value = await getProperty('org.freedesktop.timedate1', 'NTPSynchronized', signature: DBusSignature('b'));
    return value.asBoolean();
  }

  /// Gets org.freedesktop.timedate1.TimeUSec
  Future<int> getTimeUSec() async {
    var value = await getProperty('org.freedesktop.timedate1', 'TimeUSec', signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Gets org.freedesktop.timedate1.RTCTimeUSec
  Future<int> getRTCTimeUSec() async {
    var value = await getProperty('org.freedesktop.timedate1', 'RTCTimeUSec', signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Invokes org.freedesktop.timedate1.SetTime()
  Future<void> callSetTime(int usec_utc, bool relative, bool interactive, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.timedate1', 'SetTime', [DBusInt64(usec_utc), DBusBoolean(relative), DBusBoolean(interactive)], replySignature: DBusSignature(''), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.timedate1.SetTimezone()
  Future<void> callSetTimezone(String timezone, bool interactive, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.timedate1', 'SetTimezone', [DBusString(timezone), DBusBoolean(interactive)], replySignature: DBusSignature(''), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.timedate1.SetLocalRTC()
  Future<void> callSetLocalRTC(bool local_rtc, bool fix_system, bool interactive, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.timedate1', 'SetLocalRTC', [DBusBoolean(local_rtc), DBusBoolean(fix_system), DBusBoolean(interactive)], replySignature: DBusSignature(''), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.timedate1.SetNTP()
  Future<void> callSetNTP(bool use_ntp, bool interactive, {bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.timedate1', 'SetNTP', [DBusBoolean(use_ntp), DBusBoolean(interactive)], replySignature: DBusSignature(''), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.timedate1.ListTimezones()
  Future<List<String>> callListTimezones({bool noAutoStart = false, bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.timedate1', 'ListTimezones', [], replySignature: DBusSignature('as'), noAutoStart: noAutoStart, allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asStringArray().toList();
  }
}
