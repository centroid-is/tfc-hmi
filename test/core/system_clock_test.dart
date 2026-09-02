import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/core/system_clock.dart';

/// The `NTPMessage` struct exactly as `busctl` printed it on a live station
/// (Debian 13, systemd 257), alongside the `timedatectl show-timesync` output
/// for the same moment:
///
/// ```
/// NTPMessage  (uuuuittayttttbtt)
///   0 4 4 2 -25 625 183  4 193 4 58 77
///   1788276157781726 1788276157782739 1788276157782855 1788276157783921
///   false 6013 184
///
/// NTPMessage={ Leap=0, Version=4, Mode=4, Stratum=2, Precision=-25,
///   RootDelay=625us, RootDispersion=183us, Reference=C1043A4D,
///   ... Ignored=no, PacketCount=6013, Jitter=184us }
/// ```
///
/// Pinning the real bytes is the point: the field order is not in any header
/// we control, and getting it wrong would silently mislabel stratum as mode.
List<DBusValue> _realNtpMessage() => [
      const DBusUint32(0), // leap
      const DBusUint32(4), // version
      const DBusUint32(4), // mode
      const DBusUint32(2), // stratum
      const DBusInt32(-25), // precision
      const DBusUint64(625), // root delay, usec
      const DBusUint64(183), // root dispersion, usec
      DBusArray.byte([193, 4, 58, 77]), // reference id -> C1043A4D
      const DBusUint64(1788276157781726), // originate
      const DBusUint64(1788276157782739), // receive
      const DBusUint64(1788276157782855), // transmit
      const DBusUint64(1788276157783921), // destination
      const DBusBoolean(false), // ignored
      const DBusUint64(6013), // packet count
      const DBusUint64(184), // jitter, usec
    ];

