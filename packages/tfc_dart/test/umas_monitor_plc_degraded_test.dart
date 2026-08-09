/// TD-022 (v1.1.x): MonitorPlc degraded-circuit breaker tests.
///
/// Reproduces the production "long-uptime 0x82 cascade" bug observed
/// on the M580 at 192.168.112.159 after ~1 week of uptime: every UMAS
/// read started failing with `UmasException(130, sec=128)` from the
/// 0x50 (MonitorPlc) path, and the per-key fallback in the adapter
/// cascaded the same 0x82 forever because [UmasClient.readVariables]
/// always routes through MonitorPlc when [_useMonitorPlc] is true.
///
/// Contract under test:
///   * After [_monitorPlc0x82TripThreshold] consecutive 0x82 responses,
///     a degraded flag latches and subsequent reads bypass MonitorPlc
///     (the 0x22 ReadVariable path runs instead).
///   * The flag auto-clears after [_monitorPlcDegradedRetryAfter], so
///     the next call probes MonitorPlc again.
///   * A non-0x82 outcome (success or different error) resets the
///     counter so transient 0x82s don't trip the breaker.
///   * [_useMonitorPlc] itself is never reset (TD-009 — sticky M580
///     hardware fingerprint).
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:modbus_client/modbus_client.dart';
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

