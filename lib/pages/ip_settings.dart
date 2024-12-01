import 'dart:core';
import 'package:flutter/material.dart';
import 'package:nm/nm.dart'; // Ensure nm.dart is correctly added in pubspec.yaml
import '../widgets/base_scaffold.dart';
import 'package:dbus/dbus.dart';

class IpSettingsPage extends StatefulWidget {
  const IpSettingsPage({super.key});
  @override
  IpSettingsPageState createState() => IpSettingsPageState();
}

class IpSettingsPageState extends State<IpSettingsPage> {
  final NetworkManagerClient client = NetworkManagerClient();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    client.close();
  }

  void _openInterfaceSettings(
      NetworkManagerClient client, NetworkManagerDevice device) {
    showDialog(
      context: context,
      builder: (context) =>
          InterfaceSettingsDialog(nmClient: client, device: device),
    );
  }

  IconData iconFromType(NetworkManagerDeviceType type) {
    switch (type) {
      case NetworkManagerDeviceType.ethernet:
        return Icons.settings_ethernet;
      case NetworkManagerDeviceType.wifi:
        return Icons.wifi;
      default:
        return Icons.question_mark;
    }
  }

  bool supportedDeviceTypes(NetworkManagerDeviceType type) {
    return type == NetworkManagerDeviceType.ethernet ||
        type == NetworkManagerDeviceType.wifi;
  }

  String connectivityStateToString(NetworkManagerConnectivityState state) {
    switch (state) {
      case NetworkManagerConnectivityState.full:
        return 'Internet connected';
      case NetworkManagerConnectivityState.limited:
        return 'Internet connection limited';
      case NetworkManagerConnectivityState.none:
        return 'Internet disconnected';
      default:
        return 'Internet status unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: client.connect(),
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          Widget body;
          if (snapshot.connectionState == ConnectionState.done) {
            // Reload the page if devices are added or removed and are of supported type.
            client.deviceAdded
                .where((device) => supportedDeviceTypes(device.deviceType))
                .listen((_) => setState(() {
                      // Should reload
                    }));
            client.deviceRemoved
                .where((device) => supportedDeviceTypes(device.deviceType))
                .listen((_) => setState(() {
                      // Should reload
                    }));
            List<NetworkManagerDevice> relevantDevices = client.devices
                .where((device) => supportedDeviceTypes(device.deviceType))
                .toList();
            if (relevantDevices.isEmpty) {
              body = const Center(
                child: Text(
                  'No relevant network devices found.',
                ),
              );
            } else {
              body = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Text(
                          client.connectivityCheckEnabled
                              ? connectivityStateToString(client.connectivity)
                              : 'Connectivity check disabled',
                          textAlign: TextAlign.left,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                          child: Text(
                              'Connection tested to ${client.connectivityCheckUri}',
                              style: Theme.of(context).textTheme.titleSmall),
                        )
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: relevantDevices.length,
                      itemBuilder: (context, index) {
                        NetworkManagerDevice device = relevantDevices[index];
                        return StreamBuilder<Object>(
                            stream: device.propertiesChanged,
                            builder: (context, snapshot) {
                              final connectionActivated =
                                  device.activeConnection != null &&
                                      device.activeConnection!.state ==
                                          NetworkManagerActiveConnectionState
                                              .activated;
                              final cardColor = connectionActivated
                                  ? Theme.of(context).colorScheme.surface
                                  : Theme.of(context).colorScheme.error;
                              final itemColor = connectionActivated
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context).colorScheme.onError;
                              final tStyle = Theme.of(context)
                                  .textTheme
                                  .labelLarge!
                                  .copyWith(color: itemColor);
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                child: ListTile(
                                    leading: Icon(
                                      iconFromType(device.deviceType),
                                      color: itemColor,
                                    ),
                                    title: Text(
                                      device.interface,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall!
                                          .copyWith(color: itemColor),
                                    ),
                                    subtitle: Text(
                                      device.deviceType.name,
                                      style: tStyle,
                                    ),
                                    trailing: Icon(
                                      Icons.settings,
                                      color: itemColor,
                                    ),
                                    onTap: () =>
                                        _openInterfaceSettings(client, device),
                                    tileColor: cardColor,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(5.0))),
                              );
                            });
                      },
                    ),
                  ),
                ],
              );
            }
          } else if (snapshot.hasError) {
            body = Center(
              child: Text(
                'Failed to connect to NetworkManager: ${snapshot.error.toString()}',
                style: TextStyle(color: Theme.of(context).colorScheme.onError),
              ),
            );
          } else {
            body = Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.onPrimary),
              ),
            );
          }
          return BaseScaffold(
            title: 'IP Settings',
            body: body,
          );
        });
  }
}

