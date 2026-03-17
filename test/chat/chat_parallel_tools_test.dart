import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_dart/mcp_dart.dart' show CallToolResult, TextContent;
import 'package:riverpod/riverpod.dart';
import 'package:tfc_dart/core/preferences.dart';

import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/llm/llm_provider.dart';
import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/preferences.dart';
import '../helpers/test_helpers.dart';

/// Fake LLM provider that returns tool calls on the first request
/// and a text response on subsequent requests.
class _ToolCallLlmProvider implements LlmProvider {
  final List<ToolCall> toolCallsToReturn;
  int completeCalls = 0;

  _ToolCallLlmProvider({required this.toolCallsToReturn});

  @override
  LlmProviderType get providerType => LlmProviderType.claude;

  @override
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  }) async {
    completeCalls++;
    if (completeCalls == 1) {
      // First call: return tool calls
      return LlmResponse(
        content: '',
        toolCalls: toolCallsToReturn,
        stopReason: 'tool_use',
      );
    }
    // Subsequent calls: return text
    return const LlmResponse(
      content: 'Here are the results.',
      toolCalls: [],
      stopReason: 'end_turn',
    );
  }

  @override
  void dispose() {}

  @override
  String get apiKeyPreferenceKey => kClaudeApiKey;
}

/// Fake bridge that tracks concurrent tool calls and simulates latency.
class _TrackingBridge extends McpBridgeNotifier {
  /// Records the order each tool started execution.
  final List<String> startOrder = [];

  /// Records the order each tool finished execution.
  final List<String> finishOrder = [];

  /// Tracks the peak number of concurrent calls.
  int peakConcurrent = 0;

  int _currentConcurrent = 0;

  /// How long each tool call takes (simulated).
  final Duration callDuration;

  _TrackingBridge({this.callDuration = const Duration(milliseconds: 50)});

  @override
  Future<CallToolResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    startOrder.add(name);
    _currentConcurrent++;
    if (_currentConcurrent > peakConcurrent) {
      peakConcurrent = _currentConcurrent;
    }

    // Yield to let other parallel calls start, then simulate work.
    // A single microtask yield ensures all Future.wait futures have
    // a chance to begin before any of them proceed.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(callDuration);

    _currentConcurrent--;
    finishOrder.add(name);

    return CallToolResult(content: [TextContent(text: 'result_$name')]);
  }
}

/// Fake bridge where specific tools throw errors.
class _ErrorBridge extends McpBridgeNotifier {
  final Set<String> failingTools;

  _ErrorBridge({required this.failingTools});

  @override
  Future<CallToolResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failingTools.contains(name)) {
      throw Exception('Tool $name failed');
    }
    return CallToolResult(content: [TextContent(text: 'result_$name')]);
  }
}

