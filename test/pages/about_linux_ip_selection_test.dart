import 'package:flutter_test/flutter_test.dart';
import 'package:nm/nm.dart';
import 'package:tfc/pages/about_linux.dart';

void main() {
  group('selectHostIps', () {
    test('primary connection wins over every device', () {
      final ips = selectHostIps([
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.bridge,
          isActivated: true,
          addresses: ['172.17.0.1'],
        ),
        const HostIpCandidate(
          isPrimary: true,
          isActivated: true,
          addresses: ['10.104.29.10'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.ethernet,
          isActivated: true,
          addresses: ['192.168.1.5'],
        ),
      ]);
      expect(ips, ['10.104.29.10']);
    });

    test('docker bridge enumerated first never beats the ethernet NIC', () {
      final ips = selectHostIps([
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.bridge,
          isActivated: true,
          addresses: ['172.17.0.1'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.veth,
          isActivated: true,
          addresses: ['172.17.0.2'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.ethernet,
          isActivated: true,
          addresses: ['10.104.29.10'],
        ),
      ]);
      expect(ips, ['10.104.29.10']);
    });

    test('deactivated ethernet does not contribute', () {
      final ips = selectHostIps([
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.ethernet,
          isActivated: false,
          addresses: ['192.168.1.5'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.wifi,
          isActivated: true,
          addresses: ['10.0.0.7'],
        ),
      ]);
      expect(ips, ['10.0.0.7']);
    });

    test('falls back to bond/vlan but never to virtual interfaces', () {
      final ips = selectHostIps([
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.bridge,
          isActivated: true,
          addresses: ['172.17.0.1'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.bond,
          isActivated: true,
          addresses: ['10.104.30.2'],
        ),
      ]);
      expect(ips, ['10.104.30.2']);
    });

    test('loopback addresses are filtered everywhere', () {
      final ips = selectHostIps([
        const HostIpCandidate(
          isPrimary: true,
          isActivated: true,
          addresses: ['127.0.0.1'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.ethernet,
          isActivated: true,
          addresses: ['127.0.0.1', '10.104.29.10'],
        ),
      ]);
      expect(ips, ['10.104.29.10']);
    });

    test('duplicate addresses collapse and multiple NICs all show', () {
      final ips = selectHostIps([
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.ethernet,
          isActivated: true,
          addresses: ['10.104.29.10'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.ethernet,
          isActivated: true,
          addresses: ['10.104.29.10', '192.168.1.5'],
        ),
      ]);
      expect(ips, ['10.104.29.10', '192.168.1.5']);
    });

    test('only virtual interfaces means no IPs at all', () {
      final ips = selectHostIps([
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.bridge,
          isActivated: true,
          addresses: ['172.17.0.1'],
        ),
        const HostIpCandidate(
          deviceType: NetworkManagerDeviceType.veth,
          isActivated: true,
          addresses: ['172.17.0.2'],
        ),
      ]);
      expect(ips, isEmpty);
    });
  });
}
