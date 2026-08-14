/// `RemoteStateMan`: the `StateManApi` a panel actually holds.
///
/// The class is structurally `ChannelStateMan` — same store, same
/// synchronous-answers-from-cache shape, same `subscribe` adapter — and the
/// value of this file is entirely in the four differences a socket forces,
/// which `channel_state_man.dart:60-65` lists as deliberately absent there:
/// there is no connection at construction, every async method waits on a
/// readiness barrier, every request carries a deadline, and a write that dies
/// in flight resolves *unknown* rather than throwing.
///
/// **Why "constructs with nothing listening" is the first case.** The shared
/// contract suite calls `StateManApi Function() make` synchronously
/// (04-RESEARCH Finding 6), so a client that connected in its constructor could
/// not be handed to it at all. That constraint is also the right production
/// shape: a panel in the packing hall boots with the rest of the line, on a
/// switch still learning MAC addresses, and a client that threw at construction
/// would put the plant's start-up order in the operator's hands.
///
/// **The bite for CLI-06** is `an unchanged value notifies nobody`. A store
/// wired to notify unconditionally passes every other value case in this file —
/// the numbers are all correct, they just arrive too often — and fails that one.
/// It is asserted with an anti-vacuity arm in the same case: the counter must
/// move for the changed value that follows, or the zero is a measurement of
/// nothing.
///
/// **The bite for the write path** is `a reconnect re-queries status and never
/// re-actuates`. An implementation that re-sent the original `write` after a
/// reconnect passes "the write eventually resolves" and fails that one — and on
/// a plant, re-sending is a second stroke of a ram an operator commanded once.
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_relay_client/src/client_config.dart';
import 'package:tfc_relay_client/src/connection_supervisor.dart';
import 'package:tfc_relay_client/src/remote_state_man.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:tfc_relay_server/tfc_relay_server.dart';
import 'package:tfc_stateman_contract/faults.dart';
import 'package:tfc_stateman_contract/testing/fake_state_man.dart';

/// A key `FakeStateMan` seeds at construction, so a subscribe against a real
/// gateway answers with a real snapshot and no plant has to be simulated.
const String _seededKey = 'PIPE.connected';

/// A second seeded key, so the write cases can move one value without
/// disturbing the one the notification cases are counting on.
const String _writableKey = 'PIPE.rtt_ms';

/// The budget for "the panel came back", named once and used everywhere.
///
/// Generous against the tick-quantised round trip this transport carries
/// (04-RESEARCH Finding 8) plus a capped backoff draw: a liveness budget, not a
/// latency measurement.
const Duration _recovery = Duration(seconds: 5);

/// The client's timing knobs, with the deadline floor lowered deliberately.
///
/// Lowering it is explicit and greppable for the reason `client_config.dart`
/// gives — nobody lowers it in production by accident. Here it buys deadlines
/// short enough that a gateway which accepts a socket and then says nothing
/// fails the pass inside a case's own budget instead of stalling it.
ClientConfig _config({Duration? write}) => ClientConfig(
      controlDeadline: const Duration(milliseconds: 600),
      writeDeadline: write ?? const Duration(milliseconds: 600),
      freshnessDeadline: const Duration(seconds: 3),
      backoffBase: const Duration(milliseconds: 40),
      backoffCap: const Duration(seconds: 2),
      deadlineFloor: const Duration(milliseconds: 50),
    );

/// A real gateway on an ephemeral port, optionally behind a fault proxy.
///
/// The server package's own `relayFixture` is not reachable from here — it
/// lives in that package's `test/` tree, which no `package:` URI addresses — so
/// this is the same wiring, minus the client the fixture builds for itself.
Future<({FakeStateMan served, RelayServer server, FaultProxy? proxy, Uri uri})>
    _gateway({bool withProxy = false}) async {
  final served = FakeStateMan();
  final server = RelayServer(
    api: served,
    config: ServerConfig(tick: ServerConfig.minTick),
    // Several arms here provoke errors on purpose; a suite that printed a stack
    // per provoked error trains everyone to scroll past them.
    onError: (_, __, ___) {},
  );
  await server.start();
  addTearDown(server.close);
  addTearDown(served.dispose);

  FaultProxy? proxy;
  if (withProxy) {
    proxy = FaultProxy(targetPort: server.port);
    await proxy.start();
    addTearDown(proxy.shutdown);
  }
  final port = proxy?.port ?? server.port;
  return (
    served: served,
    server: server,
    proxy: proxy,
    uri: Uri.parse('ws://127.0.0.1:$port'),
  );
}

/// A client pointed at [uri], torn down with the case.
RemoteStateMan _client(Uri uri, {ClientConfig? config, Set<String>? keys}) {
  final client = RemoteStateMan(
    uri: uri,
    config: config ?? _config(),
    keys: keys ?? const {_seededKey, _writableKey},
  );
  addTearDown(client.dispose);
  return client;
}

