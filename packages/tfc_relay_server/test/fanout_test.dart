/// The counter that stands between this gateway and a plant floor watching
/// yesterday's numbers.
///
/// 03-RESEARCH Finding 2 measured the two fan-out strategies at 100 clients ×
/// 200 changed keys per tick: `Peer.sendNotification`, which encodes once per
/// peer because `json_rpc_2` wraps each peer's channel in its own JSON codec,
/// cost **7 639 µs per tick**; encoding the body once and splicing per-client
/// envelopes around it cost **110 µs**. **69.6×**, and the wrong one throws
/// nothing, logs nothing and passes every functional test in this package.
/// The only symptom is a screen in a fish factory that is late. So the exact
/// integer in `expect(encoder.calls, …)` *is* the alarm, and it is asserted at
/// N=1 and at N=50 (03-CONTEXT amendment) because a shape that shares nothing
/// still looks right at one client.
///
/// **The honest property is per distinct changed-key set per tick**, not per
/// tick (Finding 3). Handles are server-global, so two panels watching one
/// motor produce byte-identical bodies and share one encode; two panels
/// watching different motors do not, and cost two. The disjoint case below is
/// named for that, so nobody later "fixes" a 50 into a 1.
///
/// **Everything here runs on `tickOnce(nowMs)`**, with the server's real timer
/// stopped where a real server is involved. A fan-out test that waited for a
/// `Timer.periodic` would be measuring the runner; the ordering case still
/// wants a real socket, because "the client received A before B" is a property
/// of the wire.
library;

import 'dart:async';
import 'dart:convert';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/src/frame_encoder.dart';
import 'package:tfc_relay_server/src/handle_table.dart';
import 'package:tfc_relay_server/src/lag_monitor.dart';
import 'package:tfc_relay_server/src/relay_server.dart';
import 'package:tfc_relay_server/src/relay_session.dart';
import 'package:tfc_relay_server/src/server_config.dart';
import 'package:tfc_relay_server/src/session_sink.dart';
import 'package:tfc_relay_server/src/tick_engine.dart';
import 'package:tfc_stateman_contract/channel_harness.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';
import 'package:tfc_stateman_contract/tfc_stateman_contract.dart';

import 'support/counting_encoder.dart';
import 'support/fake_clock.dart';
import 'support/ws_harness.dart';

/// One in-memory panel: a real session in its production shape, and every
/// frame the tick engine wrote to it.
///
/// The channel's sink is a [SessionSink] — the shape `relay_server.dart`
/// builds — so an RPC answer lands in the priority lane and reaches the client
/// only when a tick drains it. That is the property this file asserts on, so
/// it would be self-defeating to test it through a channel that bypassed it.
final class _Panel {
  _Panel(this.sub, this.session, this.client, this.frames);

  final String sub;
  final RelaySession session;
  final rpc.Client client;

  /// Everything [RelaySession.emit] wrote, in order — this session's wire.
  final List<String> frames;

  /// The `u` notifications received, decoded through the DTO so a hand-spliced
  /// envelope that drifted from `UpdateParams` fails here rather than on a
  /// panel.
  List<UpdateParams> get updates => [
        for (final frame in frames)
          if (_methodOf(frame) == Methods.update)
            UpdateParams.fromJson(_paramsOf(frame)),
      ];

  void clear() => frames.clear();
}

String? _methodOf(String frame) =>
    (jsonDecode(frame) as Map)['method'] as String?;

Map<String, Object?> _paramsOf(String frame) =>
    ((jsonDecode(frame) as Map)['params'] as Map).cast<String, Object?>();

/// A plant, a handle table, a registry and one tick engine — the server's
/// wiring without the sockets.
final class _Plant {
  _Plant() {
    addTearDown(dispose);
  }

  final api = FakeStateMan();
  final handles = HandleTable();
  final registry = SessionRegistry();
  final counter = CountingEncoder();
  final clock = FakeClock(start: 1_000_000);
  final config = ServerConfig(tick: ServerConfig.minTick);

  late final TickEngine engine = TickEngine(
    registry: registry,
    config: config,
    encoder: FrameEncoder(encode: counter.call),
    lag: LagMonitor(
      periodMs: config.tick.inMilliseconds,
      thresholdMs: config.stallThreshold.inMilliseconds,
    ),
    clock: clock.now,
  );

  final _panels = <_Panel>[];

  /// Seeds [count] keys with a value, so the source will serve them:
  /// `FakeStateMan.keys` filters to keys a value has arrived for, on purpose.
  List<String> seed(int count, {String prefix = 'CN01.MOT'}) {
    final keys = [for (var i = 0; i < count; i++) '$prefix$i.speed'];
    api.setValues({for (final key in keys) key: 0});
    return keys;
  }

  /// One tick at the next timestamp, exactly as the timer would have.
  int tick() {
    clock.advance(config.tick.inMilliseconds);
    engine.tickOnce(clock.nowMs);
    return clock.nowMs;
  }

