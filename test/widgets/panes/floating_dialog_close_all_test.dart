/// Contract for `FloatingDialogs.closeAll()` and its `closeAllFloatingDialogs()`
/// wrapper, covering the behaviours f8ef2c4 introduced and never tested.
///
/// A floating dialog lives in the ROOT overlay, so leaving a page does not
/// remove it — a trend opened on Home followed the operator to Advanced and
/// stacked under the next two. f8ef2c4 calls `closeAllFloatingDialogs()` from
/// the three places the side pane already closes from: the router listener,
/// the back button and the navigation bar. What those three callers rely on:
///
///   - EVERY dialog goes, not just the top one, and the count comes back so a
///     caller can tell whether it did anything.
///   - each dialog's `onClosed` still fires — that is where a chart drops its
///     history subscription, so skipping it leaks the stream.
///   - `closeAll` iterates a COPY of `_stack`. `close()` mutates `_stack`, and
///     an `onClosed` may close a sibling on its way out; walking the live list
///     skips dialogs or throws mid-navigation.
///   - removal is SYNCHRONOUS. The commit's own comment leans on this ("safe
///     from a dispose() in the same frame"); the back button closes and beams
///     in one callback, so anything deferred to a later frame runs after the
///     page it belonged to is gone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/panes/standard_dialog.dart';

void main() {
  /// Pumps an app and hands back a context that lives under the Navigator's
  /// overlay, which is what `showFloatingDialog` inserts into.
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

  /// Opens a floating dialog whose body is findable by its id.
  void open(BuildContext ctx, String id, {VoidCallback? onClosed}) {
    showFloatingDialog(
      context: ctx,
      id: id,
      title: id,
      builder: (_) => Text('body $id'),
      onClosed: onClosed,
    );
  }

  tearDown(() {
    // Static registry state leaks between tests otherwise.
    for (final id in FloatingDialogs.openIds) {
      closeFloatingDialog(id);
    }
  });

  testWidgets('closes every open dialog and returns how many', (t) async {
    final ctx = await pumpHost(t);
    open(ctx, 'a');
    open(ctx, 'b');
    open(ctx, 'c');
    await t.pumpAndSettle();
    expect(FloatingDialogs.openIds, ['a', 'b', 'c']);
    expect(find.byType(StandardDialog), findsNWidgets(3));

    final closed = closeAllFloatingDialogs();
    await t.pumpAndSettle();

    expect(closed, 3,
        reason: 'the count is the caller\'s only signal that navigation had '
            'dialogs to clear');
    expect(FloatingDialogs.openIds, isEmpty);
    expect(find.byType(StandardDialog), findsNothing,
        reason: 'closeTop() would have left the two underneath on screen, '
            'which is the stacking bug f8ef2c4 set out to fix');
  });

  testWidgets('fires every dialog\'s onClosed exactly once', (t) async {
    final ctx = await pumpHost(t);
    final closedIds = <String>[];
    open(ctx, 'a', onClosed: () => closedIds.add('a'));
    open(ctx, 'b', onClosed: () => closedIds.add('b'));
    open(ctx, 'c', onClosed: () => closedIds.add('c'));
    await t.pumpAndSettle();

    closeAllFloatingDialogs();
    await t.pumpAndSettle();

    expect(closedIds, ['a', 'b', 'c'],
        reason: 'a trend dialog cancels its history subscription in onClosed; '
            'dropping the callback leaks the stream on every navigation');
  });

  testWidgets('returns 0 and does not throw when nothing is open', (t) async {
    await pumpHost(t);
    expect(FloatingDialogs.isEmpty, isTrue);

    // The router listener fires on EVERY route change, so the empty case is
    // the common one, not an edge case.
    expect(closeAllFloatingDialogs(), 0);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('an onClosed that closes a sibling skips nothing', (t) async {
    // The subtle one. `close()` removes from `_stack` as it goes, and here
    // 'b' removes 'c' on its way out too — so by the time the loop reaches
    // 'c' the live list has shifted twice under it. Walking `_stack` directly
    // either skips a dialog or throws ConcurrentModificationError; walking a
    // copy is what makes the traversal total.
    final ctx = await pumpHost(t);
    final closedIds = <String>[];
    open(ctx, 'a', onClosed: () => closedIds.add('a'));
    open(ctx, 'b', onClosed: () {
      closedIds.add('b');
      closeFloatingDialog('c');
    });
    open(ctx, 'c', onClosed: () => closedIds.add('c'));
    await t.pumpAndSettle();
    expect(FloatingDialogs.openIds, ['a', 'b', 'c']);

    final closed = closeAllFloatingDialogs();
    await t.pumpAndSettle();

    expect(t.takeException(), isNull,
        reason: 'mutating `_stack` while iterating it throws');
    expect(closedIds, ['a', 'b', 'c'],
        reason: 'every dialog is closed once and only once — the snapshot is '
            'what stops the shifting list dropping one, and close() on an '
            'already-closed id is a no-op rather than a second onClosed');
    expect(FloatingDialogs.openIds, isEmpty);
    expect(find.byType(StandardDialog), findsNothing);
    expect(closed, 3, reason: 'the count is of the snapshot taken up front');
  });

  testWidgets('removal is synchronous, before the next frame', (t) async {
    final ctx = await pumpHost(t);
    open(ctx, 'a');
    open(ctx, 'b');
    await t.pumpAndSettle();

    closeAllFloatingDialogs();

    // NO pump. The back button closes and beams inside one callback, and the
    // commit's comment claims this is safe from a dispose() in the same
    // frame; that only holds if the registry and the overlay entries are
    // already gone the instant closeAll returns.
    expect(FloatingDialogs.isEmpty, isTrue,
        reason: 'deferring removal to a microtask or a post-frame callback '
            'leaves the dialogs registered while the page tears down');

    // A SINGLE pump. Anything scheduled for a later frame would still be on
    // screen here.
    await t.pump();
    expect(find.byType(StandardDialog), findsNothing);
  });

  testWidgets('safe to call from a dispose() in the same frame', (t) async {
    // The real caller shape: a page closes the dialogs as it goes away.
    // Removing an overlay entry marks the overlay dirty, and doing that
    // during a teardown is exactly what throws "markNeedsBuild() called
    // during build".
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _ClosesDialogsOnDispose(
          child: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          }),
        ),
      ),
    ));
    open(ctx, 'a');
    open(ctx, 'b');
    await t.pumpAndSettle();
    expect(find.byType(StandardDialog), findsNWidgets(2));

    // Replace the tree; the page's dispose() runs mid-teardown.
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('next'))));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull,
        reason: 'closing from dispose() must not mark the overlay dirty '
            'during the teardown build');
    expect(FloatingDialogs.openIds, isEmpty);
    expect(find.byType(StandardDialog), findsNothing);
  });
}

/// A page that clears the floating dialogs as it leaves, the way the back
/// button and the router listener do.
class _ClosesDialogsOnDispose extends StatefulWidget {
  final Widget child;

  const _ClosesDialogsOnDispose({required this.child});

  @override
  State<_ClosesDialogsOnDispose> createState() =>
      _ClosesDialogsOnDisposeState();
}

class _ClosesDialogsOnDisposeState extends State<_ClosesDialogsOnDispose> {
  @override
  void dispose() {
    closeAllFloatingDialogs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
