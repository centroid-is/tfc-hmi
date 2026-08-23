import 'dart:io';

import 'package:modbus_client_tcp/src/modbus_client_tcp.dart';
import 'package:test/test.dart';

/// The socket options behind Modbus TCP keepalive.
///
/// Two things are being pinned, and neither was covered before.
///
/// **The Windows constants.** They are different numbers from every other
/// platform (`TCP_KEEPIDLE` is 3 on Windows and 4 on Linux; `TCP_KEEPCNT` and
/// `TCP_KEEPINTVL` are 16 and 17, against Linux's 6 and 5 — note they are not
/// even in the same order). Nobody developing on macOS or Linux ever executes
/// that branch, so a transposed pair would ship.
///
/// **That tuning cannot fail a connection.** `_enableKeepAlive` is called
/// inside `connect()`'s `try`, and the only guard was a `SocketException`
/// catch on the Windows branch. A Windows build that rejects those options
/// with anything else — or a Linux kernel refusing one of its own — lost the
/// entire connection and logged "failed to connect". For a plant that is a
/// PLC that never comes up, to save a keepalive timer.
void main() {
  List<RawSocketOption> optionsFor({
    bool isWindows = false,
    bool isLinuxOrAndroid = false,
    bool isMac = false,
  }) =>
      ModbusClientTcp.keepAliveOptions(
        isWindows: isWindows,
        isLinuxOrAndroid: isLinuxOrAndroid,
        isMac: isMac,
        idleSeconds: 5,
        intervalSeconds: 2,
        count: 3,
      );

  /// `level:option` for each entry, in order. A string rather than a record
  /// because this package's SDK constraint predates records, and bumping it
  /// for a test is not a thing to do the week of a release.
  List<String> shapeOf(List<RawSocketOption> options) =>
      [for (final o in options) '${o.level}:${o.option}'];

  String sock(int o) => '${RawSocketOption.levelSocket}:$o';
  String tcp(int o) => '${RawSocketOption.levelTcp}:$o';

  group('SO_KEEPALIVE, which is what actually turns keepalive on', () {
    test('is 0x0009 on Linux and Android, 0x0008 everywhere else', () {
      expect(shapeOf(optionsFor(isLinuxOrAndroid: true)).first,
          sock(0x0009));

      for (final platform in [
        optionsFor(isWindows: true),
        optionsFor(isMac: true),
        optionsFor(),
      ]) {
        expect(shapeOf(platform).first, sock(0x0008));
      }
    });

    test('comes first, so the tuning that follows has something to tune', () {
      for (final platform in [
        optionsFor(isWindows: true),
        optionsFor(isLinuxOrAndroid: true),
        optionsFor(isMac: true),
      ]) {
        expect(platform.first.level, RawSocketOption.levelSocket);
        expect(platform.skip(1).every((o) => o.level == RawSocketOption.levelTcp),
            isTrue,
            reason: 'everything after SO_KEEPALIVE tunes TCP');
      }
    });
  });

  group('the per-platform TCP constants', () {
    test('Windows: idle 3, interval 17, count 16', () {
      // Deliberately spelled out rather than derived. The whole risk here is
      // a number being wrong, so a test that computed them the same way the
      // code does would agree with any mistake.
      expect(shapeOf(optionsFor(isWindows: true)), [
        sock(0x0008),
        tcp(3), // TCP_KEEPIDLE
        tcp(17), // TCP_KEEPINTVL
        tcp(16), // TCP_KEEPCNT
      ]);
    });

    test('Linux: idle 4, interval 5, count 6', () {
      expect(shapeOf(optionsFor(isLinuxOrAndroid: true)), [
        sock(0x0009),
        tcp(4),
        tcp(5),
        tcp(6),
      ]);
    });

    test('macOS: idle 0x10, interval 0x101, count 0x102', () {
      expect(shapeOf(optionsFor(isMac: true)), [
        sock(0x0008),
        tcp(0x10),
        tcp(0x101),
        tcp(0x102),
      ]);
    });

    test('Windows did not silently inherit another platform\'s block', () {
      // Compared as ordered lists, not as sets. The numbers do overlap
      // legitimately -- macOS TCP_KEEPALIVE is 0x10, which is 16, the same
      // integer Windows uses for TCP_KEEPCNT -- so "no shared numbers" is
      // false and was the first version of this test. What must not happen
      // is Windows getting a whole block copied from elsewhere.
      final windows = shapeOf(optionsFor(isWindows: true)).skip(1).toList();

      expect(windows,
          isNot(shapeOf(optionsFor(isLinuxOrAndroid: true)).skip(1).toList()));
      expect(windows,
          isNot(shapeOf(optionsFor(isMac: true)).skip(1).toList()));
    });
  });

  group('the values carried', () {
    test('idle, interval and count reach the options as given', () {
      final options = ModbusClientTcp.keepAliveOptions(
        isWindows: true,
        isLinuxOrAndroid: false,
        isMac: false,
        idleSeconds: 11,
        intervalSeconds: 7,
        count: 2,
      );
      // fromInt stores the value little-endian in 4 bytes.
      int valueOf(RawSocketOption o) =>
          o.value[0] | o.value[1] << 8 | o.value[2] << 16 | o.value[3] << 24;

      expect(valueOf(options[1]), 11, reason: 'idle');
      expect(valueOf(options[2]), 7, reason: 'interval');
      expect(valueOf(options[3]), 2, reason: 'count');
    });
  });

  group('every platform gets the same shape', () {
    test('one SO_KEEPALIVE and three TCP options, always', () {
      // So a platform cannot quietly end up with keepalive enabled but
      // untuned, which looks fine until a cable is pulled and nothing
      // notices for two hours.
      for (final platform in [
        optionsFor(isWindows: true),
        optionsFor(isLinuxOrAndroid: true),
        optionsFor(isMac: true),
        optionsFor(),
      ]) {
        expect(platform, hasLength(4));
      }
    });
  });
}
