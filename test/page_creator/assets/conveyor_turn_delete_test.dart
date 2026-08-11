import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/providers/state_man.dart';

import '../../helpers/test_helpers.dart';

Widget _wrap(ConveyorConfig config) => ProviderScope(
      overrides: [
        preferencesProvider.overrideWith((ref) => createTestPreferences()),
        databaseProvider.overrideWith((ref) async => null),
        stateManProvider
            .overrideWith((ref) => throw StateError('No StateMan in tests')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => config.configure(context)),
        ),
      ),
    );

/// The panel is a fixed 300px column, and the test font is far wider per
/// glyph than the real one, so its checkbox rows overflow here and nowhere
/// else. Drop those so a genuine failure is not buried in them.
void _ignoreTestFontOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// Values shown in the per-turn number boxes. Each turn card carries three:
/// position, angle, radius — [offset] picks which.
List<String> _boxValues(WidgetTester tester, int offset) {
  final fields = tester
      .widgetList<TextField>(find.descendant(
          of: find.byType(Card), matching: find.byType(TextField)))
      .toList();
  return [
    for (var i = offset; i < fields.length; i += 3) fields[i].controller!.text
  ];
}

void main() {
  testWidgets('deleting a turn removes the turn whose button was tapped',
      (tester) async {
    _ignoreTestFontOverflow();
    final config = ConveyorConfig(turns: [
      ConveyorTurnEntry(position: 0.2, angle: 10, radius: 1.0),
      ConveyorTurnEntry(position: 0.5, angle: 20, radius: 2.0),
      ConveyorTurnEntry(position: 0.8, angle: 30, radius: 3.0),
    ]);

    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(config));
    await tester.pump();

    final deletes = find.byTooltip('Remove turn');
    expect(deletes, findsNWidgets(3));

    await tester.tap(deletes.at(1));
    await tester.pump();

    expect(config.turns.map((t) => t.angle).toList(), [10.0, 30.0]);

    // And the surviving cards must show the surviving turns.
    expect(_boxValues(tester, 1), ['10', '30']);
    expect(_boxValues(tester, 0), ['20', '80']);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    // 3 sliders per turn card (position, angle, radius) + the thickness slider.
    expect(sliders.length, 3 * 2 + 1);
  });

  testWidgets('repeated deletes each remove the tapped turn', (tester) async {
    _ignoreTestFontOverflow();
    final config = ConveyorConfig(turns: [
      ConveyorTurnEntry(position: 0.2, angle: 10, radius: 1.0),
      ConveyorTurnEntry(position: 0.5, angle: 20, radius: 2.0),
      ConveyorTurnEntry(position: 0.8, angle: 30, radius: 3.0),
      ConveyorTurnEntry(position: 0.9, angle: 40, radius: 4.0),
    ]);

    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(config));
    await tester.pump();

    final deletes = find.byTooltip('Remove turn');
    await tester.tap(deletes.at(3));
    await tester.pump();
    expect(config.turns.map((t) => t.angle).toList(), [10.0, 20.0, 30.0]);

    await tester.tap(deletes.at(0));
    await tester.pump();
    expect(config.turns.map((t) => t.angle).toList(), [20.0, 30.0]);

    await tester.tap(deletes.at(1));
    await tester.pump();
    expect(config.turns.map((t) => t.angle).toList(), [20.0]);
  });

  testWidgets('turn cards are listed in the order the belt bends',
      (tester) async {
    _ignoreTestFontOverflow();
    // "Add Turn" always appends at 50%, so a turn added after one that was
    // moved down the belt lands *before* it. The editor listed insertion
    // order while the belt renders sorted by position, so the card labelled
    // "Turn 1" was the belt's second bend.
    final config = ConveyorConfig(turns: [
      ConveyorTurnEntry(position: 0.8, angle: 30, radius: 1.0),
      ConveyorTurnEntry(position: 0.5, angle: 20, radius: 2.0),
      ConveyorTurnEntry(position: 0.2, angle: 10, radius: 3.0),
    ]);

    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(config));
    await tester.pump();

    expect(_boxValues(tester, 0), ['20', '50', '80']);

    // Turn 1 is the belt's first bend, so deleting it removes the 20% entry.
    await tester.tap(find.byTooltip('Remove turn').at(0));
    await tester.pump();
    expect(config.turns.map((t) => t.position).toList(), [0.5, 0.8]);
  });

  testWidgets('Add Turn spreads new turns instead of stacking them',
      (tester) async {
    _ignoreTestFontOverflow();
    final config = ConveyorConfig();

    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(config));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Add Turn'));
      await tester.pump();
    }

    expect(config.turns, hasLength(3));
    final positions = config.turns.map((t) => t.position).toList();
    expect(positions.toSet(), hasLength(3), reason: 'stacked: $positions');
    // And the list is kept in belt order, so the cards are numbered by bend.
    expect(positions, orderedEquals(List.of(positions)..sort()));
  });

  testWidgets('turn values can be typed instead of dragged', (tester) async {
    _ignoreTestFontOverflow();
    final config = ConveyorConfig(turns: [
      ConveyorTurnEntry(position: 0.5, angle: 45, radius: 1.5),
    ]);

    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(config));
    await tester.pump();

    // One box per turn setting: position, angle, radius.
    final boxes = find.descendant(
      of: find.byType(Card),
      matching: find.byType(TextField),
    );
    expect(boxes, findsNWidgets(3));

    await tester.enterText(boxes.at(0), '37');
    await tester.pump();
    expect(config.turns.single.position, closeTo(0.37, 1e-9));

    await tester.enterText(boxes.at(1), '-62');
    await tester.pump();
    expect(config.turns.single.angle, closeTo(-62, 1e-9));

    await tester.enterText(boxes.at(2), '3.4');
    await tester.pump();
    expect(config.turns.single.radius, closeTo(3.4, 1e-9));
  });

  testWidgets('typed turn values are held inside the slider range',
      (tester) async {
    _ignoreTestFontOverflow();
    final config = ConveyorConfig(turns: [
      ConveyorTurnEntry(position: 0.5, angle: 45, radius: 1.5),
    ]);

    tester.view.physicalSize = const Size(1400, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(config));
    await tester.pump();

    final boxes = find.descendant(
      of: find.byType(Card),
      matching: find.byType(TextField),
    );

    // A turn past a half circle would send the belt back over itself.
    await tester.enterText(boxes.at(1), '400');
    await tester.pump();
    expect(config.turns.single.angle, 180);

    await tester.enterText(boxes.at(0), '-40');
    await tester.pump();
    expect(config.turns.single.position, 0);

    await tester.enterText(boxes.at(2), '99');
    await tester.pump();
    expect(config.turns.single.radius, 5.0);

    // Gibberish leaves the value alone rather than zeroing it.
    await tester.enterText(boxes.at(2), 'abc');
    await tester.pump();
    expect(config.turns.single.radius, 5.0);
  });

  testWidgets('delete works inside the scrolling page-editor config dialog',
      (tester) async {
    _ignoreTestFontOverflow();
    final config = ConveyorConfig(turns: [
      ConveyorTurnEntry(position: 0.2, angle: 10, radius: 1.0),
      ConveyorTurnEntry(position: 0.5, angle: 20, radius: 2.0),
      ConveyorTurnEntry(position: 0.8, angle: 30, radius: 3.0),
    ]);

    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesProvider.overrideWith((ref) => createTestPreferences()),
        databaseProvider.overrideWith((ref) async => null),
        stateManProvider
            .overrideWith((ref) => throw StateError('No StateMan in tests')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 600,
              child: IntrinsicWidth(
                child: Builder(builder: (c) => config.configure(c)),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final deletes = find.byTooltip('Remove turn');
    await tester.scrollUntilVisible(deletes.at(2), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(deletes.at(2));
    await tester.pump();

    expect(config.turns.map((t) => t.angle).toList(), [10.0, 20.0]);
  });
}
