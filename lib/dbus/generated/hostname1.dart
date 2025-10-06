// This file was generated using the following command and may be overwritten.
// dart-dbus generate-remote-object hostname1.xml

import 'dart:io';
import 'package:dbus/dbus.dart';

/// Signal data for org.freedesktop.DBus.Properties.PropertiesChanged.
class OrgFreedesktopDBusPeerPropertiesChanged extends DBusSignal {
  String get interface_name => values[0].asString();
  Map<String, DBusValue> get changed_properties =>
      values[1].asStringVariantDict();
  List<String> get invalidated_properties => values[2].asStringArray().toList();

  OrgFreedesktopDBusPeerPropertiesChanged(DBusSignal signal)
      : super(
            sender: signal.sender,
            path: signal.path,
            interface: signal.interface,
            name: signal.name,
            values: signal.values);
}

class OrgFreedesktopDBusPeer extends DBusRemoteObject {
  /// Stream of org.freedesktop.DBus.Properties.PropertiesChanged signals.
  late final Stream<OrgFreedesktopDBusPeerPropertiesChanged>
      customPropertiesChanged;

  OrgFreedesktopDBusPeer(
      DBusClient client, String destination, DBusObjectPath path)
      : super(client, name: destination, path: path) {
    customPropertiesChanged = DBusRemoteObjectSignalStream(
            object: this,
            interface: 'org.freedesktop.DBus.Properties',
            name: 'PropertiesChanged',
            signature: DBusSignature('sa{sv}as'))
        .asBroadcastStream()
        .map((signal) => OrgFreedesktopDBusPeerPropertiesChanged(signal));
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

  /// Gets org.freedesktop.hostname1.Hostname
  Future<String> getHostname() async {
    var value = await getProperty('org.freedesktop.hostname1', 'Hostname',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.StaticHostname
  Future<String> getStaticHostname() async {
    var value = await getProperty('org.freedesktop.hostname1', 'StaticHostname',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.PrettyHostname
  Future<String> getPrettyHostname() async {
    var value = await getProperty('org.freedesktop.hostname1', 'PrettyHostname',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.DefaultHostname
  Future<String> getDefaultHostname() async {
    var value = await getProperty(
        'org.freedesktop.hostname1', 'DefaultHostname',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.HostnameSource
  Future<String> getHostnameSource() async {
    var value = await getProperty('org.freedesktop.hostname1', 'HostnameSource',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.IconName
  Future<String> getIconName() async {
    var value = await getProperty('org.freedesktop.hostname1', 'IconName',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.Chassis
  Future<String> getChassis() async {
    var value = await getProperty('org.freedesktop.hostname1', 'Chassis',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.Deployment
  Future<String> getDeployment() async {
    var value = await getProperty('org.freedesktop.hostname1', 'Deployment',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.Location
  Future<String> getLocation() async {
    var value = await getProperty('org.freedesktop.hostname1', 'Location',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.KernelName
  Future<String> getKernelName() async {
    var value = await getProperty('org.freedesktop.hostname1', 'KernelName',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.KernelRelease
  Future<String> getKernelRelease() async {
    var value = await getProperty('org.freedesktop.hostname1', 'KernelRelease',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.KernelVersion
  Future<String> getKernelVersion() async {
    var value = await getProperty('org.freedesktop.hostname1', 'KernelVersion',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.OperatingSystemPrettyName
  Future<String> getOperatingSystemPrettyName() async {
    var value = await getProperty(
        'org.freedesktop.hostname1', 'OperatingSystemPrettyName',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.OperatingSystemCPEName
  Future<String> getOperatingSystemCPEName() async {
    var value = await getProperty(
        'org.freedesktop.hostname1', 'OperatingSystemCPEName',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.OperatingSystemSupportEnd
  Future<int> getOperatingSystemSupportEnd() async {
    var value = await getProperty(
        'org.freedesktop.hostname1', 'OperatingSystemSupportEnd',
        signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Gets org.freedesktop.hostname1.HomeURL
  Future<String> getHomeURL() async {
    var value = await getProperty('org.freedesktop.hostname1', 'HomeURL',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.HardwareVendor
  Future<String> getHardwareVendor() async {
    var value = await getProperty('org.freedesktop.hostname1', 'HardwareVendor',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.HardwareModel
  Future<String> getHardwareModel() async {
    var value = await getProperty('org.freedesktop.hostname1', 'HardwareModel',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.FirmwareVersion
  Future<String> getFirmwareVersion() async {
    var value = await getProperty(
        'org.freedesktop.hostname1', 'FirmwareVersion',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.FirmwareVendor
  Future<String> getFirmwareVendor() async {
    var value = await getProperty('org.freedesktop.hostname1', 'FirmwareVendor',
        signature: DBusSignature('s'));
    return value.asString();
  }

  /// Gets org.freedesktop.hostname1.FirmwareDate
  Future<int> getFirmwareDate() async {
    var value = await getProperty('org.freedesktop.hostname1', 'FirmwareDate',
        signature: DBusSignature('t'));
    return value.asUint64();
  }

  /// Gets org.freedesktop.hostname1.MachineID
  Future<List<int>> getMachineID() async {
    var value = await getProperty('org.freedesktop.hostname1', 'MachineID',
        signature: DBusSignature('ay'));
    return value.asByteArray().toList();
  }

  /// Gets org.freedesktop.hostname1.BootID
  Future<List<int>> getBootID() async {
    var value = await getProperty('org.freedesktop.hostname1', 'BootID',
        signature: DBusSignature('ay'));
    return value.asByteArray().toList();
  }

  /// Gets org.freedesktop.hostname1.VSockCID
  Future<int> getVSockCID() async {
    var value = await getProperty('org.freedesktop.hostname1', 'VSockCID',
        signature: DBusSignature('u'));
    return value.asUint32();
  }

  /// Invokes org.freedesktop.hostname1.SetHostname()
  Future<void> callSetHostname(String hostname, bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.hostname1', 'SetHostname',
        [DBusString(hostname), DBusBoolean(interactive)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.hostname1.SetStaticHostname()
  Future<void> callSetStaticHostname(String hostname, bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.hostname1', 'SetStaticHostname',
        [DBusString(hostname), DBusBoolean(interactive)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.hostname1.SetPrettyHostname()
  Future<void> callSetPrettyHostname(String hostname, bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.hostname1', 'SetPrettyHostname',
        [DBusString(hostname), DBusBoolean(interactive)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.hostname1.SetIconName()
  Future<void> callSetIconName(String icon, bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.hostname1', 'SetIconName',
        [DBusString(icon), DBusBoolean(interactive)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.hostname1.SetChassis()
  Future<void> callSetChassis(String chassis, bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.hostname1', 'SetChassis',
        [DBusString(chassis), DBusBoolean(interactive)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.hostname1.SetDeployment()
  Future<void> callSetDeployment(String deployment, bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.hostname1', 'SetDeployment',
        [DBusString(deployment), DBusBoolean(interactive)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.hostname1.SetLocation()
  Future<void> callSetLocation(String location, bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    await callMethod('org.freedesktop.hostname1', 'SetLocation',
        [DBusString(location), DBusBoolean(interactive)],
        replySignature: DBusSignature(''),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
  }

  /// Invokes org.freedesktop.hostname1.GetProductUUID()
  Future<List<int>> callGetProductUUID(bool interactive,
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.hostname1', 'GetProductUUID',
        [DBusBoolean(interactive)],
        replySignature: DBusSignature('ay'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asByteArray().toList();
  }

  /// Invokes org.freedesktop.hostname1.GetHardwareSerial()
  Future<String> callGetHardwareSerial(
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod(
        'org.freedesktop.hostname1', 'GetHardwareSerial', [],
        replySignature: DBusSignature('s'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asString();
  }

  /// Invokes org.freedesktop.hostname1.Describe()
  Future<String> callDescribe(
      {bool noAutoStart = false,
      bool allowInteractiveAuthorization = false}) async {
    var result = await callMethod('org.freedesktop.hostname1', 'Describe', [],
        replySignature: DBusSignature('s'),
        noAutoStart: noAutoStart,
        allowInteractiveAuthorization: allowInteractiveAuthorization);
    return result.returnValues[0].asString();
  }
}
