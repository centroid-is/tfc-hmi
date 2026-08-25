import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:nm/nm.dart';

import '../core/network_settings.dart';
import '../widgets/base_scaffold.dart';
import '../widgets/panes/pane_chrome.dart';

/// Network configuration for the station: every ethernet/wifi/bond interface
/// as a card with its live addressing, a per-interface IPv4 dialog, and
/// creation of active-backup bonds for stations with redundant cabling.

class IpSettingsPage extends StatelessWidget {
  final DBusClient dbusClient;

  const IpSettingsPage({super.key, required this.dbusClient});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'IP Settings',
      body: IpSettingsBody(dbusClient: dbusClient),
    );
  }
}

/// The page content, split from [IpSettingsPage] so tests can pump it
/// without [BaseScaffold]'s routing context and with an injected client.
class IpSettingsBody extends StatefulWidget {
  final DBusClient? dbusClient;

  /// Test seam — a fake client bypasses the D-Bus connection entirely.
  @visibleForTesting
  final NetworkManagerClient? client;

  const IpSettingsBody({super.key, this.dbusClient, this.client})
      : assert(dbusClient != null || client != null,
            'Either a dbusClient or an injected client is required');

  @override
  IpSettingsBodyState createState() => IpSettingsBodyState();
}

class IpSettingsBodyState extends State<IpSettingsBody> {
  late final NetworkManagerClient client;
  late final bool _ownsClient;
  late final Future<void> _connectFuture;
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    client =
        widget.client ?? NetworkManagerClient(bus: widget.dbusClient);
    _connectFuture = client.connect().then((_) => _subscribe());
  }

  void _subscribe() {
    void refresh(dynamic _) {
      if (mounted) setState(() {});
    }

    _subscriptions.add(client.deviceAdded
        .where((device) => _supportedDeviceType(device.deviceType))
        .listen(refresh));
    _subscriptions.add(client.deviceRemoved
        .where((device) => _supportedDeviceType(device.deviceType))
        .listen(refresh));
    // Connectivity state, primary connection, etc.
    _subscriptions.add(client.propertiesChanged.listen(refresh));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_ownsClient) client.close();
    super.dispose();
  }

  static bool _supportedDeviceType(NetworkManagerDeviceType type) {
    return type == NetworkManagerDeviceType.ethernet ||
        type == NetworkManagerDeviceType.wifi ||
        type == NetworkManagerDeviceType.bond;
  }

  static int _typeOrder(NetworkManagerDeviceType type) {
    switch (type) {
      case NetworkManagerDeviceType.bond:
        return 0;
      case NetworkManagerDeviceType.ethernet:
        return 1;
      default:
        return 2;
    }
  }

  List<NetworkManagerDevice> get _relevantDevices {
    final devices = client.devices
        .where((device) => _supportedDeviceType(device.deviceType))
        .toList();
    devices.sort((a, b) {
      final order = _typeOrder(a.deviceType) - _typeOrder(b.deviceType);
      return order != 0 ? order : a.interface.compareTo(b.interface);
    });
    return devices;
  }

  List<NetworkManagerDevice> get _ethernetDevices => client.devices
      .where(
          (device) => device.deviceType == NetworkManagerDeviceType.ethernet)
      .toList();

  PaneStatus _connectivityStatus() {
    if (!client.connectivityCheckEnabled) {
      return const PaneStatus.unknown('Connectivity check disabled');
    }
    switch (client.connectivity) {
      case NetworkManagerConnectivityState.full:
        return const PaneStatus.running('Internet connected');
      case NetworkManagerConnectivityState.limited:
        return const PaneStatus.warning('Internet limited');
      case NetworkManagerConnectivityState.portal:
        return const PaneStatus.warning('Captive portal');
      case NetworkManagerConnectivityState.none:
        return const PaneStatus.stopped('Internet disconnected');
      default:
        return const PaneStatus.unknown('Internet status unknown');
    }
  }

  Future<void> _openInterfaceSettings(NetworkManagerDevice device) async {
    await showDialog(
      context: context,
      builder: (context) =>
          InterfaceSettingsDialog(nmClient: client, device: device),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openCreateBond() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => CreateBondDialog(nmClient: client),
    );
    if (created == true && mounted) setState(() {});
  }

  Future<void> _deleteBond(NetworkManagerDevice device) async {
    final bondName = device.interface;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete bond $bondName?'),
        content: const Text(
            'The bond and its member connections are removed. Members fall '
            'back to their own connection profiles, if any.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      for (final connection in client.settings.connections) {
        final settings = await connection.getSettings();
        final section = settings['connection'] ?? {};
        final interfaceName = section['interface-name']?.asString();
        final master = section['master']?.asString();
        if (interfaceName == bondName || master == bondName) {
          await connection.delete();
        }
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to delete bond: $e')),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _connectFuture,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          Widget body;
          if (snapshot.hasError) {
            body = Center(
              child: Text(
                'Failed to connect to NetworkManager: ${snapshot.error}',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          } else if (snapshot.connectionState != ConnectionState.done) {
            body = const Center(child: CircularProgressIndicator());
          } else {
            final devices = _relevantDevices;
            body = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      PaneStatusChip(status: _connectivityStatus()),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          client.connectivityCheckEnabled
                              ? 'Checked against ${client.connectivityCheckUri}'
                              : '',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Tooltip(
                        message: _ethernetDevices.length >= 2
                            ? 'Bond two ethernet ports for failover '
                                '(active-backup)'
                            : 'Needs at least two ethernet ports',
                        child: FilledButton.tonalIcon(
                          onPressed: _ethernetDevices.length >= 2
                              ? _openCreateBond
                              : null,
                          icon: const Icon(Icons.device_hub),
                          label: const Text('Create bond'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: devices.isEmpty
                      ? const Center(
                          child: Text('No relevant network devices found.'))
                      : ListView.builder(
                          itemCount: devices.length,
                          itemBuilder: (context, index) {
                            final device = devices[index];
                            return DeviceCard(
                              client: client,
                              device: device,
                              onConfigure: () =>
                                  _openInterfaceSettings(device),
                              onDeleteBond: device.deviceType ==
                                      NetworkManagerDeviceType.bond
                                  ? () => _deleteBond(device)
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            );
          }
          return body;
        });
  }
}

// ---------------------------------------------------------------------------
// Device card
// ---------------------------------------------------------------------------

/// One network interface: identity, live status chip, and the addressing an
/// operator actually asks about (IP, gateway, DNS, MAC, link speed, SSID).
class DeviceCard extends StatelessWidget {
  final NetworkManagerClient client;
  final NetworkManagerDevice device;
  final VoidCallback onConfigure;
  final VoidCallback? onDeleteBond;

  const DeviceCard({
    super.key,
    required this.client,
    required this.device,
    required this.onConfigure,
    this.onDeleteBond,
  });

  static IconData _iconFromType(NetworkManagerDeviceType type) {
    switch (type) {
      case NetworkManagerDeviceType.ethernet:
        return Icons.settings_ethernet;
      case NetworkManagerDeviceType.wifi:
        return Icons.wifi;
      case NetworkManagerDeviceType.bond:
        return Icons.device_hub;
      default:
        return Icons.question_mark;
    }
  }

  static PaneStatus _statusFor(NetworkManagerDevice device) {
    switch (device.state) {
      case NetworkManagerDeviceState.activated:
        return const PaneStatus.running('Connected');
      case NetworkManagerDeviceState.disconnected:
        return const PaneStatus.stopped('Disconnected');
      case NetworkManagerDeviceState.unavailable:
        return const PaneStatus(
            label: 'No link', color: Colors.amber, icon: Icons.link_off);
      case NetworkManagerDeviceState.failed:
        return const PaneStatus.fault('Failed');
      case NetworkManagerDeviceState.deactivating:
        return const PaneStatus.stopped('Disconnecting…');
      case NetworkManagerDeviceState.unmanaged:
        return const PaneStatus.unknown('Unmanaged');
      case NetworkManagerDeviceState.unknown:
        return const PaneStatus.unknown();
      default:
        return const PaneStatus.warning('Connecting…');
    }
  }

  List<(String, String)> _details() {
    final details = <(String, String)>[];
    final ip4 = device.ip4Config;

    final addresses = ip4?.addressData
            .map((data) => '${data['address']}/${data['prefix']}')
            .join(', ') ??
        '';
    if (addresses.isNotEmpty) {
      details.add(('IPv4', addresses));
      details.add(
          ('Method', device.dhcp4Config != null ? 'DHCP' : 'Static'));
    }
    final gateway = ip4?.gateway ?? '';
    if (gateway.isNotEmpty) details.add(('Gateway', gateway));
    final dns =
        ip4?.nameserverData.map((data) => data['address']).join(', ') ?? '';
    if (dns.isNotEmpty) details.add(('DNS', dns));

    if (device.hwAddress.isNotEmpty) details.add(('MAC', device.hwAddress));

    final wired = device.wired;
    if (wired != null && wired.speed > 0) {
      details.add(('Speed', '${wired.speed} Mb/s'));
    }
    if (device.mtu > 0) details.add(('MTU', '${device.mtu}'));

    final accessPoint = device.wireless?.activeAccessPoint;
    if (accessPoint != null) {
      final ssid = utf8.decode(accessPoint.ssid, allowMalformed: true);
      if (ssid.isNotEmpty) details.add(('SSID', ssid));
      details.add(('Signal', '${accessPoint.strength}%'));
    }

    if (device.deviceType == NetworkManagerDeviceType.bond) {
      final members = client.devices
          .where((d) =>
              d.activeConnection?.master?.interface == device.interface)
          .map((d) => d.interface)
          .toList()
        ..sort();
      details.add((
        'Members',
        members.isEmpty ? 'none' : members.join(', '),
      ));
      details.add(('Mode', 'active-backup'));
    }
    return details;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Object>(
        stream: device.propertiesChanged,
        builder: (context, snapshot) {
          final theme = Theme.of(context);
          final status = _statusFor(device);
          final connectionId = device.activeConnection?.id ?? '';
          final subtitle = connectionId.isEmpty
              ? device.deviceType.name
              : '${device.deviceType.name} · $connectionId';
          return Card(
            margin:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(12.0),
              onTap: onConfigure,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_iconFromType(device.deviceType),
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.interface,
                                  style: theme.textTheme.titleLarge),
                              Text(subtitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        PaneStatusChip(status: status),
                        if (onDeleteBond != null)
                          PopupMenuButton<String>(
                            tooltip: 'Bond actions',
                            onSelected: (value) {
                              if (value == 'delete') onDeleteBond!();
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete bond')),
                            ],
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.settings),
                            tooltip: 'Configure IPv4',
                            onPressed: onConfigure,
                          ),
                      ],
                    ),
                    if (_details().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 24,
                        runSpacing: 8,
                        children: [
                          for (final (label, value) in _details())
                            _InfoItem(label: label, value: value),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        });
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// IPv4 form fields (shared by the interface dialog and the bond dialog)
// ---------------------------------------------------------------------------

class Ipv4FormControllers {
  final ip = TextEditingController();
  final netmask = TextEditingController();
  final gateway = TextEditingController();
  final dns = TextEditingController();

  void dispose() {
    ip.dispose();
    netmask.dispose();
    gateway.dispose();
    dns.dispose();
  }

  /// Builds the `ipv4` settings section from the current field state. Only
  /// valid after the enclosing [Form] validated.
  Map<String, DBusValue> toSection({required bool isDhcp}) {
    if (isDhcp) return ipv4AutoSection();
    return ipv4ManualSection(
      address: ip.text.trim(),
      prefix: parsePrefixOrNetmask(netmask.text)!,
      gateway: gateway.text.trim(),
      dnsServers: splitDnsServers(dns.text),
    );
  }
}

class Ipv4MethodFields extends StatelessWidget {
  final bool isDhcp;
  final ValueChanged<bool> onMethodChanged;
  final Ipv4FormControllers controllers;

  const Ipv4MethodFields({
    super.key,
    required this.isDhcp,
    required this.onMethodChanged,
    required this.controllers,
  });

  static String? _validateIp(String? value) {
    final text = value?.trim() ?? '';
    if (!isValidIpv4(text)) return 'Enter a valid IPv4 address';
    return null;
  }

  static String? _validateNetmask(String? value) {
    final prefix = parsePrefixOrNetmask(value ?? '');
    if (prefix == null || prefix < 1 || prefix > 32) {
      return 'Enter a netmask (255.255.0.0) or prefix (/16)';
    }
    return null;
  }

  static String? _validateGateway(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (!isValidIpv4(text)) return 'Enter a valid IPv4 address';
    return null;
  }

  static String? _validateDns(String? value) {
    for (final server in splitDnsServers(value ?? '')) {
      if (!isValidIpv4(server)) return 'Invalid DNS server: $server';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          title: const Text('Use DHCP'),
          subtitle:
              const Text('Obtain address automatically from the network'),
          value: isDhcp,
          onChanged: onMethodChanged,
        ),
        if (!isDhcp) ...[
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'IP Address',
              hintText: '192.0.2.10',
            ),
            controller: controllers.ip,
            validator: _validateIp,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          const SizedBox(height: 10),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Netmask or prefix',
              hintText: '255.255.255.0 or /24',
            ),
            controller: controllers.netmask,
            validator: _validateNetmask,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          const SizedBox(height: 10),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Gateway (optional)',
              hintText: '192.0.2.1',
            ),
            controller: controllers.gateway,
            validator: _validateGateway,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          const SizedBox(height: 10),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'DNS servers (comma separated)',
              hintText: '192.0.2.53, 8.8.8.8',
            ),
            controller: controllers.dns,
            validator: _validateDns,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Interface settings dialog
// ---------------------------------------------------------------------------

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
  final _formKey = GlobalKey<FormState>();
  final _controllers = Ipv4FormControllers();

  NetworkManagerActiveConnection? _activeConnection;
  bool _isDhcp = true;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadConnectionSettings();
  }

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  Future<void> _loadConnectionSettings() async {
    try {
      _activeConnection = widget.device.activeConnection;

      // Prefill from the live lease/config so a DHCP → static switch starts
      // from the address the device already has.
      final ip4Config =
          _activeConnection?.ip4Config ?? widget.device.ip4Config;
      if (ip4Config != null) {
        if (ip4Config.addressData.isNotEmpty) {
          final first = ip4Config.addressData.first;
          _controllers.ip.text = '${first['address']}';
          _controllers.netmask.text =
              prefixToNetmask(first['prefix'] as int);
        }
        _controllers.gateway.text = ip4Config.gateway;
        _controllers.dns.text =
            ip4Config.nameserverData.map((e) => e['address']).join(', ');
      }

      // The configured method comes from the connection profile — presence
      // of a DHCP lease is only a fallback (a static profile on a network
      // with a rogue DHCP server must still read as static).
      // A port without any connection yet starts from DHCP.
      var isDhcp =
          _activeConnection == null || widget.device.dhcp4Config != null;
      final connection = _activeConnection?.connection;
      if (connection != null) {
        final settings = await connection.getSettings();
        final method = settings['ipv4']?['method']?.asString();
        if (method != null) isDhcp = method == 'auto';
      }

      if (!mounted) return;
      setState(() {
        _isDhcp = isDhcp;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load connection settings: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_isDhcp && !(_formKey.currentState?.validate() ?? false)) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final ipv4Section = _controllers.toSection(isDhcp: _isDhcp);
      final activeConnection = _activeConnection;
      final connection = activeConnection?.connection;
      if (activeConnection != null && connection != null) {
        final updatedSettings = await connection.getSettings();
        updatedSettings['ipv4'] = ipv4Section;
        await connection.update(updatedSettings);

        // Bounce the connection so the new addressing takes effect.
        await widget.nmClient.deactivateConnection(activeConnection);
        await widget.nmClient.activateConnection(
            device: widget.device, connection: connection);
      } else if (widget.device.deviceType ==
          NetworkManagerDeviceType.ethernet) {
        // Port has no connection profile yet — create one.
        await widget.nmClient.addAndActivateConnection(
          device: widget.device,
          connection: {
            'connection': {
              'id': DBusString(widget.device.interface),
              'uuid': DBusString(generateUuid()),
              'type': const DBusString('802-3-ethernet'),
              'interface-name': DBusString(widget.device.interface),
              'autoconnect': const DBusBoolean(true),
            },
            'ipv4': ipv4Section,
          },
        );
      } else {
        throw Exception(
            'No active connection on ${widget.device.interface}');
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to save settings: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content;
    if (_isLoading) {
      content = const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final creatingNew = _activeConnection == null;
      content = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Settings — ${widget.device.interface}',
                    style: theme.textTheme.titleLarge),
                if (creatingNew) ...[
                  const SizedBox(height: 12),
                  Text(
                    'This interface has no active connection. Saving '
                    'creates a new connection profile.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 8),
                Ipv4MethodFields(
                  isDhcp: _isDhcp,
                  onMethodChanged: (value) =>
                      setState(() => _isDhcp = value),
                  controllers: _controllers,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: content,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bond creation dialog
// ---------------------------------------------------------------------------

/// Creates an active-backup (mode 1) bond from two or more ethernet ports.
/// One member carries traffic; on link loss NetworkManager fails over to a
/// backup within `miimon` (100 ms) — no switch-side LACP needed.
class CreateBondDialog extends StatefulWidget {
  final NetworkManagerClient nmClient;

  const CreateBondDialog({super.key, required this.nmClient});

  @override
  State<CreateBondDialog> createState() => _CreateBondDialogState();
}

class _CreateBondDialogState extends State<CreateBondDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'bond0');
  final _controllers = Ipv4FormControllers();
  final Set<String> _selectedMembers = {};
  String? _primaryMember;
  bool _isDhcp = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _controllers.dispose();
    super.dispose();
  }

  List<NetworkManagerDevice> get _ethernetDevices => widget.nmClient.devices
      .where(
          (device) => device.deviceType == NetworkManagerDeviceType.ethernet)
      .toList()
    ..sort((a, b) => a.interface.compareTo(b.interface));

  String? _validateBondName(String? value) {
    final text = value?.trim() ?? '';
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,14}$').hasMatch(text)) {
      return 'Interface name, e.g. bond0';
    }
    if (widget.nmClient.devices.any((d) => d.interface == text)) {
      return 'An interface named $text already exists';
    }
    return null;
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedMembers.length < 2) {
      setState(() => _errorMessage =
          'Select at least two member ports (active + backup)');
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final bondName = _nameController.text.trim();
    try {
      await widget.nmClient.settings.addConnection(bondMasterSettings(
        bondName: bondName,
        uuid: generateUuid(),
        primaryMember: _primaryMember,
        ipv4Section: _controllers.toSection(isDhcp: _isDhcp),
      ));

      // Activating a member pulls the bond master up with it, so no
      // device-less master activation (which D-Bus cannot express) needed.
      final members = _ethernetDevices
          .where((device) => _selectedMembers.contains(device.interface));
      for (final member in members) {
        final memberConnection =
            await widget.nmClient.settings.addConnection(bondMemberSettings(
          memberInterface: member.interface,
          bondName: bondName,
          uuid: generateUuid(),
        ));
        await widget.nmClient.activateConnection(
            device: member, connection: memberConnection);
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Bond $bondName created')),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Failed to create bond: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _ethernetDevices;
    return Dialog(
      insetPadding: const EdgeInsets.all(16.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Create bond', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Active-backup (mode 1): one port carries traffic, the '
                    'others take over when its link drops.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration:
                        const InputDecoration(labelText: 'Bond name'),
                    controller: _nameController,
                    validator: _validateBondName,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: 12),
                  Text('Member ports', style: theme.textTheme.titleSmall),
                  for (final device in devices)
                    CheckboxListTile(
                      dense: true,
                      title: Text(device.interface),
                      subtitle: Text(device.hwAddress),
                      value: _selectedMembers.contains(device.interface),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedMembers.add(device.interface);
                          } else {
                            _selectedMembers.remove(device.interface);
                            if (_primaryMember == device.interface) {
                              _primaryMember = null;
                            }
                          }
                        });
                      },
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    // The member set defines the item list; rebuilding on a
                    // membership change drops a primary that was unchecked
                    // (a stale selection here is a hard assert).
                    key: ValueKey((_selectedMembers.toList()..sort()).join()),
                    initialValue: _primaryMember,
                    decoration: const InputDecoration(
                      labelText: 'Primary port',
                      helperText:
                          'Preferred active port; automatic when unset',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Automatic')),
                      for (final member in _selectedMembers.toList()..sort())
                        DropdownMenuItem<String?>(
                            value: member, child: Text(member)),
                    ],
                    onChanged: (value) =>
                        setState(() => _primaryMember = value),
                  ),
                  const SizedBox(height: 8),
                  Ipv4MethodFields(
                    isDhcp: _isDhcp,
                    onMethodChanged: (value) =>
                        setState(() => _isDhcp = value),
                    controllers: _controllers,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _isSaving ? null : _create,
                        child: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Create'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