class InterfaceSettingsDialog extends StatefulWidget {
  final NetworkManagerClient nmClient;
  final NetworkManagerDevice device;

  const InterfaceSettingsDialog(
      {super.key, required this.nmClient, required this.device});

  @override
  State<InterfaceSettingsDialog> createState() =>
      _InterfaceSettingsDialogState();
}

class _InterfaceSettingsDialogState extends State<InterfaceSettingsDialog> {
  NetworkManagerActiveConnection? _activeConnection;
  bool _isDhcp = true;
  String _ipAddress = '';
  String _netmask = '';
  String _gateway = '';
  String _dns = '';

  late TextEditingController _ipController;
  late TextEditingController _netmaskController;
  late TextEditingController _gatewayController;
  late TextEditingController _dnsController;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _netmaskController = TextEditingController();
    _gatewayController = TextEditingController();
    _dnsController = TextEditingController();
    _loadConnectionSettings();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _netmaskController.dispose();
    _gatewayController.dispose();
    _dnsController.dispose();
    super.dispose();
  }

  Future<void> _loadConnectionSettings() async {
    try {
      _activeConnection = widget.device.activeConnection;
      if (_activeConnection == null) {
        setState(() {
          _errorMessage =
              'TODO: No active connection found for device ${widget.device.interface}';
          _isLoading = false;
        });
        return;
      }

      final ip4Setting = _activeConnection!.ip4Config;
      final dhcp4Setting = _activeConnection!.dhcp4Config;

      if (ip4Setting != null) {
        // Assuming addressData is a list of maps with 'address' and 'prefix'
        if (ip4Setting.addressData.isNotEmpty) {
          _ipAddress = ip4Setting.addressData.first['address'];
          _netmask = _prefixToNetmask(ip4Setting.addressData.first['prefix']);
          _ipController.text = _ipAddress;
          _netmaskController.text = _netmask;
        }

        _gateway = ip4Setting.gateway;
        _gatewayController.text = _gateway;

        // Assuming nameserverData is a list of maps with 'address'
        if (ip4Setting.nameserverData.isNotEmpty) {
          _dns = ip4Setting.nameserverData.map((e) => e['address']).join(', ');
          _dnsController.text = _dns;
        }
      }

      setState(() {
        _isDhcp = dhcp4Setting != null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load connection settings: $e';
        _isLoading = false;
      });
    }
  }

  String _prefixToNetmask(int prefixLength) {
    // Convert prefix length to netmask string
    int mask = prefixLength == 0 ? 0 : 0xffffffff << (32 - prefixLength);
    return '${(mask >> 24) & 0xff}.${(mask >> 16) & 0xff}.${(mask >> 8) & 0xff}.${mask & 0xff}';
  }

  Future<void> _saveSettings() async {
    if (_activeConnection == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final ip4Config = widget.device.ip4Config;
      if (ip4Config == null) {
        throw Exception('IP4 Config not found.');
      }
      // Retrieve the associated settings connection
      final connection = _activeConnection!.connection;
      if (connection == null) {
        throw Exception('Connection not found.');
      }

      // Prepare the updated settings
      Map<String, Map<String, DBusValue>> updatedSettings =
          await connection.getSettings();

      if (_isDhcp) {
        // Configure DHCP
        updatedSettings['ipv4'] = {
          'method': const DBusString('auto'),
        };
      } else {
        // Configure Static IP
        String ip = _ipController.text.trim();
        String netmask = _netmaskController.text.trim();
        String gateway = _gatewayController.text.trim();
        List<String> dnsServers = _dnsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        // Validate Inputs
        if (!_isValidIp(ip)) {
          throw Exception('Invalid IP Address: $ip');
        }
        if (!_isValidNetmask(netmask)) {
          throw Exception('Invalid Netmask: $netmask');
        }
        if (gateway.isNotEmpty && !_isValidIp(gateway)) {
          throw Exception('Invalid Gateway: $gateway');
        }
        for (String dns in dnsServers) {
          if (!_isValidIp(dns)) {
            throw Exception('Invalid DNS Server: $dns');
          }
        }

        // Convert netmask to prefix
        int prefix = _netmaskToPrefix(netmask);

        updatedSettings['ipv4'] = {
          'method': const DBusString('manual'),
          'address-data': DBusArray(DBusSignature('a{sv}'), [
            DBusDict(DBusSignature('s'), DBusSignature('v'), {
              const DBusString('address'): DBusVariant(DBusString(ip)),
              const DBusString('prefix'): DBusVariant(DBusUint32(prefix)),
            })
          ]),
          'dns-data': DBusArray(DBusSignature('s'),
              dnsServers.map((dns) => DBusString(dns)).toList()),
          'gateway': DBusString(gateway)
        };
      }

      // Update the connection settings to persistent storage
      await connection.update(updatedSettings);

      // Reload the updated config
      await widget.nmClient.deactivateConnection(_activeConnection!);
      await widget.nmClient
          .activateConnection(device: widget.device, connection: connection);

      // Show success message
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Settings saved successfully',
          ),
        ),
      );

      // Close the dialog or navigate back
      navigator.pop();
    } catch (e) {
      // Show error message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save settings: $e',
          ),
        ),
      );
    }
  }

  /// Helper method to validate IPv4 addresses
  bool _isValidIp(String ip) {
    final ipRegex = RegExp(r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$');
    return ipRegex.hasMatch(ip);
  }

  /// Helper method to validate Netmask
  bool _isValidNetmask(String netmask) {
    final netmaskRegex =
        RegExp(r'^((255)\.){3}(255|254|252|248|240|224|192|128|0)$');
    return netmaskRegex.hasMatch(netmask);
  }

  /// Helper method to convert netmask to prefix length
  int _netmaskToPrefix(String netmask) {
    List<String> parts = netmask.split('.');
    int mask = 0;
    for (String part in parts) {
      mask = (mask << 8) + int.parse(part);
    }
    String binary = mask.toRadixString(2).padLeft(32, '0');
    return binary.replaceAll('0', '').length;
  }

  @override
  Widget build(BuildContext context) {
    // Todo hot reload any external changes
    // _loadConnectionSettings();
    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      child: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _errorMessage != null
              ? Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage!,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Settings - ${widget.device.interface}',
                        ),
                        const SizedBox(height: 20),
                        SwitchListTile(
                          title: const Text(
                            'Use DHCP',
                          ),
                          value: _isDhcp,
                          onChanged: (value) {
                            setState(() {
                              _isDhcp = value;
                            });
                          },
                        ),
                        if (!_isDhcp) ...[
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'IP Address',
                            ),
                            controller: _ipController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Netmask',
                            ),
                            controller: _netmaskController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'Gateway',
                            ),
                            controller: _gatewayController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            decoration: const InputDecoration(
                              labelText: 'DNS Servers (comma separated)',
                            ),
                            controller: _dnsController,
                            keyboardType: TextInputType.multiline,
                            maxLines: null,
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'Cancel',
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _saveSettings,
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
