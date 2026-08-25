import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm/nm.dart';
import 'package:tfc/pages/ip_settings.dart';

import '../helpers/fake_network_manager.dart';
import '../helpers/test_helpers.dart';

Widget _buildPage(FakeNetworkManagerClient client) {
  return MaterialApp(
    home: Scaffold(body: IpSettingsBody(client: client)),
  );
}

FakeNetworkManagerDevice _staticEthernet({
  FakeSettingsConnection? connection,
}) {
  return FakeNetworkManagerDevice(
    interface: 'eth0',
    hwAddress: '00:0A:95:9D:68:16',
    mtu: 1500,
    wired: FakeDeviceWired(speed: 1000),
    ip4Config: FakeIp4Config(
      addressData: [
        {'address': '10.104.29.10', 'prefix': 24},
      ],
      gateway: '10.104.29.1',
      nameserverData: [
        {'address': '10.104.1.1'},
      ],
    ),
    activeConnection: FakeActiveConnection(
      id: 'Wired connection 1',
      connection: connection ??
          FakeSettingsConnection(id: 'Wired connection 1', settings: {
            'connection': {'id': const DBusString('Wired connection 1')},
            'ipv4': {'method': const DBusString('manual')},
          }),
    ),
  );
}

void main() {
  testWidgets('device card shows live addressing details', (tester) async {
    final client = FakeNetworkManagerClient(devices: [_staticEthernet()]);
    await pumpAndLoad(tester, _buildPage(client));

    expect(find.text('eth0'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('10.104.29.10/24'), findsOneWidget);
    expect(find.text('Static'), findsOneWidget);
    expect(find.text('10.104.29.1'), findsOneWidget);
    expect(find.text('10.104.1.1'), findsOneWidget);
    expect(find.text('00:0A:95:9D:68:16'), findsOneWidget);
    expect(find.text('1000 Mb/s'), findsOneWidget);
    expect(find.textContaining('Wired connection 1'), findsOneWidget);
  });

  testWidgets('wifi card shows SSID, signal and DHCP method', (tester) async {
    final client = FakeNetworkManagerClient(devices: [
      FakeNetworkManagerDevice(
        interface: 'wlan0',
        deviceType: NetworkManagerDeviceType.wifi,
        dhcp4Config: FakeDhcp4Config(),
        ip4Config: FakeIp4Config(addressData: [
          {'address': '192.168.1.50', 'prefix': 24},
        ]),
        wireless: FakeDeviceWireless(
          activeAccessPoint: FakeAccessPoint(ssidText: 'PlantNet', strength: 78),
        ),
      ),
    ]);
    await pumpAndLoad(tester, _buildPage(client));

    expect(find.text('PlantNet'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    expect(find.text('DHCP'), findsOneWidget);
  });

  testWidgets('disconnected and no-link devices read as such', (tester) async {
    final client = FakeNetworkManagerClient(devices: [
      FakeNetworkManagerDevice(
          interface: 'eth1',
          state: NetworkManagerDeviceState.disconnected),
      FakeNetworkManagerDevice(
          interface: 'eth2',
          state: NetworkManagerDeviceState.unavailable),
    ]);
    await pumpAndLoad(tester, _buildPage(client));

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('No link'), findsOneWidget);
  });

  testWidgets('bond card lists its member ports', (tester) async {
    final bond = FakeNetworkManagerDevice(
      interface: 'bond0',
      deviceType: NetworkManagerDeviceType.bond,
      ip4Config: FakeIp4Config(addressData: [
        {'address': '10.104.29.20', 'prefix': 24},
      ]),
    );
    final client = FakeNetworkManagerClient(devices: [
      bond,
      FakeNetworkManagerDevice(
          interface: 'eth0',
          activeConnection: FakeActiveConnection(master: bond)),
      FakeNetworkManagerDevice(
          interface: 'eth1',
          activeConnection: FakeActiveConnection(master: bond)),
    ]);
    await pumpAndLoad(tester, _buildPage(client));

    expect(find.text('eth0, eth1'), findsOneWidget);
    expect(find.text('active-backup'), findsOneWidget);
  });

  testWidgets('create-bond button needs two ethernet ports', (tester) async {
    final client = FakeNetworkManagerClient(
        devices: [FakeNetworkManagerDevice(interface: 'eth0')]);
    await pumpAndLoad(tester, _buildPage(client));

    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create bond'));
    expect(button.onPressed, isNull);
  });

  testWidgets('interface dialog prefills the static config', (tester) async {
    final client = FakeNetworkManagerClient(devices: [_staticEthernet()]);
    await pumpAndLoad(tester, _buildPage(client));

    await tester.tap(find.text('eth0'));
    await settle(tester);

    expect(find.text('Settings — eth0'), findsOneWidget);
    final dhcpSwitch =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(dhcpSwitch.value, isFalse, reason: 'profile method is manual');
    expect(find.widgetWithText(TextFormField, '10.104.29.10'), findsOneWidget);
    expect(
        find.widgetWithText(TextFormField, '255.255.255.0'), findsOneWidget);
  });

  testWidgets('an invalid netmask blocks saving with an inline error',
      (tester) async {
    final connection = FakeSettingsConnection(id: 'Wired connection 1',
        settings: {
          'ipv4': {'method': const DBusString('manual')},
        });
    final client = FakeNetworkManagerClient(
        devices: [_staticEthernet(connection: connection)]);
    await pumpAndLoad(tester, _buildPage(client));

    await tester.tap(find.text('eth0'));
    await settle(tester);

    // The old page accepted only 255.255.255.x masks; the new field takes
    // any contiguous mask but must still reject a non-contiguous one.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Netmask or prefix'),
        '255.0.255.0');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.textContaining('Enter a netmask'), findsOneWidget);
    expect(connection.updates, isEmpty);
  });

  testWidgets('saving static settings updates and bounces the connection',
      (tester) async {
    final connection = FakeSettingsConnection(id: 'Wired connection 1',
        settings: {
          'connection': {'id': const DBusString('Wired connection 1')},
          'ipv4': {'method': const DBusString('manual')},
        });
    final client = FakeNetworkManagerClient(
        devices: [_staticEthernet(connection: connection)]);
    await pumpAndLoad(tester, _buildPage(client));

    await tester.tap(find.text('eth0'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Netmask or prefix'), '/16');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Settings — eth0'), findsNothing,
        reason: 'dialog closes on success');
    final ipv4 = connection.updates.single['ipv4']!;
    expect(ipv4['method'], const DBusString('manual'));
    final entry =
        (ipv4['address-data'] as DBusArray).children.single as DBusDict;
    expect(entry.children[const DBusString('prefix')],
        const DBusVariant(DBusUint32(16)));
    expect(
        connection.updates.single['connection']?['id']?.asString(),
        'Wired connection 1',
        reason: 'non-ipv4 sections survive the update');
    expect(client.deactivations, hasLength(1));
    expect(client.activations, [('eth0', 'Wired connection 1')]);
  });

  testWidgets('a port with no connection profile creates one on save',
      (tester) async {
    final client = FakeNetworkManagerClient(devices: [
      FakeNetworkManagerDevice(
          interface: 'eth3',
          state: NetworkManagerDeviceState.disconnected),
    ]);
    await pumpAndLoad(tester, _buildPage(client));

    await tester.tap(find.text('eth3'));
    await settle(tester);

    expect(find.textContaining('no active connection'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);

    final added = client.addAndActivated.single;
    expect(added['connection']?['interface-name'], const DBusString('eth3'));
    expect(added['ipv4']?['method'], const DBusString('auto'));
  });

  testWidgets('bond creation adds master plus members and activates them',
      (tester) async {
    final client = FakeNetworkManagerClient(devices: [
      FakeNetworkManagerDevice(interface: 'eth0'),
      FakeNetworkManagerDevice(interface: 'eth1'),
    ]);
    await pumpAndLoad(tester, _buildPage(client));

    await tester.tap(find.text('Create bond'));
    await settle(tester);

    // Fewer than two members is refused.
    final createButton = find.widgetWithText(FilledButton, 'Create');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await settle(tester);
    expect(find.textContaining('at least two member ports'), findsOneWidget);
    expect(client.fakeSettings.addedConnections, isEmpty);

    await tester.ensureVisible(find.widgetWithText(CheckboxListTile, 'eth0'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'eth0'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'eth1'));
    await settle(tester);
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await settle(tester);

    final added = client.fakeSettings.addedConnections;
    expect(added, hasLength(3));
    final master = added.first;
    expect(master['connection']?['type'], const DBusString('bond'));
    final options = master['bond']?['options'] as DBusDict;
    expect(options.children[const DBusString('mode')],
        const DBusString('active-backup'));
    for (final member in added.skip(1)) {
      expect(member['connection']?['master'], const DBusString('bond0'));
      expect(member['connection']?['slave-type'], const DBusString('bond'));
    }
    expect(client.activations, [('eth0', 'bond0-eth0'), ('eth1', 'bond0-eth1')]);
  });

  testWidgets('deleting a bond removes its master and member profiles',
      (tester) async {
    final bondConnection = FakeSettingsConnection(id: 'bond0', settings: {
      'connection': {'interface-name': const DBusString('bond0')},
    });
    final memberConnection =
        FakeSettingsConnection(id: 'bond0-eth0', settings: {
      'connection': {
        'interface-name': const DBusString('eth0'),
        'master': const DBusString('bond0'),
      },
    });
    final unrelatedConnection =
        FakeSettingsConnection(id: 'wifi', settings: {
      'connection': {'interface-name': const DBusString('wlan0')},
    });
    final client = FakeNetworkManagerClient(
      devices: [
        FakeNetworkManagerDevice(
            interface: 'bond0',
            deviceType: NetworkManagerDeviceType.bond),
        FakeNetworkManagerDevice(interface: 'eth0'),
        FakeNetworkManagerDevice(interface: 'eth1'),
      ],
      settings: FakeNetworkManagerSettings(connections: [
        bondConnection,
        memberConnection,
        unrelatedConnection,
      ]),
    );
    await pumpAndLoad(tester, _buildPage(client));

    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester);
    await tester.tap(find.text('Delete bond'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(bondConnection.deleted, isTrue);
    expect(memberConnection.deleted, isTrue);
    expect(unrelatedConnection.deleted, isFalse);
  });
}
