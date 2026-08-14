/// Every server number has one home, and the combinations that cannot work
/// are refused at construction rather than at 3 a.m.
///
/// The load-bearing case here is the heartbeat/ping relationship. 03-RESEARCH
/// Finding 7 measured it: with `pingInterval: 2s` and a TCP relay black-holing
/// traffic both ways, the server reaped the dead client 3.70 s after the
/// blackhole — 1.85× the interval. At the design's 20 s interval that is a
/// ~37 second window in which the gateway still believes a dead panel is
/// alive, holding its subscriptions, its send buffer and its upstream
/// monitored items. Without the construction rule asserted below, that window
/// is one config line away, and nothing in the running system complains about
/// it: the server simply detects half-open panels late, which is the one
/// thing SRV-05 exists to prevent.
///
/// The tick band (SRV-03) is the other one. A 500 ms tick still runs, still
/// passes every functional test, and is a silently different product — an
/// operator watching a 500 ms screen is watching a slideshow of the plant.
library;

import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:test/test.dart';

/// Matches an `ArgumentError` whose message names every one of [fragments].
///
/// The point is not that it threw — it is that an operator reading the crash
/// can see which two numbers disagreed without opening the source.
Matcher argumentErrorNaming(List<String> fragments) => isA<ArgumentError>()
    .having((e) => e.message.toString(), 'message',
        allOf(fragments.map(contains).toList()));

