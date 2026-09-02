/// Host clock and time-synchronisation state, read over the system bus.
///
/// Two systemd services back this, and the split matters because only one
/// half needs privileges:
///
/// * `org.freedesktop.timedate1` (systemd-timedated) owns the clock itself —
///   timezone, whether NTP is enabled, whether the RTC is in local time, and
///   setting the time by hand. Every setter is polkit `auth_admin_keep`.
/// * `org.freedesktop.timesync1` (systemd-timesyncd) owns the sync detail —
///   which server is in use and how well it is tracking. Reads need no
///   authorisation at all; the one setter,
///   [TimeSyncApi.setRuntimeNtpServers], is polkit `auth_admin_keep`.
///
/// Reading either is unprivileged, so [SystemClockStatus] renders without a
/// login. That is deliberate: "is the clock right?" is an operator question,
/// not an administrator one.
library;

import 'package:dbus/dbus.dart';
import 'package:tfc_dart/core/preferences.dart';

import '../dbus/generated/timedate1.dart' as timedate1;
import '../dbus/generated/timesync1.dart' as timesync1;

/// SharedPreferences key holding the NTP servers this station should use.
///
/// Device-local on purpose, and for a blunter reason than most such keys:
/// systemd offers no way to persist an NTP server list over D-Bus at all.
/// `timesync1` exposes exactly one setter, `SetRuntimeNTPServers`, and
/// "runtime" is literal — timesyncd forgets the list when it restarts. The
/// persistent list lives in `/etc/systemd/timesyncd.conf`, which the HMI
/// container cannot write (it mounts only the D-Bus socket).
///
/// So the HMI remembers the operator's choice and re-applies it on start.
/// See [ntpServersToApply].
const String ntpServersPrefsKey = 'ntp_servers';

/// Reads the operator's chosen NTP servers. Empty means "never configured",
/// which is distinct from "configured to nothing".
Future<List<String>> readNtpServers(PreferencesApi prefs) async {
  final stored = await prefs.getStringList(ntpServersPrefsKey);
  return stored ?? const [];
}

/// Persists the chosen NTP servers. An empty list clears the key, so a reset
/// station is indistinguishable from one that was never configured.
Future<void> writeNtpServers(
    PreferencesApi prefs, List<String> servers) async {
  final cleaned = normaliseNtpServers(servers);
  if (cleaned.isEmpty) {
    await prefs.remove(ntpServersPrefsKey);
  } else {
    await prefs.setStringList(ntpServersPrefsKey, cleaned);
  }
}

/// Trims, drops blanks, and removes duplicates while keeping the operator's
/// ordering — timesyncd tries servers in order, so the order is meaningful.
List<String> normaliseNtpServers(Iterable<String> servers) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in servers) {
    final server = raw.trim();
    if (server.isEmpty) continue;
    if (!seen.add(server)) continue;
    out.add(server);
  }
  return out;
}

/// Whether [server] is a plausible NTP server: an IPv4 literal or a hostname.
///
/// Deliberately permissive — timesyncd accepts anything it can resolve, and
/// rejecting a valid internal hostname is worse than accepting a typo the
/// status display will then show as unreachable.
bool isValidNtpServer(String server) {
  final value = server.trim();
  if (value.isEmpty || value.length > 253) return false;
  if (value.contains(RegExp(r'\s'))) return false;
  // A hostname label may not be empty, and may not start or end with '-'.
  final label = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$');
  final parts = value.split('.');
  if (parts.any((p) => p.isEmpty || p.length > 63 || !label.hasMatch(p))) {
    // Not a hostname; an IPv6 literal is still fine.
    return value.contains(':') && RegExp(r'^[0-9A-Fa-f:.]+$').hasMatch(value);
  }
  return true;
}

/// The list to hand `SetRuntimeNTPServers` on startup: the operator's choice,
/// or nothing at all when they never made one.
///
/// Returning empty rather than a default matters — pushing an empty list to
/// timesyncd would *clear* servers a station had configured elsewhere (a
/// `/etc/systemd/timesyncd.conf` written by provisioning, or DHCP-supplied
/// per-link servers), so the caller must skip the call entirely.
List<String> ntpServersToApply(List<String> stored) =>
    normaliseNtpServers(stored);

