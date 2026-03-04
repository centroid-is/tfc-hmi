// TODO: These tests belong in the open62541_dart bindings package, not here.
// They test raw OPC UA subscription/monitor behaviour (Inactivity,
// SubscriptionDeleted, SecureChannelClosed) using a real Server + Client.
// Move to open62541_dart when possible.
//
// Tests A-C verify raw open62541 behaviour:
// A) Heartbeat monitor prevents subscription inactivity during short traffic delays.
// B) SubscriptionDeleted fires on monitor streams when server deletes the subscription.
// C) SecureChannelClosed fires on monitor streams when TCP connection is killed.
//
// Tests D-E verify StateMan integration:
// D) ClientWrapper.startHeartbeat clears subscriptionId when the subscription dies.
// E) AutoDisposingStream filters Inactivity/SubscriptionDeleted errors.
import 'dart:async';
import 'dart:math';

import 'package:open62541/open62541.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:test/test.dart';

import 'proxy.dart';

final intNodeId = NodeId.fromString(1, "the.int");
final serverTimeNode = NodeId.fromNumeric(0, 2258);

void main() {
  final rng = Random();
  final serverPort = 14840 + rng.nextInt(1000);

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
    try {
      server.shutdown();
    } catch (_) {} // Test C shuts down the server early
    server.delete();
  });

  // --- Test A: uses TCP proxy to buffer server→client responses ---
  test(
      'A: Heartbeat prevents subscription inactivity during short traffic delay',
      () async {
    final proxy = TcpProxy(targetPort: serverPort);
    await proxy.start();

    // Long secure channel lifetime + no connectivity check so the client
    // doesn't kill the channel while responses are buffered.
    final client = Client(
      logLevel: LogLevel.UA_LOGLEVEL_WARNING,
      secureChannelLifeTime: Duration(minutes: 10),
      connectivityCheckInterval: Duration.zero,
    );
    final clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
      client.runIterate(Duration(milliseconds: 10));
    });
    await client.connect("opc.tcp://127.0.0.1:${proxy.port}");

    try {
      // Generous lifetime: 100ms × 600 = 60s.
      final subscriptionId = await client.subscriptionCreate(
        requestedPublishingInterval: Duration(milliseconds: 100),
        requestedLifetimeCount: 600,
        requestedMaxKeepAliveCount: 10,
      );

      // Heartbeat monitor (ServerStatus.CurrentTime VALUE-only)
      final heartbeatStream = client.monitoredItems(
        {
          serverTimeNode: [AttributeId.UA_ATTRIBUTEID_VALUE]
        },
        subscriptionId,
      );
      final heartbeatSub = heartbeatStream.listen((_) {});

      // Monitor the test int variable
      final stream = client.monitor(
        intNodeId,
        subscriptionId,
        samplingInterval: Duration(milliseconds: 100),
      );

      final values = <int>[];
      final errors = <Object>[];
      final sub = stream.listen(
        (event) => values.add(event.value as int),
        onError: (error) => errors.add(error),
      );

      // Wait for initial value (event-driven with timeout for slow CI)
      await Future.doWhile(() async {
        if (values.isNotEmpty) return false;
        await Future.delayed(Duration(milliseconds: 50));
        return true;
      }).timeout(Duration(seconds: 10),
          onTimeout: () => fail('Never received initial value'));

      server.write(intNodeId, DynamicValue(value: 42, typeId: NodeId.int32));

      // Wait for the write to arrive
      final preWriteCount = values.length;
      await Future.doWhile(() async {
        if (values.length > preWriteCount) return false;
        await Future.delayed(Duration(milliseconds: 50));
        return true;
      }).timeout(Duration(seconds: 5),
          onTimeout: () => fail('Write value never arrived'));

      final preBlockCount = values.length;

      // Buffer server→client responses for 2 seconds.
      // Client→server traffic still flows, keeping the subscription alive
      // on the server side. The client just doesn't see responses.
      proxy.bufferServerToClient = true;
      await Future.delayed(Duration(seconds: 2));
      proxy.bufferServerToClient = false;
      proxy.flush();

      // Write a sentinel value — if subscription survived, we'll see it.
      server.write(intNodeId, DynamicValue(value: 999, typeId: NodeId.int32));

      // Wait for sentinel (event-driven — returns early on fast machines)
      await Future.doWhile(() async {
        if (values.contains(999)) return false;
        await Future.delayed(Duration(milliseconds: 50));
        return true;
      }).timeout(Duration(seconds: 15),
          onTimeout: () =>
              fail('Sentinel value 999 never arrived — subscription died'));

      expect(values.length, greaterThan(preBlockCount),
          reason: 'Subscription survived buffered traffic delay');

      await sub.cancel();
      await heartbeatSub.cancel();
    } finally {
      clientTimer.cancel();
      await client.delete();
      await proxy.shutdown();
    }
  }, timeout: Timeout(Duration(seconds: 60)));

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
        {
          serverTimeNode: [AttributeId.UA_ATTRIBUTEID_VALUE]
        },
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
        intNodeId,
        subscriptionId,
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

      // Wait long enough for the server to delete the subscription.
      // 10 outstanding × 10ms keepAlive + 30ms lifetime + generous margin.
      await Future.delayed(Duration(seconds: 5));

      // Resume client → BadNoSubscription → SubscriptionDeleted
      clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
        client.runIterate(Duration(milliseconds: 10));
      });

      await deletedCompleter.future.timeout(
        Duration(seconds: 15),
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
  }, timeout: Timeout(Duration(seconds: 60)));

  // --- Test C: server shutdown → SecureChannelClosed on monitor streams ---
  test(
      'C: SecureChannelClosed fires on monitor streams when connection is killed',
      () async {
    final client = Client(logLevel: LogLevel.UA_LOGLEVEL_WARNING);
    final clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
      client.runIterate(Duration(milliseconds: 10));
    });
    await client.connect("opc.tcp://127.0.0.1:$serverPort");

    try {
      final subscriptionId = await client.subscriptionCreate(
        requestedPublishingInterval: Duration(milliseconds: 100),
        requestedLifetimeCount: 600,
        requestedMaxKeepAliveCount: 10,
      );

      final errors = <Object>[];
      final closedCompleter = Completer<void>();
      final stream = client.monitor(
        intNodeId,
        subscriptionId,
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

      // Shut down the OPC UA server → client detects disconnect →
      // SecureChannelClosed fires on monitor streams.
      serverTimer.cancel();
      server.shutdown();

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
    }
  }, timeout: Timeout(Duration(seconds: 30)));

  // --- Test D: ClientWrapper.startHeartbeat clears subscriptionId on death ---
  test('D: Heartbeat clears subscriptionId when subscription expires',
      () async {
    final client = Client(logLevel: LogLevel.UA_LOGLEVEL_WARNING);
    Timer? clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
      client.runIterate(Duration(milliseconds: 10));
    });
    await client.connect("opc.tcp://127.0.0.1:$serverPort");

    try {
      // Very short-lived subscription (same as test B)
      final subId = await client.subscriptionCreate(
        requestedPublishingInterval: Duration(milliseconds: 10),
        requestedLifetimeCount: 3,
        requestedMaxKeepAliveCount: 1,
      );

      // Wire up ClientWrapper with the real client and start heartbeat
      final config = OpcUAConfig()
        ..endpoint = "opc.tcp://127.0.0.1:$serverPort";
      final wrapper = ClientWrapper(client, config);
      wrapper.subscriptionId = subId;
      wrapper.startHeartbeat(subId);

      // Confirm heartbeat is running
      await Future.delayed(Duration(milliseconds: 500));
      expect(wrapper.subscriptionId, equals(subId));

      // Pause client → server exhausts publish requests → subscription expires
      clientTimer.cancel();
      clientTimer = null;
      await Future.delayed(Duration(seconds: 5));

      // Resume client → Inactivity/SubscriptionDeleted → heartbeat should
      // clear subscriptionId
      clientTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
        client.runIterate(Duration(milliseconds: 10));
      });

      // Wait for subscriptionId to be cleared
      await Future.doWhile(() async {
        if (wrapper.subscriptionId == null) return false;
        await Future.delayed(Duration(milliseconds: 50));
        return true;
      }).timeout(Duration(seconds: 15),
          onTimeout: () => fail(
              'subscriptionId was never cleared — heartbeat did not clean up'));

      expect(wrapper.subscriptionId, isNull,
          reason:
              'Heartbeat should clear subscriptionId on Inactivity/SubscriptionDeleted');
      expect(wrapper.connectionStatus, ConnectionStatus.disconnected,
          reason:
              'Connection status should be disconnected after subscription death');

      wrapper.dispose();
    } finally {
      clientTimer?.cancel();
      await client.delete();
    }
  }, timeout: Timeout(Duration(seconds: 60)));

  // --- Test E: AutoDisposingStream filters subscription-level errors ---
  test(
      'E: AutoDisposingStream filters Inactivity/SubscriptionDeleted from widget streams',
      () async {
    final widgetErrors = <Object>[];

    final ads = AutoDisposingStream<int>('test.key', (_) {},
        idleTimeout: Duration(minutes: 10));

    // Add a widget listener to capture what the widget stream sees
    final widgetSub = ads.stream.listen(
      (_) {},
      onError: (error) => widgetErrors.add(error),
    );

    // Create a raw stream that emits values then errors
    final rawController = StreamController<int>();
    ads.subscribe(rawController.stream, null);

    // Emit a normal value — should reach widget
    rawController.add(42);
    await Future.delayed(Duration(milliseconds: 50));
    expect(widgetErrors, isEmpty, reason: 'No errors yet');

    // Emit Inactivity — should NOT reach widget stream
    rawController.addError(Inactivity());
    await Future.delayed(Duration(milliseconds: 50));

    // Emit SubscriptionDeleted — should NOT reach widget stream
    rawController.addError(SubscriptionDeleted(1));
    await Future.delayed(Duration(milliseconds: 50));

    // Emit a regular error — SHOULD reach widget stream
    rawController.addError(Exception('real error'));
    await Future.delayed(Duration(milliseconds: 50));

    expect(widgetErrors.whereType<Inactivity>(), isEmpty,
        reason: 'Inactivity should be filtered from widget stream');
    expect(widgetErrors.whereType<SubscriptionDeleted>(), isEmpty,
        reason: 'SubscriptionDeleted should be filtered from widget stream');
    expect(widgetErrors, hasLength(1),
        reason: 'Only the real error should reach the widget');
    expect(widgetErrors.first, isA<Exception>());

    await widgetSub.cancel();
    await rawController.close();
  });
}
