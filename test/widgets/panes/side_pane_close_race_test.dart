/// Closing a pane is animated, and the 220 ms it takes is long enough for the
/// operator to tap another machine. `panes_test.dart` pins the headline case —
/// the new pane survives the old one's slide-out. These are the neighbours of
/// that race: the strip the page yielded, a chain more than one deep, and the
/// `onClosed` callback that the page editor uses to flush pending edits.
///
/// Timing is driven with explicit `pump(Duration)` throughout. `pumpAndSettle`
/// runs the slide-out to completion before anything else happens, and then
/// there is no race left to test.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/panes/pane_chrome.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

/// Long enough for the 220 ms slide-out to have finished.
const _afterSlide = Duration(milliseconds: 400);

/// Inside the slide-out, with plenty of it left to run.
const _midSlide = Duration(milliseconds: 50);

/// A device box under the pane's strip, so opening a pane over it makes the
/// page yield — `occupiedWidth` goes non-zero only for a *covered* device.
const _coveredRect = Rect.fromLTWH(700, 100, 60, 60);

void main() {
  tearDown(() {
    closeSidePane(immediate: true);
  });

  Widget host({required void Function(BuildContext context) onOpen}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black12)),
            Align(
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => onOpen(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SidePane demoPane({required String title}) => SidePane(
        title: title,
        subtitle: 'Conveyor',
        icon: Icons.conveyor_belt,
        status: const PaneStatus.running(),
        child: const PaneSection(
          title: 'Status',
          child: PaneDetailRow(label: 'Frequency', value: '48.20 Hz'),
        ),
      );

  group('a pane opened during another pane\'s slide-out', () {
    testWidgets('keeps the strip the page yielded to it', (tester) async {
      // The bug removed the *host's* entry when the old slide ended, which ran
      // the full teardown — including releasing the inset. The page would snap
      // back over a pane that is still there.
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          width: 380,
          avoidRect: _coveredRect,
          builder: (_) => demoPane(title: 'DEV-A'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final claimed = SidePaneHost.occupiedWidth.value;
      expect(claimed, greaterThan(0),
          reason: 'the device is covered, so the page yields the strip');

      await tester.tap(find.text('open')); // toggle A shut — animated
      await tester.pump(_midSlide);

      showSidePane(
        context: tester.element(find.text('open')),
        id: 'b',
        width: 380,
        avoidRect: _coveredRect,
        builder: (_) => demoPane(title: 'DEV-B'),
      );
      await tester.pump();
      await tester.pump(_afterSlide);

      expect(find.text('DEV-B'), findsOneWidget);
      expect(SidePaneHost.occupiedWidth.value, claimed,
          reason: "A's slide-out ending must not release the strip B is "
              'standing in — the page would slide back under an open pane');
    });

    testWidgets('survives a chain more than one deep', (tester) async {
      // A closing while B opens, B closing while C opens. Each close captures
      // its own entry, so none of them may reach for a successor's.
      final closed = <String>[];
      var nextId = 'a';
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: nextId,
          onClosed: () => closed.add(nextId),
          builder: (_) => demoPane(title: 'DEV-${nextId.toUpperCase()}'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final context = tester.element(find.text('open'));
      for (final id in ['b', 'c']) {
        closeSidePane();
        await tester.pump(_midSlide);
        showSidePane(
          context: context,
          id: id,
          onClosed: () => closed.add(id),
          builder: (_) => demoPane(title: 'DEV-${id.toUpperCase()}'),
        );
        await tester.pump();
      }
      await tester.pump(_afterSlide);

      expect(find.byType(SidePane), findsOneWidget,
          reason: 'exactly one shell survives the chain');
      expect(find.text('DEV-C'), findsOneWidget, reason: 'and it is the last');
      expect(SidePaneHost.openId, 'c');
      // Not order: B is closed a pump after it opened, so its slide-out has
      // almost nothing to reverse and finishes before A's. What matters is
      // that both departing panes are told, once each, and the survivor is
      // not told at all.
      expect(closed..sort(), ['a', 'b'],
          reason: 'each departing pane fires its own callback exactly once');
      expect(closed, isNot(contains('c')),
          reason: 'C is still open — its callback is not A\'s or B\'s to fire');
    });

    testWidgets('fires the departing pane\'s onClosed only once it has left',
        (tester) async {
      var aClosed = 0;
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          onClosed: () => aClosed++,
          builder: (_) => demoPane(title: 'DEV-A'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pump(_midSlide);
      expect(aClosed, 0,
          reason: 'the pane is still on screen — it has not closed yet');

      showSidePane(
        context: tester.element(find.text('open')),
        id: 'b',
        builder: (_) => demoPane(title: 'DEV-B'),
      );
      await tester.pump();
      expect(aClosed, 0, reason: 'opening B does not close A early');

      await tester.pump(_afterSlide);
      expect(aClosed, 1, reason: 'once A is actually gone, exactly once');
    });
  });

  group('a pane whose overlay is torn down mid-slide', () {
    testWidgets('still tells its owner it closed', (tester) async {
      // The page editor's onClosed flushes the config edits made in the pane
      // being left into the undo history. Losing the callback silently drops
      // them, so it has to survive a route change landing inside the 220 ms.
      var aClosed = 0;
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          onClosed: () => aClosed++,
          builder: (_) => demoPane(title: 'DEV-A'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open')); // animated close
      await tester.pump(_midSlide);

      // The overlay goes away underneath the slide.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump(_afterSlide);

      expect(aClosed, 1,
          reason: 'a pane torn down mid-slide must not swallow its onClosed — '
              'the page editor flushes pending edits from it');
      expect(SidePaneHost.openId, isNull);
    });
  });
}