/// The clock half of the status, from `timedate1`.
class SystemClockStatus {
  /// Host wall-clock time, as the host reports it. Not the HMI's own clock —
  /// on a remote D-Bus connection these differ, and that difference is the
  /// whole point of showing it.
  final DateTime time;

  /// Hardware clock, when readable.
  final DateTime? rtcTime;

  /// IANA zone name, e.g. `Atlantic/Reykjavik`.
  final String timezone;

  /// Whether the RTC is kept in local time rather than UTC. Dual-boot legacy;
  /// on a plant station this should be false.
  final bool localRtc;

  /// Whether an NTP client is enabled.
  final bool ntpEnabled;

  /// Whether the clock is actually synchronised. The pair (enabled, synced)
  /// is what tells an operator "switched on but not working".
  final bool ntpSynchronized;

  /// Whether this host has an NTP client that timedated can control at all.
  final bool canNtp;

  const SystemClockStatus({
    required this.time,
    required this.rtcTime,
    required this.timezone,
    required this.localRtc,
    required this.ntpEnabled,
    required this.ntpSynchronized,
    required this.canNtp,
  });

  /// How far the hardware clock has drifted from system time, when both are
  /// known. Large values point at a dying RTC battery.
  Duration? get rtcDrift {
    final rtc = rtcTime;
    if (rtc == null) return null;
    return rtc.difference(time);
  }
}

/// One-line health verdict, so the UI and any future alarm agree on wording.
enum TimeSyncHealth {
  /// NTP is on and the clock is synchronised.
  synchronized,

  /// NTP is on but the clock has not synchronised (yet, or at all).
  notSynchronized,

  /// NTP is switched off; the clock is free-running or set by hand.
  disabled,

  /// This host has no NTP client timedated can drive.
  unavailable,
}

TimeSyncHealth timeSyncHealth(SystemClockStatus status) {
  if (!status.canNtp) return TimeSyncHealth.unavailable;
  if (!status.ntpEnabled) return TimeSyncHealth.disabled;
  return status.ntpSynchronized
      ? TimeSyncHealth.synchronized
      : TimeSyncHealth.notSynchronized;
}

/// The last NTP packet timesyncd processed, as exposed by the `NTPMessage`
/// property (D-Bus signature `(uuuuittayttttbtt)`).
///
/// Field order is fixed by systemd and verified against `timedatectl
/// show-timesync` on a live station.
class NtpMessage {
  final int leap;
  final int version;
  final int mode;

  /// Distance from the reference clock. 1 is a reference clock itself, 2 is
  /// one hop away. 16 means unsynchronised.
  final int stratum;

  /// Clock precision as a power of two, in seconds.
  final int precision;

  final Duration rootDelay;
  final Duration rootDispersion;

  /// Reference identifier — an IPv4 address for stratum 2+, or an ASCII
  /// source name like `GPS` for stratum 1. Rendered as hex, matching
  /// `timedatectl`.
  final String referenceId;

  final DateTime originateTime;
  final DateTime receiveTime;
  final DateTime transmitTime;
  final DateTime destinationTime;

  /// Whether timesyncd discarded this packet (a spike).
  final bool ignored;

  final int packetCount;
  final Duration jitter;

  const NtpMessage({
    required this.leap,
    required this.version,
    required this.mode,
    required this.stratum,
    required this.precision,
    required this.rootDelay,
    required this.rootDispersion,
    required this.referenceId,
    required this.originateTime,
    required this.receiveTime,
    required this.transmitTime,
    required this.destinationTime,
    required this.ignored,
    required this.packetCount,
    required this.jitter,
  });

  /// Round-trip delay to the server: the time on the wire, excluding the time
  /// the server spent thinking.
  Duration get roundTrip {
    final total = destinationTime.difference(originateTime);
    final serverTime = transmitTime.difference(receiveTime);
    final wire = total - serverTime;
    return wire.isNegative ? Duration.zero : wire;
  }

  /// Estimated offset between this clock and the server's, by the standard
  /// NTP formula: the mean of the two one-way discrepancies.
  Duration get offset {
    final forward = receiveTime.difference(originateTime);
    final backward = transmitTime.difference(destinationTime);
    return Duration(
        microseconds: (forward.inMicroseconds + backward.inMicroseconds) ~/ 2);
  }
}

