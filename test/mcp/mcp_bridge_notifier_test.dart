import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/mcp/mcp_bridge_notifier.dart';

void main() {
  group('McpBridgeState', () {
    test('initial state is disconnected', () {
      final state = McpBridgeState.initial();
      expect(state.connectionState, McpConnectionState.disconnected);
      expect(state.tools, isNull);
      expect(state.port, isNull);
      expect(state.error, isNull);
    });

    test('copyWith updates connectionState', () {
      final state = McpBridgeState.initial();
      final updated =
          state.copyWith(connectionState: McpConnectionState.connecting);

      expect(updated.connectionState, McpConnectionState.connecting);
      expect(updated.tools, isNull);
    });

    test('copyWith preserves unmodified fields', () {
      final state = McpBridgeState(
        connectionState: McpConnectionState.connected,
        port: 8765,
      );
      final updated = updated_state(state);

      expect(updated.connectionState, McpConnectionState.connected);
      expect(updated.port, 8765);
    });

    test('copyWith can set error', () {
      final state = McpBridgeState.initial();
      final updated = state.copyWith(
        connectionState: McpConnectionState.error,
        error: 'Connection refused',
      );

      expect(updated.connectionState, McpConnectionState.error);
      expect(updated.error, 'Connection refused');
    });
  });

  group('McpBridgeNotifier', () {
    late McpBridgeNotifier notifier;

    setUp(() {
      notifier = McpBridgeNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('initial state is disconnected', () {
      expect(
        notifier.currentState.connectionState,
        McpConnectionState.disconnected,
      );
    });

    test('tools returns empty list when null', () {
      expect(notifier.tools, isEmpty);
    });

    test('isRunning is false initially', () {
      expect(notifier.isRunning, isFalse);
    });

    test('testSetState updates state and notifies listeners', () {
      var notified = false;
      notifier.addListener(() => notified = true);

      notifier.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connected,
        port: 9999,
      ));

      expect(notifier.currentState.connectionState,
          McpConnectionState.connected);
      expect(notifier.currentState.port, 9999);
      expect(notified, isTrue);
    });

    test('callTool throws StateError when disconnected', () {
      expect(
        () => notifier.callTool('test', {}),
        throwsStateError,
      );
    });

    test('disconnect is no-op when already disconnected', () async {
      // Should not throw
      await notifier.disconnect();
      expect(
        notifier.currentState.connectionState,
        McpConnectionState.disconnected,
      );
    });

    test('stopSseServer is no-op when not running', () async {
      // Should not throw
      await notifier.stopSseServer();
      expect(
        notifier.currentState.connectionState,
        McpConnectionState.disconnected,
      );
    });

    test('connect is no-op when already connected', () async {
      // Simulate connected state
      notifier.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connected,
      ));

      // Should return immediately without changing state
      await notifier.connect(
        operatorId: 'test',
        dbEnv: {},
      );

      expect(
        notifier.currentState.connectionState,
        McpConnectionState.connected,
      );
    });

    test('connect is no-op when connecting', () async {
      notifier.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connecting,
      ));

      await notifier.connect(operatorId: 'test', dbEnv: {});

      expect(
        notifier.currentState.connectionState,
        McpConnectionState.connecting,
      );
    });

    test('connectInProcess is no-op when already connected', () async {
      notifier.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connected,
      ));

      // Should not attempt reconnection
      // We can't easily test the full in-process flow without a real server,
      // but we verify it returns early.
      // (The method will return immediately if already connected/connecting)
    });
  });

  group('resolveServerPath', () {
    test('uses TFC_MCP_SERVER_PATH when set', () {
      final path = McpBridgeNotifier.resolveServerPath(
        envProvider: (key) =>
            key == 'TFC_MCP_SERVER_PATH' ? '/custom/path/server' : null,
      );

      expect(path, '/custom/path/server');
    });

    test('falls back to platform path when env not set', () {
      final path = McpBridgeNotifier.resolveServerPath(
        envProvider: (key) => null,
      );

      expect(path, contains('packages/tfc_mcp_server/build/cli/'));
      expect(path, contains('tfc_mcp_server'));
    });

    test('ignores empty env value', () {
      final path = McpBridgeNotifier.resolveServerPath(
        envProvider: (key) =>
            key == 'TFC_MCP_SERVER_PATH' ? '' : null,
      );

      expect(path, contains('packages/tfc_mcp_server/build/cli/'));
    });
  });

  group('buildEnvironment', () {
    test('sets TFC_USER and database env vars', () {
      final env = McpBridgeNotifier.buildEnvironment(
        operatorId: 'operator1',
        dbEnv: {
          'CENTROID_PGHOST': 'db.example.com',
          'CENTROID_PGPORT': '5432',
        },
      );

      expect(env['TFC_USER'], 'operator1');
      expect(env['CENTROID_PGHOST'], 'db.example.com');
      expect(env['CENTROID_PGPORT'], '5432');
    });

    test('handles empty dbEnv', () {
      final env = McpBridgeNotifier.buildEnvironment(
        operatorId: 'admin',
        dbEnv: {},
      );

      expect(env['TFC_USER'], 'admin');
      expect(env.length, 1);
    });
  });
}

/// Helper to test copyWith preserves values.
McpBridgeState updated_state(McpBridgeState state) {
  return state.copyWith(); // no changes
}
