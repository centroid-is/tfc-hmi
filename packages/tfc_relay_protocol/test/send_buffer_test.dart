/// Cases derived from Home Assistant's websocket_api test_http.py
/// (test_pending_msg_overflow, test_pending_msg_peak,
/// test_pending_msg_peak_recovery, test_pending_msg_peak_but_does_not_
/// overflow, test_enable_coalesce) mapped onto the conflating send buffer
/// from relay-comm-design.md §5 / notes §7.6. The clock is injected as
/// explicit timestamps so every case is deterministic.
library;

import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

void main() {
  group('conflation (last-value-wins)', () {
    test('1000 updates to one handle occupy one slot and drain to the latest',
        () {
      final buf = ConflatingSendBuffer(maxPending: 100);
      for (var i = 0; i < 1000; i++) {
        buf.putValue('s1', 7, WireValue.of(i));
      }
      expect(buf.pendingCount, 1,
          reason: 'memory bounded by subscription size, not update rate');
      final frame = buf.drain();
      expect(frame.subs['s1']!.changes[7]!.v, 999,
          reason: 'a slow client gets the newest value, never an old one');
    });

    test('drain leaves the buffer empty — recovery has no backlog to flush',
        () {
      final buf = ConflatingSendBuffer(maxPending: 100);
      buf.putValue('s1', 1, WireValue.of(1.5));
      buf.drain();
      expect(buf.pendingCount, 0);
      expect(buf.drain().isEmpty, isTrue);
    });

    test('a removed handle is reported once and revives on a new value', () {
      final buf = ConflatingSendBuffer(maxPending: 100);
      buf.putValue('s1', 3, WireValue.of(1));
      buf.remove('s1', 3);
      var frame = buf.drain();
      expect(frame.subs['s1']!.changes.containsKey(3), isFalse,
          reason: 'a removal supersedes the pending value');
      expect(frame.subs['s1']!.removed, [3]);
      buf.putValue('s1', 3, WireValue.of(2));
      frame = buf.drain();
      expect(frame.subs['s1']!.changes[3]!.v, 2);
      expect(frame.subs['s1']!.removed, isEmpty);
    });
  });

  group('quality-only transitions', () {
    test('a link transition cannot launder a non-finite reading back to good',
        () {
      // CR-04. The badNonFinite band is a property of the value: the number
      // is gone, and nothing about the link brings it back. Laundering it
      // reaches the client as null under good quality — a blank box that
      // reads as an unbound tag rather than the open-circuit input it is.
      final buf = ConflatingSendBuffer(maxPending: 100);
      buf.putValue('s1', 1, WireValue.of(double.nan));
      buf.putQuality('s1', 1, Quality.good);

      final staged = buf.drain().subs['s1']!.changes[1]!;
      expect(staged.v, isNull, reason: 'the number never survived sanitize');
      expect(staged.q, Quality.badNonFinite);
    });

    test('a worse quality still wins over a non-finite pending value', () {
      final buf = ConflatingSendBuffer(maxPending: 100);
      buf.putValue('s1', 1, WireValue.of(double.infinity));
      buf.putQuality('s1', 1, Quality.errorConfig);
      expect(buf.drain().subs['s1']!.changes[1]!.q, Quality.errorConfig,
          reason: 'a deleted tag is worse news than an unencodable number');
    });

    test('a healthy pending value takes the new quality outright', () {
      final buf = ConflatingSendBuffer(maxPending: 100);
      buf.putValue('s1', 1, WireValue.of(21.5, t: 99));
      buf.putQuality('s1', 1, Quality.badCommFault);
      final staged = buf.drain().subs['s1']!.changes[1]!;
      expect([staged.v, staged.q, staged.t],
          [21.5, Quality.badCommFault, 99],
          reason: 'the value and its source instant are untouched');
    });

    test('with nothing pending it stages as a quality-only entry', () {
      final buf = ConflatingSendBuffer(maxPending: 100);
      buf.putQuality('s1', 4, Quality.uncertainLastKnown);
      final sub = buf.drain().subs['s1']!;
      expect(sub.changes, isEmpty);
      expect(sub.qualities[4], Quality.uncertainLastKnown);
    });
  });

  group('priority lane', () {
    test('never conflated, order preserved, drains ahead of telemetry', () {
      final buf = ConflatingSendBuffer(maxPending: 100);
      buf.putValue('s1', 1, WireValue.of(42));
      buf.putPriority({'kind': 'writeAck', 'cmd': 'a'});
      buf.putPriority({'kind': 'writeAck', 'cmd': 'a'}); // identical, stays 2
      buf.putPriority({'kind': 'status'});
      final frame = buf.drain();
      expect(frame.priority, hasLength(3),
          reason: 'acks/status are never conflated or dropped');
      expect((frame.priority[0] as Map)['cmd'], 'a');
      expect((frame.priority[2] as Map)['kind'], 'status');
    });
  });

  group('overflow (HA test_pending_msg_overflow)', () {
    test('exceeding maxPending demands disconnect, immediately', () {
      final buf = ConflatingSendBuffer(maxPending: 1);
      buf.putPriority('m1');
      buf.putPriority('m2'); // 2 > 1 — HA closes the socket here
      final verdict = buf.poll(0);
      final disconnect = verdict as BufferDisconnect;
      expect(disconnect.closeCode, CloseCodes.backpressureOverrun);
    });

    test('conflated telemetry alone cannot overflow a sane bound', () {
      final buf = ConflatingSendBuffer(maxPending: 50);
      for (var i = 0; i < 10_000; i++) {
        buf.putValue('s1', i % 20, WireValue.of(i)); // 20 distinct handles
      }
      expect(buf.poll(0), isA<BufferOk>());
    });
  });

  group('sustained peak (HA test_pending_msg_peak family)', () {
    ConflatingSendBuffer make() => ConflatingSendBuffer(
        maxPending: 1000, peakThreshold: 5, peakWindowMs: 10_000);

    void fill(ConflatingSendBuffer buf, int n) {
      for (var i = 0; i < n; i++) {
        buf.putValue('s1', i, WireValue.of(i));
      }
    }

    test('above threshold for the full window: client cannot keep up', () {
      final buf = make();
      fill(buf, 6);
      expect(buf.poll(0), isA<BufferOk>(),
          reason: 'a burst is not a verdict');
      expect(buf.poll(9_999), isA<BufferOk>());
      final verdict = buf.poll(10_001) as BufferDisconnect;
      expect(verdict.closeCode, CloseCodes.backpressureOverrun);
      expect(verdict.reason, contains('keep up'));
    });

    test('recovering below threshold resets the window', () {
      final buf = make();
      fill(buf, 6);
      expect(buf.poll(0), isA<BufferOk>());
      buf.drain(); // client caught up at t=5000
      expect(buf.poll(5_000), isA<BufferOk>());
      fill(buf, 6); // new burst at t=6000
      expect(buf.poll(6_000), isA<BufferOk>());
      expect(buf.poll(12_000), isA<BufferOk>(),
          reason: 'only 6s above threshold since recovery — window reset');
      expect(buf.poll(16_001), isA<BufferDisconnect>());
    });

    test('a spike that ends inside the window never disconnects', () {
      final buf = make();
      for (var t = 0; t < 100_000; t += 1000) {
        // Busy tick, then a quiet one. The quiet tick is what closes the
        // window, and it is the *poll* that reads it: a count under the
        // threshold is the only recovery signal there is.
        fill(buf, 6);
        expect(buf.poll(t), isA<BufferOk>());
        buf.drain();
        fill(buf, 2);
        expect(buf.poll(t + 500), isA<BufferOk>());
        buf.drain();
      }
    });

    test('draining every tick does not reset the window (03-REVIEW WR-02)',
        () {
      // The falsification of the dead soft verdict. `drain()` used to clear
      // `_peakSinceMs` whenever it drained anything, so this loop — which is
      // exactly what the tick engine does — could run forever without ever
      // producing a verdict, and the soft ceiling was decorative.
      final buf = make();
      BufferVerdict? verdict;
      for (var t = 0; t <= 20_000 && verdict is! BufferDisconnect; t += 1000) {
        fill(buf, 6);
        verdict = buf.poll(t);
        buf.drain();
      }
      expect(verdict, isA<BufferDisconnect>(),
          reason: 'a client held above the soft ceiling on every tick for '
              'longer than the whole window must eventually be judged, and a '
              'drain the server performed on its own schedule is not the '
              'client saying it caught up');
    });
  });

  group('the priority lane has a byte budget as well as an entry count', () {
    // 03-REVIEW WR-04. `maxPending` counts entries, so 4096 arbitrarily large
    // ones fit under it — and json_rpc_2's parse-error responder appends the
    // *entire* offending frame into this lane verbatim.
    test('a few enormous priority entries exceed the byte ceiling', () {
      final buf = ConflatingSendBuffer(maxPending: 4096, maxPendingBytes: 1000);
      buf.putPriority('x' * 400);
      expect(buf.poll(0), isA<BufferOk>(),
          reason: 'two entries against a ceiling of 4096 is nothing, and 400 '
              'bytes against 1000 is nothing either');
      buf.putPriority('x' * 700);

      final verdict = buf.poll(0);
      expect(verdict, isA<BufferDisconnect>(),
          reason: 'two entries — 0.05% of the entry ceiling — are over the '
              'byte ceiling, which is the whole shape of the amplification');
      expect((verdict as BufferDisconnect).closeCode,
          CloseCodes.backpressureOverrun,
          reason: 'a lane that overran is a lane that overran, whichever '
              'dimension it overran in');
      expect(verdict.reason, contains('bytes'),
          reason: 'the reason has to say which ceiling, or whoever reads the '
              'log tunes the wrong number');
    });

    test('draining releases the byte budget', () {
      final buf = ConflatingSendBuffer(maxPending: 4096, maxPendingBytes: 1000);
      buf.putPriority('x' * 900);
      buf.drain();
      expect(buf.pendingBytes, 0);
      buf.putPriority('x' * 900);
      expect(buf.poll(0), isA<BufferOk>(),
          reason: 'the budget is what the lane is holding, not what it has '
              'ever held');
    });

    test('no byte ceiling is the default, and counts nothing against you', () {
      final buf = ConflatingSendBuffer(maxPending: 4096);
      buf.putPriority('x' * 10_000_000);
      expect(buf.poll(0), isA<BufferOk>(),
          reason: 'the protocol package keeps its own defaults permissive; '
              'ServerConfig is where the gateway\'s numbers live');
    });
  });
}
