/// Behaviour of the one colour picker: [ColorPickerRow] +
/// [showColorPickerDialog].
///
/// The regression pinned here crashed a live HMI: the third-party asset
/// editor's hand-rolled picker popped with the EDITOR's context instead of
/// the dialog's own, so a Done tap racing a barrier dismiss popped the app's
/// only page — `'_history.isNotEmpty': is not true` in Navigator.build. The
/// shared dialog pops with its own route context, which cannot reach the
/// page below.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/panes/color_picker_dialog.dart';

Widget _app(Widget body) {
  return MaterialApp(home: Scaffold(body: Center(child: body)));
}

void main() {
  testWidgets('row opens the dialog and Done keeps the page alive',
      (tester) async {
    Color color = Colors.green;
    await tester.pumpWidget(_app(StatefulBuilder(
      builder: (context, setState) => ColorPickerRow(
        label: 'Stopped Color',
        color: color,
        onChanged: (c) => setState(() => color = c),
      ),
    )));

    await tester.tap(find.text('Stopped Color'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    // The page below the dialog must survive — this is the crash the shared
    // dialog exists to prevent.
    expect(find.text('Stopped Color'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('barrier dismiss then a queued Done tap cannot pop the page',
      (tester) async {
    await tester.pumpWidget(_app(ColorPickerRow(
      label: 'Colour',
      color: Colors.red,
      onChanged: (_) {},
    )));

    await tester.tap(find.text('Colour'));
    await tester.pumpAndSettle();

    // Dismiss via the barrier, then hit Done's position while the dialog is
    // still animating out — the tap must not fall through to a second pop.
    final done = tester.getCenter(find.text('Done'));
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.tapAt(done);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Colour'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear appears only with onCleared and reports null',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(_app(ColorPickerRow(
      label: 'Text Color',
      color: null,
      onChanged: (_) {},
      onCleared: () => cleared = true,
    )));

    await tester.tap(find.text('Text Color'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear colour'));
    await tester.pumpAndSettle();

    expect(cleared, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a null colour renders the reset glyph on the swatch',
      (tester) async {
    await tester.pumpWidget(_app(ColorPickerRow(
      label: 'Override',
      color: null,
      onChanged: (_) {},
    )));
    expect(find.byIcon(Icons.format_color_reset), findsOneWidget);
  });
}
