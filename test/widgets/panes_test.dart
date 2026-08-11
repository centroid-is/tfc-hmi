/// Behaviour tests for the standard popup primitives:
/// `SidePane` (docked, non-modal) and `StandardDialog` (modal + floating).
///
/// The contracts locked here are the ones equipment popups rely on:
///  * one pane at a time, re-opening the same id toggles it shut;
///  * the pane is NON-modal — the page behind stays hit-testable;
///  * Escape peels floating dialogs first, then the pane;
///  * a pane/dialog whose overlay is torn down does not strand the registry.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/panes/pane_chrome.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc/widgets/panes/standard_dialog.dart';

void main() {
  tearDown(() {
    closeSidePane();
    for (final id in FloatingDialogs.openIds) {
      closeFloatingDialog(id);
    }
  });

  /// A page with a tappable background, so tests can prove the pane does not
  /// block the plant view behind it.
  Widget host({
    required void Function(BuildContext context) onOpen,
    VoidCallback? onBackgroundTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onBackgroundTap,
                child: const ColoredBox(color: Colors.black12),
              ),
            ),
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

  SidePane demoPane(
      {String title = 'CN-04', List<PaneAction> actions = const []}) {
    return SidePane(
      title: title,
      subtitle: 'Conveyor',
      icon: Icons.conveyor_belt,
      status: const PaneStatus.running(),
      actions: actions,
      child: const PaneSection(
        title: 'Status',
        child: PaneDetailRow(label: 'Frequency', value: '48.20 Hz'),
      ),
    );
  }

  group('SidePane — open / close', () {
    testWidgets('opens docked against the right edge', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SidePane), findsOneWidget);
      expect(find.text('CN-04'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);

      final screen = tester.getSize(find.byType(MaterialApp));
      final paneRect = tester.getRect(find.byType(SidePane));
      expect(paneRect.right, lessThanOrEqualTo(screen.width));
      expect(paneRect.right, greaterThan(screen.width - 40),
          reason: 'the pane docks against the right edge');
      expect(paneRect.left, greaterThan(screen.width / 2),
          reason: 'the pane occupies only the right-hand strip');
    });

    testWidgets('Close in the pinned footer dismisses it', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing);
      expect(isSidePaneOpen(), isFalse);
    });

    testWidgets('re-showing the same id toggles it shut', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(isSidePaneOpen(id: 'a'), isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(isSidePaneOpen(), isFalse,
          reason: 'tapping the same device twice closes its pane');
    });

    testWidgets('showing another id replaces the open pane', (tester) async {
      var next = 0;
      await tester.pumpWidget(host(
        onOpen: (context) {
          next++;
          showSidePane(
            context: context,
            id: 'device-$next',
            builder: (_) => demoPane(title: 'DEV-$next'),
          );
        },
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('DEV-1'), findsOneWidget);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsOneWidget,
          reason: 'only ever one pane at a time');
      expect(find.text('DEV-2'), findsOneWidget);
      expect(find.text('DEV-1'), findsNothing);
    });

    testWidgets('closeSidePane(id:) only closes that pane', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      closeSidePane(id: 'someone-else');
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsOneWidget,
          reason: 'another asset must not be able to close this pane');

      closeSidePane(id: 'a');
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing);
    });

    testWidgets('tearing the overlay down releases the registry',
        (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(isSidePaneOpen(), isTrue);

      // A bare root: no MaterialApp, so the Navigator/Overlay holding the
      // pane is really destroyed rather than reconciled.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(isSidePaneOpen(), isFalse,
          reason: 'a pane that vanished with its overlay must not stay '
              '"open" and block the next one');
    });
  });

  group('SidePane — non-modal', () {
    testWidgets('the page behind stays interactive', (tester) async {
      var backgroundTaps = 0;
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
        onBackgroundTap: () => backgroundTaps++,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsOneWidget);

      // Tap the plant view on the left — behind a modal barrier this would
      // be swallowed. That difference is the whole point of the side pane.
      // (Avoid the vertical centre: the 'open' button lives there.)
      await tester.tapAt(const Offset(60, 80));
      await tester.pumpAndSettle();
      expect(backgroundTaps, 1);
      expect(find.byType(SidePane), findsOneWidget,
          reason: 'tapping outside must not dismiss a non-modal pane');
    });
  });

  group('SidePane — actions', () {
    testWidgets('footer actions fire and sit next to Close', (tester) async {
      var resets = 0;
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(actions: [
            PaneAction.destructive(
              label: 'Fault reset',
              onPressed: () => resets++,
            ),
            const PaneAction(label: 'Not available'),
          ]),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fault reset'));
      await tester.pumpAndSettle();
      expect(resets, 1);

      // A null onPressed is how a pane says "command exists, not available".
      final disabled = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Not available'),
      );
      expect(disabled.onPressed, isNull);
    });
  });

  group('Escape', () {
    testWidgets('closes the pane', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing);
    });

    testWidgets('peels floating dialogs before the pane', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => SidePane(
            title: 'CN-04',
            child: PaneExpandTile(
              label: 'Channel detail',
              expandedBuilder: (_) => const Text('the big grid'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel detail'));
      await tester.pumpAndSettle();
      expect(find.text('the big grid'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('the big grid'), findsNothing,
          reason: 'the first Escape closes the dialog on top');
      expect(find.byType(SidePane), findsOneWidget,
          reason: '...and leaves the pane underneath alone');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing);
    });
  });

  group('Floating StandardDialog', () {
    testWidgets('PaneExpandTile opens it, Close dismisses it', (tester) async {
      var backgroundTaps = 0;
      await tester.pumpWidget(host(
        onBackgroundTap: () => backgroundTaps++,
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => SidePane(
            title: 'DI-3725',
            child: PaneExpandTile(
              label: 'Channel detail',
              summary: 'all 16',
              // Small on purpose: leaves plant view uncovered to tap.
              expandedSize: const Size(300, 200),
              expandedBuilder: (_) => const Text('the big grid'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channel detail'));
      await tester.pumpAndSettle();

      expect(find.byType(StandardDialog), findsOneWidget);
      expect(find.text('the big grid'), findsOneWidget);
      // No barrier — the pane and the plant view behind both stay live, so
      // the operator can keep working with the chart parked on screen.
      expect(find.byType(SidePane), findsOneWidget);
      await tester.tapAt(const Offset(60, 80));
      await tester.pumpAndSettle();
      expect(backgroundTaps, 1);

      // Both the pane and the dialog carry a pinned Close — scope to the
      // dialog's own footer.
      await tester.tap(find.descendant(
        of: find.byType(StandardDialog),
        matching: find.widgetWithText(TextButton, 'Close'),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(StandardDialog), findsNothing);
      expect(find.byType(SidePane), findsOneWidget,
          reason: 'closing the chart leaves the pane behind it open');
    });

    testWidgets('is draggable by its header', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showFloatingDialog(
          context: context,
          id: 'trend',
          title: 'Trend',
          builder: (_) => const Text('chart'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Stay inside the window: the shell clamps so a dialog can never be
      // dragged off-screen where it could not be grabbed again.
      final before = tester.getTopLeft(find.byType(StandardDialog));
      await tester.drag(find.byType(PaneHeader), const Offset(-60, 40));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.byType(StandardDialog));

      expect(after.dx, closeTo(before.dx - 60, 1));
      expect(after.dy, closeTo(before.dy + 40, 1));
    });

    testWidgets('is resizable by its edges and corners', (tester) async {
      // Floating dialogs are windows: charts and grids get resized to suit
      // the screen, and the size has to survive being dragged smaller as
      // well as larger.
      await tester.pumpWidget(host(
        onOpen: (context) => showFloatingDialog(
          context: context,
          id: 'trend',
          title: 'Trend',
          size: const Size(400, 300),
          position: const Offset(120, 120),
          builder: (_) => const Text('chart'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final before = tester.getSize(find.byType(StandardDialog));
      expect(before, const Size(400, 300));

      // Drag the bottom-right corner out.
      final rect = tester.getRect(find.byType(StandardDialog));
      await tester.dragFrom(
        rect.bottomRight - const Offset(2, 2),
        const Offset(120, 60),
      );
      await tester.pumpAndSettle();
      final grown = tester.getSize(find.byType(StandardDialog));
      expect(grown.width, closeTo(520, 2));
      expect(grown.height, closeTo(360, 2));

      // And back in.
      await tester.dragFrom(
        tester.getRect(find.byType(StandardDialog)).bottomRight -
            const Offset(2, 2),
        const Offset(-100, -40),
      );
      await tester.pumpAndSettle();
      final shrunk = tester.getSize(find.byType(StandardDialog));
      expect(shrunk.width, closeTo(420, 2));
      expect(shrunk.height, closeTo(320, 2));
    });

    testWidgets('the same id does not open twice', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showFloatingDialog(
          context: context,
          id: 'trend',
          title: 'Trend',
          builder: (_) => const Text('chart'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(StandardDialog), findsOneWidget);
      expect(FloatingDialogs.openIds, ['trend']);
    });

    testWidgets('two different ids stack, cascaded', (tester) async {
      var next = 0;
      await tester.pumpWidget(host(
        onOpen: (context) {
          next++;
          showFloatingDialog(
            context: context,
            id: 'trend-$next',
            title: 'Trend $next',
            builder: (_) => Text('chart $next'),
          );
        },
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(StandardDialog), findsNWidgets(2));
      expect(FloatingDialogs.openIds, ['trend-1', 'trend-2']);
      final first = tester.getTopLeft(find.byType(StandardDialog).first);
      final second = tester.getTopLeft(find.byType(StandardDialog).last);
      expect(second.dx, greaterThan(first.dx),
          reason: 'the second window cascades so both remain grabbable');
    });
  });

  group('Modal StandardDialog', () {
    testWidgets('returns the value an action pops with', (tester) async {
      bool? answer;
      await tester.pumpWidget(host(
        onOpen: (context) async {
          answer = await showStandardDialog<bool>(
            context: context,
            title: 'Reset run hours',
            builder: (_) => const Text('Run hours will be set to zero.'),
            actionsBuilder: (ctx) => [
              PaneAction.destructive(
                label: 'Reset',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          );
        },
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(StandardDialog), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
      expect(find.byType(StandardDialog), findsNothing);
    });

    testWidgets('blocks the page behind it', (tester) async {
      // The modal variant DOES block the page behind it — that is the whole
      // reason to pick it over a pane.
      var backgroundTaps = 0;
      await tester.pumpWidget(host(
        onBackgroundTap: () => backgroundTaps++,
        onOpen: (context) => showStandardDialog<void>(
          context: context,
          title: 'Acknowledge',
          barrierDismissible: false,
          builder: (_) => const Text('body'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(60, 80));
      await tester.pumpAndSettle();
      expect(backgroundTaps, 0);
      expect(find.byType(StandardDialog), findsOneWidget);
    });

    testWidgets('Close pops with null', (tester) async {
      Object? answer = 'untouched';
      await tester.pumpWidget(host(
        onOpen: (context) async {
          answer = await showStandardDialog<bool>(
            context: context,
            title: 'Details',
            builder: (_) => const Text('body'),
          );
        },
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(answer, isNull);
    });
  });

  group('PaneStatus', () {
    testWidgets('chip renders the label for each standard state',
        (tester) async {
      const statuses = [
        PaneStatus.running(),
        PaneStatus.stopped(),
        PaneStatus.fault(),
        PaneStatus.warning(),
        PaneStatus.stale(),
        PaneStatus.unknown(),
      ];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final s in statuses) PaneStatusChip(status: s),
            ],
          ),
        ),
      ));

      for (final s in statuses) {
        expect(find.text(s.label), findsOneWidget);
      }
    });
  });
}
