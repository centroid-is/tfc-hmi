import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/preferences.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('Chat history persistence', () {
    late ProviderContainer container;
    late Preferences testPrefs;

    setUp(() async {
      testPrefs = await createTestPreferences();
      container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('ChatMessage list round-trips through JSON encode/decode', () {
      final messages = [
        ChatMessage.system('You are a helpful assistant'),
        ChatMessage.user('Hello'),
        ChatMessage.assistant('Hi there!'),
        ChatMessage.assistant(
          'Let me check that.',
          toolCalls: [
            const ToolCall(
              id: 'tc-1',
              name: 'get_value',
              arguments: {'key': 'pump.speed'},
            ),
          ],
        ),
        ChatMessage.toolResult('tc-1', '42.5'),
        ChatMessage.assistant('The pump speed is 42.5'),
      ];

      final json = jsonEncode(messages.map((m) => m.toJson()).toList());
      final decoded = (jsonDecode(json) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(decoded.length, messages.length);
      for (var i = 0; i < messages.length; i++) {
        expect(decoded[i].role, messages[i].role);
        expect(decoded[i].content, messages[i].content);
        expect(decoded[i].toolCallId, messages[i].toolCallId);
        expect(decoded[i].toolCalls.length, messages[i].toolCalls.length);
      }
    });

    test('loadHistory restores messages from preferences JSON string',
        () async {
      // Pre-populate preferences with serialized messages
      final messages = [
        ChatMessage.system('system prompt'),
        ChatMessage.user('hello'),
        ChatMessage.assistant('world'),
      ];
      final json = jsonEncode(messages.map((m) => m.toJson()).toList());
      await testPrefs.setString(kChatHistory, json, saveToDb: false);

      // Access the notifier and load history
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadHistory();

      final state = container.read(chatProvider);
      expect(state.messages.length, 3);
      expect(state.messages[0].role, ChatRole.system);
      expect(state.messages[1].role, ChatRole.user);
      expect(state.messages[1].content, 'hello');
      expect(state.messages[2].role, ChatRole.assistant);
      expect(state.messages[2].content, 'world');
    });

    test('loadHistory with empty preferences starts with empty state',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadHistory();

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
    });

    test('loadHistory with null preferences starts with empty state',
        () async {
      // Explicitly ensure no value set
      await testPrefs.remove(kChatHistory);

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadHistory();

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
    });

    test('loadHistory with corrupted JSON does not crash (silent recovery)',
        () async {
      await testPrefs.setString(kChatHistory, 'not valid json {{{',
          saveToDb: false);

      final notifier = container.read(chatProvider.notifier);
      // Should not throw
      await notifier.loadHistory();

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
    });

    test('clear() removes persisted history from preferences', () async {
      // Pre-populate preferences
      final messages = [
        ChatMessage.user('hello'),
        ChatMessage.assistant('world'),
      ];
      final json = jsonEncode(messages.map((m) => m.toJson()).toList());
      await testPrefs.setString(kChatHistory, json, saveToDb: false);

      // Load history first
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadHistory();
      expect(container.read(chatProvider).messages.length, 2);

      // Clear
      notifier.clear();

      // State should be empty
      expect(container.read(chatProvider).messages, isEmpty);

      // Wait for async clear to complete
      await Future<void>.delayed(Duration.zero);

      // Preferences should also be cleared
      final stored = await testPrefs.getString(kChatHistory);
      expect(stored, isNull);
    });

    test('history is capped at 100 messages, keeping system and newest',
        () async {
      // Create 110 messages: 2 system + 108 user/assistant pairs
      final messages = <ChatMessage>[
        ChatMessage.system('system prompt 1'),
        ChatMessage.system('system prompt 2'),
      ];
      for (var i = 0; i < 54; i++) {
        messages.add(ChatMessage.user('user message $i'));
        messages.add(ChatMessage.assistant('assistant reply $i'));
      }
      // Total: 2 system + 108 non-system = 110

      // Pre-populate preferences with the full 110 messages (legacy key)
      await testPrefs.setString(
        kChatHistory,
        jsonEncode(messages.map((m) => m.toJson()).toList()),
        saveToDb: false,
      );

      // Load then save (loadHistory migrates legacy -> per-conversation key)
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadHistory();
      await notifier.saveHistory();

      // Read back from the per-conversation key (not legacy kChatHistory)
      final activeId =
          container.read(chatProvider).activeConversationId;
      final stored = await testPrefs
          .getString('$kConversationPrefix$activeId');
      expect(stored, isNotNull);
      final decoded = (jsonDecode(stored!) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(decoded.length, kMaxHistoryMessages);

      // System messages should all be preserved
      final systemMsgs = decoded.where((m) => m.role == ChatRole.system);
      expect(systemMsgs.length, 2);

      // Non-system should be newest (trimmed from the front)
      final nonSystem =
          decoded.where((m) => m.role != ChatRole.system).toList();
      expect(nonSystem.length, kMaxHistoryMessages - 2); // 98

      // Last non-system message should be the newest
      expect(nonSystem.last.content, 'assistant reply 53');
    });

    test('saveHistory writes current messages to per-conversation key',
        () async {
      // Set up some messages via loadHistory (which migrates legacy data)
      final messages = [
        ChatMessage.user('test message'),
        ChatMessage.assistant('test reply'),
      ];
      await testPrefs.setString(
        kChatHistory,
        jsonEncode(messages.map((m) => m.toJson()).toList()),
        saveToDb: false,
      );
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadHistory();

      // Get the active conversation ID assigned during migration
      final activeId =
          container.read(chatProvider).activeConversationId;
      expect(activeId, isNotNull);

      // Clear per-conversation key to confirm saveHistory writes it back
      await testPrefs.remove('$kConversationPrefix$activeId');
      expect(
          await testPrefs.getString('$kConversationPrefix$activeId'), isNull);

      // Save history
      await notifier.saveHistory();

      // Preferences should have the messages under the per-conversation key
      final stored = await testPrefs
          .getString('$kConversationPrefix$activeId');
      expect(stored, isNotNull);
      final decoded = (jsonDecode(stored!) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(decoded.length, 2);
      expect(decoded[0].content, 'test message');
      expect(decoded[1].content, 'test reply');
    });
  });
}
