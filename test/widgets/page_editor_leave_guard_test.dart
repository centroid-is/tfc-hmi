/// Leaving the page editor with unsaved edits asks first.
///
/// The editor keeps edits in memory until Save; the back arrow and the nav
/// bar used to drop them without a word. The editor now installs a
/// [LeaveGuard] that the navigation chrome asks before beaming.
library;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/leave_guard.dart';

import '../helpers/page_editor_harness.dart';

Future<void> nudgeRight(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
  await tester.pumpAndSettle();
}

void main() {
  setUp(setUpEditorEnvironment);

  testWidgets('a clean editor lets navigation go without asking',
      (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    expect(LeaveGuard.isSet, isTrue, reason: 'the editor installs a guard');
    final may = LeaveGuard.mayLeave();
    await tester.pumpAndSettle();
    expect(await may, isTrue);
    expect(find.text('Unsaved changes'), findsNothing);
  });

  testWidgets('unsaved edits: Stay refuses, Discard allows', (tester) async {
    await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);
    await nudgeRight(tester);

    var answer = LeaveGuard.mayLeave();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);

    answer = LeaveGuard.mayLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);
  });

  testWidgets('"Save and leave" writes the page, then allows', (tester) async {
    final prefs = await pumpEditorWith(tester, [editorBox(0.3, 0.3)]);
    await tapAsset(tester, 0.3, 0.3);
    await nudgeRight(tester);

    final answer = LeaveGuard.mayLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save and leave'));
    await tester.pumpAndSettle();
    expect(await answer, isTrue);

    final saved = readBackHomeAssets(prefs)!;
    expect(coordsOf(saved.single)['x'], greaterThan(0.3),
        reason: 'the nudge reached the preferences');
  });
}
