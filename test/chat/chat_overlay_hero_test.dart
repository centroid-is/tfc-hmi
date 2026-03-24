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

/// A no-op secure storage for tests — API keys are not needed.
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

/// Creates an in-memory [Preferences] suitable for widget tests.
Preferences _createTestPreferences() {
  return Preferences(
    database: null,
    secureStorage: _FakeSecureStorage(),
  );
}

/// Regression tests for ChatOverlay Navigator architecture.
///
/// The ChatOverlay contains a nested Navigator. Without a
/// HeroControllerScope.none wrapper, that Navigator steals the
/// MaterialApp's HeroController. On unmount it nulls the controller's
/// navigator reference, causing any subsequent Hero-based navigation
/// (e.g. pushing a new route) to crash with
/// "A HeroController can not be shared by multiple Navigators".
///
/// Additionally, the Navigator must wrap the ENTIRE overlay content
/// (title bar + ChatWidget + resize handle) so that PopupMenuButton
/// in the title bar has an Overlay/Navigator ancestor for its popup.
void main() {
  group('ChatOverlay HeroController isolation', () {
    testWidgets(
      'closing ChatOverlay does not orphan the root HeroController',
      (tester) async {
        // Build a MaterialApp with the ChatOverlay inside a Stack on
        // a normal home page. The overlay is toggled via Visibility.
        final showOverlay = ValueNotifier<bool>(true);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: showOverlay,
                  builder: (context, visible, _) {
                    return Stack(
                      children: [
                        const Center(child: Text('Home')),
                        if (visible) const ChatOverlay(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify the overlay is visible.
        expect(find.text('New conversation'), findsOneWidget);

        // Close the overlay (simulates user closing the chat).
        showOverlay.value = false;
        await tester.pumpAndSettle();

        // Verify the overlay is gone.
        expect(find.text('New conversation'), findsNothing);

        // Now push a Hero-based route on the root navigator.
        // Before the fix, this crashes because MaterialApp's
        // HeroController has navigator == null.
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );

        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('New Page')),
          ),
        );
        await tester.pumpAndSettle();

        // If we get here without an assertion error, the fix works.
        expect(find.text('New Page'), findsOneWidget);
      },
    );

    testWidgets(
      'opening and closing ChatOverlay multiple times does not crash',
      (tester) async {
        final showOverlay = ValueNotifier<bool>(false);

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: showOverlay,
                  builder: (context, visible, _) {
                    return Stack(
                      children: [
                        const Center(child: Text('Home')),
                        if (visible) const ChatOverlay(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Toggle overlay on/off three times.
        for (var i = 0; i < 3; i++) {
          showOverlay.value = true;
          await tester.pumpAndSettle();
          expect(find.text('New conversation'), findsOneWidget);

          showOverlay.value = false;
          await tester.pumpAndSettle();
          expect(find.text('New conversation'), findsNothing);
        }

        // Navigate after all the toggling -- should not crash.
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );

        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('After Toggles')),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('After Toggles'), findsOneWidget);
      },
    );

    testWidgets(
      'HeroControllerScope.none prevents nested Navigator from '
      'stealing root HeroController',
      (tester) async {
        // This test directly validates the fix pattern: a nested
        // Navigator wrapped in HeroControllerScope.none should not
        // interfere with the root HeroController on unmount.
        final showNested = ValueNotifier<bool>(true);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: showNested,
                builder: (context, visible, _) {
                  return Stack(
                    children: [
                      const Center(child: Text('Main')),
                      if (visible)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: SizedBox(
                            width: 200,
                            height: 200,
                            // This is exactly the pattern from the fix:
                            child: HeroControllerScope.none(
                              child: Navigator(
                                onGenerateRoute: (_) => PageRouteBuilder<void>(
                                  pageBuilder: (_, __, ___) => const Scaffold(
                                    body: Text('Nested'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nested'), findsOneWidget);

        // Remove the nested navigator.
        showNested.value = false;
        await tester.pumpAndSettle();
        expect(find.text('Nested'), findsNothing);

        // Push a route using the root navigator -- should NOT crash.
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );

        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Pushed Page')),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Pushed Page'), findsOneWidget);
      },
    );
  });

  group('ChatOverlay PopupMenuButton Navigator ancestry', () {
    testWidgets(
      'PopupMenuButton in title bar renders without crash',
      (tester) async {
        // The title bar contains a PopupMenuButton which requires an
        // Overlay ancestor (for the popup) and Navigator.of(context)
        // (for showMenu). When the Navigator only wrapped ChatWidget,
        // the title bar was outside and had no Navigator ancestor,
        // causing a crash on tap. After the fix, the Navigator wraps
        // the entire Column so the title bar is inside the route.
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: const [ChatOverlay()],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The overflow menu icon should be present.
        expect(find.byIcon(Icons.more_vert), findsOneWidget);

        // The PopupMenuButton should be findable by its key.
        expect(
          find.byKey(const ValueKey<String>('chat-overflow-menu')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PopupMenuButton opens popup menu on tap without crash',
      (tester) async {
        // This test verifies the popup actually opens, which requires
        // Navigator.of(context) and an Overlay to succeed.
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: const [ChatOverlay()],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the overflow menu button.
        await tester.tap(
          find.byKey(const ValueKey<String>('chat-overflow-menu')),
        );
        await tester.pumpAndSettle();

        // The popup menu items should appear.
        // chatSettingsVisibleProvider defaults to true, so credentials
        // are visible and the toggle should offer to hide them.
        // Conversation picker is now in the title bar, not the overflow menu.
        expect(find.text('Hide Credentials'), findsOneWidget);
        expect(find.text('Clear All'), findsOneWidget);
        // Removed items should not appear
        expect(find.text('Hide Conversations'), findsNothing);
        expect(find.text('Clear Current'), findsNothing);
      },
    );

    testWidgets(
      'selecting credentials toggle menu item does not crash',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: const [ChatOverlay()],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the popup menu.
        await tester.tap(
          find.byKey(const ValueKey<String>('chat-overflow-menu')),
        );
        await tester.pumpAndSettle();

        // Tap 'Hide Credentials' to toggle credentials visibility.
        // (default state: credentials visible, so menu says Hide)
        await tester.tap(find.text('Hide Credentials'));
        await tester.pumpAndSettle();

        // If we reach here without a crash, the Navigator ancestry is
        // correctly providing Overlay and Navigator.of for showMenu/
        // PopupMenuButton internals.
        expect(find.text('New conversation'), findsOneWidget);
      },
    );

    testWidgets(
      'Clear All menu item resets conversations',
      (tester) async {
        late WidgetRef capturedRef;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              preferencesProvider
                  .overrideWith((_) async => _createTestPreferences()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    capturedRef = ref;
                    return Stack(
                      children: const [ChatOverlay()],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Add some messages so the state is non-empty.
        capturedRef.read(chatProvider.notifier).state = ChatState(
          activeConversationId: 'conv1',
          conversations: [
            ConversationMeta(
              id: 'conv1',
              title: 'Test',
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
          messages: [ChatMessage.user('Hello')],
        );
        await tester.pumpAndSettle();

        // Open the popup menu.
        await tester.tap(
          find.byKey(const ValueKey<String>('chat-overflow-menu')),
        );
        await tester.pumpAndSettle();

        // Verify "Clear All" menu item is present.
        expect(find.text('Clear All'), findsOneWidget);

        // Tap it.
        await tester.tap(find.text('Clear All'));
        await tester.pumpAndSettle();

        // After clear all, a fresh empty conversation should exist.
        final state = capturedRef.read(chatProvider);
        expect(state.messages, isEmpty);
        expect(state.conversations.length, 1);
        expect(state.conversations.first.title, 'New conversation');
        // The old conversation ID should be gone.
        expect(state.conversations.any((c) => c.id == 'conv1'), isFalse);
      },
    );
  });
}