  /// A connected, helloed, subscribed panel.
  Future<_Panel> connect(String sub, List<String> keys) async {
    final pair = channelPair();
    final buffer = ConflatingSendBuffer(maxPending: config.maxPending);
    final frames = <String>[];
    final session = RelaySession.serve(
      channel: StreamChannel<String>(pair.server.stream, SessionSink(buffer)),
      api: api,
      config: config,
      handles: handles,
      buffer: buffer,
      // Two destinations for one frame: the list this file asserts on, and the
      // far end, so the client's `Peer` can complete the request it is waiting
      // for. Both are what a socket would have done.
      emitFrame: (frame) {
        frames.add(frame);
        pair.server.sink.add(frame);
      },
    );
    registry.add(session);
    final client = rpc.Client(pair.client);
    unawaited(client.listen());
    final panel = _Panel(sub, session, client, frames);
    _panels.add(panel);

    await ask(
        panel,
        Methods.hello,
        HelloParams(
          protocol: protocolVersion,
          supported: const [protocolVersion],
          client: const PeerInfo('panel-under-test', '0.1.0'),
        ).toJson());
    await ask(panel, Methods.subscribe,
        SubscribeParams(sub: sub, keys: keys).toJson());
    return panel;
  }

  /// Sends a request and drains the tick that carries its answer.
  ///
  /// The tick is not an implementation detail leaking into the harness: in the
  /// production shape the answer sits in the priority lane until something
  /// drains it, and that something is the engine.
  Future<Object?> ask(_Panel panel, String method, Object? params) async {
    final pending = panel.client.sendRequest(method, params);
    await pumpEventQueue();
    tick();
    return within(pending, 'the $method answer, which reaches a client only '
        'because a tick drained the priority lane');
  }

  Future<void> dispose() async {
    for (final panel in _panels) {
      await panel.client.close();
      await panel.session.close(1000, 'test over');
    }
    _panels.clear();
    await engine.stop();
    await registry.dispose();
    await api.dispose();
  }
}

/// Pumps the event queue until [ready] is true, then returns.
///
/// A bounded pump rather than a `within()`, because what is being waited for
/// is a *state* the harness can read (a frame sitting in the priority lane)
/// and not a future anyone holds. It fails naming the state, so a timeout here
/// still reports the property.
Future<void> _until(bool Function() ready, String what,
    {int turns = 500}) async {
  for (var turn = 0; turn < turns; turn++) {
    if (ready()) return;
    await pumpEventQueue(times: 1);
  }
  fail('$what did not happen within $turns turns of the event queue');
}

