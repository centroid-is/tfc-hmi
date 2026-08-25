import 'dart:math';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/network_settings.dart';

void main() {
  group('isValidIpv4', () {
    test('accepts normal addresses', () {
      expect(isValidIpv4('10.104.29.71'), isTrue);
      expect(isValidIpv4('0.0.0.0'), isTrue);
      expect(isValidIpv4('255.255.255.255'), isTrue);
    });

    test('rejects malformed addresses', () {
      expect(isValidIpv4(''), isFalse);
      expect(isValidIpv4('10.104.29'), isFalse);
      expect(isValidIpv4('10.104.29.71.5'), isFalse);
      expect(isValidIpv4('256.1.1.1'), isFalse);
      expect(isValidIpv4('10.104.29.'), isFalse);
      expect(isValidIpv4('a.b.c.d'), isFalse);
      expect(isValidIpv4('10.104.-1.5'), isFalse);
      expect(isValidIpv4('10.104.029.5'), isFalse, reason: 'leading zero');
    });
  });

  group('netmask ⇄ prefix', () {
    test('round-trips common masks', () {
      for (final (mask, prefix) in [
        ('255.255.255.0', 24),
        ('255.255.0.0', 16),
        ('255.0.0.0', 8),
        ('255.255.255.192', 26),
        ('255.255.255.255', 32),
        ('0.0.0.0', 0),
      ]) {
        expect(netmaskToPrefix(mask), prefix, reason: mask);
        expect(prefixToNetmask(prefix), mask, reason: '$prefix');
      }
    });

    test('a /16 netmask is valid (regression: old regex required 255.255.255.x)',
        () {
      expect(isValidNetmask('255.255.0.0'), isTrue);
      expect(isValidNetmask('255.0.0.0'), isTrue);
    });

    test('rejects non-contiguous masks', () {
      expect(netmaskToPrefix('255.0.255.0'), isNull);
      expect(netmaskToPrefix('255.255.255.5'), isNull);
      expect(netmaskToPrefix('0.255.255.255'), isNull);
      expect(isValidNetmask('255.254.255.0'), isFalse);
    });

    test('rejects garbage', () {
      expect(netmaskToPrefix('not-a-mask'), isNull);
      expect(netmaskToPrefix('255.255.255'), isNull);
    });
  });

  group('parsePrefixOrNetmask', () {
    test('accepts dotted, bare and slash-prefixed forms', () {
      expect(parsePrefixOrNetmask('255.255.255.0'), 24);
      expect(parsePrefixOrNetmask('16'), 16);
      expect(parsePrefixOrNetmask('/16'), 16);
      expect(parsePrefixOrNetmask(' /24 '), 24);
    });

    test('rejects out-of-range prefixes and junk', () {
      expect(parsePrefixOrNetmask('33'), isNull);
      expect(parsePrefixOrNetmask('-1'), isNull);
      expect(parsePrefixOrNetmask('255.1.0.0'), isNull);
      expect(parsePrefixOrNetmask(''), isNull);
    });
  });

  test('splitDnsServers splits on commas and whitespace', () {
    expect(splitDnsServers('10.104.1.1, 8.8.8.8'), ['10.104.1.1', '8.8.8.8']);
    expect(splitDnsServers('10.104.1.1 8.8.8.8'), ['10.104.1.1', '8.8.8.8']);
    expect(splitDnsServers('  '), isEmpty);
  });

  test('generateUuid produces version-4 variant-1 UUIDs', () {
    final uuid = generateUuid(Random(42));
    expect(
        uuid,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(generateUuid(), isNot(generateUuid()));
  });

  group('ipv4 sections', () {
    test('auto section only sets the method', () {
      expect(ipv4AutoSection(), {'method': const DBusString('auto')});
    });

    test('manual section carries address, prefix, gateway and dns', () {
      final section = ipv4ManualSection(
        address: '10.104.29.10',
        prefix: 24,
        gateway: '10.104.29.1',
        dnsServers: ['10.104.1.1'],
      );
      expect(section['method'], const DBusString('manual'));
      expect(section['gateway'], const DBusString('10.104.29.1'));
      final addressData = section['address-data'] as DBusArray;
      final entry = addressData.children.single as DBusDict;
      expect(entry.children[const DBusString('address')],
          const DBusVariant(DBusString('10.104.29.10')));
      expect(entry.children[const DBusString('prefix')],
          const DBusVariant(DBusUint32(24)));
      final dns = section['dns-data'] as DBusArray;
      expect(dns.children, [const DBusString('10.104.1.1')]);
    });

    test('manual section omits an empty gateway', () {
      final section = ipv4ManualSection(address: '10.0.0.2', prefix: 16);
      expect(section.containsKey('gateway'), isFalse);
    });
  });

  group('bond settings', () {
    test('master is active-backup mode with miimon and primary', () {
      final settings = bondMasterSettings(
        bondName: 'bond0',
        uuid: 'uuid-1',
        primaryMember: 'eth0',
      );
      final connection = settings['connection']!;
      expect(connection['type'], const DBusString('bond'));
      expect(connection['interface-name'], const DBusString('bond0'));
      expect(connection['autoconnect'], const DBusBoolean(true));
      final options = settings['bond']!['options'] as DBusDict;
      expect(options.children[const DBusString('mode')],
          const DBusString('active-backup'));
      expect(options.children[const DBusString('miimon')],
          const DBusString('100'));
      expect(options.children[const DBusString('primary')],
          const DBusString('eth0'));
      expect(settings['ipv4'], {'method': const DBusString('auto')});
    });

    test('master omits primary when not chosen', () {
      final settings = bondMasterSettings(bondName: 'bond0', uuid: 'uuid-1');
      final options = settings['bond']!['options'] as DBusDict;
      expect(
          options.children.containsKey(const DBusString('primary')), isFalse);
    });

    test('member is an ethernet slave of the bond', () {
      final settings = bondMemberSettings(
          memberInterface: 'eth1', bondName: 'bond0', uuid: 'uuid-2');
      final connection = settings['connection']!;
      expect(connection['type'], const DBusString('802-3-ethernet'));
      expect(connection['interface-name'], const DBusString('eth1'));
      expect(connection['master'], const DBusString('bond0'));
      expect(connection['slave-type'], const DBusString('bond'));
    });
  });
}
