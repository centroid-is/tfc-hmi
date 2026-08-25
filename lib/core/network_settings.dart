import 'dart:math';

import 'package:dbus/dbus.dart';

/// Pure helpers behind the IP settings page: address validation, netmask ⇄
/// prefix conversion, and the NetworkManager settings maps for static/DHCP
/// IPv4 and active-backup bonds. No D-Bus connection required, so all of it
/// is unit-testable off-target.

bool isValidIpv4(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return false;
    if (part.length > 1 && part.startsWith('0')) return false;
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
  }
  return true;
}

/// A netmask is valid when its 32-bit value is a run of ones followed by a
/// run of zeros (255.255.0.0, 255.255.255.192, …).
bool isValidNetmask(String netmask) => netmaskToPrefix(netmask) != null;

int? netmaskToPrefix(String netmask) {
  if (!isValidIpv4(netmask)) return null;
  final octets = netmask.split('.').map(int.parse);
  var mask = 0;
  for (final octet in octets) {
    mask = (mask << 8) | octet;
  }
  // Contiguity: adding the lowest set bit of the inverse must overflow into
  // the mask itself, i.e. ~mask + 1 keeps only bits already outside the run.
  final inverse = (~mask) & 0xffffffff;
  if (((inverse + 1) & inverse) != 0) return null;
  var prefix = 0;
  for (var bit = 31; bit >= 0 && (mask >> bit) & 1 == 1; bit--) {
    prefix++;
  }
  return prefix;
}

String prefixToNetmask(int prefix) {
  final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  return '${(mask >> 24) & 0xff}.${(mask >> 16) & 0xff}.'
      '${(mask >> 8) & 0xff}.${mask & 0xff}';
}

/// Accepts what an operator is likely to type in the netmask field: a dotted
/// netmask (`255.255.0.0`), a bare prefix (`16`), or a CIDR prefix (`/16`).
/// Returns the prefix length, or null when the input is none of those.
int? parsePrefixOrNetmask(String input) {
  var text = input.trim();
  if (text.startsWith('/')) text = text.substring(1);
  final prefix = int.tryParse(text);
  if (prefix != null) {
    return (prefix >= 0 && prefix <= 32) ? prefix : null;
  }
  return netmaskToPrefix(text);
}

/// Splits a comma/space separated DNS server list into addresses.
List<String> splitDnsServers(String input) => input
    .split(RegExp(r'[,\s]+'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// Internet reachability probe target. NetworkManager's own HTTP
/// connectivity check needs a configured endpoint and is disabled on the
/// plant machines, so the page probes Cloudflare's anycast resolver over
/// TCP instead (ICMP would need privileges).
const internetProbeHost = '1.1.1.1';
const internetProbePort = 443;

/// Hostname resolved to check that DNS itself works — deliberately distinct
/// from the raw-IP probe above, so "internet up, DNS broken" is visible.
const dnsProbeHostname = 'one.one.one.one';

/// Human-readable byte count for the RX/TX counters, e.g. `1.5 GB`.
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text =
      unit == 0 ? '$bytes' : value.toStringAsFixed(value >= 100 ? 0 : 1);
  return '$text ${units[unit]}';
}

/// Human-readable throughput, e.g. `2.1 MB/s`.
String formatRate(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

/// RX/TX throughput in bytes per second.
class TrafficRates {
  final double rxPerSecond;
  final double txPerSecond;

  const TrafficRates({required this.rxPerSecond, required this.txPerSecond});
}

/// Turns NetworkManager's cumulative RX/TX byte counters into rates.
///
/// Feed it a sample per statistics update; from the second sample on it
/// yields the average rate over the interval. Counter resets (interface
/// bounce) clamp to zero instead of going negative.
class TrafficRateTracker {
  DateTime? _lastTime;
  int _lastRx = 0;
  int _lastTx = 0;

  /// The most recently computed rates, or null before two samples arrived.
  TrafficRates? rates;

  TrafficRates? update(DateTime now, int rxBytes, int txBytes) {
    final last = _lastTime;
    if (last != null) {
      final seconds = now.difference(last).inMilliseconds / 1000.0;
      if (seconds > 0) {
        rates = TrafficRates(
          rxPerSecond: max(0, (rxBytes - _lastRx) / seconds),
          txPerSecond: max(0, (txBytes - _lastTx) / seconds),
        );
      }
    }
    _lastTime = now;
    _lastRx = rxBytes;
    _lastTx = txBytes;
    return rates;
  }
}

/// Random (version 4) UUID for new NetworkManager connections.
String generateUuid([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// The `ipv4` section for a DHCP connection.
Map<String, DBusValue> ipv4AutoSection() => {
      'method': const DBusString('auto'),
    };

/// The `ipv4` section for a static connection.
Map<String, DBusValue> ipv4ManualSection({
  required String address,
  required int prefix,
  String gateway = '',
  List<String> dnsServers = const [],
}) {
  final section = <String, DBusValue>{
    'method': const DBusString('manual'),
    'address-data': DBusArray(DBusSignature('a{sv}'), [
      DBusDict(DBusSignature('s'), DBusSignature('v'), {
        const DBusString('address'): DBusVariant(DBusString(address)),
        const DBusString('prefix'): DBusVariant(DBusUint32(prefix)),
      })
    ]),
    'dns-data': DBusArray(
        DBusSignature('s'), dnsServers.map((dns) => DBusString(dns)).toList()),
  };
  if (gateway.isNotEmpty) {
    section['gateway'] = DBusString(gateway);
  }
  return section;
}

/// Full settings for the bond master connection. Mode 1 (`active-backup`)
/// keeps one member carrying traffic and fails over on link loss, which is
/// the only bond mode plain (non-LACP) plant switches support.
Map<String, Map<String, DBusValue>> bondMasterSettings({
  required String bondName,
  required String uuid,
  String? primaryMember,
  Map<String, DBusValue>? ipv4Section,
}) {
  final options = <DBusValue, DBusValue>{
    const DBusString('mode'): const DBusString('active-backup'),
    const DBusString('miimon'): const DBusString('100'),
  };
  if (primaryMember != null && primaryMember.isNotEmpty) {
    options[const DBusString('primary')] = DBusString(primaryMember);
  }
  return {
    'connection': {
      'id': DBusString(bondName),
      'uuid': DBusString(uuid),
      'type': const DBusString('bond'),
      'interface-name': DBusString(bondName),
      'autoconnect': const DBusBoolean(true),
    },
    'bond': {
      'options': DBusDict(DBusSignature('s'), DBusSignature('s'), options),
    },
    'ipv4': ipv4Section ?? ipv4AutoSection(),
  };
}

/// Full settings for one ethernet member enslaved to [bondName].
Map<String, Map<String, DBusValue>> bondMemberSettings({
  required String memberInterface,
  required String bondName,
  required String uuid,
}) {
  return {
    'connection': {
      'id': DBusString('$bondName-$memberInterface'),
      'uuid': DBusString(uuid),
      'type': const DBusString('802-3-ethernet'),
      'interface-name': DBusString(memberInterface),
      'master': DBusString(bondName),
      'slave-type': const DBusString('bond'),
      'autoconnect': const DBusBoolean(true),
    },
  };
}
