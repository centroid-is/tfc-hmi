/// The locked setpoint: it shows its number, it takes the tap, and signing in
/// hands back the field rather than the action.
///
/// Two acceptance criteria are pinned here, verbatim from
/// `.planning/REQUIREMENTS.md`:
///
///  * "A locked control shows its value, is tappable, and explains what is
///    needed. No control is ever greyed and inert."
///  * "Signing in re-opens the affordance and never replays the original
///    action: a value field goes live and focused but uncommitted."
///
/// The second half is the one most likely to be got wrong by helpfully
/// re-submitting on unlock, so it has its own test and the assertion that
/// carries it is `written, isEmpty` **before** the Enter, not after.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/panes/pane_chrome.dart';
import 'package:tfc/widgets/panes/setpoint_field.dart';

void main() {
  /// Whether a cursor is sitting in any editable field on screen.
  ///
  /// Not `FocusScope.of(...).hasFocus`, which answers true for the whole app
  /// scope whether or not a text field holds the primary focus, and would pass
  /// this file's assertions vacuously.
  bool anyFieldFocused(WidgetTester tester) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .any((w) => w.focusNode.hasFocus);

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Column(children: [child, const TextField(key: Key('other'))]),
        ),
      );

  SetpointField<double> field({
    required bool locked,
    VoidCallback? onLockedTap,
    void Function(double)? onSubmitted,
    String text = '50.00',
    double current = 50.0,
  }) =>
      SetpointField<double>(
        fieldKey: 'f',
        label: 'Auto',
        text: text,
        current: current,
        suffix: 'Hz',
        parse: double.tryParse,
        onSubmitted: onSubmitted ?? (_) {},
        locked: locked,
        onLockedTap: onLockedTap,
      );

  group('locked', () {
    testWidgets('still renders its value and its label', (tester) async {
      await tester.pumpWidget(host(field(locked: true)));
      await tester.pump();

      expect(find.text('50.00'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('a tap fires onLockedTap rather than focusing the field',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(field(
        locked: true,
        onLockedTap: () => taps++,
      )));
      await tester.pump();

      await tester.tap(find.text('50.00'));
      await tester.pump();

      expect(taps, 1);
      expect(anyFieldFocused(tester), isFalse,
          reason: 'the tap opens the prompt; it does not put a cursor in a '
              'field the operator may not commit');
    });

    testWidgets('carries a lock glyph', (tester) async {
      await tester.pumpWidget(host(field(locked: true)));
      await tester.pump();

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('the value is rendered in full, not ellipsised', (tester) async {
      // Phase 1 shipped a single-line ellipsising widget past a green
      // `find.text`. Assert the paragraph, not the finder.
      await tester.pumpWidget(host(field(locked: true, text: '1234.56')));
      await tester.pump();

      final paragraph =
          tester.renderObject<RenderParagraph>(find.text('1234.56'));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, greaterThan(0));
      expect(paragraph.size.height, greaterThan(0));
    });

    testWidgets('the lock has not pushed the value out of the box',
        (tester) async {
      // The height of the locked control against the height of the same
      // control unlocked. A glyph that grew the row would change it.
      await tester.pumpWidget(host(field(locked: false)));
      await tester.pump();
      final unlocked =
          tester.getSize(find.byType(SetpointField<double>)).height;

      await tester.pumpWidget(host(field(locked: true)));
      await tester.pump();
      final lockedHeight =
          tester.getSize(find.byType(SetpointField<double>)).height;

      expect(unlocked, greaterThan(0), reason: 'a real box to compare against');
      expect(lockedHeight, unlocked);
    });

    testWidgets('never submits, however hard it is pressed', (tester) async {
      final written = <double>[];
      await tester.pumpWidget(host(field(
        locked: true,
        onLockedTap: () {},
        onSubmitted: written.add,
      )));
      await tester.pump();

      await tester.tap(find.text('50.00'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();

      expect(written, isEmpty);
    });
  });

  group('the unlock transition', () {
    testWidgets('goes live and focused, with nothing committed until Enter',
        (tester) async {
      final written = <double>[];

      await tester.pumpWidget(host(field(
        locked: true,
        onLockedTap: () {},
        onSubmitted: written.add,
      )));
      await tester.pump();

      // Locked: there is no editable field to type into at all.
      expect(find.byType(TextFormField), findsNothing);

      // The operator signs in.
      await tester.pumpWidget(host(field(locked: false, onSubmitted: written.add)));
      await tester.pumpAndSettle();

      final focus = Focus.of(tester.element(find.byKey(const Key('f'))),
          scopeOk: true);
      expect(focus.hasFocus, isTrue,
          reason: 'the field goes live and focused');
      expect(find.text('50.00'), findsOneWidget,
          reason: 'showing what the PLC reports');
      expect(written, isEmpty,
          reason: 'signing in must never replay the refused action');

      // A fresh commit is the operator\'s to make.
      await tester.enterText(find.byKey(const Key('f')), '45');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(written, [45.0]);
    });

    testWidgets('locking again drops the focus', (tester) async {
      await tester.pumpWidget(host(field(locked: false)));
      await tester.tap(find.byKey(const Key('f')));
      await tester.pumpAndSettle();

      expect(anyFieldFocused(tester), isTrue, reason: 'a cursor to lose');

      await tester.pumpWidget(host(field(locked: true, onLockedTap: () {})));
      await tester.pumpAndSettle();

      expect(anyFieldFocused(tester), isFalse);
    });
  });

  group('PaneStatus.locked', () {
    test('equals another locked status and differs from stopped', () {
      expect(const PaneStatus.locked(), const PaneStatus.locked());
      expect(const PaneStatus.locked().hashCode,
          const PaneStatus.locked().hashCode);
      expect(const PaneStatus.locked() == const PaneStatus.stopped(), isFalse);
    });

    test('reads as locked rather than as faulted', () {
      const status = PaneStatus.locked();
      expect(status.label, 'Locked');
      expect(status.icon, Icons.lock_outline);
      // Not red — a lock is not a fault. Not orange — orange means
      // forced/override and elevation in this repo, and a locked pane is the
      // opposite of elevated.
      expect(status.color, isNot(const PaneStatus.fault().color));
      expect(status.color, isNot(const PaneStatus.warning().color));
      expect(status.color, isNot(Colors.orange));
      expect(status.color, isNot(Colors.red));
    });

    testWidgets('renders in the chip like its siblings', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: PaneStatusChip(status: PaneStatus.locked())),
        ),
      ));
      await tester.pump();

      expect(find.text('Locked'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });
  });
}
