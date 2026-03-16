import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc/llm/conversation_models.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/llm/llm_provider.dart';
import 'package:tfc/mcp/mcp_bridge_notifier.dart';
import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/preferences.dart';
import '../helpers/test_helpers.dart';

/// Fake LLM provider that returns a canned text response (no tool calls).
class _FakeLlmProvider implements LlmProvider {
  int completeCalls = 0;
  String responseText;

  _FakeLlmProvider({this.responseText = 'AI reply'});

  @override
  LlmProviderType get providerType => LlmProviderType.claude;

  @override
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  }) async {
    completeCalls++;
    return LlmResponse(
      content: responseText,
      toolCalls: const [],
      stopReason: 'end_turn',
    );
  }

  @override
  void dispose() {}

  @override
  String get apiKeyPreferenceKey => kClaudeApiKey;
}

/// Adds a user message to the active conversation in [prefs] so that
/// [ChatNotifier.newConversation] treats it as non-empty and will actually
/// create a new conversation instead of reusing the current empty one.
Future<void> _populateConversation(
    ProviderContainer container, Preferences prefs) async {
  final id = container.read(chatProvider).activeConversationId!;
  await prefs.setString(
    '$kConversationPrefix$id',
    jsonEncode([ChatMessage.user('placeholder').toJson()]),
  );
  await container.read(chatProvider.notifier).loadConversation(id);
}

