/// Behaviour tests for the history view's reworked controls.
///
/// Contract under test:
///  - the range chip offers quick presets; picking one sets the range and
///    the chip shows the preset's name, not two raw timestamps
///  - toggling Historical → Realtime → Historical keeps the picked range
///  - the realtime window chip offers preset durations
///  - selected keys appear as removable chips; deleting one deselects it
///  - "Expand all" can be undone per folder (the __ALL__ sentinel used to
///    force every folder open until "Collapse all")
///  - the saved-view selector sits above the tree and loading a view fills
///    the selection
///  - the "Adding to" indicator only appears once a second graph exists
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_view_harness.dart';

void main() {
  testWidgets('range presets: one tap sets the range and names the chip',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildHistoryView(
      keyMappings: historyKeyMappings(),
      appDb: inMemoryAppDatabase(),
    ));
    await settleHistory(tester);

    await tester.tap(find.text('Historical'));
    await settleHistory(tester);
    expect(find.text('Pick range…'), findsOneWidget,
        reason: 'no range picked yet');

    await tester.tap(find.text('Pick range…'));
    await settleHistory(tester);
    expect(find.text('Last hour'), findsOneWidget);
    expect(find.text('Last 8 hours'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Custom…'), findsOneWidget);

    await tester.tap(find.text('Last hour'));
    await settleHistory(tester);
    expect(find.text('Last hour'), findsOneWidget,
        reason: 'chip shows the preset name');
    expect(find.text('Pick range…'), findsNothing);
    expect(find.text('Pick a start & end date'), findsNothing,
        reason: 'the pane got a real range');
  });

  testWidgets('a picked range survives a trip through Realtime',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildHistoryView(
      keyMappings: historyKeyMappings(),
      appDb: inMemoryAppDatabase(),
    ));
    await settleHistory(tester);

    await tester.tap(find.text('Historical'));
    await settleHistory(tester);
    await tester.tap(find.text('Pick range…'));
    await settleHistory(tester);
    await tester.tap(find.text('Last hour'));
    await settleHistory(tester);

    await tester.tap(find.text('Realtime'));
    await settleHistory(tester);
    await tester.tap(find.text('Historical'));
    await settleHistory(tester);

    expect(find.text('Last hour'), findsOneWidget,
        reason: 'the range must not be thrown away by a mode toggle');
    expect(find.text('Pick range…'), findsNothing);
  });

  testWidgets('realtime window presets set the window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildHistoryView(
      keyMappings: historyKeyMappings(),
      appDb: inMemoryAppDatabase(),
    ));
    await settleHistory(tester);

    expect(find.text('Window: 10m 00s'), findsOneWidget);
    await tester.tap(find.text('Window: 10m 00s'));
    await settleHistory(tester);
    await tester.tap(find.text('5 min'));
    await settleHistory(tester);
    expect(find.text('Window: 5m 00s'), findsOneWidget);
  });

  testWidgets('selected keys show as chips and a chip delete deselects',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildHistoryView(
      keyMappings: historyKeyMappings(),
      appDb: inMemoryAppDatabase(),
    ));
    await settleHistory(tester);

    expect(find.text('No keys selected'), findsOneWidget);

    await expandFolder(tester, 'line1');
    await expandFolder(tester, 'motor');
    await tickKey(tester, 'speed');

    expect(find.text('Selected (1)'), findsOneWidget);
    // Chip label + tree row both say "speed".
    expect(find.text('speed'), findsNWidgets(2));

    final chip = find.byType(InputChip);
    expect(chip, findsOneWidget);
    await tester.tap(find.descendant(
        of: chip, matching: find.byIcon(Icons.close)));
    await settleHistory(tester);

    expect(find.text('No keys selected'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('expand all can be undone one folder at a time',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildHistoryView(
      keyMappings: historyKeyMappings(),
      appDb: inMemoryAppDatabase(),
    ));
    await settleHistory(tester);

    await tester.tap(find.byIcon(Icons.unfold_more));
    await settleHistory(tester);
    expect(find.text('speed'), findsOneWidget,
        reason: 'expand all reveals the leaves');

    // Collapsing line1 must actually collapse it — the old __ALL__ sentinel
    // kept forcing every folder open.
    await tester.tap(find.text('line1'));
    await settleHistory(tester);
    expect(find.text('speed'), findsNothing);
    expect(find.text('motor'), findsNothing);
  });

  testWidgets('saved view loads its keys from the selector above the tree',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appDb = inMemoryAppDatabase();
    await appDb.createHistoryView(
        'Shift A', ['line1.motor.speed', 'line1.temperature'], {}, {});

    await tester.pumpWidget(buildHistoryView(
      keyMappings: historyKeyMappings(),
      appDb: appDb,
    ));
    await settleHistory(tester);

    expect(find.text('Saved view'), findsOneWidget);
    await tester.tap(find.text('None'));
    await settleHistory(tester);
    await tester.tap(find.text('Shift A').last);
    await settleHistory(tester);

    expect(find.text('Selected (2)'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(2));
  });

  testWidgets('"Adding to" indicator appears once a second graph exists',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildHistoryView(
      keyMappings: historyKeyMappings(),
      appDb: inMemoryAppDatabase(),
    ));
    await settleHistory(tester);

    expect(find.textContaining('Adding to:'), findsNothing,
        reason: 'a single graph needs no target indicator');

    // "Add graph" picks the first unused index, so graph 1 must hold a key
    // before a second graph can exist.
    await expandFolder(tester, 'line1');
    await expandFolder(tester, 'motor');
    await tickKey(tester, 'speed');
    await tester.tap(find.byIcon(Icons.add_chart));
    await settleHistory(tester);

    expect(find.text('Adding to: Graph 2'), findsOneWidget);
  });
}
