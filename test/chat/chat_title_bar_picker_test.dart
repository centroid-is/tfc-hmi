import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/chat/chat_overlay.dart';
import 'package:tfc/llm/conversation_models.dart';
import 'package:tfc/llm/llm_models.dart';
import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/interface.dart';

// ─── Fakes ──────────────────────────────────────────────────────────────

class _FakeSecureStorage implements MySecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _store[key];

  @override
  Future<void> delete({required String key}) async {
    _store.remove(key);
  }
}

Preferences _createTestPreferences() {
  return Preferences(
    database: null,
    secureStorage: _FakeSecureStorage(),
  );
}

// ─── Helpers ────────────────────────────────────────────────────────────

Widget _wrapWithPrefsAndRef(
  Widget child,
  void Function(WidgetRef ref) onRef,
) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith((_) async => _createTestPreferences()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            onRef(ref);
            return Stack(children: [child]);
          },
        ),
      ),
    ),
  );
}

Widget _wrapInStack(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Stack(children: [child]),
      ),
    ),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────

void main() {
  group('Title bar conversation picker', () {
    testWidgets(
        'title bar shows active conversation title instead of AI Copilot',
        (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      // Seed with a named conversation
      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'Pump diagnostics',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Title bar should show the conversation title, not "AI Copilot"
      expect(find.text('Pump diagnostics'), findsOneWidget);
      expect(find.text('AI Copilot'), findsNothing);
    });

    testWidgets('title bar shows dropdown arrow icon', (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'Test chat',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Should have a dropdown arrow in the title bar
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('tapping title bar opens popup with all conversations',
        (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      // Seed with two conversations
      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'First chat',
            createdAt: DateTime(2026, 1, 1),
          ),
          ConversationMeta(
            id: 'conv2',
            title: 'Second chat',
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Tap the title bar conversation picker
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-title-picker')),
      );
      await tester.pumpAndSettle();

      // Both conversations should appear in the popup
      expect(find.text('First chat'), findsWidgets);
      expect(find.text('Second chat'), findsWidgets);
      // "New Conversation" option should be at the bottom
      expect(find.text('New Conversation'), findsOneWidget);
    });

    testWidgets('each conversation in popup has inline delete button',
        (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'Chat A',
            createdAt: DateTime(2026, 1, 1),
          ),
          ConversationMeta(
            id: 'conv2',
            title: 'Chat B',
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Open the title bar picker
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-title-picker')),
      );
      await tester.pumpAndSettle();

      // Each conversation row should have a delete (close/X) icon
      // We look for the inline delete buttons by key pattern
      expect(
        find.byKey(const ValueKey<String>('chat-delete-conv-conv1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-delete-conv-conv2')),
        findsOneWidget,
      );
    });

    testWidgets('inline delete removes conversation from list', (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'Keep this',
            createdAt: DateTime(2026, 1, 1),
          ),
          ConversationMeta(
            id: 'conv2',
            title: 'Delete this',
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Open the title bar picker
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-title-picker')),
      );
      await tester.pumpAndSettle();

      // Tap the inline delete button for conv2
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-delete-conv-conv2')),
      );
      await tester.pumpAndSettle();

      // conv2 should be removed from conversations
      final state = capturedRef.read(chatProvider);
      expect(state.conversations.any((c) => c.id == 'conv2'), isFalse);
      expect(state.conversations.any((c) => c.id == 'conv1'), isTrue);
    });

    testWidgets('selecting New Conversation creates a new one', (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'Existing chat',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        messages: [ChatMessage.user('Hello')], // non-empty so new is created
      );
      await tester.pumpAndSettle();

      // Open the title bar picker
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-title-picker')),
      );
      await tester.pumpAndSettle();

      // Tap "New Conversation"
      await tester.tap(find.text('New Conversation'));
      await tester.pumpAndSettle();

      // A new conversation should be created (total 2)
      final state = capturedRef.read(chatProvider);
      expect(state.conversations.length, 2);
      expect(state.activeConversationId, isNot('conv1'));
    });

    testWidgets('selecting a conversation switches to it', (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'Active chat',
            createdAt: DateTime(2026, 1, 1),
          ),
          ConversationMeta(
            id: 'conv2',
            title: 'Other chat',
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // Open the title bar picker
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-title-picker')),
      );
      await tester.pumpAndSettle();

      // Tap "Other chat" to switch
      // Use the menu item key rather than text to avoid ambiguity
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-conv-item-conv2')),
      );
      await tester.pumpAndSettle();

      expect(capturedRef.read(chatProvider).activeConversationId, 'conv2');
    });
  });

  group('Overflow menu cleanup', () {
    testWidgets('overflow menu does NOT contain Clear Current', (tester) async {
      await tester.pumpWidget(_wrapInStack(const ChatOverlay()));
      await tester.pumpAndSettle();

      // Open overflow menu
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-overflow-menu')),
      );
      await tester.pumpAndSettle();

      // "Clear Current" should NOT be present
      expect(find.text('Clear Current'), findsNothing);
    });

    testWidgets('overflow menu does NOT contain Show/Hide Conversations',
        (tester) async {
      await tester.pumpWidget(_wrapInStack(const ChatOverlay()));
      await tester.pumpAndSettle();

      // Open overflow menu
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-overflow-menu')),
      );
      await tester.pumpAndSettle();

      // Neither "Show Conversations" nor "Hide Conversations" should be present
      expect(find.text('Show Conversations'), findsNothing);
      expect(find.text('Hide Conversations'), findsNothing);
    });

    testWidgets(
        'overflow menu contains only Show/Hide Credentials and Clear All',
        (tester) async {
      await tester.pumpWidget(_wrapInStack(const ChatOverlay()));
      await tester.pumpAndSettle();

      // Open overflow menu
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-overflow-menu')),
      );
      await tester.pumpAndSettle();

      // Should have credentials toggle and Clear All
      expect(find.text('Hide Credentials'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
    });
  });

  group('Title bar - no separate conversation picker row', () {
    testWidgets('no separate conversation-picker widget exists',
        (tester) async {
      late WidgetRef capturedRef;

      await tester.pumpWidget(_wrapWithPrefsAndRef(
        const ChatOverlay(),
        (ref) => capturedRef = ref,
      ));
      await tester.pumpAndSettle();

      // Seed with conversations
      capturedRef.read(chatProvider.notifier).state = ChatState(
        activeConversationId: 'conv1',
        conversations: [
          ConversationMeta(
            id: 'conv1',
            title: 'Test',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // The old separate conversation picker row should NOT exist
      expect(
        find.byKey(const ValueKey<String>('chat-conversation-picker')),
        findsNothing,
      );
    });
  });
}