void main() {
  group('Multi-conversation CRUD', () {
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

    test('loadConversations creates a fresh conversation when none exist',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.title, 'New conversation');
      expect(state.activeConversationId, state.conversations.first.id);
      expect(state.messages, isEmpty);
    });

    test('loadConversations persists the new conversation to preferences',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Verify the conversation list was saved to preferences
      final stored = await testPrefs.getString(kConversationList);
      expect(stored, isNotNull);
      final list = jsonDecode(stored!) as List<dynamic>;
      expect(list, hasLength(1));

      // Verify active conversation ID was saved
      final activeId = await testPrefs.getString(kActiveConversation);
      expect(activeId, isNotNull);
      expect(activeId, container.read(chatProvider).activeConversationId);
    });

    test('loadConversations restores existing conversation list', () async {
      // Pre-populate preferences with conversations
      final conv1 = ConversationMeta(
        id: 'pre-1',
        title: 'First conversation',
        createdAt: DateTime(2024, 1, 1),
      );
      final conv2 = ConversationMeta(
        id: 'pre-2',
        title: 'Second conversation',
        createdAt: DateTime(2024, 2, 1),
      );
      await testPrefs.setString(
        kConversationList,
        jsonEncode([conv1.toJson(), conv2.toJson()]),
      );
      await testPrefs.setString(kActiveConversation, 'pre-2');

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(2));
      expect(state.conversations[0].id, 'pre-1');
      expect(state.conversations[1].id, 'pre-2');
      expect(state.activeConversationId, 'pre-2');
    });

    test('loadConversations falls back to first when active ID is invalid',
        () async {
      final conv = ConversationMeta(
        id: 'valid-id',
        title: 'Valid',
        createdAt: DateTime.now(),
      );
      await testPrefs.setString(
        kConversationList,
        jsonEncode([conv.toJson()]),
      );
      await testPrefs.setString(kActiveConversation, 'nonexistent-id');

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      expect(state.activeConversationId, 'valid-id');
    });

    test('loadConversations handles corrupted conversation list JSON',
        () async {
      await testPrefs.setString(kConversationList, 'not valid json {{{');

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      // Should create a fresh conversation (corrupted data treated as empty)
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.title, 'New conversation');
    });

    test('newConversation creates and activates a new conversation',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Populate the initial conversation so newConversation() doesn't
      // short-circuit (empty conversations are reused).
      await _populateConversation(container, testPrefs);
      final firstId = container.read(chatProvider).activeConversationId;

      await notifier.newConversation();

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(2));
      expect(state.activeConversationId, isNot(firstId));
      expect(state.messages, isEmpty);
      // New conversation should be first (newest first)
      expect(state.conversations.first.id, state.activeConversationId);
    });

    test('newConversation reuses current when conversation is empty',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final firstId = container.read(chatProvider).activeConversationId;

      // Calling newConversation on an empty conversation should be a no-op
      await notifier.newConversation();

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(1));
      expect(state.activeConversationId, firstId);
    });

    test('newConversation clears messages from previous conversation',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final firstId = container.read(chatProvider).activeConversationId!;

      // Add messages to first conversation
      final msgs = [
        ChatMessage.user('hello'),
        ChatMessage.assistant('world'),
      ];
      await testPrefs.setString(
        '$kConversationPrefix$firstId',
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
      await notifier.loadConversation(firstId);
      expect(container.read(chatProvider).messages, hasLength(2));

      // Create new conversation
      await notifier.newConversation();

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
      expect(state.status, ChatStatus.idle);
      expect(state.toolProgress, isEmpty);
    });

    test('newConversation resets status and toolProgress', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Populate so newConversation() actually creates a new conversation.
      await _populateConversation(container, testPrefs);

      await notifier.newConversation();

      final state = container.read(chatProvider);
      expect(state.status, ChatStatus.idle);
      expect(state.toolProgress, isEmpty);
    });

    test('switchConversation saves current and loads target', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final firstId = container.read(chatProvider).activeConversationId!;

      // Simulate adding messages to first conversation by saving directly
      final msgs = [
        ChatMessage.system('system'),
        ChatMessage.user('hello from first'),
      ];
      await testPrefs.setString(
        '$kConversationPrefix$firstId',
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
      // Reload to pick up the messages
      await notifier.loadConversation(firstId);
      expect(container.read(chatProvider).messages, hasLength(2));

      // Create a second conversation
      await notifier.newConversation();
      final secondId = container.read(chatProvider).activeConversationId!;
      expect(secondId, isNot(firstId));
      expect(container.read(chatProvider).messages, isEmpty);

      // Switch back to first
      await notifier.switchConversation(firstId);
      final state = container.read(chatProvider);
      expect(state.activeConversationId, firstId);
      expect(state.messages, hasLength(2));
      expect(state.messages[1].content, 'hello from first');
    });

    test('switchConversation is no-op when switching to active conversation',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final activeId = container.read(chatProvider).activeConversationId!;

      // Add messages to the active conversation
      final msgs = [ChatMessage.user('test')];
      await testPrefs.setString(
        '$kConversationPrefix$activeId',
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
      await notifier.loadConversation(activeId);

      final stateBefore = container.read(chatProvider);

      // Switch to the same conversation
      await notifier.switchConversation(activeId);

      final stateAfter = container.read(chatProvider);
      // Should be unchanged (no-op)
      expect(stateAfter.activeConversationId, stateBefore.activeConversationId);
      expect(stateAfter.messages.length, stateBefore.messages.length);
    });

    test('switchConversation updates activeConversationId in preferences',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Populate first so newConversation() creates a second
      await _populateConversation(container, testPrefs);
      final firstId = container.read(chatProvider).activeConversationId!;
      await notifier.newConversation();
      final secondId = container.read(chatProvider).activeConversationId!;

      // Switch back to first
      await notifier.switchConversation(firstId);

      final stored = await testPrefs.getString(kActiveConversation);
      expect(stored, firstId);

      // Switch to second
      await notifier.switchConversation(secondId);
      final stored2 = await testPrefs.getString(kActiveConversation);
      expect(stored2, secondId);
    });

    test('deleteConversation removes it and switches to another', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Populate first so newConversation() creates a second
      await _populateConversation(container, testPrefs);

      // Create a second conversation
      await notifier.newConversation();
      final state1 = container.read(chatProvider);
      expect(state1.conversations, hasLength(2));

      final activeId = state1.activeConversationId!;

      // Delete the active conversation
      await notifier.deleteConversation(activeId);

      final state2 = container.read(chatProvider);
      expect(state2.conversations, hasLength(1));
      expect(state2.activeConversationId, isNot(activeId));
    });

    test('deleteConversation removes messages from preferences', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Populate first conversation so newConversation() creates a second
      await _populateConversation(container, testPrefs);

      final firstId = container.read(chatProvider).activeConversationId!;

      // Create second so deletion doesn't leave us with zero
      await notifier.newConversation();

      // Delete first conversation
      await notifier.deleteConversation(firstId);

      // Messages should be removed from preferences
      final stored = await testPrefs.getString('$kConversationPrefix$firstId');
      expect(stored, isNull);
    });

    test('deleteConversation of non-active keeps active unchanged', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Populate first so newConversation() creates a second
      await _populateConversation(container, testPrefs);
      final firstId = container.read(chatProvider).activeConversationId!;
      await notifier.newConversation();
      final secondId = container.read(chatProvider).activeConversationId!;

      // secondId is active, delete firstId
      await notifier.deleteConversation(firstId);

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(1));
      expect(state.activeConversationId, secondId);
    });

    test('deleteConversation creates new when deleting the last one',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final onlyId = container.read(chatProvider).activeConversationId!;
      await notifier.deleteConversation(onlyId);

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(1));
      expect(state.activeConversationId, isNot(onlyId));
      expect(state.conversations.first.title, 'New conversation');
    });

    test('clearAllConversations removes everything and starts fresh',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Create multiple conversations (populate each before creating next)
      await _populateConversation(container, testPrefs);
      await notifier.newConversation();
      await _populateConversation(container, testPrefs);
      await notifier.newConversation();
      expect(container.read(chatProvider).conversations, hasLength(3));

      await notifier.clearAllConversations();

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.title, 'New conversation');
      expect(state.messages, isEmpty);
    });

    test('clearAllConversations removes all conversation message keys',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id1 = container.read(chatProvider).activeConversationId!;
      // Populate first conversation and load into state
      await _populateConversation(container, testPrefs);

      await notifier.newConversation();
      final id2 = container.read(chatProvider).activeConversationId!;
      // Populate second conversation and load into state
      await _populateConversation(container, testPrefs);

      await notifier.clearAllConversations();

      // Both conversation message keys should be removed
      expect(await testPrefs.getString('$kConversationPrefix$id1'), isNull);
      expect(await testPrefs.getString('$kConversationPrefix$id2'), isNull);
    });

    test('clearAllConversations also removes legacy chat.history key',
        () async {
      // Set up a legacy key that might linger
      await testPrefs.setString(kChatHistory, '[]');

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      await notifier.clearAllConversations();

      expect(await testPrefs.getString(kChatHistory), isNull);
    });

    test('max 20 conversations enforced', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Create 24 conversations (1 from loadConversations + 24 new = 25 total attempts)
      // Populate each before creating next so newConversation() doesn't
      // short-circuit on an empty conversation.
      for (var i = 0; i < 24; i++) {
        await _populateConversation(container, testPrefs);
        await notifier.newConversation();
      }

      final state = container.read(chatProvider);
      expect(state.conversations.length, kMaxConversations);
    });

    test('max conversations prunes oldest and cleans up their message keys',
        () async {
      // Pre-populate with exactly kMaxConversations conversations
      final conversations = <ConversationMeta>[];
      for (var i = 0; i < kMaxConversations; i++) {
        final conv = ConversationMeta(
          id: 'conv-$i',
          title: 'Conversation $i',
          createdAt: DateTime(2024, 1, 1 + i),
        );
        conversations.add(conv);
        // Store messages for each
        await testPrefs.setString(
          '${kConversationPrefix}conv-$i',
          jsonEncode([ChatMessage.user('msg $i').toJson()]),
        );
      }
      await testPrefs.setString(
        kConversationList,
        jsonEncode(conversations.map((c) => c.toJson()).toList()),
      );
      await testPrefs.setString(kActiveConversation, 'conv-0');

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      expect(container.read(chatProvider).conversations, hasLength(kMaxConversations));

      // Adding one more should prune the oldest (last in list)
      await notifier.newConversation();

      final state = container.read(chatProvider);
      expect(state.conversations, hasLength(kMaxConversations));

      // The oldest conversation (conv-19, last in list) should be pruned
      final ids = state.conversations.map((c) => c.id).toSet();
      expect(ids, isNot(contains('conv-${kMaxConversations - 1}')));

      // Its messages should be cleaned up from preferences
      final prunedMsgs = await testPrefs.getString(
        '${kConversationPrefix}conv-${kMaxConversations - 1}',
      );
      expect(prunedMsgs, isNull);
    });
  });

  group('loadConversation (single)', () {
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

    test('loadConversation loads messages for a specific conversation',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;

      // Store messages directly in preferences
      final msgs = [
        ChatMessage.system('system prompt'),
        ChatMessage.user('user question'),
        ChatMessage.assistant('assistant answer'),
      ];
      await testPrefs.setString(
        '$kConversationPrefix$id',
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );

      await notifier.loadConversation(id);

      final state = container.read(chatProvider);
      expect(state.messages, hasLength(3));
      expect(state.messages[0].role, ChatRole.system);
      expect(state.messages[1].role, ChatRole.user);
      expect(state.messages[1].content, 'user question');
      expect(state.messages[2].role, ChatRole.assistant);
    });

    test('loadConversation updates activeConversationId', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      await notifier.loadConversation('some-other-id');

      final state = container.read(chatProvider);
      expect(state.activeConversationId, 'some-other-id');
    });

    test('loadConversation resets status to idle', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;
      await notifier.loadConversation(id);

      final state = container.read(chatProvider);
      expect(state.status, ChatStatus.idle);
      expect(state.toolProgress, isEmpty);
    });

    test('loadConversation with empty preferences starts with empty messages',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;
      // Do not store any messages for this ID
      await notifier.loadConversation(id);

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
    });

    test('loadConversation with corrupted JSON starts with empty messages',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;
      await testPrefs.setString('$kConversationPrefix$id', '{bad json!!!');

      await notifier.loadConversation(id);

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
    });

    test('loadConversation saves activeConversationId to preferences',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      await notifier.loadConversation('target-id');

      final stored = await testPrefs.getString(kActiveConversation);
      expect(stored, 'target-id');
    });
  });

  group('Conversation persistence', () {
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

    test('saveConversation persists messages under conversation key',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;

      // Simulate some messages in state by loading them
      final msgs = [
        ChatMessage.user('test message'),
        ChatMessage.assistant('test reply'),
      ];
      await testPrefs.setString(
        '$kConversationPrefix$id',
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
      await notifier.loadConversation(id);

      // Clear the stored messages to test that saveConversation writes them
      await testPrefs.remove('$kConversationPrefix$id');
      expect(await testPrefs.getString('$kConversationPrefix$id'), isNull);

      await notifier.saveConversation();

      // Check they're saved
      final stored = await testPrefs.getString('$kConversationPrefix$id');
      expect(stored, isNotNull);
      final decoded = (jsonDecode(stored!) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(decoded, hasLength(2));
      expect(decoded[0].content, 'test message');
    });

    test('saveConversation is no-op when activeConversationId is null',
        () async {
      // Access notifier without calling loadConversations (so no active ID)
      final notifier = container.read(chatProvider.notifier);
      expect(container.read(chatProvider).activeConversationId, isNull);

      // Should not throw
      await notifier.saveConversation();
    });

    test('saveConversation caps messages at kMaxHistoryMessages', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      final id = container.read(chatProvider).activeConversationId!;

      // Create 110 messages: 2 system + 108 non-system
      final msgs = <ChatMessage>[
        ChatMessage.system('system 1'),
        ChatMessage.system('system 2'),
      ];
      for (var i = 0; i < 54; i++) {
        msgs.add(ChatMessage.user('user $i'));
        msgs.add(ChatMessage.assistant('reply $i'));
      }
      // Store and load them
      await testPrefs.setString(
        '$kConversationPrefix$id',
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
      await notifier.loadConversation(id);
      expect(container.read(chatProvider).messages, hasLength(110));

      // Save (should cap at kMaxHistoryMessages)
      await notifier.saveConversation();

      final stored = await testPrefs.getString('$kConversationPrefix$id');
      final decoded = (jsonDecode(stored!) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(decoded.length, kMaxHistoryMessages);

      // System messages should be preserved
      final systemMsgs = decoded.where((m) => m.role == ChatRole.system);
      expect(systemMsgs.length, 2);

      // Newest non-system messages should be kept
      final nonSystem =
          decoded.where((m) => m.role != ChatRole.system).toList();
      expect(nonSystem.last.content, 'reply 53');
    });

    test('conversation list persists through reload', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Create extra conversations (populate each before creating next)
      await _populateConversation(container, testPrefs);
      await notifier.newConversation();
      await _populateConversation(container, testPrefs);
      await notifier.newConversation();

      final state1 = container.read(chatProvider);
      expect(state1.conversations, hasLength(3));

      // Create a new container to simulate app restart
      container.dispose();
      container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );

      final notifier2 = container.read(chatProvider.notifier);
      await notifier2.loadConversations();

      final state2 = container.read(chatProvider);
      expect(state2.conversations, hasLength(3));
    });

    test('active conversation ID persists through reload', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      // Populate current then create extra conversation and switch to it
      await _populateConversation(container, testPrefs);
      await notifier.newConversation();
      final targetId = container.read(chatProvider).activeConversationId!;

      // Simulate app restart
      container.dispose();
      container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith((ref) async => testPrefs),
        ],
      );

      final notifier2 = container.read(chatProvider.notifier);
      await notifier2.loadConversations();

      expect(container.read(chatProvider).activeConversationId, targetId);
    });

    test('messages persist through conversation switch and reload', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;

      // Store messages
      final msgs = [
        ChatMessage.user('persisted message'),
        ChatMessage.assistant('persisted reply'),
      ];
      await testPrefs.setString(
        '$kConversationPrefix$id',
        jsonEncode(msgs.map((m) => m.toJson()).toList()),
      );
      await notifier.loadConversation(id);

      // Create new conversation (switches away)
      await notifier.newConversation();
      expect(container.read(chatProvider).messages, isEmpty);

      // Switch back
      await notifier.switchConversation(id);
      expect(container.read(chatProvider).messages, hasLength(2));
      expect(container.read(chatProvider).messages[0].content,
          'persisted message');
    });
  });

  group('Legacy migration', () {
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

    test('migrates legacy chat.history into a single conversation', () async {
      // Set up legacy history
      final messages = [
        ChatMessage.system('system prompt'),
        ChatMessage.user('hello there'),
        ChatMessage.assistant('hi!'),
      ];
      await testPrefs.setString(
        kChatHistory,
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      // Should have one conversation from the migrated history
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.title, 'hello there');
      expect(state.messages, hasLength(3));
      expect(state.messages[1].content, 'hello there');

      // Legacy key should be cleaned up
      expect(await testPrefs.getString(kChatHistory), isNull);
    });

    test('migration uses first user message for title', () async {
      final messages = [
        ChatMessage.system('system prompt'),
        ChatMessage.user('What is pump3 doing?'),
        ChatMessage.assistant('Let me check.'),
        ChatMessage.user('Also check valve4'),
      ];
      await testPrefs.setString(
        kChatHistory,
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      // Title should be from first user message, not the second
      expect(state.conversations.first.title, 'What is pump3 doing?');
    });

    test('migration uses "Migrated conversation" when no user messages',
        () async {
      final messages = [
        ChatMessage.system('system prompt'),
        ChatMessage.assistant('hello'),
      ];
      await testPrefs.setString(
        kChatHistory,
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      expect(state.conversations.first.title, 'Migrated conversation');
    });

    test('migration stores messages under per-conversation key', () async {
      final messages = [
        ChatMessage.user('migrated message'),
      ];
      await testPrefs.setString(
        kChatHistory,
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;
      final stored = await testPrefs.getString('$kConversationPrefix$id');
      expect(stored, isNotNull);
      final decoded = (jsonDecode(stored!) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(decoded, hasLength(1));
      expect(decoded[0].content, 'migrated message');
    });

    test('migration skips empty legacy history', () async {
      await testPrefs.setString(
        kChatHistory,
        jsonEncode([]),
      );

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      // Empty legacy should be cleaned up, fresh conversation created
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.title, 'New conversation');
      expect(await testPrefs.getString(kChatHistory), isNull);
    });

    test('migration does not run if conversations already exist', () async {
      // Set up both legacy and new data
      final legacyMsgs = [ChatMessage.user('old')];
      await testPrefs.setString(
        kChatHistory,
        jsonEncode(legacyMsgs.map((m) => m.toJson()).toList()),
      );

      final conv = ConversationMeta(
        id: 'existing',
        title: 'Existing',
        createdAt: DateTime.now(),
      );
      await testPrefs.setString(
        kConversationList,
        jsonEncode([conv.toJson()]),
      );

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      // Should use existing conversations, not create from legacy
      expect(state.conversations.first.title, 'Existing');
      // Legacy should be cleaned up
      expect(await testPrefs.getString(kChatHistory), isNull);
    });

    test('corrupted legacy history is cleaned up silently', () async {
      await testPrefs.setString(kChatHistory, 'not valid json {{{');

      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final state = container.read(chatProvider);
      // Should have a fresh conversation
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.title, 'New conversation');

      // Legacy key should be cleaned up
      expect(await testPrefs.getString(kChatHistory), isNull);
    });
  });

  group('sendMessage auto-save and title update', () {
    late ProviderContainer container;
    late Preferences testPrefs;
    late McpBridgeNotifier bridge;
    late _FakeLlmProvider fakeLlm;

    setUp(() async {
      testPrefs = await createTestPreferences();
      bridge = McpBridgeNotifier();
      fakeLlm = _FakeLlmProvider();

      container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith((ref) async => testPrefs),
          mcpBridgeProvider.overrideWith((ref) {
            ref.onDispose(() => bridge.dispose());
            return bridge;
          }),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('sendMessage auto-saves conversation after successful completion',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      notifier.setLlmProvider(fakeLlm);

      final id = container.read(chatProvider).activeConversationId!;

      // Clear any messages stored during loadConversations
      await testPrefs.remove('$kConversationPrefix$id');

      await notifier.sendMessage('Hello AI');

      // sendMessage uses unawaited(saveConversation()) to avoid blocking
      // the UI on PostgreSQL writes. Flush by calling saveConversation()
      // explicitly so the write completes before we inspect preferences.
      await notifier.saveConversation();

      // Messages should be saved to preferences
      final stored = await testPrefs.getString('$kConversationPrefix$id');
      expect(stored, isNotNull);
      final decoded = (jsonDecode(stored!) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      // Should contain: system prompt, user message, assistant reply
      expect(decoded, hasLength(3));
      expect(decoded[0].role, ChatRole.system);
      expect(decoded[1].role, ChatRole.user);
      expect(decoded[1].content, 'Hello AI');
      expect(decoded[2].role, ChatRole.assistant);
      expect(decoded[2].content, 'AI reply');
    });

    test('sendMessage updates conversation title on first user message',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      notifier.setLlmProvider(fakeLlm);

      // Before sending, title is the default
      expect(
        container.read(chatProvider).conversations.first.title,
        'New conversation',
      );

      await notifier.sendMessage('What is pump3 doing?');

      // Title should be updated to the first user message
      final state = container.read(chatProvider);
      final activeConv = state.conversations.firstWhere(
        (c) => c.id == state.activeConversationId,
      );
      expect(activeConv.title, 'What is pump3 doing?');
    });

    test('sendMessage does not update title on subsequent user messages',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      notifier.setLlmProvider(fakeLlm);

      // First message sets the title
      await notifier.sendMessage('First question');
      final titleAfterFirst = container.read(chatProvider).conversations
          .firstWhere(
              (c) => c.id == container.read(chatProvider).activeConversationId)
          .title;
      expect(titleAfterFirst, 'First question');

      // Second message should NOT change the title
      await notifier.sendMessage('Second question');
      final titleAfterSecond = container.read(chatProvider).conversations
          .firstWhere(
              (c) => c.id == container.read(chatProvider).activeConversationId)
          .title;
      expect(titleAfterSecond, 'First question');
    });

    test('sendMessage title uses debug-asset extraction when applicable',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      notifier.setLlmProvider(fakeLlm);

      await notifier.sendMessage(
        'Debug asset: motor3.vfd\n\nPlease gather all info...',
      );

      final state = container.read(chatProvider);
      final activeConv = state.conversations.firstWhere(
        (c) => c.id == state.activeConversationId,
      );
      expect(activeConv.title, 'motor3.vfd');
    });

    test('sendMessage auto-saves even on LLM error', () async {
      final failingLlm = _FakeLlmProvider();
      // Override complete to throw
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      notifier.setLlmProvider(failingLlm);

      // Make the LLM throw on next complete
      failingLlm.responseText = ''; // We need a way to fail
      // Instead, override with a provider that throws
      final throwingProvider = _ThrowingLlmProvider();
      notifier.setLlmProvider(throwingProvider);

      final id = container.read(chatProvider).activeConversationId!;

      await notifier.sendMessage('This will cause error');

      // State should have error
      final state = container.read(chatProvider);
      expect(state.status, ChatStatus.error);

      // sendMessage uses unawaited(saveConversation()) to avoid blocking
      // the UI on PostgreSQL writes. Flush by calling saveConversation()
      // explicitly so the write completes before we inspect preferences.
      await notifier.saveConversation();

      // But the user message should be persisted (auto-save on error too)
      final stored = await testPrefs.getString('$kConversationPrefix$id');
      expect(stored, isNotNull);
      final decoded = (jsonDecode(stored!) as List<dynamic>)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      // System prompt + user message should be saved
      expect(decoded.any((m) => m.content == 'This will cause error'), isTrue);
    });

    test('sendMessage shows error when no LLM provider configured', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      // Do NOT set an LLM provider

      await notifier.sendMessage('Hello');

      final state = container.read(chatProvider);
      expect(state.status, ChatStatus.error);
      expect(state.error, contains('No LLM provider'));
    });

    test('sendMessage adds system prompt on first message', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();
      notifier.setLlmProvider(fakeLlm);

      await notifier.sendMessage('Hello');

      final state = container.read(chatProvider);
      expect(state.messages.first.role, ChatRole.system);
      expect(state.messages[1].role, ChatRole.user);
      expect(state.messages[1].content, 'Hello');
    });
  });

  group('ChatState with conversations', () {
    test('default ChatState has null activeConversationId', () {
      const state = ChatState();
      expect(state.activeConversationId, isNull);
      expect(state.conversations, isEmpty);
      expect(state.messages, isEmpty);
      expect(state.status, ChatStatus.idle);
      expect(state.error, isNull);
      expect(state.toolProgress, isEmpty);
    });

    test('copyWith preserves conversation fields', () {
      final state = ChatState(
        activeConversationId: 'conv-1',
        conversations: [
          ConversationMeta(
            id: 'conv-1',
            title: 'Test',
            createdAt: DateTime.now(),
          ),
        ],
      );

      final updated = state.copyWith(status: ChatStatus.processing);
      expect(updated.activeConversationId, 'conv-1');
      expect(updated.conversations, hasLength(1));
    });

    test('copyWith can update conversation fields', () {
      const state = ChatState();
      final updated = state.copyWith(
        activeConversationId: 'new-id',
        conversations: [
          ConversationMeta(
            id: 'new-id',
            title: 'New',
            createdAt: DateTime.now(),
          ),
        ],
      );
      expect(updated.activeConversationId, 'new-id');
      expect(updated.conversations, hasLength(1));
    });

    test('copyWith clears error when not passed', () {
      final state = ChatState(
        status: ChatStatus.error,
        error: 'Something broke',
        activeConversationId: 'test',
      );

      final updated = state.copyWith(status: ChatStatus.idle);
      expect(updated.error, isNull);
      expect(updated.activeConversationId, 'test');
    });
  });

  group('clear() preserves conversation context', () {
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

    test('clear() keeps activeConversationId and conversations list',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final activeId = container.read(chatProvider).activeConversationId;
      final conversations = container.read(chatProvider).conversations;

      notifier.clear();

      final state = container.read(chatProvider);
      expect(state.messages, isEmpty);
      expect(state.activeConversationId, activeId);
      expect(state.conversations, conversations);
    });

    test('clear() removes persisted messages for active conversation',
        () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      final id = container.read(chatProvider).activeConversationId!;

      // Store messages
      await testPrefs.setString(
        '$kConversationPrefix$id',
        jsonEncode([ChatMessage.user('to clear').toJson()]),
      );
      await notifier.loadConversation(id);

      notifier.clear();

      // Wait for async prefs removal
      await Future<void>.delayed(Duration.zero);

      final stored = await testPrefs.getString('$kConversationPrefix$id');
      expect(stored, isNull);
    });

    test('clear() resets status to idle', () async {
      final notifier = container.read(chatProvider.notifier);
      await notifier.loadConversations();

      notifier.clear();

      final state = container.read(chatProvider);
      expect(state.status, ChatStatus.idle);
      expect(state.toolProgress, isEmpty);
      expect(state.error, isNull);
    });
  });

  group('Preference key constants', () {
    test('kChatHistory is chat.history', () {
      expect(kChatHistory, 'chat.history');
    });

    test('kConversationList is chat.conversations', () {
      expect(kConversationList, 'chat.conversations');
    });

    test('kActiveConversation is chat.active_conversation', () {
      expect(kActiveConversation, 'chat.active_conversation');
    });

    test('kConversationPrefix is chat.conversation.', () {
      expect(kConversationPrefix, 'chat.conversation.');
    });

    test('kMaxHistoryMessages is 100', () {
      expect(kMaxHistoryMessages, 100);
    });

    test('kMaxConversations is 20', () {
      expect(kMaxConversations, 20);
    });
  });
}

/// An LLM provider that always throws on complete().
class _ThrowingLlmProvider implements LlmProvider {
  @override
  LlmProviderType get providerType => LlmProviderType.claude;

  @override
  Future<LlmResponse> complete(
    List<ChatMessage> messages, {
    List<Map<String, dynamic>> tools = const [],
  }) async {
    throw Exception('LLM connection failed');
  }

  @override
  void dispose() {}

  @override
  String get apiKeyPreferenceKey => kClaudeApiKey;
}