void main() {
  group('TD-022 MonitorPlc degraded-circuit breaker', () {
    /// Variables for the read attempts.
    final variables = [
      (
        const UmasVariable(
            name: 'MálmHliðarfærslubandUppi',
            blockNo: 1,
            offset: 0,
            dataTypeId: 6),
        const UmasDataTypeRef(id: 1, name: 'BOOL', byteSize: 1),
      ),
    ];

    /// Builds a sendFn that handles session init + plcStatus, and routes
    /// 0x22 / 0x50 to caller-supplied handlers. The handlers return raw
    /// response PDUs (including the 3-byte [0x5A, pairingKey, status]
    /// header). The pairing key is fixed at 0x42 for simplicity.
    Future<ModbusResponseCode> Function(ModbusRequest) buildSendFn({
      required List<int> subFunctionLog,
      required Uint8List Function() on0x50,
      Uint8List Function()? on0x22,
    }) {
      const int pairingKey = 0x42;
      return (ModbusRequest request) async {
        final umasReq = request as UmasRequest;
        subFunctionLog.add(umasReq.umasSubFunction);

        if (umasReq.umasSubFunction == 0x02) {
          // readPlcId
          final resp = BytesBuilder();
          resp.add([0x5A, 0x00, 0xFE]);
          final pd = ByteData(16);
          pd.setUint16(0, 1, Endian.little);
          pd.setUint32(2, 0x12345678, Endian.little);
          pd.setUint8(6, 1);
          pd.setUint16(7, 0, Endian.little);
          pd.setUint8(9, 1);
          pd.setUint16(10, 0, Endian.little);
          pd.setUint32(12, 0x10000, Endian.little);
          resp.add(pd.buffer.asUint8List());
          umasReq.internalSetFromPduResponse(
              Uint8List.fromList(resp.toBytes()));
          return ModbusResponseCode.requestSucceed;
        }
        if (umasReq.umasSubFunction == 0x01) {
          // init
          final resp = BytesBuilder();
          resp.add([0x5A, pairingKey, 0xFE]);
          final pd = ByteData(2);
          pd.setUint16(0, 1021, Endian.little);
          resp.add(pd.buffer.asUint8List());
          umasReq.internalSetFromPduResponse(
              Uint8List.fromList(resp.toBytes()));
          return ModbusResponseCode.requestSucceed;
        }
        if (umasReq.umasSubFunction == 0x04) {
          // plcStatus: status + notUsed(2) + numBlocks(1) + crc(4 LE)
          final resp = BytesBuilder();
          resp.add([0x5A, pairingKey, 0xFE]);
          resp.add([0x03, 0x00, 0x00]);
          resp.addByte(1);
          final crc = ByteData(4);
          crc.setUint32(0, 0xAABBCCDD, Endian.little);
          resp.add(crc.buffer.asUint8List());
          umasReq.internalSetFromPduResponse(
              Uint8List.fromList(resp.toBytes()));
          return ModbusResponseCode.requestSucceed;
        }
        if (umasReq.umasSubFunction == 0x50) {
          umasReq.internalSetFromPduResponse(on0x50());
          return ModbusResponseCode.requestSucceed;
        }
        if (umasReq.umasSubFunction == 0x22 && on0x22 != null) {
          umasReq.internalSetFromPduResponse(on0x22());
          return ModbusResponseCode.requestSucceed;
        }
        // Unknown sub-function: success header only.
        umasReq.internalSetFromPduResponse(
            Uint8List.fromList([0x5A, pairingKey, 0xFE]));
        return ModbusResponseCode.requestSucceed;
      };
    }

    /// Build a 0x82 error PDU mirroring the production wire-format
    /// (errorCode=0x82, secondary=0x80 → `UmasException(130, sec=128)`).
    Uint8List error0x82() =>
        Uint8List.fromList([0x5A, 0x42, 0xFD, 0x82, 0x80]);

    /// Build a non-0x82 error PDU (errorCode=0x40, no secondary).
    Uint8List errorOther() => Uint8List.fromList([0x5A, 0x42, 0xFD, 0x40]);

    test(
        'after 3 consecutive 0x82 responses, MonitorPlc is bypassed '
        'and 0x22 ReadVariable runs instead', () async {
      final log = <int>[];
      final client = UmasClient(
        sendFn: buildSendFn(
          subFunctionLog: log,
          on0x50: error0x82,
          // 0x22 also fails so the read returns an error, but with a
          // different code so the test can assert the gate was bypassed
          // (i.e. 0x22 was attempted at all).
          on0x22: errorOther,
        ),
        backoffDelay: (_) async {},
        useMonitorPlc: true,
      );

      // Pre-seed plcStatus so 0x22 path has block CRCs available.
      await client.readPlcStatus();

      // Three trip-priming calls — all should throw 0x82 from MonitorPlc.
      for (var i = 0; i < 3; i++) {
        await expectLater(
          () => client.readVariables(variables),
          throwsA(isA<UmasException>().having(
              (e) => e.errorCode, 'errorCode (call $i)', 0x82)),
          reason: 'call $i must surface the underlying 0x82',
        );
      }

      expect(client.monitorPlcDegraded, isTrue,
          reason: 'breaker must latch after 3 consecutive 0x82 responses');
      expect(client.useMonitorPlc, isTrue,
          reason: 'TD-009: M580 hardware bit MUST remain set');

      // Fourth call: gate is bypassed → 0x22 must be attempted.
      log.clear();
      await expectLater(
        () => client.readVariables(variables),
        throwsA(isA<UmasException>()),
        reason: '0x22 fallback path also fails in this test',
      );
      expect(log, contains(0x22),
          reason: 'degraded breaker MUST route through 0x22 ReadVariable');
      expect(log, isNot(contains(0x50)),
          reason: 'degraded breaker MUST bypass MonitorPlc');

      client.dispose();
    });

    test(
        'breaker auto-clears after retry window; next call re-probes '
        'MonitorPlc', () async {
      final log = <int>[];
      final client = UmasClient(
        sendFn: buildSendFn(
          subFunctionLog: log,
          on0x50: error0x82,
          on0x22: errorOther,
        ),
        backoffDelay: (_) async {},
        useMonitorPlc: true,
      );

      // Drive the clock from a fake `now`.
      var fakeNow = DateTime.utc(2026, 1, 1, 12, 0, 0);
      client.nowFn = () => fakeNow;

      await client.readPlcStatus();

      // Trip the breaker.
      for (var i = 0; i < 3; i++) {
        await expectLater(
          () => client.readVariables(variables),
          throwsA(isA<UmasException>()),
        );
      }
      expect(client.monitorPlcDegraded, isTrue);

      // Advance past the retry window (60s + a smidge).
      fakeNow = fakeNow.add(const Duration(seconds: 61));

      log.clear();
      await expectLater(
        () => client.readVariables(variables),
        throwsA(isA<UmasException>()),
      );
      // After the stale-clear, MonitorPlc is retried first.
      expect(log, contains(0x50),
          reason: 'breaker MUST auto-clear and retry MonitorPlc after '
              '_monitorPlcDegradedRetryAfter');

      client.dispose();
    });

    test(
        'non-0x82 outcome resets the consecutive-0x82 counter so '
        'transient 0x82s do not trip the breaker', () async {
      final log = <int>[];
      // Alternating 0x82, 0x82, non-0x82, 0x82, 0x82 — never 3 in a row.
      final responseSequence = <Uint8List Function()>[
        error0x82,
        error0x82,
        errorOther, // resets counter
        error0x82,
        error0x82,
      ];
      var idx = 0;
      final client = UmasClient(
        sendFn: buildSendFn(
          subFunctionLog: log,
          on0x50: () {
            final r = responseSequence[idx % responseSequence.length]();
            idx++;
            return r;
          },
        ),
        backoffDelay: (_) async {},
        useMonitorPlc: true,
      );

      await client.readPlcStatus();

      for (var i = 0; i < responseSequence.length; i++) {
        await expectLater(
          () => client.readVariables(variables),
          throwsA(isA<UmasException>()),
        );
      }

      expect(client.monitorPlcDegraded, isFalse,
          reason: 'a non-0x82 outcome between 0x82s MUST reset the '
              'consecutive counter so we never reach the trip threshold');
      expect(client.useMonitorPlc, isTrue);
      client.dispose();
    });

    test(
        'when degraded breaker is tripped, 0xA1A1 from 0x22 path '
        'does NOT re-enter MonitorPlc', () async {
      // TD-022 follow-up: the existing breaker gates the top of
      // readVariables, but the 0xA1A1 catch in the 0x22 fallback path
      // unconditionally calls monitorRegisterAndRead(...). On M580
      // firmware that returns 0xA1A1 from 0x22, every read after the
      // breaker latches still re-enters MonitorPlc and gets 0x82 again
      // — the bypass becomes a no-op. The catch MUST honor the
      // breaker: when degraded, rethrow instead of re-entering 0x50.
      final log = <int>[];
      // 0x22 returns the M580 marker 0xA1A1 (errorCode=0xA1, sec=0xA1).
      Uint8List error0xA1A1() =>
          Uint8List.fromList([0x5A, 0x42, 0xFD, 0xA1, 0xA1]);
      final client = UmasClient(
        sendFn: buildSendFn(
          subFunctionLog: log,
          on0x50: error0x82,
          on0x22: error0xA1A1,
        ),
        backoffDelay: (_) async {},
        useMonitorPlc: true,
      );

      await client.readPlcStatus();

      // Trip the breaker via three consecutive 0x82 from MonitorPlc.
      for (var i = 0; i < 3; i++) {
        await expectLater(
          () => client.readVariables(variables),
          throwsA(isA<UmasException>().having(
              (e) => e.errorCode, 'errorCode (trip call $i)', 0x82)),
        );
      }
      expect(client.monitorPlcDegraded, isTrue,
          reason: 'precondition: breaker must be latched');

      // Snapshot MonitorPlc (0x50) traffic after the trip.
      final monitorCountAfterTrip = log.where((s) => s == 0x50).length;

      // Fourth call: gate bypasses 0x50 → 0x22 path runs → 0x22 returns
      // 0xA1A1 → catch MUST rethrow (not re-enter MonitorPlc).
      await expectLater(
        () => client.readVariables(variables),
        throwsA(isA<UmasException>().having(
            (e) => e.errorCode, 'errorCode (post-trip)', 0xA1)),
        reason: '0xA1A1 catch MUST honor the breaker and rethrow',
      );

      final monitorCountAfter4thCall = log.where((s) => s == 0x50).length;
      expect(monitorCountAfter4thCall, equals(monitorCountAfterTrip),
          reason: 'post-trip, 0xA1A1 catch MUST NOT issue any new '
              'MonitorPlc (0x50) request — the bypass would otherwise '
              'be defeated and the 0x82 cascade resumes');

      // TD-009 invariant: M580 hardware fingerprint is sticky.
      expect(client.useMonitorPlc, isTrue,
          reason: 'TD-009: _useMonitorPlc must remain set');

      client.dispose();
    });
  });
}