void main() {
  group('Parallel tool call execution', () {
    late ProviderContainer container;
    late Preferences testPrefs;

    setUp(() async {
      testPrefs = await createTestPreferences();
    });

    tearDown(() {
      container.dispose();
    });

    test('multiple tool calls execute concurrently via Future.wait', () async {
      final bridge = _TrackingBridge(
        callDuration: const Duration(milliseconds: 100),
      );
      // Set connected state so callTool doesn't throw
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connected,
        tools: [],
      ));

      final llm = _ToolCallLlmProvider(toolCallsToReturn: [
        const ToolCall(
            id: 'tc-1', name: 'get_tag_value', arguments: {'key': 'temp'}),
        const ToolCall(
            id: 'tc-2', name: 'list_assets', arguments: {}),
        const ToolCall(
            id: 'tc-3', name: 'get_alarm_config', arguments: {'id': '1'}),
      ]);

      container = ProviderContainer(
        overrides: [
          mcpBridgeProvider.overrideWith((ref) {
            ref.onDispose(() => bridge.dispose());
            return bridge;
          }),
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(llm);

      final stopwatch = Stopwatch()..start();
      await notifier.sendMessage('Check all values');
      stopwatch.stop();

      // All 3 tools should have been called
      expect(bridge.startOrder.length, 3);
      expect(bridge.finishOrder.length, 3);

      // Peak concurrency should be > 1, proving parallel execution.
      // With Future.wait all 3 start before any finishes.
      expect(bridge.peakConcurrent, greaterThan(1),
          reason: 'Tools should execute concurrently, not sequentially');

      // Total time should be closer to 1x tool duration (100ms) than 3x (300ms).
      // Allow generous margin for CI overhead, but it must be under 280ms
      // (which would only be possible with parallel execution).
      expect(stopwatch.elapsedMilliseconds, lessThan(280),
          reason:
              'Parallel execution should complete faster than 3x sequential '
              '(elapsed: ${stopwatch.elapsedMilliseconds}ms)');
    });

    test('tool results are added in correct order matching tool calls',
        () async {
      final bridge = _TrackingBridge(
        callDuration: const Duration(milliseconds: 10),
      );
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connected,
        tools: [],
      ));

      final llm = _ToolCallLlmProvider(toolCallsToReturn: [
        const ToolCall(
            id: 'tc-A', name: 'tool_alpha', arguments: {}),
        const ToolCall(
            id: 'tc-B', name: 'tool_beta', arguments: {}),
      ]);

      container = ProviderContainer(
        overrides: [
          mcpBridgeProvider.overrideWith((ref) {
            ref.onDispose(() => bridge.dispose());
            return bridge;
          }),
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(llm);

      await notifier.sendMessage('Run both tools');

      final state = container.read(chatProvider);
      // Messages: system, user, assistant(tool_calls), tool_result(A), tool_result(B), assistant(final)
      final toolResults =
          state.messages.where((m) => m.role == ChatRole.tool).toList();
      expect(toolResults.length, 2);
      expect(toolResults[0].toolCallId, 'tc-A',
          reason: 'First result should match first tool call');
      expect(toolResults[1].toolCallId, 'tc-B',
          reason: 'Second result should match second tool call');

      // Verify content
      expect(toolResults[0].content, 'result_tool_alpha');
      expect(toolResults[1].content, 'result_tool_beta');
    });

    test('one tool error does not prevent other tools from completing',
        () async {
      final bridge = _ErrorBridge(failingTools: {'tool_fail'});
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connected,
        tools: [],
      ));

      final llm = _ToolCallLlmProvider(toolCallsToReturn: [
        const ToolCall(
            id: 'tc-ok', name: 'tool_ok', arguments: {}),
        const ToolCall(
            id: 'tc-fail', name: 'tool_fail', arguments: {}),
        const ToolCall(
            id: 'tc-ok2', name: 'tool_ok2', arguments: {}),
      ]);

      container = ProviderContainer(
        overrides: [
          mcpBridgeProvider.overrideWith((ref) {
            ref.onDispose(() => bridge.dispose());
            return bridge;
          }),
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(llm);

      await notifier.sendMessage('Run tools with one failure');

      final state = container.read(chatProvider);
      expect(state.status, ChatStatus.idle,
          reason: 'Overall status should be idle, not error');

      final toolResults =
          state.messages.where((m) => m.role == ChatRole.tool).toList();
      expect(toolResults.length, 3);

      // First tool succeeded
      expect(toolResults[0].toolCallId, 'tc-ok');
      expect(toolResults[0].content, 'result_tool_ok');

      // Second tool failed
      expect(toolResults[1].toolCallId, 'tc-fail');
      expect(toolResults[1].content, contains('Error:'));
      expect(toolResults[1].content, contains('Tool tool_fail failed'));

      // Third tool succeeded despite the second failing
      expect(toolResults[2].toolCallId, 'tc-ok2');
      expect(toolResults[2].content, 'result_tool_ok2');
    });

    test('progress shows all tools as Running initially then Done', () async {
      final bridge = _TrackingBridge(
        callDuration: const Duration(milliseconds: 50),
      );
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connected,
        tools: [],
      ));

      final llm = _ToolCallLlmProvider(toolCallsToReturn: [
        const ToolCall(id: 'tc-1', name: 'tool_a', arguments: {}),
        const ToolCall(id: 'tc-2', name: 'tool_b', arguments: {}),
      ]);

      container = ProviderContainer(
        overrides: [
          mcpBridgeProvider.overrideWith((ref) {
            ref.onDispose(() => bridge.dispose());
            return bridge;
          }),
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(llm);

      // Capture progress state transitions
      final progressSnapshots = <List<ToolProgress>>[];
      container.listen(chatProvider, (prev, next) {
        if (next.toolProgress.isNotEmpty) {
          progressSnapshots
              .add(List<ToolProgress>.from(next.toolProgress));
        }
      });

      await notifier.sendMessage('Check progress');

      // The first snapshot should have 2 tools (all set to Running at once)
      expect(progressSnapshots, isNotEmpty);
      expect(progressSnapshots.first.length, 2,
          reason: 'All tools should be tracked from the start');

      // The first snapshot should have all tools running (set together)
      expect(
          progressSnapshots.first.every((p) => p.status == 'Running...'), isTrue,
          reason: 'Initial progress should show all tools running');

      // A later snapshot should show done statuses
      final lastWithProgress = progressSnapshots.last;
      expect(lastWithProgress.length, 2);
      expect(lastWithProgress.every((p) => p.status == 'Done'), isTrue,
          reason: 'Final progress should show all tools done');
    });

    test('single tool call still works correctly', () async {
      final bridge = _TrackingBridge(
        callDuration: const Duration(milliseconds: 10),
      );
      bridge.testSetState(const McpBridgeState(
        connectionState: McpConnectionState.connected,
        tools: [],
      ));

      final llm = _ToolCallLlmProvider(toolCallsToReturn: [
        const ToolCall(
            id: 'tc-only', name: 'single_tool', arguments: {'x': 1}),
      ]);

      container = ProviderContainer(
        overrides: [
          mcpBridgeProvider.overrideWith((ref) {
            ref.onDispose(() => bridge.dispose());
            return bridge;
          }),
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );

      final notifier = container.read(chatProvider.notifier);
      notifier.setLlmProvider(llm);

      await notifier.sendMessage('Run one tool');

      final state = container.read(chatProvider);
      expect(state.status, ChatStatus.idle);

      final toolResults =
          state.messages.where((m) => m.role == ChatRole.tool).toList();
      expect(toolResults.length, 1);
      expect(toolResults[0].toolCallId, 'tc-only');
      expect(toolResults[0].content, 'result_single_tool');
    });
  });
}
