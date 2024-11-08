import 'package:flutter/material.dart';
import 'package:nm/nm.dart'; // Import the nm.dart package

class IpSettingsPage extends StatefulWidget {
  @override
  _IpSettingsPageState createState() => _IpSettingsPageState();
}

class _IpSettingsPageState extends State<IpSettingsPage> {
  late NetworkManagerClient _nmClient;
  List<NetworkManagerDevice> _relevantDevices = [];

  @override
  void initState() {
    super.initState();
    _initNetworkManager();
  }

  Future<void> _initNetworkManager() async {
    _nmClient = NetworkManagerClient();
    await _nmClient.connect();
    List<NetworkManagerDevice> allDevices = _nmClient.devices;
    List<NetworkManagerDevice> relevantDevices = [];
    for (NetworkManagerDevice device in allDevices) {
      if (device.wired != null) {
        relevantDevices.add(device);
      }
      if (device.wireless != null) {
        relevantDevices.add(device);
      }
    }
    setState(() {
      _relevantDevices = relevantDevices;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('IP Settings'),
        ),
        body: _relevantDevices.isEmpty
            ? Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _relevantDevices.length,
                itemBuilder: (context, index) {
                  NetworkManagerDevice device = _relevantDevices[index];
                  return ListTile(
                    title: Text(device.interface),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              InterfaceSettingsPage(device: device),
                        ),
                      );
                    },
                  );
                },
              ));
  }
}

class InterfaceSettingsPage extends StatefulWidget {
  final NetworkManagerDevice device;

  InterfaceSettingsPage({required this.device});

  @override
  _InterfaceSettingsPageState createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
  late NetworkManagerActiveConnection _activeConnection;
  // late NetworkManagerConnection _connection;
  bool _isDhcp = true;
  String _ipAddress = '';
  String _netmask = '';
  String _gateway = '';
  String _dns = '';

  late TextEditingController _ipController;
  late TextEditingController _netmaskController;
  late TextEditingController _gatewayController;
  late TextEditingController _dnsController;

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
    // Get active connection
    final activeConnection = widget.device.activeConnection;

    if (activeConnection == null) {
      // log error
      print('No active connection found for device ${widget.device.interface}');
      return;
    }

    _activeConnection = activeConnection;
    // Get the connection settings
    final connection = _activeConnection.connection;
    if (connection == null) {
      // log error
      print('No connection found for device ${widget.device.interface}');
      return;
    }

    // final ip4Setting = connection.;

    // final method = await ip4Setting.method;
    // setState(() {
    //   _isDhcp = (method == 'auto');
    // });

    // if (!_isDhcp) {
    //     // Get IP addresses, netmask, gateway, DNS
    //     List<NMIP4Address> addresses = await ip4Setting.getAddresses();
    //     if (addresses.isNotEmpty) {
    //       NMIP4Address address = addresses[0];
    //       _ipAddress = address.address;
    //       _netmask = _prefixToNetmask(address.prefix);
    //       _ipController.text = _ipAddress;
    //       _netmaskController.text = _netmask;
    //     }
    //     _gateway = await ip4Setting.getGateway();
    //     _gatewayController.text = _gateway;

    //     List<String> dnsList = await ip4Setting.getDns();
    //     if (dnsList.isNotEmpty) {
    //       _dns = dnsList.join(', ');
    //       _dnsController.text = _dns;
    //     }
    //   }
    // } else {
    //   // Handle the case when there's no active connection
    // }
    // setState(() {});
  }

  String _prefixToNetmask(int prefixLength) {
    // Convert prefix length to netmask string
    int mask = 0xffffffff << (32 - prefixLength);
    return '${(mask >> 24) & 0xff}.${(mask >> 16) & 0xff}.${(mask >> 8) & 0xff}.${mask & 0xff}';
  }

  int _netmaskToPrefix(String netmask) {
    // Convert netmask string to prefix length
    List<String> parts = netmask.split('.');
    int mask = 0;
    for (String part in parts) {
      mask = (mask << 8) + int.parse(part);
    }
    return mask.toRadixString(2).replaceAll('0', '').length;
  }

  Future<void> _saveSettings() async {
    // if (_connection == null) return;
    // NMSettingIP4 ip4Setting = await _connection.getSettingIP4();
    // if (_isDhcp) {
    //   await ip4Setting.setMethod('auto');
    // } else {
    //   await ip4Setting.setMethod('manual');
    //   // Set the IP address, netmask, gateway, DNS
    //   int prefix = _netmaskToPrefix(_netmaskController.text);
    //   NMIP4Address address =
    //       NMIP4Address(address: _ipController.text, prefix: prefix);
    //   await ip4Setting.setAddresses([address]);
    //   await ip4Setting.setGateway(_gatewayController.text);
    //   List<String> dnsList =
    //       _dnsController.text.split(',').map((s) => s.trim()).toList();
    //   await ip4Setting.setDns(dnsList);
    // }
    // // Save the connection
    // await _connection.save();
    // // Restart the connection
    // await _activeConnection.deactivate();
    // await _nmClient.activateConnection(_connection, widget.device, null);

    // Navigator.pop(context);
  }

  // NMClient get _nmClient => NMClient.instance; // Assuming singleton instance

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings - ${widget.device.interface}'),
      ),
      body: _activeConnection == null
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: Text('Use DHCP'),
                      value: _isDhcp,
                      onChanged: (value) {
                        setState(() {
                          _isDhcp = value;
                        });
                      },
                    ),
                    if (!_isDhcp) ...[
                      TextField(
                        decoration: InputDecoration(labelText: 'IP Address'),
                        controller: _ipController,
                      ),
                      TextField(
                        decoration: InputDecoration(labelText: 'Netmask'),
                        controller: _netmaskController,
                      ),
                      TextField(
                        decoration: InputDecoration(labelText: 'Gateway'),
                        controller: _gatewayController,
                      ),
                      TextField(
                        decoration: InputDecoration(labelText: 'DNS Servers'),
                        controller: _dnsController,
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                      ),
                    ],
                    SizedBox(height: 20),
                    ElevatedButton(
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
