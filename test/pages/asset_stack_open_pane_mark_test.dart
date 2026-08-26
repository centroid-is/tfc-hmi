// The plant view marks the asset whose side pane is open.
//
// A pane is a strip against the right edge of a screen full of machinery. On
// a mimic with four identical conveyors in a row, the pane's header does not
// settle WHICH of them an operator is about to jog — so the asset the pane
// was opened from wears a thin ring for as long as the pane is up.
//
// Nothing about this is per-asset: an asset opens its pane from its own build
// context (it already has to, for `showSidePane`'s `avoidRect`), and the
// `SidePaneSubject` that `AssetStack` puts around every asset is what turns
// that context into "this pane is about that asset".
//
// Contract under test:
//   - a pane opened from inside an asset marks that asset, and only it;
//   - the mark follows a swap to another asset's pane;
//   - closing the pane takes the mark with it;
//   - a pane opened from outside any asset (the page editor's config pane,
//     the database stats pane) marks nothing;
//   - the mark never takes a tap meant for the asset underneath it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/widgets/panes/side_pane.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    // The host is static; a pane left open leaks into the next test.
    closeSidePane(immediate: true);
  });

  /// The ring, or nothing. `findsNothing` covers both "never marked" and
  /// "faded out": the mark stays in the tree at zero opacity once it has been
  /// used, so an opacity check is what says whether it is on screen.
  double markOpacity(WidgetTester tester) {
    final finder = find.byKey(openPaneMarkKey);
    if (finder.evaluate().isEmpty) return 0;
    // `.first` — the nearest one out. The route's own transition is a
    // FadeTransition too, and it is further up the same path.
    return tester
        .widget<FadeTransition>(
          find
              .ancestor(of: finder, matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
  }

  /// The centre of the ring on screen — which asset it is around.
  Offset markCentre(WidgetTester tester) =>
      tester.getRect(find.byKey(openPaneMarkKey)).center;

  testWidgets('a pane opened from an asset marks that asset', (tester) async {
    // Both well clear of the right edge: the pane docks over it, and a tap
    // meant for the second asset would land on the pane instead.
    final left = _PaneAsset('left', x: 0.15);
    final right = _PaneAsset('right', x: 0.35);
    await tester.pumpWidget(_wrap([left, right]));
    await tester.pumpAndSettle();

    expect(markOpacity(tester), 0, reason: 'nothing is open yet');

    await tester.tap(find.text('left'));
    await tester.pumpAndSettle();

    expect(isSidePaneOpen(id: 'pane:left'), isTrue);
    expect(markOpacity(tester), 1);
    expect(
      markCentre(tester).dx,
      closeTo(tester.getCenter(find.text('left')).dx, 1),
      reason: 'the ring belongs to the asset the pane was opened from',
    );

    // A second asset: the pane swaps, and so does the ring.
    await tester.tap(find.text('right'));
    await tester.pumpAndSettle();

    expect(markOpacity(tester), 1);
    expect(
      markCentre(tester).dx,
      closeTo(tester.getCenter(find.text('right')).dx, 1),
    );
    expect(find.byKey(openPaneMarkKey), findsOneWidget,
        reason: 'one pane is open, so exactly one asset is marked');
  });

  testWidgets('closing the pane clears the mark', (tester) async {
    await tester.pumpWidget(_wrap([_PaneAsset('one', x: 0.5)]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();
    expect(markOpacity(tester), 1);

    closeSidePane();
    await tester.pumpAndSettle();

    expect(isSidePaneOpen(), isFalse);
    expect(markOpacity(tester), 0);
  });

  testWidgets('a pane opened from outside an asset marks nothing',
      (tester) async {
    // What the page editor does: it opens its config pane from the page's own
    // context, not the asset's, and marks the asset itself with the editor's
    // selection border. Same for panes that are about no asset at all.
    late BuildContext pageContext;
    await tester.pumpWidget(_wrap(
      [_PaneAsset('one', x: 0.5)],
      onPageContext: (c) => pageContext = c,
    ));
    await tester.pumpAndSettle();

    showSidePane(
      context: pageContext,
      id: 'not-an-asset',
      builder: (_) => const Text('stats'),
    );
    await tester.pumpAndSettle();

    expect(isSidePaneOpen(id: 'not-an-asset'), isTrue);
    expect(markOpacity(tester), 0);
  });

  testWidgets('the mark does not swallow taps on its asset', (tester) async {
    // The ring is drawn over the asset it is around, and the plant view is
    // live underneath a pane: a start button that stopped taking taps the
    // moment its pane opened would be worse than no mark at all.
    final asset = _PaneAsset('one', x: 0.5);
    await tester.pumpWidget(_wrap([asset]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('one'));
    await tester.pumpAndSettle();
    expect(asset.taps, 1);
    expect(markOpacity(tester), 1);

    // Straight through the middle of the ring, into the asset.
    await tester.tapAt(markCentre(tester));
    await tester.pumpAndSettle();
    expect(asset.taps, 2);
  });
}

Widget _wrap(
  List<Asset> assets, {
  ValueChanged<BuildContext>? onPageContext,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
      body: Builder(builder: (context) {
        onPageContext?.call(context);
        return SizedBox(
          width: 800,
          height: 600,
          child: LayoutBuilder(
            builder: (context, constraints) => AssetStack(
              assets: assets,
              constraints: constraints,
              selectedAssets: const {},
              mirroringDisabled: true,
              // Runtime mode: assets take their own taps and open their own
              // panes, which is the only path the mark is about.
              absorb: false,
            ),
          ),
        );
      }),
      ),
    ),
  );
}

/// An asset that opens a pane from its own build context, the way every
/// pane-owning asset in the app does.
class _PaneAsset extends BaseAsset {
  final String name;
  int taps = 0;

  _PaneAsset(this.name, {required double x}) {
    coordinates = Coordinates(x: x, y: 0.5);
    size = const RelativeSize(width: 0.2, height: 0.2);
  }

  @override
  String get displayName => 'PaneAsset';

  @override
  String get category => 'Test';

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          taps++;
          showSidePane(
            context: context,
            id: 'pane:$name',
            builder: (_) => Text('pane $name'),
          );
        },
        child: ColoredBox(
          color: const Color(0xFF888888),
          child: Center(child: Text(name)),
        ),
      );

  @override
  Widget configure(BuildContext context) => const SizedBox.shrink();

  @override
  Map<String, dynamic> toJson() => {constAssetName: 'PaneAsset'};
}
