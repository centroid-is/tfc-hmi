import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

/// Contract for the docked pane's host, covering the three behaviours
/// 6f7cbee introduced and never tested:
///
///   - `closeSidePane(immediate: true)` drops the overlay entry in the SAME
///     frame. The normal path awaits the exit glide, so the pane stays
///     mounted and rebuilding against a state object whose dispose() has
///     already run — that is the "ChangeNotifier used after being disposed"
///     the commit set out to fix.
///   - showing a second pane while one is open SWAPS the contents instead of
///     tearing the sheet down, and still fires the outgoing pane's onClosed
///     (the page editor flushes config edits into the undo history there).
///   - a swapped-in pane gets ITS OWN `resizable` / `onWidthChanged`, not the
///     ones belonging to whichever pane happened to open first.
void main() {
  /// The resize handle the shell only builds when `resizable` is true.
  final resizeHandle = find.byWidgetPredicate(
    (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeLeftRight,
  );

  /// Pumps an app and hands back a context that lives under the Navigator's
  /// overlay, which is what `showSidePane` inserts into.
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        }),
      ),
    ));
    return ctx;
  }

  tearDown(() {
    // Static host state leaks between tests otherwise.
    closeSidePane(immediate: true);
  });

  testWidgets('immediate close drops the pane in the same frame', (t) async {
    final ctx = await pumpHost(t);
    showSidePane(
      context: ctx,
      id: 'a',
      builder: (_) => const Text('pane A'),
    );
    await t.pumpAndSettle();
    expect(find.text('pane A'), findsOneWidget);

    closeSidePane(immediate: true);
    // A SINGLE pump. The animated path would still have the pane on screen
    // here, rebuilding, for the length of the 220ms glide.
    await t.pump();
    expect(find.text('pane A'), findsNothing,
        reason: 'immediate close must not leave the entry mounted to animate');
    expect(isSidePaneOpen(), isFalse);
  });

  testWidgets('the animated close is still animated', (t) async {
    // Guards the test above from passing because close() became immediate
    // for everyone, which would reintroduce the glide-less exit everywhere.
    final ctx = await pumpHost(t);
    showSidePane(context: ctx, id: 'a', builder: (_) => const Text('pane A'));
    await t.pumpAndSettle();

    closeSidePane();
    await t.pump();
    expect(find.text('pane A'), findsOneWidget,
        reason: 'the default close glides out, so it is still mounted here');
    await t.pumpAndSettle();
    expect(find.text('pane A'), findsNothing);
  });

  testWidgets('swapping fires the outgoing pane onClosed exactly once',
      (t) async {
    final ctx = await pumpHost(t);
    var closedA = 0;
    showSidePane(
      context: ctx,
      id: 'a',
      builder: (_) => const Text('pane A'),
      onClosed: () => closedA++,
    );
    await t.pumpAndSettle();

    showSidePane(
      context: ctx,
      id: 'b',
      builder: (_) => const Text('pane B'),
    );
    await t.pumpAndSettle();

    expect(closedA, 1,
        reason: 'the page editor flushes config edits in onClosed; skip it '
            'and edits to the previous asset are silently dropped');
    expect(find.text('pane B'), findsOneWidget);
    expect(find.text('pane A'), findsNothing);
  });

  testWidgets('swapping to a resizable pane gives it a resize handle',
      (t) async {
    final ctx = await pumpHost(t);
    // An equipment pane: not resizable, no width persistence.
    showSidePane(context: ctx, id: 'a', builder: (_) => const Text('pane A'));
    await t.pumpAndSettle();
    expect(resizeHandle, findsNothing);

    // The page editor's asset-config pane is the one caller that is
    // resizable. Opening it over an equipment pane must not leave it stuck
    // with the equipment pane's chrome.
    showSidePane(
      context: ctx,
      id: 'b',
      builder: (_) => const Text('pane B'),
      resizable: true,
      onWidthChanged: (_) {},
    );
    await t.pumpAndSettle();

    expect(find.text('pane B'), findsOneWidget);
    expect(resizeHandle, findsOneWidget,
        reason: 'the swapped-in pane must get its own `resizable`, not the '
            'value the first pane happened to open with');
  });

  testWidgets('swapping away from a resizable pane removes the handle',
      (t) async {
    final ctx = await pumpHost(t);
    showSidePane(
      context: ctx,
      id: 'a',
      builder: (_) => const Text('pane A'),
      resizable: true,
      onWidthChanged: (_) {},
    );
    await t.pumpAndSettle();
    expect(resizeHandle, findsOneWidget);

    showSidePane(context: ctx, id: 'b', builder: (_) => const Text('pane B'));
    await t.pumpAndSettle();

    expect(resizeHandle, findsNothing,
        reason: 'a non-resizable pane must not inherit the previous pane\'s '
            'resize handle');
  });

  testWidgets('a swapped-in pane is laid out with ITS OWN insets', (t) async {
    // The insets keep the pane clear of the AppBar and NavigationBar. A pane
    // that asks for different chrome must get it, not the first pane's.
    final ctx = await pumpHost(t);
    showSidePane(
      context: ctx,
      id: 'a',
      builder: (_) => const Text('pane A'),
      insets: EdgeInsets.zero,
    );
    await t.pumpAndSettle();
    final topA = t.getTopLeft(find.text('pane A')).dy;

    showSidePane(
      context: ctx,
      id: 'b',
      builder: (_) => const Text('pane B'),
      insets: const EdgeInsets.only(top: 200),
    );
    await t.pumpAndSettle();
    final topB = t.getTopLeft(find.text('pane B')).dy;

    expect(topB - topA, closeTo(200, 1),
        reason: 'pane B asked to start 200px down; reading insets off the '
            'first pane\'s widget leaves it at pane A\'s offset');
  });

  testWidgets('a resized swapped-in pane reports to ITS OWN onWidthChanged',
      (t) async {
    final ctx = await pumpHost(t);
    final toA = <double>[];
    final toB = <double>[];

    showSidePane(
      context: ctx,
      id: 'a',
      builder: (_) => const Text('pane A'),
      resizable: true,
      onWidthChanged: toA.add,
    );
    await t.pumpAndSettle();

    showSidePane(
      context: ctx,
      id: 'b',
      builder: (_) => const Text('pane B'),
      resizable: true,
      onWidthChanged: toB.add,
    );
    await t.pumpAndSettle();

    await t.drag(resizeHandle, const Offset(-40, 0));
    await t.pumpAndSettle();

    expect(toB, isNotEmpty,
        reason: 'dragging pane B must call pane B\'s width callback');
    expect(toA, isEmpty,
        reason: 'the first pane\'s callback is still wired up, so dragging '
            'the SECOND pane drives the FIRST pane\'s state — for the page '
            'editor that is a setState on a pane it no longer owns');
  });
}
