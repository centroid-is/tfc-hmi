/// The two notice blocks the roles section and the users section share.
///
/// They exist as one file, tested once, because 06-07 and 06-08 are written in
/// parallel by two executors: two sections each inventing a warning block is how
/// two warning registers — and then two refusal wordings — start disagreeing.
///
/// Every test pumps inside a `MaterialApp` built from `muted()` rather than a
/// bare one, for the reason `audit_trail_row_test.dart` gives at its own head:
/// `HmiStateColors.of` falls back to `solarizedLight` when the theme carries no
/// extension, so a colour assertion under a bare `MaterialApp` would be an
/// assertion about a palette this build does not ship. Colours are compared
/// against `Theme.of(context).colorScheme` read from the element under test,
/// never against a literal — a literal would pin the token instead of the rule.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/theme.dart' show muted;
import 'package:tfc/widgets/access_admin_notice.dart';
import 'package:tfc_dart/core/access/access_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Three holders, so a test can assert the **count** is in the sentence as well
/// as the names. One holder would let a sentence that merely lists names pass.
const List<String> _kThree = ['admin', 'jon', 'sigga'];

LastUsersHolderException _lockout({List<String> holders = _kThree}) =>
    LastUsersHolderException('Engineering', holders);

RoleInUseException _inUse({List<String> holders = _kThree}) =>
    RoleInUseException('Cleaning', holders);

/// Pumps [child] under the muted light theme at a width a 1080p panel would
/// give it, so an ellipsis in a test means the widget clipped rather than that
/// the 800px default test surface did.
Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: muted().$1,
        home: Scaffold(
          body: Center(child: SizedBox(width: 760, child: child)),
        ),
      ),
    );

/// The background the block actually painted.
Color? _background(WidgetTester tester, Key blockKey) {
  final container = tester.widget<Container>(find.byKey(blockKey));
  return (container.decoration as BoxDecoration?)?.color;
}

/// The colour scheme the block resolved, read from its own element.
ColorScheme _scheme(WidgetTester tester, Key blockKey) =>
    Theme.of(tester.element(find.byKey(blockKey))).colorScheme;

/// Every rendered sentence in the subtree, as the `Text` widgets themselves.
List<Text> _sentences(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).toList();

