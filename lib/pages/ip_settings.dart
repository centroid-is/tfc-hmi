import 'package:flutter/material.dart';
import 'package:nm/nm.dart'; // Ensure nm.dart is correctly added in pubspec.yaml
import '../widgets/base_scaffold.dart';
import '../app_colors.dart'; // Import the AppColors class
import 'package:dbus/dbus.dart';

class IpSettingsPage extends StatefulWidget {
  @override
  _IpSettingsPageState createState() => _IpSettingsPageState();
}

class _IpSettingsPageState extends State<IpSettingsPage> {
  late NetworkManagerClient _nmClient;
  List<NetworkManagerDevice> _relevantDevices = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initNetworkManager();
  }

  Future<void> _initNetworkManager() async {
    try {
      _nmClient = NetworkManagerClient();
      await _nmClient.connect();
      List<NetworkManagerDevice> allDevices = _nmClient.devices;

      List<NetworkManagerDevice> relevantDevices = allDevices.where((device) {
        // Filter for wired and wireless devices
        return device.wired != null || device.wireless != null;
      }).toList();

      setState(() {
        _relevantDevices = relevantDevices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to connect to NetworkManager: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nmClient.close();
    super.dispose();
  }

  void _openInterfaceSettings(NetworkManagerDevice device) {
    showDialog(
      context: context,
      builder: (context) =>
          InterfaceSettingsDialog(nmClient: _nmClient, device: device),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'IP Settings',
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: AppColors.errorTextColor),
                  ),
                )
              : _relevantDevices.isEmpty
                  ? Center(
                      child: Text(
                        'No relevant network devices found.',
                        style: TextStyle(color: AppColors.primaryTextColor),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _relevantDevices.length,
                      itemBuilder: (context, index) {
                        NetworkManagerDevice device = _relevantDevices[index];
                        String deviceType =
                            device.wired != null ? 'Wired' : 'Wireless';
                        return Card(
                          color: AppColors.cardBackgroundColor,
                          margin: EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 4.0),
                          child: ListTile(
                            leading: Icon(
                              deviceType == 'Wired' ? Icons.cable : Icons.wifi,
                              color: AppColors.primaryIconColor,
                            ),
                            title: Text(
                              device.interface,
                              style:
                                  TextStyle(color: AppColors.primaryTextColor),
                            ),
                            subtitle: Text(
                              deviceType,
                              style: TextStyle(
                                  color: AppColors.secondaryTextColor),
                            ),
                            trailing: Icon(
                              Icons.settings,
                              color: AppColors.secondaryIconColor,
                            ),
                            onTap: () => _openInterfaceSettings(device),
                          ),
                        );
                      },
                    ),
    );
  }
}

class InterfaceSettingsDialog extends StatefulWidget {
  final NetworkManagerClient nmClient;
  final NetworkManagerDevice device;

  InterfaceSettingsDialog({required this.nmClient, required this.device});

  @override
  _InterfaceSettingsDialogState createState() =>
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
      _activeConnection = await widget.device.activeConnection;
      if (_activeConnection == null) {
        setState(() {
          _errorMessage =
              'No active connection found for device ${widget.device.interface}';
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

        _gateway = ip4Setting.gateway ?? '';
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
          'address-data': DBusArray(DBusSignature('a{sv}'), []),
          'gateway': const DBusString(''),
          // 'dns': DBusArray(DBusSignature('s'), []),
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

      await widget.nmClient.deactivateConnection(_activeConnection!);
      await widget.nmClient
          .activateConnection(device: widget.device, connection: connection);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settings saved successfully',
            style: TextStyle(color: AppColors.successTextColor),
          ),
          backgroundColor: AppColors.backgroundColor,
        ),
      );

      // Close the dialog or navigate back
      Navigator.pop(context);
    } catch (e) {
      print('$e');
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save settings: $e',
            style: TextStyle(color: AppColors.errorTextColor),
          ),
          backgroundColor: AppColors.backgroundColor,
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
    return Dialog(
      backgroundColor: AppColors.backgroundColor,
      insetPadding: EdgeInsets.all(16.0),
      child: _isLoading
          ? Container(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
                ),
              ),
            )
          : _errorMessage != null
              ? Container(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: AppColors.errorTextColor),
                      ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.elevatedButtonColor,
                          foregroundColor: AppColors.elevatedButtonTextColor,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text('Close'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Settings - ${widget.device.interface}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryTextColor),
                        ),
                        SizedBox(height: 20),
                        SwitchListTile(
                          title: Text(
                            'Use DHCP',
                            style: TextStyle(color: AppColors.primaryTextColor),
                          ),
                          value: _isDhcp,
                          activeColor: AppColors.primaryColor,
                          onChanged: (value) {
                            setState(() {
                              _isDhcp = value;
                            });
                          },
                        ),
                        if (!_isDhcp) ...[
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'IP Address',
                              labelStyle: TextStyle(
                                  color: AppColors.secondaryTextColor),
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.primaryColor),
                              ),
                            ),
                            controller: _ipController,
                            style: TextStyle(color: AppColors.primaryTextColor),
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: 10),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Netmask',
                              labelStyle: TextStyle(
                                  color: AppColors.secondaryTextColor),
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.primaryColor),
                              ),
                            ),
                            controller: _netmaskController,
                            style: TextStyle(color: AppColors.primaryTextColor),
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: 10),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Gateway',
                              labelStyle: TextStyle(
                                  color: AppColors.secondaryTextColor),
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.primaryColor),
                              ),
                            ),
                            controller: _gatewayController,
                            style: TextStyle(color: AppColors.primaryTextColor),
                            keyboardType: TextInputType.number,
                          ),
                          SizedBox(height: 10),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'DNS Servers (comma separated)',
                              labelStyle: TextStyle(
                                  color: AppColors.secondaryTextColor),
                              enabledBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide:
                                    BorderSide(color: AppColors.primaryColor),
                              ),
                            ),
                            controller: _dnsController,
                            style: TextStyle(color: AppColors.primaryTextColor),
                            keyboardType: TextInputType.multiline,
                            maxLines: null,
                          ),
                        ],
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                    color: AppColors.secondaryTextColor),
                              ),
                            ),
                            SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.elevatedButtonColor,
                                foregroundColor:
                                    AppColors.elevatedButtonTextColor,
                              ),
                              onPressed: _saveSettings,
                              child: Text('Save'),
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
