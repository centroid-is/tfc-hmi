import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/mcp/mcp_bridge_notifier.dart';

void main() {
  group('McpBridgeState', () {
    test('initial state is disconnected', () {
      final state = McpBridgeState.initial();
      expect(state.connectionState, McpConnectionState.disconnected);
      expect(state.port, isNull);
      expect(state.error, isNull);
    });
  });

  group('McpConnectionState', () {
    test('has all expected values', () {
      expect(McpConnectionState.values, hasLength(4));
      expect(
          McpConnectionState.values, contains(McpConnectionState.disconnected));
      expect(
          McpConnectionState.values, contains(McpConnectionState.connecting));
      expect(McpConnectionState.values, contains(McpConnectionState.connected));
      expect(McpConnectionState.values, contains(McpConnectionState.error));
    });
  });

  group('McpBridgeNotifier', () {
    late McpBridgeNotifier notifier;

    setUp(() {
      notifier = McpBridgeNotifier();
    });

    tearDown(() async {
      await notifier.dispose();
    });

    test('initial state is disconnected', () {
      final state = notifier.currentState;
      expect(state.connectionState, McpConnectionState.disconnected);
    });

    test('isRunning is false when not started', () {
      expect(notifier.isRunning, isFalse);
    });

    test('stopSseServer is safe when already disconnected (no-op)', () async {
      await notifier.stopSseServer();
      expect(
          notifier.currentState.connectionState, McpConnectionState.disconnected);
    });

    test('dispose is safe when not started', () async {
      await notifier.dispose();
      expect(
          notifier.currentState.connectionState, McpConnectionState.disconnected);
    });

    test('notifies listeners when state changes', () {
      var notifyCount = 0;
      notifier.addListener(() => notifyCount++);

      // Simulate a state change (use the test setter)
      notifier.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connected,
        port: 8765,
      ));

      expect(notifyCount, 1);
      expect(notifier.currentState.connectionState,
          McpConnectionState.connected);
      expect(notifier.currentState.port, 8765);

      // Another state change
      notifier.testSetState(McpBridgeState.initial());
      expect(notifyCount, 2);
      expect(notifier.currentState.connectionState,
          McpConnectionState.disconnected);
    });
  });

  group('Preference keys', () {
    test('consolidated config key is defined', () {
      expect(kMcpConfigKey, 'mcp.config');
    });
  });
}