void main() {
  group('encode-once fan-out', () {
    test('one client and two hundred changed handles cost one encode',
        () async {
      final plant = _Plant();
      final keys = plant.seed(200);
      final panel = await plant.connect('page-1', keys);

      // The warm-up tick pays the once-per-session costs — escaping the
      // subscription name, and the first body — so the counter that follows
      // measures one tick's fan-out and nothing else.
      plant.api.setValues({for (final key in keys) key: 1});
      plant.tick();
      plant.counter.reset();
      panel.clear();

      plant.api.setValues({for (final key in keys) key: 2});
      plant.tick();

      expect(plant.counter.calls, 1,
          reason: 'two hundred handles are one body; encoding per key or per '
              'client is the 7 639 µs strategy, and its only symptom is a '
              'late screen');
      expect(panel.updates, hasLength(1),
          reason: 'a tick delivers a subscription one frame, not one per key');
      expect(panel.updates.single.changes, hasLength(200),
          reason: 'every changed handle rides in that one frame or a tag on '
              'the page silently stops updating');
    });

    test('fifty clients sharing a key set cost one encode', () async {
      final plant = _Plant();
      final keys = plant.seed(200);
      final panels = [
        for (var i = 0; i < 50; i++) await plant.connect('page-$i', keys),
      ];

      plant.api.setValues({for (final key in keys) key: 1});
      plant.tick();
      plant.counter.reset();
      for (final panel in panels) {
        panel.clear();
      }

      plant.api.setValues({for (final key in keys) key: 2});
      plant.tick();

      expect(plant.counter.calls, 1,
          reason: 'fifty panels watching one line share one body; encoding it '
              'fifty times burns 7.6 % of a core per tick and nothing '
              'anywhere reports it');
      expect([for (final panel in panels) panel.updates.length], everyElement(1),
          reason: 'sharing the body must not cost a client its frame');
    });

    test(
        'fifty clients with disjoint key sets cost one encode per distinct '
        'changed-key set', () async {
      final plant = _Plant();
      final sets = [
        for (var i = 0; i < 50; i++) plant.seed(4, prefix: 'CN$i.MOT'),
      ];
      for (var i = 0; i < 50; i++) {
        await plant.connect('page-$i', sets[i]);
      }

      for (final set in sets) {
        plant.api.setValues({for (final key in set) key: 1});
      }
      plant.tick();
      plant.counter.reset();

      for (final set in sets) {
        plant.api.setValues({for (final key in set) key: 2});
      }
      plant.tick();

      expect(plant.counter.calls, 50,
          reason: 'the promise is one encode per distinct changed-key set, '
              'not one per tick — fifty panels on fifty machines share '
              'nothing, and a test that expected 1 here would be asserting a '
              'thing this code cannot do');
    });
  });

  group('what one client gets around the shared body', () {
    test('every client gets its own sub name and its own seq', () async {
      final plant = _Plant();
      final keys = plant.seed(3);
      final panels = [
        for (var i = 0; i < 3; i++) await plant.connect('page-$i', keys),
      ];

      plant.api.setValues({for (final key in keys) key: 7});
      plant.tick();

      for (var i = 0; i < panels.length; i++) {
        final update = panels[i].updates.single;
        expect(update.sub, 'page-$i',
            reason: 'a frame addressed to the wrong subscription lands in the '
                'wrong page\'s cache, which is a wrong number on a screen '
                'rather than a missing one');
        expect(update.seq, 1,
            reason: 'seq is per subscription and starts at the first push; a '
                'shared counter would make every page resync when any other '
                'page moved');
      }
    });

    test('a subscription whose keys did not change gets no u frame', () async {
      final plant = _Plant();
      final watched = plant.seed(2, prefix: 'CN01.PUMP');
      final quiet = plant.seed(2, prefix: 'CN02.PUMP');
      final busy = await plant.connect('busy', watched);
      final idle = await plant.connect('idle', quiet);

      plant.api.setValues({for (final key in watched) key: 5});
      plant.tick();

      expect(busy.updates, hasLength(1),
          reason: 'the page whose tags moved must be told');
      expect(idle.updates, isEmpty,
          reason: 'a page whose tags are steady must not be handed an empty '
              'frame; its liveness is the tick notification, and a u frame '
              'with no changes would advance a seq for nothing');
    });

    test('two changes to one key in a tick ship once, carrying the latest',
        () async {
      final plant = _Plant();
      final keys = plant.seed(1, prefix: 'CN01.VALVE');
      final panel = await plant.connect('page-1', keys);
      final handle = plant.handles.handleFor(keys.single);

      plant.api.setValue(keys.single, 41);
      plant.api.setValue(keys.single, 42);
      plant.tick();

      final update = panel.updates.single;
      expect(update.changes[handle]?.v, 42,
          reason: 'conflation keeps the latest reading; shipping the older one '
              'would put a number on the screen the plant has already left '
              'behind');
      expect(
          panel.frames.where((frame) => frame.contains('41')), isEmpty,
          reason: 'the intermediate value must never reach the client — a '
              'queue that replays it is the backlog conflation exists to '
              'refuse');
    });
  });

  group('lane order, over a real socket', () {
    test('priority frames arrive before telemetry in the same tick', () async {
      final fixture = relayFixture(config: ServerConfig(tick: ServerConfig.maxTick));
      await fixture.ready;

      // The server's own timer is stopped and the ticks are driven by hand:
      // "both frames were pending in the same tick" is the property, and a
      // free-running timer would decide that for us at random.
      final engine = fixture.server.engine!;
      await engine.stop();
      final session = fixture.server.sessions.sessions.single;
      final clock = FakeClock(start: 2_000_000);
      int tick() {
        clock.advance(100);
        engine.tickOnce(clock.nowMs);
        return clock.nowMs;
      }

      final hello = fixture.request(Methods.hello, params: helloParams());
      await _until(() => session.buffer.pendingCount > 0,
          'the hello answer reaching the priority lane');
      tick();
      await within(hello, 'the hello answer over a real socket');

      const key = 'CN01.MOT01.speed';
      fixture.served.setValue(key, 1);
      final subscribed = fixture.request(Methods.subscribe,
          params: const SubscribeParams(sub: 'page-1', keys: [key]).toJson());
      await _until(() => session.buffer.pendingCount > 0,
          'the subscribe answer reaching the priority lane');
      tick();
      await within(subscribed, 'the subscribe answer over a real socket');

      // Both lanes loaded, no tick in between: an RPC answer in the priority
      // lane and a plant change in the telemetry lane.
      final ping = fixture.request(Methods.ping);
      await _until(() => session.buffer.pendingCount > 0,
          'the ping answer reaching the priority lane');
      fixture.served.setValue(key, 2);
      expect(session.buffer.pendingCount, greaterThan(1),
          reason: 'the case is only meaningful if both lanes were loaded when '
              'the tick ran');
      tick();
      await within(ping, 'the ping answer over a real socket');

      await _until(
          () => fixture.inbound.any((f) => f.contains('"method":"u"')),
          'the update frame reaching the client');
      final frames = fixture.inbound;
      final answer = frames.lastIndexWhere((f) => f.contains('"serverTime"') &&
          !f.contains('"method"'));
      final update =
          frames.indexWhere((f) => f.contains('"method":"${Methods.update}"'));
      expect(answer, greaterThanOrEqualTo(0),
          reason: 'the ping answer must have reached the client at all');
      expect(update, greaterThan(answer),
          reason: 'an RPC answer and a resync announcement must overtake '
              'telemetry, or a client already behind never learns why — the '
              'priority lane is the only news that survives a degraded link');
    }, tags: 'ws');
  });
}