/// The sync half of the status, from `timesync1`.
class TimeSyncStatus {
  /// Server name as configured, e.g. `0.debian.pool.ntp.org`.
  final String serverName;

  /// Resolved address of [serverName], when timesyncd has one.
  final String? serverAddress;

  /// Servers supplied per-interface, typically by DHCP.
  final List<String> linkServers;

  /// Servers from `/etc/systemd/timesyncd.conf`. Read-only here — nothing on
  /// the bus can write them, which is why [ntpServersPrefsKey] exists.
  final List<String> systemServers;

  /// Servers pushed at runtime, by this HMI or anything else.
  final List<String> runtimeServers;

  /// Built-in servers used when no others are configured.
  final List<String> fallbackServers;

  final Duration pollInterval;
  final Duration pollIntervalMin;
  final Duration pollIntervalMax;

  /// How far off the reference a source may be before timesyncd rejects it.
  final Duration rootDistanceMax;

  /// Null until the first packet has been processed — which is exactly the
  /// state a misconfigured server sits in, so the UI must handle it.
  final NtpMessage? lastMessage;

  const TimeSyncStatus({
    required this.serverName,
    required this.serverAddress,
    required this.linkServers,
    required this.systemServers,
    required this.runtimeServers,
    required this.fallbackServers,
    required this.pollInterval,
    required this.pollIntervalMin,
    required this.pollIntervalMax,
    required this.rootDistanceMax,
    required this.lastMessage,
  });

  /// The servers actually in effect, in the precedence timesyncd applies:
  /// per-link first, then configured, then fallback.
  List<String> get effectiveServers {
    if (linkServers.isNotEmpty) return linkServers;
    final configured = [...systemServers, ...runtimeServers];
    if (configured.isNotEmpty) return normaliseNtpServers(configured);
    return fallbackServers;
  }

  /// Whether the servers in use are only the built-in defaults — worth
  /// surfacing on a plant network that is meant to have its own source.
  bool get usingFallbackOnly =>
      linkServers.isEmpty && systemServers.isEmpty && runtimeServers.isEmpty;
}

/// Parses the `(iay)` address pair timesyncd reports: an address family
/// followed by raw bytes.
///
/// Returns null for the "no server yet" case, where the byte array is empty.
String? parseServerAddress(List<DBusValue> struct) {
  if (struct.length < 2) return null;
  final family = struct[0].asInt32();
  final bytes = struct[1].asByteArray().toList();
  if (bytes.isEmpty) return null;
  // AF_INET
  if (family == 2 && bytes.length == 4) return bytes.join('.');
  // AF_INET6
  if (family == 10 && bytes.length == 16) {
    final groups = <String>[];
    for (var i = 0; i < 16; i += 2) {
      groups.add(((bytes[i] << 8) | bytes[i + 1]).toRadixString(16));
    }
    return groups.join(':');
  }
  return null;
}

DateTime _fromUsec(int usec) =>
    DateTime.fromMicrosecondsSinceEpoch(usec, isUtc: true).toLocal();

/// Parses the `NTPMessage` struct. Returns null when timesyncd has not
/// processed a packet yet, which it reports as an all-zero struct.
NtpMessage? parseNtpMessage(List<DBusValue> struct) {
  if (struct.length < 15) return null;
  final packetCount = struct[13].asUint64();
  if (packetCount == 0) return null;

  final reference = struct[7].asByteArray().toList();
  final referenceId = reference
      .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join();

  return NtpMessage(
    leap: struct[0].asUint32(),
    version: struct[1].asUint32(),
    mode: struct[2].asUint32(),
    stratum: struct[3].asUint32(),
    precision: struct[4].asInt32(),
    rootDelay: Duration(microseconds: struct[5].asUint64()),
    rootDispersion: Duration(microseconds: struct[6].asUint64()),
    referenceId: referenceId,
    originateTime: _fromUsec(struct[8].asUint64()),
    receiveTime: _fromUsec(struct[9].asUint64()),
    transmitTime: _fromUsec(struct[10].asUint64()),
    destinationTime: _fromUsec(struct[11].asUint64()),
    ignored: struct[12].asBoolean(),
    packetCount: packetCount,
    jitter: Duration(microseconds: struct[14].asUint64()),
  );
}

