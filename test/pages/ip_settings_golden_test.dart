/// Golden images of the IP settings page, for design review and PR
/// descriptions.
///
/// Frames: the device overview (ethernet static, wifi DHCP, a dead port),
/// a bond with its member ports, the interface dialog prefilled with a
/// static config, its inline validation error, and the create-bond dialog.
///
/// To update: flutter test test/pages/ip_settings_golden_test.dart --update-goldens --run-skipped
@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm/nm.dart';
import 'package:tfc/pages/ip_settings.dart';

import '../helpers/fake_network_manager.dart';
import '../helpers/test_helpers.dart';

/// Tall enough for four device cards; wide enough for the details wrap to
/// stay on one or two rows per card.
const Size _viewport = Size(900, 720);

Widget _buildPage(FakeNetworkManagerClient client) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: IpSettingsBody(client: client)),
  );
}

Future<void> _pumpPage(
    WidgetTester tester, FakeNetworkManagerClient client) async {
  await tester.binding.setSurfaceSize(_viewport);
  // 1:1 pixels — these goldens are for reading, not for pixel archaeology.
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await pumpAndLoad(tester, _buildPage(client));
}

Future<void> _expectGolden(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name'));

FakeNetworkManagerDevice _staticEthernet() => FakeNetworkManagerDevice(
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
        connection: FakeSettingsConnection(id: 'Wired connection 1', settings: {
          'connection': {'id': const DBusString('Wired connection 1')},
          'ipv4': {'method': const DBusString('manual')},
        }),
      ),
    );

FakeNetworkManagerClient _overviewClient() => FakeNetworkManagerClient(
      devices: [
        _staticEthernet(),
        FakeNetworkManagerDevice(
          interface: 'eth1',
          hwAddress: '00:0A:95:9D:68:17',
          state: NetworkManagerDeviceState.unavailable,
          wired: FakeDeviceWired(),
        ),
        FakeNetworkManagerDevice(
          interface: 'wlan0',
          deviceType: NetworkManagerDeviceType.wifi,
          hwAddress: '48:2A:E3:11:22:33',
          mtu: 1500,
          dhcp4Config: FakeDhcp4Config(),
          ip4Config: FakeIp4Config(
            addressData: [
              {'address': '192.168.1.50', 'prefix': 24},
            ],
            gateway: '192.168.1.1',
            nameserverData: [
              {'address': '192.168.1.1'},
            ],
          ),
          wireless: FakeDeviceWireless(
            activeAccessPoint:
                FakeAccessPoint(ssidText: 'PlantNet', strength: 78),
          ),
          activeConnection: FakeActiveConnection(id: 'PlantNet'),
        ),
      ],
    );

FakeNetworkManagerClient _bondClient() {
  final bond = FakeNetworkManagerDevice(
    interface: 'bond0',
    deviceType: NetworkManagerDeviceType.bond,
    hwAddress: '00:0A:95:9D:68:16',
    mtu: 1500,
    ip4Config: FakeIp4Config(
      addressData: [
        {'address': '10.104.29.20', 'prefix': 24},
      ],
      gateway: '10.104.29.1',
      nameserverData: [
        {'address': '10.104.1.1'},
      ],
    ),
    activeConnection: FakeActiveConnection(id: 'bond0'),
  );
  FakeNetworkManagerDevice member(String name, String mac) =>
      FakeNetworkManagerDevice(
        interface: name,
        hwAddress: mac,
        wired: FakeDeviceWired(speed: 1000),
        activeConnection:
            FakeActiveConnection(id: 'bond0-$name', master: bond),
      );
  return FakeNetworkManagerClient(devices: [
    bond,
    member('eth0', '00:0A:95:9D:68:16'),
    member('eth1', '00:0A:95:9D:68:17'),
  ]);
}

// ---------------------------------------------------------------------------
// Fonts — see server_config_reorder_golden_test.dart for the why.
// ---------------------------------------------------------------------------

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
        .load();
  }

  await load('Roboto', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await load('MaterialIcons',
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  }

  final faRoot = _packageRoot('font_awesome_flutter');
  if (faRoot != null) {
    await load('packages/font_awesome_flutter/FontAwesomeSolid',
        '$faRoot/lib/fonts/Font-Awesome-7-Free-Solid-900.otf');
    await load('packages/font_awesome_flutter/FontAwesomeRegular',
        '$faRoot/lib/fonts/Font-Awesome-7-Free-Regular-400.otf');
  }
}

String? _packageRoot(String package) {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final packages = (jsonDecode(config.readAsStringSync())
      as Map<String, dynamic>)['packages'] as List<dynamic>;
  for (final entry in packages.cast<Map<String, dynamic>>()) {
    if (entry['name'] == package) {
      return Uri.parse(entry['rootUri'] as String).toFilePath();
    }
  }
  return null;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('overview — ethernet static, dead port, wifi DHCP',
      (tester) async {
    await _pumpPage(tester, _overviewClient());
    await _expectGolden(tester, 'ip_settings_overview.png');
  });

  testWidgets('bond — master card with member ports', (tester) async {
    await _pumpPage(tester, _bondClient());
    await _expectGolden(tester, 'ip_settings_bond.png');
  });

  testWidgets('interface dialog — static config prefilled', (tester) async {
    await _pumpPage(tester, _overviewClient());
    await tester.tap(find.text('eth0'));
    await settle(tester);
    await _expectGolden(tester, 'ip_settings_dialog_static.png');
  });

  testWidgets('interface dialog — inline netmask error', (tester) async {
    await _pumpPage(tester, _overviewClient());
    await tester.tap(find.text('eth0'));
    await settle(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Netmask or prefix'),
        '255.0.255.0');
    await tester.tap(find.text('Save'));
    await settle(tester);
    await _expectGolden(tester, 'ip_settings_dialog_error.png');
  });

  testWidgets('create-bond dialog — two members, primary chosen',
      (tester) async {
    await _pumpPage(tester, _overviewClient());
    await tester.tap(find.text('Create bond'));
    await settle(tester);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'eth0'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'eth1'));
    await settle(tester);
    await tester.tap(find.text('Automatic'));
    await settle(tester);
    await tester.tap(find.text('eth0').last);
    await settle(tester);

    await _expectGolden(tester, 'ip_settings_bond_dialog.png');
  });
}
