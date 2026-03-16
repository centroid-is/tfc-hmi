import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/chat/chat_overlay.dart';
import 'package:tfc/chat/chat_skill_chips.dart';
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

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

Widget _wrapInStackWithPrefs(Widget child) {
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWith((_) async => _createTestPreferences()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Stack(children: [child]),
      ),
    ),
  );
}

// ─── Tests ──────────────────────────────────────────────────────────────

void main() {
  group('ChatSkillChips', () {
    testWidgets('renders all default skill chips', (tester) async {
      String? tappedPrompt;

      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (prompt) => tappedPrompt = prompt,
        ),
      ));

      // All four default chips should be rendered
      expect(find.text('Create alarm'), findsOneWidget);
      expect(find.text('Create page'), findsOneWidget);
      expect(find.text('Show history'), findsOneWidget);
      expect(find.text('Explain asset'), findsOneWidget);

      // Tapped prompt should be null initially
      expect(tappedPrompt, isNull);
    });

    testWidgets('each chip has a Marionette-compatible ValueKey',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (_) {},
        ),
      ));

      expect(
        find.byKey(const ValueKey<String>('chat-skill-create-alarm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-skill-create-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-skill-show-history')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-skill-explain-asset')),
        findsOneWidget,
      );
    });

    testWidgets('tapping a chip invokes onSkillTapped with prompt',
        (tester) async {
      String? tappedPrompt;

      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (prompt) => tappedPrompt = prompt,
        ),
      ));

      // Tap the "Create alarm" chip
      await tester.tap(find.text('Create alarm'));
      await tester.pumpAndSettle();

      expect(tappedPrompt, 'Create a new alarm for ');
    });

    testWidgets('tapping "Create page" chip pre-fills correct prompt',
        (tester) async {
      String? tappedPrompt;

      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (prompt) => tappedPrompt = prompt,
        ),
      ));

      await tester.tap(find.text('Create page'));
      await tester.pumpAndSettle();

      expect(tappedPrompt, 'Create a new page for ');
    });

    testWidgets('tapping "Show history" chip pre-fills correct prompt',
        (tester) async {
      String? tappedPrompt;

      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (prompt) => tappedPrompt = prompt,
        ),
      ));

      await tester.tap(find.text('Show history'));
      await tester.pumpAndSettle();

      expect(tappedPrompt, 'Show the history for ');
    });

    testWidgets('tapping "Explain asset" chip pre-fills correct prompt',
        (tester) async {
      String? tappedPrompt;

      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (prompt) => tappedPrompt = prompt,
        ),
      ));

      await tester.tap(find.text('Explain asset'));
      await tester.pumpAndSettle();

      expect(tappedPrompt, 'Explain what this asset does: ');
    });

    testWidgets('renders icons for each skill', (tester) async {
      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (_) {},
        ),
      ));

      expect(find.byIcon(Icons.alarm_add), findsOneWidget);
      expect(find.byIcon(Icons.dashboard_customize), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });

    testWidgets('accepts custom skills list', (tester) async {
      const customSkills = [
        ChatSkill(
          id: 'custom-one',
          label: 'Custom Action',
          icon: Icons.star,
          prompt: 'Do something custom',
        ),
      ];

      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          skills: customSkills,
          onSkillTapped: (_) {},
        ),
      ));

      expect(find.text('Custom Action'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
      // Default chips should not be present
      expect(find.text('Create alarm'), findsNothing);
    });

    testWidgets('chips use ActionChip widget type', (tester) async {
      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (_) {},
        ),
      ));

      // Should find ActionChip widgets for each skill
      expect(find.byType(ActionChip), findsNWidgets(defaultChatSkills.length));
    });

    testWidgets('renders nothing when skills list is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          skills: const [],
          onSkillTapped: (_) {},
        ),
      ));

      // No ActionChip widgets should be rendered
      expect(find.byType(ActionChip), findsNothing);
      // The Wrap container should still exist but be empty
      expect(find.byType(Wrap), findsOneWidget);
    });

    testWidgets('tapping different chips in sequence updates prompt each time',
        (tester) async {
      final tappedPrompts = <String>[];

      await tester.pumpWidget(_wrap(
        ChatSkillChips(
          onSkillTapped: (prompt) => tappedPrompts.add(prompt),
        ),
      ));

      await tester.tap(find.text('Create alarm'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explain asset'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show history'));
      await tester.pumpAndSettle();

      expect(tappedPrompts, [
        'Create a new alarm for ',
        'Explain what this asset does: ',
        'Show the history for ',
      ]);
    });

    testWidgets('all default prompts end with trailing space for user input',
        (tester) async {
      // Ensures prompts are designed for the user to append an asset name
      for (final skill in defaultChatSkills) {
        expect(skill.prompt.endsWith(' '), isTrue,
            reason: '${skill.id} prompt should end with a space');
      }
    });

    testWidgets('each skill has a unique id', (tester) async {
      final ids = defaultChatSkills.map((s) => s.id).toSet();
      expect(ids.length, defaultChatSkills.length,
          reason: 'All skill IDs should be unique');
    });
  });

  group('ChatSkillChips in ChatOverlay empty state', () {
    // ChatOverlay computes 30% width × 60% height — use a large surface
    // so skill chips are fully visible and tappable.
    void setLargeTestSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
    }

    void resetTestSurface(WidgetTester tester) {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    testWidgets('skill chips appear in empty chat state', (tester) async {
      setLargeTestSurface(tester);
      addTearDown(() => resetTestSurface(tester));

      await tester.pumpWidget(_wrapInStackWithPrefs(const ChatOverlay()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The empty state message should be shown
      expect(find.textContaining('Ask the AI copilot'), findsOneWidget);

      // Skill chips should be visible
      expect(find.text('Create alarm'), findsOneWidget);
      expect(find.text('Create page'), findsOneWidget);
      expect(find.text('Show history'), findsOneWidget);
      expect(find.text('Explain asset'), findsOneWidget);
    });

    testWidgets('tapping a skill chip pre-fills the message input',
        (tester) async {
      setLargeTestSurface(tester);
      addTearDown(() => resetTestSurface(tester));

      await tester.pumpWidget(_wrapInStackWithPrefs(const ChatOverlay()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the "Create alarm" skill chip
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-skill-create-alarm')),
      );
      await tester.pumpAndSettle();

      // The text field should now contain the prompt template
      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('chat-message-input')),
      );
      expect(textField.controller?.text, 'Create a new alarm for ');
    });

    testWidgets('skill chips have correct semantic keys in overlay',
        (tester) async {
      setLargeTestSurface(tester);
      addTearDown(() => resetTestSurface(tester));

      await tester.pumpWidget(_wrapInStackWithPrefs(const ChatOverlay()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byKey(const ValueKey<String>('chat-skill-create-alarm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-skill-create-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-skill-show-history')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('chat-skill-explain-asset')),
        findsOneWidget,
      );
    });

    testWidgets('chip tap places cursor at end of prompt text',
        (tester) async {
      setLargeTestSurface(tester);
      addTearDown(() => resetTestSurface(tester));

      await tester.pumpWidget(_wrapInStackWithPrefs(const ChatOverlay()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the "Create alarm" chip (first chip, always visible in overlay)
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-skill-create-alarm')),
      );
      await tester.pumpAndSettle();

      // Verify cursor is at the end of the prompt text
      final textField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('chat-message-input')),
      );
      final controller = textField.controller!;
      expect(controller.text, 'Create a new alarm for ');
      expect(
        controller.selection,
        TextSelection.collapsed(offset: controller.text.length),
      );
    });

    testWidgets('tapping a second chip replaces the first prompt',
        (tester) async {
      setLargeTestSurface(tester);
      addTearDown(() => resetTestSurface(tester));

      await tester.pumpWidget(_wrapInStackWithPrefs(const ChatOverlay()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap "Create alarm" (first chip)
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-skill-create-alarm')),
      );
      await tester.pumpAndSettle();

      var textField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('chat-message-input')),
      );
      expect(textField.controller?.text, 'Create a new alarm for ');

      // Tap "Create page" (second chip, adjacent to first) -- should replace
      await tester.tap(
        find.byKey(const ValueKey<String>('chat-skill-create-page')),
      );
      await tester.pumpAndSettle();

      textField = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('chat-message-input')),
      );
      expect(textField.controller?.text, 'Create a new page for ');
    });
  });
}