/// The `timedate1` calls this app makes. An interface so widget tests can
/// drive the page without a bus.
abstract class TimeDateApi {
  Future<SystemClockStatus> readStatus();
  Future<void> setNtp(bool enabled);
  Future<void> setTimezone(String timezone);
  Future<void> setLocalRtc(bool localRtc, {bool fixSystem});
  Future<void> setTime(DateTime time);
  Future<List<String>> listTimezones();
}

/// The `timesync1` calls this app makes.
abstract class TimeSyncApi {
  /// Null when timesyncd is not running — a station using chrony, or none at
  /// all. The clock half still works in that case.
  Future<TimeSyncStatus?> readStatus();
  Future<void> setRuntimeNtpServers(List<String> servers);
}

/// [TimeDateApi] over a real bus.
class DBusTimeDate implements TimeDateApi {
  final timedate1.OrgFreedesktopDBusPeer _object;

  DBusTimeDate(DBusClient client)
      : _object = timedate1.OrgFreedesktopDBusPeer(
          client,
          'org.freedesktop.timedate1',
          DBusObjectPath('/org/freedesktop/timedate1'),
        );

  @override
  Future<SystemClockStatus> readStatus() async {
    // One GetAll rather than eight property reads: timedated is dbus-activated,
    // and each round trip on a busy station is a visible stall.
    final props = await _object.callGetAll('org.freedesktop.timedate1');

    T? read<T>(String key, T? Function(DBusValue) convert) {
      var value = props[key];
      if (value == null) return null;
      if (value is DBusVariant) value = value.value;
      try {
        return convert(value);
      } catch (_) {
        return null;
      }
    }

    final timeUsec = read<int>('TimeUSec', (v) => v.asUint64());
    final rtcUsec = read<int>('RTCTimeUSec', (v) => v.asUint64());

    return SystemClockStatus(
      // Falling back to the local clock keeps the page rendering; the
      // timezone and sync flags are the parts that carry the information.
      time: timeUsec != null ? _fromUsec(timeUsec) : DateTime.now(),
      rtcTime: rtcUsec != null && rtcUsec > 0 ? _fromUsec(rtcUsec) : null,
      timezone: read<String>('Timezone', (v) => v.asString()) ?? '',
      localRtc: read<bool>('LocalRTC', (v) => v.asBoolean()) ?? false,
      ntpEnabled: read<bool>('NTP', (v) => v.asBoolean()) ?? false,
      ntpSynchronized:
          read<bool>('NTPSynchronized', (v) => v.asBoolean()) ?? false,
      canNtp: read<bool>('CanNTP', (v) => v.asBoolean()) ?? false,
    );
  }

  /// `interactive: true` lets polkit put up a prompt where an agent exists.
  /// There is none in the HMI container, so in practice an unauthorised call
  /// still fails — but it fails with a message naming the action, which is
  /// what [describeClockError] turns into something an operator can act on.
  @override
  Future<void> setNtp(bool enabled) =>
      _object.callSetNTP(enabled, true, allowInteractiveAuthorization: true);

  @override
  Future<void> setTimezone(String timezone) => _object
      .callSetTimezone(timezone, true, allowInteractiveAuthorization: true);

  @override
  Future<void> setLocalRtc(bool localRtc, {bool fixSystem = true}) =>
      _object.callSetLocalRTC(localRtc, fixSystem, true,
          allowInteractiveAuthorization: true);

  @override
  Future<void> setTime(DateTime time) => _object.callSetTime(
        time.toUtc().microsecondsSinceEpoch,
        false,
        true,
        allowInteractiveAuthorization: true,
      );

  @override
  Future<List<String>> listTimezones() => _object.callListTimezones();
}

/// [TimeSyncApi] over a real bus.
class DBusTimeSync implements TimeSyncApi {
  final timesync1.OrgFreedesktopDBusPeer _object;

  DBusTimeSync(DBusClient client)
      : _object = timesync1.OrgFreedesktopDBusPeer(
          client,
          'org.freedesktop.timesync1',
          DBusObjectPath('/org/freedesktop/timesync1'),
        );