void main() {
  group('defaults', () {
    test('every knob has a default, and they are the researched numbers', () {
      final c = ServerConfig();

      expect(c.tick, const Duration(milliseconds: 100),
          reason: 'the tick is how often the screen can change; changing this '
              'default changes what operators see, not just a number');
      expect(c.heartbeatDeadline, const Duration(seconds: 6),
          reason: '6 s is OPC UA\'s 3× LifetimeCount ratio over a 2 s app '
              'heartbeat — the deadline that reaps a dead panel in seconds');
      expect(c.pingInterval, const Duration(seconds: 20),
          reason: 'the WS ping is NAT keepalive and backstop only; it is not '
              'the reaper, and a shorter interval would imply it is');
      expect(c.stallThreshold, const Duration(milliseconds: 300),
          reason: 'three ticks: comfortably above the +/-2 ms idle drift '
              'noise floor, so a reported stall means the event loop really '
              'stopped serving panels');
      expect(c.allowedOrigins, isEmpty,
          reason: 'an empty list rejects every browser Origin with 403 and '
              'leaves the non-browser panels, which send no Origin, working; '
              'Phase 6 supplies the real list');
      expect(c.maxPending, greaterThan(0));
      expect(c.peakThreshold, isNotNull);
      expect(c.peakWindowMs, 10_000,
          reason: 'matches ConflatingSendBuffer\'s own default, so the buffer '
              'this config configures behaves as its tests describe');
      expect(c.maxKeysPerSubscribe, greaterThan(1500),
          reason: 'a real panel carries about 1500 keys; a ceiling below that '
              'rejects a legitimate screen');
      expect(c.maxSubscriptionsPerSession, greaterThan(0));
    });

    test('the default combination is itself legal', () {
      expect(ServerConfig.new, returnsNormally,
          reason: 'a default that its own validation rejects is a server that '
              'cannot start');
    });
  });

  group('the tick band', () {
    test('a tick outside 50-100 ms is refused, naming the bound', () {
      expect(
          () => ServerConfig(tick: const Duration(milliseconds: 500)),
          throwsA(argumentErrorNaming(['500', '50', '100'])),
          reason: 'a 500 ms tick is a slideshow of the plant, and it would '
              'otherwise start and pass every functional test');

      expect(() => ServerConfig(tick: const Duration(milliseconds: 40)),
          throwsA(argumentErrorNaming(['40', '50', '100'])),
          reason: 'below the band the server burns a core to redraw screens '
              'nobody can read that fast');
    });

    test('both ends of the band are legal', () {
      expect(() => ServerConfig(tick: const Duration(milliseconds: 50)),
          returnsNormally);
      expect(() => ServerConfig(tick: const Duration(milliseconds: 100)),
          returnsNormally);
    });
  });

  group('liveness', () {
    test('heartbeat deadline at or beyond the ping interval is refused', () {
      expect(
          () => ServerConfig(
                heartbeatDeadline: const Duration(seconds: 25),
                pingInterval: const Duration(seconds: 20),
              ),
          throwsA(argumentErrorNaming(['25000 ms', '20000 ms'])),
          reason: 'a deadline the ping could beat leaves a ~37 s window in '
              'which the gateway believes a dead panel is alive and keeps '
              'serving its subscriptions to nobody');

      expect(
          () => ServerConfig(
                heartbeatDeadline: const Duration(seconds: 20),
                pingInterval: const Duration(seconds: 20),
              ),
          throwsA(argumentErrorNaming(['20000 ms'])),
          reason: 'equal is not safe either: detection was measured at 1.85x '
              'the ping interval, so a tie is still lost by the heartbeat');
    });

    test('a deadline comfortably inside the ping interval is accepted', () {
      expect(
          () => ServerConfig(
                heartbeatDeadline: const Duration(seconds: 6),
                pingInterval: const Duration(seconds: 20),
              ),
          returnsNormally,
          reason: 'the rule must refuse the unfireable case only; refusing '
              'the intended configuration would be worse than no rule');
    });

    test('a stall threshold inside the measurement noise is refused', () {
      expect(() => ServerConfig(stallThreshold: const Duration(milliseconds: 1)),
          throwsA(argumentErrorNaming(['1 ms'])),
          reason: 'idle drift alone measured +/-2 ms, so a 1 ms threshold '
              'reports a stalled event loop on a server doing nothing — and '
              'an alarm that is always on is an alarm nobody reads');
    });
  });

  group('the denial-of-service ceilings', () {
    test('a non-positive maxKeysPerSubscribe is refused', () {
      expect(() => ServerConfig(maxKeysPerSubscribe: 0),
          throwsA(argumentErrorNaming(['maxKeysPerSubscribe', '0'])),
          reason: 'zero means no panel can subscribe to anything, which is a '
              'server that starts and then serves nothing');
      expect(() => ServerConfig(maxKeysPerSubscribe: -1),
          throwsA(argumentErrorNaming(['maxKeysPerSubscribe'])));
    });

    test('a non-positive maxSubscriptionsPerSession is refused', () {
      expect(() => ServerConfig(maxSubscriptionsPerSession: 0),
          throwsA(argumentErrorNaming(['maxSubscriptionsPerSession', '0'])));
      expect(() => ServerConfig(maxSubscriptionsPerSession: -3),
          throwsA(argumentErrorNaming(['maxSubscriptionsPerSession'])));
    });

    test('a non-positive maxFrameBytes or maxPendingBytes is refused', () {
      expect(() => ServerConfig(maxFrameBytes: 0),
          throwsA(argumentErrorNaming(['maxFrameBytes'])));
      expect(() => ServerConfig(maxPendingBytes: -1),
          throwsA(argumentErrorNaming(['maxPendingBytes'])));
    });

    test('the ingress ceiling has room for the largest legitimate request',
        () {
      final config = ServerConfig();
      // A subscribe carrying the full key allowance, at a generous 60 bytes
      // per plant tag (`CN01.MOT01.speed` is 16). The ceiling exists to refuse
      // an order of magnitude, so a default that could refuse a real page
      // config would be a denial of service written as a defence.
      expect(config.maxFrameBytes,
          greaterThan(config.maxKeysPerSubscribe * 60),
          reason: 'the largest request a real panel sends is a page config of '
              'about ${config.maxKeysPerSubscribe} keys');
    });

    test('a non-positive maxPending is refused', () {
      expect(() => ServerConfig(maxPending: 0),
          throwsA(argumentErrorNaming(['maxPending'])),
          reason: 'the hard ceiling is what converts silent server-heap '
              'growth into a visible reconnect; zero disconnects everyone on '
              'the first pending message');
    });
  });

  test('the config is data, not a clock', () {
    final a = ServerConfig();
    final b = ServerConfig();
    expect(a.tick, b.tick,
        reason: 'two configs built from the same arguments must be the same '
            'configuration — nothing here may read a clock at construction');
  });
}
