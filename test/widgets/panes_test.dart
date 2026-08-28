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
import 'package:flutter/rendering.dart' show RenderParagraph;
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

    testWidgets('the header close button dismisses it', (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
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

    testWidgets(
        'a pane opened while the previous one is still sliding out survives it',
        (tester) async {
      // Toggle A shut (animated), and before the 220 ms slide-out has ended
      // open B. The host used to remove "the" entry when A's slide finished --
      // by then B's -- so B vanished and A's shell stayed mounted for good,
      // invisible, rebuilding a builder whose asset had been disposed.
      var buildsOfA = 0;
      var aClosed = 0;
      var bClosed = 0;
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          onClosed: () => aClosed++,
          builder: (_) {
            buildsOfA++;
            return demoPane(title: 'DEV-A');
          },
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('DEV-A'), findsOneWidget);

      await tester.tap(find.text('open')); // toggle A shut -- animated
      await tester.pump(const Duration(milliseconds: 50));
      expect(isSidePaneOpen(), isFalse);

      final context = tester.element(find.text('open'));
      showSidePane(
        context: context,
        id: 'b',
        onClosed: () => bClosed++,
        builder: (_) => demoPane(title: 'DEV-B'),
      );
      await tester.pumpAndSettle();

      expect(isSidePaneOpen(id: 'b'), isTrue, reason: 'B is the open pane');
      expect(find.text('DEV-B'), findsOneWidget,
          reason: "A's slide-out finishing must not take B down");
      expect(find.text('DEV-A'), findsNothing,
          reason: "A's shell is gone, not lingering off-screen");
      expect(find.byType(SidePane), findsOneWidget);
      expect(aClosed, 1, reason: 'A got its own onClosed, once');
      expect(bClosed, 0, reason: "B's onClosed is not A's to fire");

      final builds = buildsOfA;
      await tester.pump(const Duration(seconds: 1));
      expect(buildsOfA, builds, reason: "A's builder is never run again");

      closeSidePane();
      await tester.pumpAndSettle();
      expect(bClosed, 1);
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

  group('SidePane — the content inset', () {
    // What [SidePaneInset] consumers (the plant view, the page editor's
    // canvas) lean on: the host publishes the settled strip the pane claims
    // from the screen's right edge — but only when the device that opened the
    // pane (its avoidRect, defaulting to the opener's own box) would
    // otherwise end up underneath it. A pane opened for something in plain
    // view must not move the page at all.

    /// At the test surface's 800 width, a 380-wide pane's strip starts at
    /// 800 - 380 - 2*margin = 396. This rect reaches under it.
    const coveredRect = Rect.fromLTWH(700, 100, 60, 60);

    testWidgets('a pane opened for a device in plain view claims no strip',
        (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          width: 380,
          builder: (_) => demoPane(),
        ),
      ));
      // The 'open' button sits against the left edge, and its box is the
      // default avoidRect — nowhere near the pane.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsOneWidget);
      expect(SidePaneHost.occupiedWidth.value, 0,
          reason: 'nothing the operator tapped is covered — the page must '
              'not move');

      closeSidePane();
      await tester.pumpAndSettle();
    });

    testWidgets('occupiedWidth claims the strip for a covered device, '
        'follows resize and releases on close', (tester) async {
      expect(SidePaneHost.occupiedWidth.value, 0);

      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          width: 380,
          resizable: true,
          avoidRect: coveredRect,
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
          SidePaneHost.occupiedWidth.value, 380 + 2 * SidePaneDefaults.margin);

      // The drag handle moves the pane's left edge; the claim follows.
      final pane = tester.getRect(find.byType(SidePane));
      final gesture =
          await tester.startGesture(Offset(pane.left + 5, pane.center.dy));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          SidePaneHost.occupiedWidth.value, 460 + 2 * SidePaneDefaults.margin);

      closeSidePane();
      await tester.pumpAndSettle();
      expect(SidePaneHost.occupiedWidth.value, 0);
    });

    testWidgets('widening the pane over the device claims the strip then',
        (tester) async {
      // right = 360 clears the 380-wide pane's strip (starts at 396) but not
      // a 460-wide one (starts at 316).
      const nearRect = Rect.fromLTWH(300, 100, 60, 60);
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          width: 380,
          resizable: true,
          avoidRect: nearRect,
          builder: (_) => demoPane(),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(SidePaneHost.occupiedWidth.value, 0);

      final pane = tester.getRect(find.byType(SidePane));
      final gesture =
          await tester.startGesture(Offset(pane.left + 5, pane.center.dy));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          SidePaneHost.occupiedWidth.value, 460 + 2 * SidePaneDefaults.margin,
          reason: 'the wider pane now covers the device — the page yields');

      closeSidePane();
      await tester.pumpAndSettle();
    });

    testWidgets('a claimed strip rides across a swap to another pane',
        (tester) async {
      var next = 0;
      await tester.pumpWidget(host(
        onOpen: (context) {
          next++;
          showSidePane(
            context: context,
            id: 'device-$next',
            width: 380,
            // The first device is covered; the second is in plain view.
            avoidRect: next == 1 ? coveredRect : const Rect.fromLTWH(60, 100, 60, 60),
            builder: (_) => demoPane(title: 'DEV-$next'),
          );
        },
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
          SidePaneHost.occupiedWidth.value, 380 + 2 * SidePaneDefaults.margin);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
          SidePaneHost.occupiedWidth.value, 380 + 2 * SidePaneDefaults.margin,
          reason: 'once yielded, the strip stays yielded for the life of the '
              'pane — swapping devices must not bounce the page in and out');

      closeSidePane();
      await tester.pumpAndSettle();
      expect(SidePaneHost.occupiedWidth.value, 0);
    });

    testWidgets(
        'SidePaneInset yields the strip in one layout pass, glides the '
        'appearance, and takes the strip back', (tester) async {
      const contentKey = Key('inset-content');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(
                child: SidePaneInset(
                  child: SizedBox.expand(
                    child: ColoredBox(key: contentKey, color: Colors.black12),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => showSidePane(
                      context: context,
                      id: 'a',
                      width: 380,
                      avoidRect: coveredRect,
                      builder: (_) => demoPane(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      final full = tester.getSize(find.byKey(contentKey)).width;
      final insetWidth = full - 380 - 2 * SidePaneDefaults.margin;

      await tester.tap(find.text('open'));
      // Frame 1 mounts the shell and publishes the claim at frame's end;
      // frame 2 starts the glide.
      await tester.pump();
      await tester.pump();
      expect(tester.getSize(find.byKey(contentKey)).width, insetWidth,
          reason: 'the pad lands in a single layout pass — re-laying the '
              'page out per animation frame is what made the glide stutter');
      // ...while the APPEARANCE (layout × paint transform) glides from the
      // full width down to the inset one alongside the pane's slide.
      await tester.pump(const Duration(milliseconds: 110));
      final midway = tester.getRect(find.byKey(contentKey)).width;
      expect(midway, greaterThan(insetWidth));
      expect(midway, lessThan(full));

      await tester.pumpAndSettle();
      final inset = tester.getRect(find.byKey(contentKey));
      expect(inset.width, insetWidth);
      expect(inset.right, lessThan(tester.getRect(find.byType(SidePane)).left),
          reason: 'the content ends with daylight before the pane begins');

      closeSidePane();
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(contentKey)).width, full,
          reason: 'the strip is a loan — content gets it back on close');
      expect(tester.getRect(find.byKey(contentKey)).width, full,
          reason: 'and the glide ends at identity — no transform left over');
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

  group('SidePane — route popups from pane content', () {
    /// The pane lives in the root overlay, ABOVE every route the app
    /// Navigator will ever push — `Overlay.rearrange` keeps foreign entries
    /// on top. Anything route-based opened from inside the pane (a
    /// `DropdownButton`'s menu, `showDialog`) must therefore not land on the
    /// app Navigator, or it opens invisibly BEHIND the pane.
    Widget dropdownPane(ValueChanged<String?> onChanged) {
      return SidePane(
        title: 'CN-04',
        child: DropdownButton<String>(
          value: 'A',
          items: const [
            DropdownMenuItem(value: 'A', child: Text('A')),
            DropdownMenuItem(value: 'B', child: Text('B')),
          ],
          onChanged: onChanged,
        ),
      );
    }

    testWidgets('a DropdownButton opens a usable menu above the pane',
        (tester) async {
      String? picked;
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => dropdownPane((v) => picked = v),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('B').hitTestable(), findsOneWidget,
          reason: 'the menu must open on top of the pane, not behind it');

      await tester.tap(find.text('B').hitTestable());
      await tester.pumpAndSettle();
      expect(picked, 'B');
    });

    testWidgets('tapping the dropdown again while its menu is open is safe',
        (tester) async {
      // The field bug: the menu opened behind the pane, so the button stayed
      // visible and the second tap tripped the framework's
      // `_dropdownRoute == null` assertion.
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => dropdownPane((_) {}),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>),
          warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SidePane), findsOneWidget);
    });

    testWidgets('Escape closes the open menu first, then the pane',
        (tester) async {
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => dropdownPane((_) {}),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('B').hitTestable(), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('B').hitTestable(), findsNothing,
          reason: 'the first Escape closes the menu on top');
      expect(find.byType(SidePane), findsOneWidget,
          reason: '...and leaves the pane alone');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SidePane), findsNothing);
    });

    testWidgets('a modal dialog opened from the pane blocks the pane',
        (tester) async {
      var resets = 0;
      await tester.pumpWidget(host(
        onOpen: (context) => showSidePane(
          context: context,
          id: 'a',
          builder: (_) => SidePane(
            title: 'CN-04',
            actions: [
              PaneAction.destructive(
                label: 'Fault reset',
                onPressed: () => resets++,
              ),
            ],
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showStandardDialog<void>(
                  context: context,
                  title: 'Acknowledge',
                  builder: (_) => const Text('dialog body'),
                ),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.text('dialog body'), findsOneWidget);

      await tester.tap(find.text('Fault reset'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(resets, 0,
          reason: 'the modal barrier must sit above the pane it came from');
      expect(find.text('dialog body'), findsNothing,
          reason: 'the tap landed on the dismissible barrier, not the pane');
      expect(find.byType(SidePane), findsOneWidget);
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

      // Both the pane and the dialog carry a header close button — scope to
      // the dialog's own header.
      await tester.tap(find.descendant(
        of: find.byType(StandardDialog),
        matching: find.byIcon(Icons.close),
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

    testWidgets('resizes by its corner grip', (tester) async {
      // The grip is the touch-sized, visible way to resize — 44px square in
      // the bottom-right corner, where the invisible 6px frame edges are
      // unusable with a finger.
      await tester.pumpWidget(host(
        onOpen: (context) => showFloatingDialog(
          context: context,
          id: 'trend',
          title: 'Trend',
          size: const Size(400, 300),
          position: const Offset(100, 100),
          builder: (_) => const Text('chart'),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(StandardDialog)), const Size(400, 300));

      final grip = find.byType(CustomPaint).last;
      await tester.drag(grip, const Offset(90, 50));
      await tester.pumpAndSettle();
      final grown = tester.getSize(find.byType(StandardDialog));
      expect(grown.width, closeTo(490, 2));
      expect(grown.height, closeTo(350, 2));

      await tester.drag(find.byType(CustomPaint).last, const Offset(-60, -30));
      await tester.pumpAndSettle();
      final shrunk = tester.getSize(find.byType(StandardDialog));
      expect(shrunk.width, closeTo(430, 2));
      expect(shrunk.height, closeTo(320, 2));
    });

    testWidgets('moving and resizing does not rebuild the content',
        (tester) async {
      // These windows mostly hold charts, and a chart rebuilt mid-gesture
      // drops its subscriptions and re-runs its history query — the window an
      // operator is dragging aside flickers back to "loading" the whole way
      // across the screen. Geometry must repaint the frame only.
      var builds = 0;
      await tester.pumpWidget(host(
        onOpen: (context) => showFloatingDialog(
          context: context,
          id: 'trend',
          title: 'Trend',
          size: const Size(400, 300),
          position: const Offset(120, 120),
          builder: (_) => Builder(builder: (_) {
            builds++;
            return const Text('chart');
          }),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(builds, 1);

      await tester.drag(find.byType(PaneHeader), const Offset(-60, 40));
      await tester.pumpAndSettle();
      expect(builds, 1, reason: 'dragging the window rebuilt the chart');

      // Moved, not just repainted — otherwise this test would pass on a
      // dialog that ignored every gesture.
      expect(tester.getTopLeft(find.byType(StandardDialog)),
          const Offset(60, 160));

      final beforeEdge = tester.getSize(find.byType(StandardDialog));
      await tester.dragFrom(
        tester.getRect(find.byType(StandardDialog)).bottomRight -
            const Offset(2, 2),
        const Offset(80, 40),
      );
      await tester.pumpAndSettle();
      expect(builds, 1, reason: 'resizing by the edge rebuilt the chart');
      final afterEdge = tester.getSize(find.byType(StandardDialog));
      expect(afterEdge.width, greaterThan(beforeEdge.width));

      await tester.drag(find.byType(CustomPaint).last, const Offset(40, 20));
      await tester.pumpAndSettle();
      expect(builds, 1, reason: 'resizing by the grip rebuilt the chart');
      expect(tester.getSize(find.byType(StandardDialog)).width,
          greaterThan(afterEdge.width));
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
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(answer, isNull);
    });
  });

  group('PaneHeader — identity stays legible', () {
    /// A pane at its default width, as a station panel shows it.
    Future<void> pumpHeader(
      WidgetTester tester, {
      required String title,
      String? subtitle,
      PaneStatus? status,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: SidePaneDefaults.width,
              child: PaneHeader(
                title: title,
                subtitle: subtitle,
                icon: Icons.conveyor_belt,
                status: status,
                onClose: () {},
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('a long key beside a long status is not ellipsised',
        (tester) async {
      // The pair that came out as `CVS02.CN0…` when the chip shared the
      // title row: a full PLC key and the widest standard status.
      const title = 'CVS02.CN01.FD01';
      await pumpHeader(
        tester,
        title: title,
        subtitle: 'Conveyor',
        status: const PaneStatus.unknown('Connecting'),
      );

      final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
      expect(paragraph.didExceedMaxLines, isFalse,
          reason: 'the identity is what the operator opened the pane for');
    });

    testWidgets('the status chip sits under the title, level with the subtitle',
        (tester) async {
      await pumpHeader(
        tester,
        title: 'CVS02.CN01.FD01',
        subtitle: 'Conveyor',
        status: const PaneStatus.stopped(),
      );

      final title = tester.getRect(find.text('CVS02.CN01.FD01'));
      final subtitle = tester.getRect(find.text('Conveyor'));
      final chip = tester.getRect(find.byType(PaneStatusChip));
      final close = tester.getRect(find.byIcon(Icons.close));

      // Second line: below the title, beside the subtitle, clear of the
      // close button's column.
      expect(chip.top, greaterThanOrEqualTo(title.bottom));
      expect(chip.left, greaterThan(subtitle.right));
      expect(chip.right, lessThanOrEqualTo(close.left));
      // Subtitle and chip are one row: their vertical centres coincide.
      expect(chip.center.dy, closeTo(subtitle.center.dy, 1));
    });

    testWidgets('no subtitle still puts the chip on its own line',
        (tester) async {
      await pumpHeader(
        tester,
        title: 'DI-3725-A',
        status: const PaneStatus.warning('2 forced'),
      );
      final title = tester.getRect(find.text('DI-3725-A'));
      final chip = tester.getRect(find.byType(PaneStatusChip));
      expect(chip.top, greaterThanOrEqualTo(title.bottom));
    });
  });

  group('PaneExplainRow — label and value', () {
    Future<void> pumpRow(
      WidgetTester tester, {
      required String label,
      required String value,
      double width = 348,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PaneExplainRow(
                label: label,
                value: value,
                explanationBuilder: (_) => const Text('why'),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('share one line while both fit', (tester) async {
      await pumpRow(tester, label: 'LFT', value: 'NOF');
      final label = tester.getRect(find.text('LFT'));
      final value = tester.getRect(find.text('NOF'));
      expect(value.center.dy, closeTo(label.center.dy, 1));
      expect(value.left, greaterThan(label.right));
    });

    testWidgets('stack the value under the label when they do not',
        (tester) async {
      const label = 'Last fault (LFT)';
      const value = 'CNF · Fieldbus communication lost';
      await pumpRow(tester, label: label, value: value);

      final labelRect = tester.getRect(find.text(label));
      final valueRect = tester.getRect(find.text(value));
      expect(valueRect.top, greaterThanOrEqualTo(labelRect.bottom),
          reason: 'a long row stacks instead of squeezing the value');
      for (final t in [label, value]) {
        expect(
            tester
                .renderObject<RenderParagraph>(find.text(t))
                .didExceedMaxLines,
            isFalse);
      }
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

  group('PaneBody section order', () {
    /// The pane body's whole job: an operator who has learned one pane has
    /// learned them all, so the four standard sections always land in the
    /// same places no matter what order a pane author wrote them in.
    Future<List<String>> headings(
      WidgetTester tester,
      List<PaneBodySection?> sections,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PaneBody(sections: sections)),
      ));
      // PaneSection upper-cases its heading, and the bodies below are plain
      // text, so the headings are exactly the shouted strings on screen.
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t == t.toUpperCase() && t.isNotEmpty)
          .toList();
    }

    testWidgets('sorts scrambled sections into the house order',
        (tester) async {
      expect(
        await headings(tester, const [
          PaneBodySection.setpoints(child: Text('sp')),
          PaneBodySection.manual(child: Text('man')),
          PaneBodySection.trend(child: Text('tr')),
          PaneBodySection.status(child: Text('st')),
        ]),
        ['STATUS', 'TREND', 'MANUAL', 'SETPOINTS'],
      );
    });

    testWidgets('details sections come last, in the order given',
        (tester) async {
      expect(
        await headings(tester, const [
          PaneBodySection.details(title: 'Notes', child: Text('n')),
          PaneBodySection.details(title: 'Channels', child: Text('c')),
          PaneBodySection.status(child: Text('st')),
        ]),
        ['STATUS', 'NOTES', 'CHANNELS'],
      );
    });

    testWidgets('a device may rename a slot without moving it', (tester) async {
      expect(
        await headings(tester, const [
          PaneBodySection.manual(title: 'Force', child: Text('f')),
          PaneBodySection.status(title: 'Signal', child: Text('s')),
        ]),
        ['SIGNAL', 'FORCE'],
      );
    });

    testWidgets('null entries drop out, and dividers only sit between',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PaneBody(sections: [
            PaneBodySection.status(child: Text('st')),
            null,
            PaneBodySection.trend(child: Text('tr')),
          ]),
        ),
      ));
      expect(find.byType(PaneSection), findsNWidgets(2));
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('a single section gets no divider', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PaneBody(sections: [
            PaneBodySection.status(child: Text('st')),
          ]),
        ),
      ));
      expect(find.byType(Divider), findsNothing);
    });
  });
}
