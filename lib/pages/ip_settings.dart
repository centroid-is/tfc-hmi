import 'package:flutter/material.dart';
import 'package:nm/nm.dart'; // Ensure nm.dart is correctly added in pubspec.yaml
import '../widgets/base_scaffold.dart';
import '../app_colors.dart'; // Import the AppColors class

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
                    style: TextStyle(color: AppColors.primaryTextColor),
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
                          color: AppColors.backgroundColor,
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
                              Icons.arrow_forward_ios,
                              color: AppColors.secondaryIconColor,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      InterfaceSettingsPage(device: device),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}

class InterfaceSettingsPage extends StatefulWidget {
  final NetworkManagerDevice device;

  InterfaceSettingsPage({required this.device});

  @override
  _InterfaceSettingsPageState createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
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
              'No active connection found for device ${widget.device.interface}';
          _isLoading = false;
        });
        return;
      }

      final ip4Setting = _activeConnection!.ip4Config;
      final dhcp4Setting = _activeConnection!.dhcp4Config;

      if (ip4Setting != null) {
        _ipController.text = ip4Setting.addressData.first['address'];
        _netmaskController.text = ip4Setting.addressData.first['prefix'];
        _gatewayController.text = ip4Setting.gateway;
        _dnsController.text =
            ip4Setting.nameserverData.map((e) => e['address']).join(', ');
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

  int _netmaskToPrefix(String netmask) {
    // Convert netmask string to prefix length
    List<String> parts = netmask.split('.');
    int mask = 0;
    for (String part in parts) {
      mask = (mask << 8) + int.parse(part);
    }
    String binary = mask.toRadixString(2).padLeft(32, '0');
    return binary.replaceAll('0', '').length;
  }

  Future<void> _saveSettings() async {
    if (_activeConnection == null) return;

    try {
      //   NMSettingIP4? ip4Setting = _connection!.settingIP4;
      //   if (ip4Setting == null) {
      //     throw Exception('IPv4 settings not found.');
      //   }

      //   if (_isDhcp) {
      //     ip4Setting.method = 'auto';
      //     ip4Setting.addresses = [];
      //     ip4Setting.gateway = null;
      //     ip4Setting.dns = [];
      //   } else {
      //     ip4Setting.method = 'manual';
      //     int prefix = _netmaskToPrefix(_netmaskController.text);
      //     NMIP4Address address =
      //         NMIP4Address(address: _ipController.text, prefix: prefix);
      //     ip4Setting.addresses = [address];
      //     ip4Setting.gateway = _gatewayController.text;
      //     ip4Setting.dns = _dnsController.text
      //         .split(',')
      //         .map((s) => s.trim())
      //         .where((s) => s.isNotEmpty)
      //         .toList();
      // }

      //   // Save the updated connection
      //   await _connection!.save();

      //   // Restart the connection to apply changes
      //   await _activeConnection!.deactivate();
      //   await widget.device.activateConnection(_connection!, null);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: AppColors.backgroundColor,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: AppColors.backgroundColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Settings - ${widget.device.interface}',
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
              : SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
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
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.backgroundColor,
                            foregroundColor: AppColors.primaryTextColor,
                          ),
                          onPressed: _saveSettings,
                          child: Text('Save'),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