/// Polls [done] until it holds or [budget] runs out, and fails naming [what].
///
/// A poll rather than a stream wait because what these cases are asserting is a
/// *state* the client reached, and the transition that got it there is the
/// supervisor's business, tested in `reconnect_test.dart`.
Future<void> _until(String what, bool Function() done,
    {Duration budget = _recovery}) async {
  final deadline = DateTime.now().add(budget);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after ${budget.inMilliseconds} ms waiting for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Long enough for the gateway's fan-out to have flushed whatever was set
/// before it, on a tick configured at [ServerConfig.minTick].
///
/// Used only where the property under test is that *nothing* arrives, which is
/// the one shape a poll cannot establish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  group('construction and the readiness barrier', () {
    test('constructing with nothing listening does not throw', () async {
      // A port nothing is bound to: the panel's ordinary state at power-on.
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();

      final client = _client(Uri.parse('ws://127.0.0.1:$port'));

      // Constructed, dialling, and answering reads from an empty cache rather
      // than throwing or blocking.
      expect(client.read(_seededKey), isNull);
      expect(client.keys, isEmpty);
      expect(client.linkState, isNot(LinkState.ready));
    });

    test('a read before readiness answers from the cache synchronously',
        () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);

      // Same event-loop turn as the constructor: nothing can have arrived, and
      // `read` is documented never to be a round trip.
      expect(client.read(_seededKey), isNull);

      await _until('the link to reach ready', () => client.isReady);
      expect(client.read(_seededKey), isNotNull);
    });

    test('a request issued before the link exists completes once it comes up',
        () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);

      // Issued in the turn after construction — the barrier is shut, the peer
      // is null, and this call has to wait rather than fail.
      expect(client.isReady, isFalse);
      final value = await client.readFresh(_seededKey).timeout(_recovery);
      expect(value.quality, Quality.good);
    });

    test('dispose while a call is waiting for the link settles that call',
        () async {
      // The page that closed while a read was in flight. A future that never
      // settles is a spinner that never stops.
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();

      final client = RemoteStateMan(
        uri: Uri.parse('ws://127.0.0.1:$port'),
        config: _config(),
        keys: const {_seededKey},
      );
      // The expectation is attached *before* the dispose that provokes the
      // failure. A future that rejects with nothing listening yet reports to
      // the isolate's ambient handler, which `package:test` attributes to
      // whichever case runs next — the same trap `readiness_barrier.dart:83-87`
      // mutes on its own side.
      final pending = client.readFresh(_seededKey);
      final settled =
          expectLater(pending.timeout(_recovery), throwsA(isA<StateError>()));
      await client.dispose();
      await settled;
    });
  });

  group('answers from the store', () {
    test('listen returns the same notifier instance for the same key',
        () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);

      final first = client.listen(_seededKey);
      final second = client.listen(_seededKey);
      expect(identical(first, second), isTrue,
          reason: 'a widget holds the node it was handed');

      // And it survives the snapshot that fills it in — a resync that swapped
      // the node would take every listening widget dark.
      await _until('a snapshot', () => client.read(_seededKey) != null);
      expect(identical(client.listen(_seededKey), first), isTrue);
    });

    test('an unchanged value notifies nobody', () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);

      await _until('the first value', () => client.read(_seededKey) != null);
      final node = client.listen(_seededKey);
      final held = node.value.value;

      var notifications = 0;
      void count() => notifications++;
      node.addListener(count);
      addTearDown(() => node.removeListener(count));

      // Exactly what is already on screen, pushed again — the ordinary shape of
      // a gateway re-reading a device that has not moved.
      gateway.served.setValue(_seededKey, held);
      await _settle();
      expect(notifications, 0,
          reason: 'CLI-06: a page with 1500 keys must cost k rebuilds per '
              'batch, not 1500');

      // Anti-vacuity: the counter has to be able to move, or the zero above is
      // a measurement of a listener that was never wired up.
      gateway.served.setValue(_seededKey, !(held as bool));
      await _until('the changed value',
          () => client.read(_seededKey)?.value == !held);
      expect(notifications, 1);
    });

    test('keys excludes a key that was asked for but never arrived', () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);
      await _until('a snapshot', () => client.read(_seededKey) != null);

      // The mistyped page key. `listen` creates a node for anything, and
      // offering that back to the picker launders a typo into a valid binding.
      client.listen('PIPE.conected');

      expect(client.keys, contains(_seededKey));
      expect(client.keys, isNot(contains('PIPE.conected')));
    });

    test('a subscribe stream never listened to is still closed at dispose',
        () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);
      await _until('a snapshot', () => client.read(_seededKey) != null);

      final handedOut = client.subscribe(_seededKey);
      await client.dispose();

      await expectLater(
          handedOut.isEmpty.timeout(const Duration(seconds: 2)),
          completion(isTrue));
    });

    test('a subscribe stream delivers the values that arrive on it', () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);
      await _until('a snapshot', () => client.read(_seededKey) != null);

      final seen = <Object?>[];
      final sub = client.subscribe(_seededKey).listen((v) => seen.add(v.value));
      addTearDown(sub.cancel);

      gateway.served.setValue(_seededKey, false);
      await _until('the pushed value', () => seen.contains(false));
    });

    test('dispose is idempotent', () async {
      final gateway = await _gateway();
      final client = _client(gateway.uri);
      await _until('a snapshot', () => client.read(_seededKey) != null);

      await client.dispose();
      await client.dispose();

      // And nothing is left ticking: the watchdog's deadline and the pending
      // reconnect are the only two timers this client ever owns.
      expect(client.debugTimerCount, 0);
    });
  });
}
