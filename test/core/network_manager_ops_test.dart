import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/network_manager_ops.dart';

import '../helpers/fake_network_manager.dart';

Object? _nothing() => null;

/// What `nm` 0.5.0 throws when the object path NetworkManager returned is not
/// in the client's cache yet: `_getConnection(path)!`.
Object get _nullCheckFailure {
  try {
    return _nothing()!;
  } catch (e) {
    return e;
  }
}

Map<String, Map<String, DBusValue>> _ethernetProfile({
  required String id,
  required String uuid,
  String interfaceName = 'eth0',
  String method = 'auto',
  String address = '',
  int prefix = 24,
  String gateway = '',
  List<String> dns = const [],
}) {
  return {
    'connection': {
      'id': DBusString(id),
      'uuid': DBusString(uuid),
      'type': const DBusString('802-3-ethernet'),
      'interface-name': DBusString(interfaceName),
    },
    'ipv4': {
      'method': DBusString(method),
      if (address.isNotEmpty)
        'address-data': DBusArray(DBusSignature('a{sv}'), [
          DBusDict(DBusSignature('s'), DBusSignature('v'), {
            const DBusString('address'): DBusVariant(DBusString(address)),
            const DBusString('prefix'): DBusVariant(DBusUint32(prefix)),
          })
        ]),
      if (gateway.isNotEmpty) 'gateway': DBusString(gateway),
      if (dns.isNotEmpty)
        'dns-data': DBusArray(
            DBusSignature('s'), dns.map((s) => DBusString(s)).toList()),
    },
  };
}

void main() {
  test('the null-check failure really is a TypeError', () {
    expect(_nullCheckFailure, isA<TypeError>(),
        reason: 'the recovery paths below catch exactly this');
  });

  group('addConnectionResilient', () {
    test('returns the connection when the add succeeds', () async {
      final client = FakeNetworkManagerClient();
      final settings = _ethernetProfile(id: 'bond0', uuid: 'uuid-1');

      final connection = await addConnectionResilient(client, settings);

      expect((connection as FakeSettingsConnection).id, 'bond0');
      expect(client.fakeSettings.addedConnections.single, settings);
    });

    test('recovers the connection by UUID when nm loses the cache race',
        () async {
      final client = FakeNetworkManagerClient();
      client.fakeSettings.addConnectionError = _nullCheckFailure;
      final settings = _ethernetProfile(id: 'bond0-eth1', uuid: 'uuid-2');

      final connection = await addConnectionResilient(client, settings,
          retryDelay: Duration.zero);

      expect((connection as FakeSettingsConnection).id, 'bond0-eth1',
          reason: 'NetworkManager committed it; only the wrapper was lost');
    });

    test('rethrows when the connection really was not created', () async {
      final client = FakeNetworkManagerClient();
      client.fakeSettings
        ..addConnectionError = _nullCheckFailure
        ..commitOnError = false;

      await expectLater(
        addConnectionResilient(
            client, _ethernetProfile(id: 'bond0', uuid: 'uuid-3'),
            attempts: 2, retryDelay: Duration.zero),
        throwsA(isA<TypeError>()),
      );
    });

    test('rethrows a real NetworkManager rejection untouched', () async {
      final client = FakeNetworkManagerClient();
      client.fakeSettings.addConnectionError =
          Exception('Not authorized to add a connection');

      await expectLater(
        addConnectionResilient(
            client, _ethernetProfile(id: 'bond0', uuid: 'uuid-4')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('activateConnectionResilient', () {
    test('swallows the cache race, since the wrapper is unused', () async {
      final client = FakeNetworkManagerClient(activateError: _nullCheckFailure);
      final device = FakeNetworkManagerDevice(interface: 'eth1');

      await activateConnectionResilient(client, device: device);

      expect(client.activations, [('eth1', null)],
          reason: 'NetworkManager still got the call');
    });

    test('lets a real failure through', () async {
      final client = FakeNetworkManagerClient(
          activateError: Exception('Connection not available on device'));

      await expectLater(
        activateConnectionResilient(client,
            device: FakeNetworkManagerDevice(interface: 'eth1')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('lookups', () {
    test('findConnectionForInterface matches on interface-name', () async {
      final eth0 = FakeSettingsConnection(
          id: 'Wired 1', settings: _ethernetProfile(id: 'Wired 1', uuid: 'a'));
      final eno1 = FakeSettingsConnection(
          id: 'Wired 2',
          settings: _ethernetProfile(
              id: 'Wired 2', uuid: 'b', interfaceName: 'eno1'));
      final client = FakeNetworkManagerClient(
          settings: FakeNetworkManagerSettings(connections: [eth0, eno1]));

      expect(await findConnectionForInterface(client, 'eno1'), same(eno1));
      expect(await findConnectionForInterface(client, 'eth9'), isNull);
    });

    test('findConnectionByUuid gives up after its attempts', () async {
      final client = FakeNetworkManagerClient();
      expect(
        await findConnectionByUuid(client, 'missing',
            attempts: 2, retryDelay: Duration.zero),
        isNull,
      );
    });
  });

  group('loadSavedConnections', () {
    test('resolves the fields the page shows and drops other types', () async {
      final client = FakeNetworkManagerClient(
        settings: FakeNetworkManagerSettings(connections: [
          FakeSettingsConnection(
              settings: _ethernetProfile(
            id: 'Wired connection 1',
            uuid: 'bb1eae34',
            interfaceName: 'eno1',
            method: 'manual',
            address: '10.50.10.11',
            gateway: '10.50.10.1',
            dns: ['10.50.10.1', '1.1.1.1'],
          )),
          FakeSettingsConnection(settings: {
            'connection': {
              'id': const DBusString('docker0'),
              'type': const DBusString('bridge'),
            },
          }),
        ]),
      );

      final saved = await loadSavedConnections(client);

      expect(saved, hasLength(1), reason: 'a bridge is not ours to edit');
      final wired = saved.single;
      expect(wired.id, 'Wired connection 1');
      expect(wired.uuid, 'bb1eae34');
      expect(wired.typeLabel, 'ethernet');
      expect(wired.interfaceName, 'eno1');
      expect(wired.ipv4.isDhcp, isFalse);
      expect(wired.ipv4.address, '10.50.10.11');
      expect(wired.ipv4.netmask, '255.255.255.0');
      expect(wired.ipv4.gateway, '10.50.10.1');
      expect(wired.ipv4.dns, '10.50.10.1, 1.1.1.1');
      expect(wired.ipv4.summary, '10.50.10.11/24');
    });

    test('sorts by name and skips unreadable profiles', () async {
      final client = FakeNetworkManagerClient(
        settings: FakeNetworkManagerSettings(connections: [
          FakeSettingsConnection(
              settings: _ethernetProfile(id: 'zeta', uuid: 'z')),
          FakeSettingsConnection(getSettingsError: Exception('deleted')),
          FakeSettingsConnection(
              settings: _ethernetProfile(id: 'alpha', uuid: 'a')),
        ]),
      );

      expect((await loadSavedConnections(client)).map((s) => s.id),
          ['alpha', 'zeta']);
    });
  });
}