void main() {
  group('parseNtpMessage', () {
    test('decodes a real packet from the station', () {
      final message = parseNtpMessage(_realNtpMessage())!;

      expect(message.leap, 0);
      expect(message.version, 4);
      expect(message.mode, 4);
      expect(message.stratum, 2);
      expect(message.precision, -25);
      expect(message.rootDelay, const Duration(microseconds: 625));
      expect(message.rootDispersion, const Duration(microseconds: 183));
      expect(message.ignored, isFalse);
      expect(message.packetCount, 6013);
      expect(message.jitter, const Duration(microseconds: 184));
    });

    test('renders the reference id the way timedatectl does', () {
      // timedatectl showed Reference=C1043A4D for these bytes.
      expect(parseNtpMessage(_realNtpMessage())!.referenceId, 'C1043A4D');
    });

    test('pads single-digit reference bytes', () {
      final struct = _realNtpMessage();
      struct[7] = DBusArray.byte([0x0A, 0x00, 0x01, 0x02]);
      expect(parseNtpMessage(struct)!.referenceId, '0A000102');
    });

    test('is null before the first packet', () {
      // timesyncd reports an all-zero struct until it has talked to a server.
      // That is exactly the state a wrong server address leaves it in, so it
      // must read as "no data", never as a stratum-0 packet.
      final struct = _realNtpMessage();
      struct[13] = const DBusUint64(0);
      expect(parseNtpMessage(struct), isNull);
    });

    test('is null for a truncated struct', () {
      expect(parseNtpMessage(const [DBusUint32(0)]), isNull);
    });

    test('computes round trip and offset from the four timestamps', () {
      final message = parseNtpMessage(_realNtpMessage())!;

      // (destination - originate) - (transmit - receive)
      // = (1788276157783921 - 1788276157781726) - (1788276157782855 - 1788276157782739)
      // = 2195 - 116 = 2079us
      expect(message.roundTrip, const Duration(microseconds: 2079));

      // ((receive - originate) + (transmit - destination)) / 2
      // = (1013 + -1066) / 2 = -26us  (Dart truncates toward zero)
      expect(message.offset, const Duration(microseconds: -26));
    });

    test('never reports a negative round trip', () {
      // Clock stepping mid-exchange can invert the timestamps; a negative
      // "round trip" would render as nonsense.
      final struct = _realNtpMessage();
      struct[11] = const DBusUint64(1788276157781000); // destination < originate
      expect(parseNtpMessage(struct)!.roundTrip, Duration.zero);
    });
  });

  group('parseServerAddress', () {
    test('decodes the IPv4 address the station reported', () {
      // busctl: ServerAddress (iay) = 2 4 93 95 229 195
      // timedatectl: ServerAddress=93.95.229.195
      final address = parseServerAddress([
        const DBusInt32(2),
        DBusArray.byte([93, 95, 229, 195]),
      ]);
      expect(address, '93.95.229.195');
    });

    test('decodes IPv6', () {
      final address = parseServerAddress([
        const DBusInt32(10),
        DBusArray.byte([
          0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, //
          0, 0, 0, 0, 0, 0, 0, 0x01,
        ]),
      ]);
      expect(address, '2001:db8:0:0:0:0:0:1');
    });

    test('is null when no server has been contacted', () {
      expect(
        parseServerAddress([const DBusInt32(0), DBusArray.byte([])]),
        isNull,
      );
    });

    test('is null for a family and length that disagree', () {
      expect(
        parseServerAddress([const DBusInt32(2), DBusArray.byte([1, 2])]),
        isNull,
      );
    });
  });

  group('normaliseNtpServers', () {
    test('keeps operator ordering, since timesyncd tries servers in order', () {
      expect(
        normaliseNtpServers(['b.example', 'a.example']),
        ['b.example', 'a.example'],
      );
    });

    test('trims, drops blanks and de-duplicates', () {
      expect(
        normaliseNtpServers(['  a.example ', '', '   ', 'a.example', 'b']),
        ['a.example', 'b'],
      );
    });
  });

  group('isValidNtpServer', () {
    test('accepts hostnames, IPv4 and IPv6 literals', () {
      expect(isValidNtpServer('0.debian.pool.ntp.org'), isTrue);
      expect(isValidNtpServer('10.104.29.1'), isTrue);
      expect(isValidNtpServer('plc-st101'), isTrue);
      expect(isValidNtpServer('2001:db8::1'), isTrue);
    });

    test('rejects blanks, whitespace and malformed labels', () {
      expect(isValidNtpServer(''), isFalse);
      expect(isValidNtpServer('   '), isFalse);
      expect(isValidNtpServer('a b'), isFalse);
      expect(isValidNtpServer('-leading.example'), isFalse);
      expect(isValidNtpServer('trailing-.example'), isFalse);
      expect(isValidNtpServer('double..dot'), isFalse);
    });
  });

  group('timeSyncHealth', () {
    SystemClockStatus status({
      bool canNtp = true,
      bool enabled = true,
      bool synced = true,
    }) =>
        SystemClockStatus(
          time: DateTime(2026, 9, 1, 15, 32, 31),
          rtcTime: null,
          timezone: 'Atlantic/Reykjavik',
          localRtc: false,
          ntpEnabled: enabled,
          ntpSynchronized: synced,
          canNtp: canNtp,
        );

    test('separates "switched on but not working" from "switched off"', () {
      // The distinction the whole status display exists to make.
      expect(timeSyncHealth(status(synced: false)),
          TimeSyncHealth.notSynchronized);
      expect(timeSyncHealth(status(enabled: false)), TimeSyncHealth.disabled);
    });

    test('reports synchronized only when enabled and synced', () {
      expect(timeSyncHealth(status()), TimeSyncHealth.synchronized);
    });

    test('reports unavailable when the host has no NTP client', () {
      expect(timeSyncHealth(status(canNtp: false)), TimeSyncHealth.unavailable);
    });

    test('a stale synchronized flag cannot outrank a disabled client', () {
      // timedated leaves NTPSynchronized set after NTP is turned off; the
      // health verdict must not read that as healthy.
      expect(timeSyncHealth(status(enabled: false, synced: true)),
          TimeSyncHealth.disabled);
    });
  });

  group('TimeSyncStatus.effectiveServers', () {
    TimeSyncStatus status({
      List<String> link = const [],
      List<String> system = const [],
      List<String> runtime = const [],
      List<String> fallback = const ['0.debian.pool.ntp.org'],
    }) =>
        TimeSyncStatus(
          serverName: '',
          serverAddress: null,
          linkServers: link,
          systemServers: system,
          runtimeServers: runtime,
          fallbackServers: fallback,
          pollInterval: Duration.zero,
          pollIntervalMin: Duration.zero,
          pollIntervalMax: Duration.zero,
          rootDistanceMax: Duration.zero,
          lastMessage: null,
        );

    test('per-link servers win, as they do in timesyncd', () {
      expect(
        status(link: ['dhcp.example'], system: ['conf.example'])
            .effectiveServers,
        ['dhcp.example'],
      );
    });

    test('configured servers beat the fallback pool', () {
      expect(status(runtime: ['hmi.example']).effectiveServers,
          ['hmi.example']);
    });

    test('falls back only when nothing is configured', () {
      expect(status().effectiveServers, ['0.debian.pool.ntp.org']);
      expect(status().usingFallbackOnly, isTrue);
    });

    test('a runtime push means the station is no longer on fallbacks', () {
      expect(status(runtime: ['hmi.example']).usingFallbackOnly, isFalse);
    });
  });

  group('ntpServersToApply', () {
    test('is empty when the operator never configured servers', () {
      // The caller must then skip SetRuntimeNTPServers entirely: pushing an
      // empty list would clear servers configured on the host itself.
      expect(ntpServersToApply(const []), isEmpty);
    });

    test('cleans the stored list', () {
      expect(ntpServersToApply(['  a ', 'a', '']), ['a']);
    });
  });

  group('formatSyncDuration', () {
    test('uses the units timedatectl uses', () {
      expect(formatSyncDuration(const Duration(microseconds: 184)), '184us');
      expect(formatSyncDuration(const Duration(microseconds: 2079)), '2.08ms');
      expect(formatSyncDuration(const Duration(milliseconds: 250)), '250.0ms');
      expect(formatSyncDuration(const Duration(seconds: 5)), '5.00s');
      expect(formatSyncDuration(const Duration(seconds: 2048)), '34min 8s');
    });

    test('keeps the sign, since an offset has a direction', () {
      expect(formatSyncDuration(const Duration(microseconds: -26)), '-26us');
    });
  });

  group('isAuthorizationError', () {
    test('recognises polkit refusing an auth_admin action', () {
      // Every timedate1 setter is auth_admin_keep, so on a station without a
      // polkit rule this is the expected reply, not a fault.
      for (final name in [
        'org.freedesktop.DBus.Error.AccessDenied',
        'org.freedesktop.DBus.Error.InteractiveAuthorizationRequired',
        'org.freedesktop.PolicyKit1.Error.NotAuthorized',
      ]) {
        expect(
          isAuthorizationError(
              DBusMethodResponseException(DBusMethodErrorResponse(name))),
          isTrue,
          reason: name,
        );
      }
    });

    test('does not swallow a genuine failure', () {
      expect(
        isAuthorizationError(DBusMethodResponseException(
            DBusMethodErrorResponse('org.freedesktop.DBus.Error.Failed'))),
        isFalse,
      );
      expect(isAuthorizationError(Exception('boom')), isFalse);
    });

    test('points at the station-side fix, which no HMI click can supply', () {
      final message = describeClockError(DBusMethodResponseException(
          DBusMethodErrorResponse(
              'org.freedesktop.DBus.Error.InteractiveAuthorizationRequired')));
      expect(message, contains('polkit'));
      expect(message, contains('49-centroid-clock.rules'));
    });
  });
}
