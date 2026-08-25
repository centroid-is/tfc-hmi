@TestOn('!windows')
@Timeout(Duration(minutes: 3))
library;

// End-to-end reproduction of docs/opcua-frozen-session-repro.md (#345):
// OPC UA sessions freezing on live sockets while the app runs, with nothing
// ever surfacing as an error — so the old per-client loop, which only retried
// when `runIterate()` completed or `connect()` threw, never fired again and
// the UI showed the last values forever.
//
// Two shapes, both captured on the plant test station 2026-08-25:
//
//  A) The ".74" shape: the endpoint wedges during connect (channel dies
//     mid-session-create / the wire goes silent). No error is surfaced,
//     nothing retries, the client is permanently dead from t=+2s.
//  B) The ST101/CloseWait shape: an ACTIVATED session dies silently on an
//     Established socket. No state transition, no error, no log line — the
//     only symptom is that values (and the heartbeat) stop.
//
// The TcpProxy freeze() mode reproduces the network side of both: sockets
// stay Established, traffic just stops. The tests then assert the one thing
// that matters to an operator: values flow again, without an app restart,
// once the network heals — which requires StateMan's supervisor to notice
// the freeze on its own (session state for A, heartbeat/data age for B) and
// re-issue connect.

import 'dart:async';
import 'dart:math';

import 'package:open62541/open62541.dart';
import 'package:test/test.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../proxy.dart';

final intNodeId = NodeId.fromString(1, 'the.int');

// Short enough that both scenarios complete in seconds; the production
// defaults only change the magnitudes, not the mechanism.
const testSupervision = OpcuaSupervisionConfig(
  pollInterval: Duration(milliseconds: 100),
  retryInterval: Duration(milliseconds: 250),
  maxBackoff: Duration(seconds: 1),
  stuckTimeout: Duration(seconds: 3),
  heartbeatStaleTimeout: Duration(seconds: 2),
  connectTimeout: Duration(seconds: 2),
);

void main() {
  final rng = Random();
  final basePort = 15840 + rng.nextInt(1000);
  var testIndex = 0;

  late Server server;
  late Timer serverTimer;
  late Timer counterTimer;
  late TcpProxy proxy;
  late int serverPort;
  var counter = 0;

  setUp(() async {
    serverPort = basePort + testIndex++;
    server = Server(port: serverPort, logLevel: LogLevel.UA_LOGLEVEL_WARNING);
    server.start();
    server.addVariableNode(
        intNodeId, DynamicValue(value: 0, typeId: NodeId.int32, name: 'the.int'));
    serverTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      server.runIterate();
    });
    // The value climbs continuously so "values flow again" is provable: any
    // post-recovery emission is strictly greater than everything seen before
    // the freeze. A static value could be satisfied by a replayed cache.
    counter = 0;
    counterTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      counter++;
      server.write(intNodeId, DynamicValue(value: counter, typeId: NodeId.int32));
    });

    proxy = TcpProxy(targetPort: serverPort);
    await proxy.start();
  });

  tearDown(() async {
    counterTimer.cancel();
    serverTimer.cancel();
    await proxy.shutdown();
    try {
      server.shutdown();
    } catch (_) {}
    server.delete();
  });

  Future<StateMan> createStateMan() {
    final opcua = OpcUAConfig()
      ..endpoint = 'opc.tcp://127.0.0.1:${proxy.port}'
      ..serverAlias = 's1';
    return StateMan.create(
      config: StateManConfig(opcua: [opcua]),
      keyMappings: KeyMappings(nodes: {
        'myint': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'the.int')
            ..serverAlias = 's1',
        ),
      }),
      supervision: testSupervision,
    );
  }

  test('shape A: endpoint silent from startup — values arrive once the wire heals',
      () async {
    // Freeze BEFORE the client exists: connections are accepted (socket shows
    // Established) and then never answered — the connect wedges silently.
    proxy.freeze();

    final stateMan = await createStateMan();
    try {
      final received = <int>[];
      unawaited(stateMan.subscribe('myint').then((stream) {
        stream.listen((v) => received.add(v.asInt), onError: (_) {});
      }));

      // Give the old-code failure mode its window: one connect has been
      // fired-and-forgotten against the silent wire, runIterate() reports
      // nothing, and without a supervisor nothing will ever try again.
      await Future.delayed(const Duration(seconds: 6));
      expect(received, isEmpty,
          reason: 'sanity: nothing can arrive through a frozen proxy');

      proxy.unfreeze();

      // Recovery requires someone to re-issue connect — the frozen sockets
      // themselves never come back.
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (received.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      expect(received, isNotEmpty,
          reason: 'client must reconnect on its own after a wedged connect '
              '(the .74 shape: no error ever surfaces, so waiting for one '
              'means waiting forever)');
    } finally {
      await stateMan.close();
    }
  });

  test(
      'shape B: ACTIVATED session dies on an Established socket — heartbeat watchdog reconnects',
      () async {
    final stateMan = await createStateMan();
    try {
      final received = <int>[];
      final first = Completer<void>();
      final stream = await stateMan.subscribe('myint');
      stream.listen((v) {
        received.add(v.asInt);
        if (!first.isCompleted) first.complete();
      }, onError: (_) {});

      await first.future.timeout(const Duration(seconds: 15));
      // Let the heartbeat (server-time monitored item) tick at least once so
      // data age is measured from a live baseline.
      await Future.delayed(const Duration(seconds: 1));
      final maxBefore = received.reduce(max);

      // The plant lifecycle: the session dies, the socket stays Established,
      // not a single byte or state transition tells the client. Server-side
      // the peer is gone (it later FINs — CloseWait — but that arrives
      // minutes late in the field, so the client must not depend on it).
      proxy.freeze();
      await Future.delayed(const Duration(seconds: 5));

      proxy.unfreeze();

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while ((received.isEmpty || received.reduce(max) <= maxBefore) &&
          DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      expect(received.reduce(max), greaterThan(maxBefore),
          reason: 'values must resume after a silent session death: the '
              'heartbeat going stale while the session still reads ACTIVATED '
              'is the only timely signal (repro notes, watchdog item 4)');
    } finally {
      await stateMan.close();
    }
  });
}
