import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' show JsonSchema, Tool;
import 'package:riverpod/riverpod.dart';
import 'package:tfc_dart/core/preferences.dart';

import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/llm/llm_provider.dart';
import 'package:tfc/mcp/mcp_bridge_notifier.dart';
import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/preferences.dart';
import '../helpers/test_helpers.dart';

/// Fake LLM provider that records what tools were passed to complete().
class FakeLlmProvider implements LlmProvider {
  List<Map<String, dynamic>>? lastTools;
  int completeCalls = 0;

  @override
  LlmProviderType get providerType => LlmProviderType.claude;

  @override
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  }) async {
    completeCalls++;
    lastTools = tools;
    return const LlmResponse(
      content: 'test response',
      toolCalls: [],
      stopReason: 'end_turn',
    );
  }

  @override
  void dispose() {}

  @override
  String get apiKeyPreferenceKey => kClaudeApiKey;
}

void main() {
  group('sendMessage waits for bridge readiness', () {
    late ProviderContainer container;
    late McpBridgeNotifier bridge;
    late FakeLlmProvider fakeLlm;
    late Preferences testPrefs;

    setUp(() async {
      testPrefs = await createTestPreferences();
      bridge = McpBridgeNotifier();
      fakeLlm = FakeLlmProvider();

      container = ProviderContainer(
        overrides: [
          mcpBridgeProvider.overrideWith((ref) {
            ref.onDispose(() => bridge.dispose());
            return bridge;
          }),
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('sendMessage waits for bridge to connect before reading tools',
        () async {
      // Put bridge in "connecting" state (simulating chatLifecycleProvider async work)
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connecting,
      ));

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(fakeLlm);

      // Start sendMessage — it should wait for bridge to become ready
      final sendFuture = notifier.sendMessage('Hello');

      // Verify the LLM has NOT been called yet (bridge is still connecting)
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(fakeLlm.completeCalls, 0,
          reason: 'LLM should not be called while bridge is connecting');

      // Now simulate bridge becoming connected (with tools)
      bridge.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connected,
        tools: [
          Tool(
            name: 'get_tag_value',
            description: 'Get a tag value',
            inputSchema: JsonSchema.fromJson({'type': 'object'}),
          ),
        ],
      ));

      // sendMessage should now complete
      await sendFuture;

      // Verify the LLM was called
      expect(fakeLlm.completeCalls, greaterThan(0),
          reason: 'LLM should have been called after bridge connected');

      // Verify tools were passed to the LLM
      expect(fakeLlm.lastTools, isNotNull);
      expect(fakeLlm.lastTools, isNotEmpty,
          reason: 'Tools should have been available after waiting for bridge');
    });

    test('sendMessage proceeds without tools when bridge connection fails',
        () async {
      // Put bridge in "connecting" state
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connecting,
      ));

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(fakeLlm);

      // Start sendMessage
      final sendFuture = notifier.sendMessage('Hello');

      // Simulate bridge error
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.error,
        error: 'Connection refused',
      ));

      // sendMessage should still complete (graceful degradation)
      await sendFuture;

      // LLM was called but without tools
      expect(fakeLlm.completeCalls, 1);
      expect(fakeLlm.lastTools, isEmpty,
          reason: 'Tools should be empty when bridge errored');
    });

    test('sendMessage does not wait when bridge is already connected',
        () async {
      // Bridge is already connected with tools
      bridge.testSetState(McpBridgeState(
        connectionState: McpConnectionState.connected,
        tools: [
          Tool(
            name: 'list_assets',
            description: 'List assets',
            inputSchema: JsonSchema.fromJson({'type': 'object'}),
          ),
        ],
      ));

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(fakeLlm);

      await notifier.sendMessage('Hello');

      // LLM should have been called with tools immediately
      expect(fakeLlm.completeCalls, 1);
      expect(fakeLlm.lastTools, isNotEmpty);
    });

    test('sendMessage proceeds without tools when bridge is disconnected',
        () async {
      // Bridge is disconnected (no MCP at all)
      expect(
        bridge.currentState.connectionState,
        McpConnectionState.disconnected,
      );

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(fakeLlm);

      await notifier.sendMessage('Hello');

      // LLM should have been called without tools
      expect(fakeLlm.completeCalls, 1);
      expect(fakeLlm.lastTools, isEmpty);
    });

    test('sendMessage times out if bridge never finishes connecting', () async {
      // Put bridge in "connecting" state and never resolve it
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connecting,
      ));

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(fakeLlm);

      // Use a very short timeout for testing — we override waitForReady behavior
      // by leaving the bridge in connecting state. The default 10s timeout
      // will be used in production; here we just verify it doesn't hang forever.
      // The test itself calls sendMessage which uses the default timeout.
      // For testing, we simulate the bridge timing out by going to error state after a delay.
      Timer(const Duration(milliseconds: 100), () {
        // Simulate bridge erroring out
        bridge.testSetState(const McpBridgeState(
          connectionState: McpConnectionState.error,
          error: 'Timeout',
        ));
      });

      await notifier.sendMessage('Hello');

      // LLM should have been called without tools (graceful degradation)
      expect(fakeLlm.completeCalls, 1);
      expect(fakeLlm.lastTools, isEmpty);
    });
  });

  group('McpBridgeNotifier.waitForReady', () {
    late McpBridgeNotifier bridge;

    setUp(() {
      bridge = McpBridgeNotifier();
    });

    tearDown(() {
      bridge.dispose();
    });

    test('completes immediately when already connected', () async {
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connected,
      ));

      // Should complete without any delay
      await bridge.waitForReady();
    });

    test('waits for connecting to transition to connected', () async {
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connecting,
      ));

      // Schedule state transition after a delay
      Timer(const Duration(milliseconds: 50), () {
        bridge.testSetState(const McpBridgeState(
          connectionState: McpConnectionState.connected,
        ));
      });

      await bridge.waitForReady();
      expect(
        bridge.currentState.connectionState,
        McpConnectionState.connected,
      );
    });

    test('throws StateError when bridge transitions to error', () async {
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connecting,
      ));

      Timer(const Duration(milliseconds: 50), () {
        bridge.testSetState(const McpBridgeState(
          connectionState: McpConnectionState.error,
          error: 'Connection refused',
        ));
      });

      expect(
        () => bridge.waitForReady(),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError when not in connecting state', () {
      // Bridge is disconnected, not connecting
      expect(
        () => bridge.waitForReady(),
        throwsA(isA<StateError>()),
      );
    });

    test('throws TimeoutException on timeout', () {
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connecting,
      ));

      expect(
        () => bridge.waitForReady(
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
