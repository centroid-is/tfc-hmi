// TDD tests for the subscription heartbeat monitor.
//
// These tests verify that:
// A) A heartbeat monitor (ServerStatus.CurrentTime) on the subscription
//    prevents false inactivity during short traffic delays.
// B) SubscriptionDeleted fires on monitor streams when the server deletes
//    the subscription (due to lifetime expiry).
// C) SecureChannelClosed fires on monitor streams when the TCP connection
//    is killed.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:open62541/open62541.dart';
import 'package:test/test.dart';

final intNodeId = NodeId.fromString(1, "the.int");
final serverTimeNode = NodeId.fromNumeric(0, 2258);

/// TCP proxy that can buffer traffic (simulating network delay) or kill
/// connections (simulating connection drop).
///
/// When [blocked] is set to true, data is queued instead of forwarded.
/// When [blocked] is set back to false, all queued data is flushed.
/// This preserves the secure channel (no dropped/reordered messages).
class _TcpProxy {
  final int listenPort;
  final int targetPort;
  ServerSocket? _server;
  final List<_Pair> _pairs = [];
  bool _blocked = false;

  _TcpProxy({required this.listenPort, required this.targetPort});

  Future<void> start() async {
    _server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, listenPort);
    _server!.listen((clientSocket) async {
      try {
        final serverSocket = await Socket.connect(
            InternetAddress.loopbackIPv4, targetPort,
            timeout: Duration(seconds: 5));
        final pair = _Pair(clientSocket, serverSocket, this);
        _pairs.add(pair);
        pair.start();
      } catch (e) {
        clientSocket.destroy();
      }
    });
  }

  /// Buffer traffic while blocked, flush when unblocked.
  set blocked(bool value) {
    _blocked = value;
    if (!value) {
      for (final p in _pairs) {
        p.flush();
      }
    }
  }

  bool get blocked => _blocked;

  /// Kill all active connections but keep listening for new ones.
  void disconnectAll() {
    for (final p in _pairs) {
      p.close();
    }
    _pairs.clear();
  }

  Future<void> stop() async {
    disconnectAll();
    await _server?.close();
  }
}

class _Pair {
  final Socket client;
  final Socket server;
  final _TcpProxy proxy;
  bool _closed = false;
  final List<List<int>> _toServer = [];
  final List<List<int>> _toClient = [];

  _Pair(this.client, this.server, this.proxy);

  void start() {
    client.done.catchError((_) {});
    server.done.catchError((_) {});
    client.listen(
      (data) {
        if (proxy.blocked) {
          _toServer.add(List.from(data));
        } else {
          server.add(data);
        }
      },
      onDone: close,
      onError: (_) => close,
    );
    server.listen(
      (data) {
        if (proxy.blocked) {
          _toClient.add(List.from(data));
        } else {
          client.add(data);
        }
      },
      onDone: close,
      onError: (_) => close,
    );
  }

  void flush() {
    if (_closed) return;
    for (final data in _toServer) {
      server.add(data);
    }
    _toServer.clear();
    for (final data in _toClient) {
      client.add(data);
    }
    _toClient.clear();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      client.destroy();
    } catch (_) {}
    try {
      server.destroy();
    } catch (_) {}
  }
}