  @override
  Future<TimeSyncStatus?> readStatus() async {
    final Map<String, DBusValue> props;
    try {
      props = await _object.callGetAll('org.freedesktop.timesync1.Manager');
    } catch (_) {
      // timesyncd absent or not activatable — the caller renders the clock
      // half alone rather than showing an error for a service that this
      // station may legitimately not run.
      return null;
    }

    T? read<T>(String key, T? Function(DBusValue) convert) {
      var value = props[key];
      if (value == null) return null;
      if (value is DBusVariant) value = value.value;
      try {
        return convert(value);
      } catch (_) {
        return null;
      }
    }

    List<String> strings(String key) =>
        read<List<String>>(key, (v) => v.asStringArray().toList()) ?? const [];

    Duration usec(String key) =>
        Duration(microseconds: read<int>(key, (v) => v.asUint64()) ?? 0);

    final address =
        read<List<DBusValue>>('ServerAddress', (v) => v.asStruct().toList());
    final message =
        read<List<DBusValue>>('NTPMessage', (v) => v.asStruct().toList());

    return TimeSyncStatus(
      serverName: read<String>('ServerName', (v) => v.asString()) ?? '',
      serverAddress: address == null ? null : parseServerAddress(address),
      linkServers: strings('LinkNTPServers'),
      systemServers: strings('SystemNTPServers'),
      runtimeServers: strings('RuntimeNTPServers'),
      fallbackServers: strings('FallbackNTPServers'),
      pollInterval: usec('PollIntervalUSec'),
      pollIntervalMin: usec('PollIntervalMinUSec'),
      pollIntervalMax: usec('PollIntervalMaxUSec'),
      rootDistanceMax: usec('RootDistanceMaxUSec'),
      lastMessage: message == null ? null : parseNtpMessage(message),
    );
  }

  @override
  Future<void> setRuntimeNtpServers(List<String> servers) =>
      _object.callSetRuntimeNTPServers(normaliseNtpServers(servers),
          allowInteractiveAuthorization: true);
}

/// Whether [error] is polkit refusing the call rather than the operation
/// genuinely failing.
///
/// Every timedate1 setter is `auth_admin_keep` by default, so on a station
/// without a polkit rule granting them this is the *expected* outcome, and it
/// needs a different message from a real fault.
bool isAuthorizationError(Object error) {
  if (error is! DBusMethodResponseException) return false;
  const denials = {
    'org.freedesktop.DBus.Error.AccessDenied',
    'org.freedesktop.DBus.Error.AuthFailed',
    'org.freedesktop.DBus.Error.InteractiveAuthorizationRequired',
    'org.freedesktop.PolicyKit1.Error.NotAuthorized',
  };
  return denials.contains(error.errorName);
}

/// A message worth putting in front of an operator.
///
/// The polkit case names the missing station-side rule, because no amount of
/// clicking in the HMI will fix it.
String describeClockError(Object error) {
  if (isAuthorizationError(error)) {
    return 'Not permitted. This station needs a polkit rule granting the '
        'timedate1 and timesync1 actions — see '
        'docs/polkit/49-centroid-clock.rules.';
  }
  if (error is DBusMethodResponseException) {
    final values = error.response.values;
    final message = values.isEmpty ? '' : values.first.toNative().toString();
    return message.isEmpty ? error.errorName : message;
  }
  return error.toString();
}

/// Formats a duration the way `timedatectl` does — the units an operator
/// reading an NTP offset expects, rather than Dart's `0:00:00.000184`.
String formatSyncDuration(Duration d) {
  final usec = d.inMicroseconds.abs();
  final sign = d.isNegative ? '-' : '';
  if (usec < 1000) return '$sign${usec}us';
  if (usec < 1000000) {
    final ms = usec / 1000;
    return '$sign${ms.toStringAsFixed(ms < 10 ? 2 : 1)}ms';
  }
  final seconds = usec / 1000000;
  if (seconds < 60) return '$sign${seconds.toStringAsFixed(2)}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$sign${minutes}min ${(seconds % 60).round()}s';
  final hours = minutes ~/ 60;
  return '$sign${hours}h ${minutes % 60}min';
}
