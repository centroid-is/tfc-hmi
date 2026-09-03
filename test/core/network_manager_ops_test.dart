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

  group('validateConnectionName', () {
    test('rejects an empty or whitespace-only name', () {
      expect(validateConnectionName(''), 'Name cannot be empty');
      expect(validateConnectionName('   '), 'Name cannot be empty');
    });

    test('rejects a name another profile already uses', () {
      expect(
        validateConnectionName('bond0', existingIds: ['bond0', 'eno1']),
        contains('already called'),
      );
    });

    test('accepts keeping the current name unchanged', () {
      // Re-saving a dialog without touching the field must not error.
      expect(
        validateConnectionName('bond0',
            currentId: 'bond0', existingIds: ['bond0']),
        isNull,
      );
    });

    test('accepts a new, unused name', () {
      expect(
        validateConnectionName('Plant bond',
            currentId: 'bond0', existingIds: ['bond0', 'eno1']),
        isNull,
      );
    });

    test('trims before comparing', () {
      expect(
        validateConnectionName('  eno1  ', existingIds: ['eno1']),
        contains('already called'),
      );
    });
  });

  group('renameConnection', () {
    test('changes the id and nothing else', () async {
      final connection = FakeSettingsConnection(
        settings: _ethernetProfile(
            id: 'bond0', uuid: 'u1', interfaceName: 'bond0', method: 'manual',
            address: '10.50.10.11', gateway: '10.50.10.1'),
      );

      await renameConnection(connection, 'Plant bond');

      final written = connection.updates.single;
      expect(written['connection']!['id']!.asString(), 'Plant bond');
      expect(written['connection']!['uuid']!.asString(), 'u1');
      expect(written['ipv4']!['method']!.asString(), 'manual');
      expect(written['ipv4']!['gateway']!.asString(), '10.50.10.1');
    });

    test('leaves interface-name alone', () async {
      // The whole point of renaming the profile rather than the interface:
      // bond0 must still bind to the bond0 device afterwards.
      final connection = FakeSettingsConnection(
        settings: _ethernetProfile(
            id: 'bond0', uuid: 'u1', interfaceName: 'bond0'),
      );

      await renameConnection(connection, 'Plant bond');

      expect(connection.updates.single['connection']!['interface-name']!
          .asString(), 'bond0');
    });

    test('trims the new name', () async {
      final connection = FakeSettingsConnection(
        settings: _ethernetProfile(id: 'a', uuid: 'u'),
      );
      await renameConnection(connection, '  Renamed  ');
      expect(connection.updates.single['connection']!['id']!.asString(),
          'Renamed');
    });

    test('refuses an empty name instead of writing one', () async {
      final connection = FakeSettingsConnection(
        settings: _ethernetProfile(id: 'a', uuid: 'u'),
      );
      await expectLater(
          renameConnection(connection, '  '), throwsArgumentError);
      expect(connection.updates, isEmpty);
    });

    test('does not wipe the wifi PSK', () async {
      // GetSettings blanks secrets and Update replaces the whole profile, so
      // a naive round-trip drops the key and takes the station off the air.
      final connection = FakeSettingsConnection(
        settings: {
          'connection': {
            'id': const DBusString('plant-wifi'),
            'uuid': const DBusString('u1'),
            'type': const DBusString('802-11-wireless'),
          },
          '802-11-wireless-security': {
            'key-mgmt': const DBusString('wpa-psk'),
          },
        },
        secrets: {
          '802-11-wireless-security': {'psk': const DBusString('hunter2')},
        },
      );

      await renameConnection(connection, 'Plant wifi');

      final written = connection.updates.single;
      expect(written['802-11-wireless-security']!['psk']!.asString(),
          'hunter2');
      expect(written['802-11-wireless-security']!['key-mgmt']!.asString(),
          'wpa-psk');
      expect(connection.secretRequests, ['802-11-wireless-security']);
    });

    test('does not ask for secrets a profile cannot have', () async {
      final connection = FakeSettingsConnection(
        settings: _ethernetProfile(id: 'a', uuid: 'u'),
      );
      await renameConnection(connection, 'b');
      expect(connection.secretRequests, isEmpty,
          reason: 'ethernet carries no secret-bearing section');
    });

    test('still renames when the secrets are unreadable', () async {
      final connection = FakeSettingsConnection(
        settings: {
          'connection': {'id': const DBusString('w'), 'uuid': const DBusString('u')},
          '802-11-wireless-security': {'key-mgmt': const DBusString('wpa-psk')},
        },
        getSecretsError: Exception('not authorized'),
      );

      await renameConnection(connection, 'Renamed');

      expect(connection.updates.single['connection']!['id']!.asString(),
          'Renamed');
    });
  });

  group('connectionsRemovedWith', () {
    FakeSettingsConnection bond({String id = 'bond0', String uuid = 'b1'}) =>
        FakeSettingsConnection(settings: {
          'connection': {
            'id': DBusString(id),
            'uuid': DBusString(uuid),
            'type': const DBusString('bond'),
            'interface-name': const DBusString('bond0'),
          },
        });

    FakeSettingsConnection member(String id, String master) =>
        FakeSettingsConnection(settings: {
          'connection': {
            'id': DBusString(id),
            'uuid': DBusString('m-$id'),
            'type': const DBusString('802-3-ethernet'),
            'master': DBusString(master),
          },
        });

    test('takes the bond members with the bond', () async {
      // Leaving members enslaved to a bond that no longer exists keeps the
      // ports down, which looks like the delete broke the network.
      final master = bond();
      final byInterface = member('port1', 'bond0');
      final byUuid = member('port2', 'b1');
      final unrelated = member('other', 'bond1');
      final client = FakeNetworkManagerClient(
        settings: FakeNetworkManagerSettings(
            connections: [master, byInterface, byUuid, unrelated]),
      );

      final removed = await connectionsRemovedWith(client, master);

      expect(removed.first, same(master), reason: 'the target comes first');
      expect(removed, containsAll([byInterface, byUuid]));
      expect(removed, isNot(contains(unrelated)));
    });

    test('a plain ethernet profile takes nothing with it', () async {
      final wired = FakeSettingsConnection(
          settings: _ethernetProfile(id: 'eno1', uuid: 'u'));
      final client = FakeNetworkManagerClient(
        settings: FakeNetworkManagerSettings(
            connections: [wired, member('port1', 'bond0')]),
      );

      expect(await connectionsRemovedWith(client, wired), [wired]);
    });

    test('skips profiles that vanish mid-walk', () async {
      final master = bond();
      final client = FakeNetworkManagerClient(
        settings: FakeNetworkManagerSettings(connections: [
          master,
          FakeSettingsConnection(getSettingsError: Exception('deleted')),
          member('port1', 'bond0'),
        ]),
      );

      expect(await connectionsRemovedWith(client, master), hasLength(2));
    });

    test('an unreadable target still deletes itself', () async {
      final broken = FakeSettingsConnection(
          getSettingsError: Exception('not authorized'));
      final client = FakeNetworkManagerClient(
        settings: FakeNetworkManagerSettings(connections: [broken]),
      );

      expect(await connectionsRemovedWith(client, broken), [broken]);
    });
  });

  group('deleteConnections', () {
    test('deletes every profile it is given', () async {
      final a = FakeSettingsConnection();
      final b = FakeSettingsConnection();

      expect(await deleteConnections([a, b]), isEmpty);
      expect(a.deleted, isTrue);
      expect(b.deleted, isTrue);
    });

    test('reports the ones it could not delete and keeps going', () async {
      // A half-deleted bond is worth naming precisely; claiming success would
      // leave the operator thinking the members are gone.
      final ok = FakeSettingsConnection();
      final refused =
          FakeSettingsConnection(deleteError: Exception('not authorized'));
      final alsoOk = FakeSettingsConnection();

      final failed = await deleteConnections([ok, refused, alsoOk]);

      expect(failed, [refused]);
      expect(ok.deleted, isTrue);
      expect(alsoOk.deleted, isTrue,
          reason: 'a refusal must not stop the rest');
    });
  });
}