void main() {
  final rng = Random();
  final serverPort = 14840 + rng.nextInt(1000);
  final proxyPort = serverPort + 1000;

  late Server server;
  late Timer serverTimer;

  setUp(() async {
    server = Server(port: serverPort, logLevel: LogLevel.UA_LOGLEVEL_WARNING);
    server.start();

    DynamicValue intValue =
        DynamicValue(value: 0, typeId: NodeId.int32, name: "the.int");
    server.addVariableNode(intNodeId, intValue);

    serverTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
      server.runIterate();
    });
  });

  tearDown(() async {
    serverTimer.cancel();
    server.shutdown();
    server.delete();
  });

  // --- Test A: uses TCP proxy to buffer traffic ---
  test(
      'A: Heartbeat prevents subscription inactivity during short traffic delay',
      () async {
    final proxy =
        _TcpProxy(listenPort: proxyPort, targetPort: serverPort);
    await proxy.start();

    final client = Client(logLevel: LogLevel.UA_LOGLEVEL_WARNING);
    final clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
      client.runIterate(Duration(milliseconds: 10));
    });
    await client.connect("opc.tcp://127.0.0.1:$proxyPort");

    try {
      // Generous lifetime: 100ms × 600 = 60s (well beyond 3s delay).
      final subscriptionId = await client.subscriptionCreate(
        requestedPublishingInterval: Duration(milliseconds: 100),
        requestedLifetimeCount: 600,
        requestedMaxKeepAliveCount: 10,
      );

      // Heartbeat monitor (ServerStatus.CurrentTime VALUE-only)
      final heartbeatStream = client.monitoredItems(
        {serverTimeNode: [AttributeId.UA_ATTRIBUTEID_VALUE]},
        subscriptionId,
      );
      final heartbeatSub = heartbeatStream.listen((_) {});

      // Monitor the test int variable
      final stream = client.monitor(
        intNodeId, subscriptionId,
        samplingInterval: Duration(milliseconds: 100),
      );

      final values = <int>[];
      final errors = <Object>[];
      final sub = stream.listen(
        (event) => values.add(event.value as int),
        onError: (error) => errors.add(error),
      );

      // Confirm subscription works
      await Future.delayed(Duration(milliseconds: 500));
      expect(values, isNotEmpty, reason: 'Should have received initial value');

      server.write(intNodeId, DynamicValue(value: 42, typeId: NodeId.int32));
      await Future.delayed(Duration(milliseconds: 300));
      final preBlockCount = values.length;

      // Buffer traffic for 3 seconds (delay, not data loss)
      proxy.blocked = true;
      await Future.delayed(Duration(seconds: 3));
      proxy.blocked = false; // Flush

      // Give time for flushed publish responses to arrive
      await Future.delayed(Duration(seconds: 2));

      // Write new values — subscription should still be alive
      for (int i = 100; i < 103; i++) {
        server.write(intNodeId, DynamicValue(value: i, typeId: NodeId.int32));
        await Future.delayed(Duration(milliseconds: 200));
      }
      await Future.delayed(Duration(seconds: 1));

      final finalCount = values.length;
      expect(finalCount, greaterThan(preBlockCount),
          reason: 'Subscription survived buffered traffic delay');

      await sub.cancel();
      await heartbeatSub.cancel();
    } finally {
      clientTimer.cancel();
      await client.delete();
      await proxy.stop();
    }
  }, timeout: Timeout(Duration(seconds: 30)));

  // --- Test B: direct connection, pause runIterate to expire subscription ---
  test(
      'B: SubscriptionDeleted fires on monitor streams when subscription expires',
      () async {
    final client = Client(logLevel: LogLevel.UA_LOGLEVEL_WARNING);
    Timer? clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
      client.runIterate(Duration(milliseconds: 10));
    });
    await client.connect("opc.tcp://127.0.0.1:$serverPort");

    try {
      // Very short-lived subscription:
      //   publishingInterval = 10ms, maxKeepAlive = 1, lifetime = 3
      //   Total silence to kill: ~130ms
      final subscriptionId = await client.subscriptionCreate(
        requestedPublishingInterval: Duration(milliseconds: 10),
        requestedLifetimeCount: 3,
        requestedMaxKeepAliveCount: 1,
      );

      // Heartbeat monitor
      final heartbeatErrors = <Object>[];
      final deletedCompleter = Completer<void>();
      final heartbeatStream = client.monitoredItems(
        {serverTimeNode: [AttributeId.UA_ATTRIBUTEID_VALUE]},
        subscriptionId,
      );
      final heartbeatSub = heartbeatStream.listen(
        (_) {},
        onError: (error) {
          heartbeatErrors.add(error);
          if (error is SubscriptionDeleted && !deletedCompleter.isCompleted) {
            deletedCompleter.complete();
          }
        },
      );

      // Also monitor the int variable
      final monitorErrors = <Object>[];
      final monitorStream = client.monitor(
        intNodeId, subscriptionId,
        samplingInterval: Duration(milliseconds: 10),
      );
      final monitorSub = monitorStream.listen(
        (_) {},
        onError: (error) => monitorErrors.add(error),
      );

      // Confirm subscription works
      await Future.delayed(Duration(milliseconds: 500));

      // Pause client → server exhausts publish requests → subscription expires
      clientTimer.cancel();
      clientTimer = null;
      await Future.delayed(Duration(seconds: 2));

      // Resume client → BadNoSubscription → SubscriptionDeleted
      clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
        client.runIterate(Duration(milliseconds: 10));
      });

      await deletedCompleter.future.timeout(
        Duration(seconds: 10),
        onTimeout: () =>
            fail('SubscriptionDeleted never fired on heartbeat stream'),
      );

      expect(heartbeatErrors.whereType<SubscriptionDeleted>(), isNotEmpty,
          reason: 'Heartbeat stream should receive SubscriptionDeleted');

      await Future.delayed(Duration(milliseconds: 500));
      expect(monitorErrors.whereType<SubscriptionDeleted>(), isNotEmpty,
          reason: 'Monitor stream should also receive SubscriptionDeleted');

      await heartbeatSub.cancel();
      await monitorSub.cancel();
    } finally {
      clientTimer?.cancel();
      await client.delete();
    }
  }, timeout: Timeout(Duration(seconds: 30)));

  // --- Test C: TCP proxy disconnect → SecureChannelClosed on monitor streams ---
  test(
      'C: SecureChannelClosed fires on monitor streams when connection is killed',
      () async {
    final proxy =
        _TcpProxy(listenPort: proxyPort, targetPort: serverPort);
    await proxy.start();

    final client = Client(logLevel: LogLevel.UA_LOGLEVEL_WARNING);
    final clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
      client.runIterate(Duration(milliseconds: 10));
    });
    await client.connect("opc.tcp://127.0.0.1:$proxyPort");

    try {
      final subscriptionId = await client.subscriptionCreate(
        requestedPublishingInterval: Duration(milliseconds: 100),
        requestedLifetimeCount: 600,
        requestedMaxKeepAliveCount: 10,
      );

      final errors = <Object>[];
      final closedCompleter = Completer<void>();
      final stream = client.monitor(
        intNodeId, subscriptionId,
        samplingInterval: Duration(milliseconds: 100),
      );
      final sub = stream.listen(
        (_) {},
        onError: (error) {
          errors.add(error);
          if (error is SecureChannelClosed && !closedCompleter.isCompleted) {
            closedCompleter.complete();
          }
        },
      );

      // Confirm subscription works
      await Future.delayed(Duration(milliseconds: 500));

      // Stop the proxy entirely — kill connections AND close the listener.
      // The client detects the broken TCP connection and tries to reconnect,
      // but can't (proxy is gone), so the channel stays CLOSED.
      await proxy.stop();

      await closedCompleter.future.timeout(
        Duration(seconds: 10),
        onTimeout: () =>
            fail('SecureChannelClosed never fired on monitor stream'),
      );

      expect(errors.whereType<SecureChannelClosed>(), isNotEmpty,
          reason: 'Monitor stream should receive SecureChannelClosed');

      await sub.cancel();
    } finally {
      clientTimer.cancel();
      await client.delete();
      await proxy.stop();
    }
  }, timeout: Timeout(Duration(seconds: 20)));
}