void main() {
  // -------------------------------------------------------------------------
  // The warning block
  // -------------------------------------------------------------------------

  group('AccessAdminWarning', () {
    testWidgets('renders its sentence and its names', (tester) async {
      await _pump(
        tester,
        const AccessAdminWarning(
          text: 'Ticking a group here grants it to every logged-out panel.',
          names: _kThree,
        ),
      );

      expect(
          find.text(
              'Ticking a group here grants it to every logged-out panel.'),
          findsOneWidget);
      for (final name in _kThree) {
        expect(find.byKey(kAccessAdminNoticeNameKey(name)), findsOneWidget);
      }
    });

    testWidgets('draws the milestone warning register from the theme',
        (tester) async {
      await _pump(
        tester,
        const AccessAdminWarning(text: 'A sentence.'),
      );

      final scheme = _scheme(tester, kAccessAdminWarningKey);
      expect(
        _background(tester, kAccessAdminWarningKey),
        scheme.surfaceContainerHighest,
        reason: 'the theme\'s own warning surface rather than a raw colour or '
            'HmiStateColors.red/.orange: a lock is not a fault, and only a '
            'fault may be saturated. Settled twice already, in '
            'access_templates_section.dart and in access_gate.dart',
      );
      final border =
          (tester.widget<Container>(find.byKey(kAccessAdminWarningKey)).decoration
              as BoxDecoration)
              .border as Border;
      expect(border.top.color, scheme.outlineVariant);
    });

    testWidgets('ellipsises nothing', (tester) async {
      await _pump(
        tester,
        const AccessAdminWarning(
          text: 'A sentence long enough that a one-line box would cut it, '
              'which is the failure this assertion exists to catch — a warning '
              'the eye skips because it was clipped has not been given.',
          names: _kThree,
          footnote: 'And a second sentence beneath it.',
        ),
      );

      for (final sentence in _sentences(tester)) {
        expect(sentence.maxLines, isNull,
            reason: 'find.text passing is not the same as the operator being '
                'able to read it');
        expect(sentence.overflow, anyOf(isNull, TextOverflow.visible));
      }
    });
  });

  // -------------------------------------------------------------------------
  // The refusal block
  // -------------------------------------------------------------------------

  group('AccessAdminRefusal', () {
    testWidgets('the lockout refusal names every holder', (tester) async {
      await _pump(tester, AccessAdminRefusal.lastUsersHolder(_lockout()));

      for (final name in _kThree) {
        expect(find.byKey(kAccessAdminNoticeNameKey(name)), findsOneWidget,
            reason: 'naming the accounts that are left is what makes the fix '
                'obvious — a shift that can read who is left knows who to ask');
      }
    });

    testWidgets('both refusals carry the holder count in the sentence',
        (tester) async {
      await _pump(tester, AccessAdminRefusal.lastUsersHolder(_lockout()));
      expect(
        find.textContaining('3'),
        findsOneWidget,
        reason: '06-CONTEXT locks the refusal to "showing the count and names '
            'of the holders", and the precedent it names — '
            'kAccessTemplateDeleteBlockedNote(String name, int keys) at '
            'access_templates_section.dart — takes the count as a parameter of '
            'the sentence with the names listed beneath. A sentence naming '
            'three people without saying "3" makes the reader count them',
      );
      for (final name in _kThree) {
        expect(find.byKey(kAccessAdminNoticeNameKey(name)), findsOneWidget);
      }

      await _pump(tester, AccessAdminRefusal.roleInUse(_inUse()));
      expect(find.textContaining('3'), findsOneWidget,
          reason: 'the same ruling, the other refusal type');
      for (final name in _kThree) {
        expect(find.byKey(kAccessAdminNoticeNameKey(name)), findsOneWidget);
      }
    });

    testWidgets('the lockout refusal points at the break-glass section',
        (tester) async {
      await _pump(tester, AccessAdminRefusal.lastUsersHolder(_lockout()));
      expect(find.byKey(kAccessAdminNoticeFootnoteKey), findsOneWidget);
      expect(find.textContaining('docs/access-control-deployment.md'),
          findsOneWidget);
    });

    testWidgets('the in-use refusal does not point at break-glass',
        (tester) async {
      await _pump(tester, AccessAdminRefusal.roleInUse(_inUse()));
      expect(
        find.byKey(kAccessAdminNoticeFootnoteKey),
        findsNothing,
        reason: 'a role still held is not a lockout: it is resolved by moving '
            'the accounts, and sending a commissioning engineer to the '
            'break-glass procedure for it would be advice that breaks things',
      );
    });

    testWidgets('offers no action at all', (tester) async {
      await _pump(tester, AccessAdminRefusal.lastUsersHolder(_lockout()));

      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is ButtonStyleButton),
        findsNothing,
        reason: '06-CONTEXT rejects a typed-confirmation lockout override — '
            '"No destructive override is offered — no typed-confirmation '
            'escape" — and lists "A typed-confirmation lockout override (type '
            'LOCKOUT to proceed)" among the ideas it deferred as rejected. '
            '_DeleteTemplateDialog\'s doctrine is that the instruction takes '
            'the action\'s place; a control that is present and always refuses '
            'teaches the operator to press it twice. This test is what stops a '
            'well-meaning later edit from adding one',
      );
    });

    testWidgets('draws the same register as the warning', (tester) async {
      await _pump(tester, AccessAdminRefusal.roleInUse(_inUse()));
      expect(_background(tester, kAccessAdminRefusalKey),
          _scheme(tester, kAccessAdminRefusalKey).surfaceContainerHighest);
    });

    testWidgets('ellipsises nothing', (tester) async {
      await _pump(tester, AccessAdminRefusal.lastUsersHolder(_lockout()));
      for (final sentence in _sentences(tester)) {
        expect(sentence.maxLines, isNull);
        expect(sentence.overflow, anyOf(isNull, TextOverflow.visible));
      }
    });

    testWidgets('a single holder reads as one account, not "1 accounts"',
        (tester) async {
      await _pump(
          tester, AccessAdminRefusal.lastUsersHolder(_lockout(holders: ['jon'])));
      expect(find.textContaining('1 accounts'), findsNothing);
      expect(find.textContaining('1 account'), findsOneWidget);
    });
  });
}
