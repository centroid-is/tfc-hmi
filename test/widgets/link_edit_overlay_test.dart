import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/ethercat_link.dart';
import 'package:tfc/page_creator/assets/link_edit_overlay.dart';
import 'package:tfc/page_creator/assets/link_anchors.dart';
import 'package:tfc/page_creator/assets/link_geometry.dart';

const Size _canvas = Size(800, 600);

class _Block extends BaseAsset {
  _Block({required double x, required double y, String? name}) {
    coordinates = Coordinates(x: x, y: y);
    size = const RelativeSize(width: 0.12, height: 0.1);
    text = name;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
  @override
  Widget configure(BuildContext context) => const SizedBox.shrink();
  @override
  Map<String, dynamic> toJson() => const {};
}

/// The overlay on its own canvas, which is all it needs — it takes the page as
/// a plain list rather than reaching for one.
Future<int> pumpOverlay(
  WidgetTester tester, {
  required EtherCatLinkConfig link,
  required List<Asset> assets,
}) async {
  var changes = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _canvas.width,
          height: _canvas.height,
          child: Stack(
            children: [
              LinkEditOverlay(
                link: link,
                assets: assets,
                canvas: _canvas,
                onBeginEdit: () {},
                onChanged: () => changes++,
              ),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return changes;
}

/// Canvas pixels → screen, for driving gestures.
Offset onCanvas(WidgetTester tester, Offset canvasPoint) {
  final origin = tester.getTopLeft(find.byType(LinkEditOverlay));
  return origin + canvasPoint;
}

void main() {
  late _Block a;
  late _Block b;
  late EtherCatLinkConfig link;
  late List<Asset> page;

  setUp(() {
    a = _Block(x: 0.15, y: 0.5, name: 'EK1100')..ensureId();
    b = _Block(x: 0.85, y: 0.5, name: 'EP2338')..ensureId();
    link = EtherCatLinkConfig(
      run: LinkRun(
        from: LinkEnd(assetId: a.id, port: 'X2'),
        to: LinkEnd(assetId: b.id, port: 'X1'),
      ),
    );
    page = [a, b, link];
  });

  Offset resolvedPoint(int index) =>
      link.run.resolve(_canvas, _anchorsFor(page)).points[index];

  testWidgets('a fresh run has no corners and two end handles', (tester) async {
    await pumpOverlay(tester, link: link, assets: page);
    // Two ends plus one ghost on the single segment.
    expect(link.run.waypoints, isEmpty);
    expect(find.byType(GestureDetector), findsWidgets);
  });

  testWidgets('dragging the ghost midpoint makes a corner', (tester) async {
    await pumpOverlay(tester, link: link, assets: page);
    final mid = (resolvedPoint(0) + resolvedPoint(1)) / 2;

    await tester.dragFrom(onCanvas(tester, mid), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(link.run.waypoints, hasLength(1),
        reason: 'the ghost should have become a real corner');
    // Dragged up, so it sits above the straight line between the ports.
    expect(resolvedPoint(1).dy, lessThan(mid.dy - 50));
  });

  testWidgets('a corner drags to a new place', (tester) async {
    link.run.waypoints.add(LinkWaypoint.onRun(0.5, 0.0));
    await pumpOverlay(tester, link: link, assets: page);
    final before = resolvedPoint(1);

    await tester.dragFrom(onCanvas(tester, before), const Offset(60, -90));
    await tester.pumpAndSettle();

    final after = resolvedPoint(1);
    expect(after.dx, greaterThan(before.dx + 30));
    expect(after.dy, lessThan(before.dy - 40));
    expect(link.run.waypoints, hasLength(1), reason: 'still one corner');
  });

  testWidgets('dropping a corner on its neighbour deletes it', (tester) async {
    // The gesture the benches offered alongside the menu: drag it away and it
    // is gone, without going hunting for a command.
    link.run.waypoints.add(LinkWaypoint.onRun(0.5, -0.3));
    await pumpOverlay(tester, link: link, assets: page);

    final corner = resolvedPoint(1);
    final end = resolvedPoint(0);
    await tester.dragFrom(onCanvas(tester, corner), end - corner);
    await tester.pumpAndSettle();

    expect(link.run.waypoints, isEmpty);
  });

  testWidgets('dragging an end onto another device re-plugs it',
      (tester) async {
    final c = _Block(x: 0.5, y: 0.9, name: 'EL9222')..ensureId();
    page = [a, b, c, link];
    await pumpOverlay(tester, link: link, assets: page);

    final end = resolvedPoint(link.run.waypoints.length + 1);
    final target = Offset(
        c.coordinates.x * _canvas.width, c.coordinates.y * _canvas.height);
    await tester.dragFrom(onCanvas(tester, end), target - end);
    await tester.pumpAndSettle();

    expect(link.run.to.assetId, c.id,
        reason: 'the end should now belong to the device it was dropped on');
    expect(link.run.to.port, isNotNull);
  });

  testWidgets('dragging an end onto empty canvas unplugs it', (tester) async {
    await pumpOverlay(tester, link: link, assets: page);

    final end = resolvedPoint(link.run.waypoints.length + 1);
    const empty = Offset(400, 60);
    await tester.dragFrom(onCanvas(tester, end), empty - end);
    await tester.pumpAndSettle();

    expect(link.run.to.assetId, isNull);
    expect(link.run.to.x, closeTo(empty.dx / _canvas.width, 0.05));
  });

  testWidgets('right-clicking a corner offers delete and what it follows',
      (tester) async {
    link.run.waypoints.add(LinkWaypoint.onRun(0.5, -0.2));
    await pumpOverlay(tester, link: link, assets: page);

    await tester.tapAt(onCanvas(tester, resolvedPoint(1)),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete point'), findsOneWidget);
    expect(find.text('Straighten run'), findsOneWidget);
    expect(find.text('This corner follows'), findsOneWidget);
    // Named by the devices the run is plugged into, not by opaque ids.
    expect(find.text('EK1100'), findsOneWidget);
    expect(find.text('EP2338'), findsOneWidget);
  });

  testWidgets('Delete point removes that corner', (tester) async {
    link.run.waypoints
      ..add(LinkWaypoint.onRun(0.3, -0.2))
      ..add(LinkWaypoint.onRun(0.7, -0.2));
    await pumpOverlay(tester, link: link, assets: page);

    await tester.tapAt(onCanvas(tester, resolvedPoint(1)),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete point'));
    await tester.pumpAndSettle();

    expect(link.run.waypoints, hasLength(1));
    // The one that survived is the second, so the right index was removed.
    expect(link.run.waypoints.single.t, closeTo(0.7, 1e-6));
  });

  testWidgets('pinning a corner to a device changes what holds it',
      (tester) async {
    link.run.waypoints.add(LinkWaypoint.onRun(0.4, -0.2));
    await pumpOverlay(tester, link: link, assets: page);

    await tester.tapAt(onCanvas(tester, resolvedPoint(1)),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EK1100'));
    await tester.pumpAndSettle();

    expect(link.run.waypoints.single.pinnedTo, a.id);
    expect(link.run.waypoints.single.t, isNull,
        reason: 'the rule it no longer uses must be cleared');
  });

  testWidgets('a pinned corner then ignores the far device', (tester) async {
    link.run.waypoints.add(LinkWaypoint.pinned('${a.id}', 0.1, -0.1));
    await pumpOverlay(tester, link: link, assets: page);
    final before = resolvedPoint(1);

    b.coordinates = Coordinates(x: 0.6, y: 0.2);
    await pumpOverlay(tester, link: link, assets: page);

    expect(resolvedPoint(1), within(distance: 0.01, from: before));
  });

  testWidgets('right-clicking the cable adds a point there', (tester) async {
    await pumpOverlay(tester, link: link, assets: page);
    final mid = (resolvedPoint(0) + resolvedPoint(1)) / 2;

    await tester.tapAt(onCanvas(tester, mid), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Add point here'), findsOneWidget);

    await tester.tap(find.text('Add point here'));
    await tester.pumpAndSettle();

    expect(link.run.waypoints, hasLength(1));
  });

  testWidgets('every edit reports a change so the page is re-encoded',
      (tester) async {
    // A drag that never told the editor would be lost on save, which is the
    // silent kind of broken.
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _canvas.width,
            height: _canvas.height,
            child: Stack(children: [
              LinkEditOverlay(
                link: link,
                assets: page,
                canvas: _canvas,
                onBeginEdit: () {},
                onChanged: () => changes++,
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final mid = (resolvedPoint(0) + resolvedPoint(1)) / 2;
    await tester.dragFrom(onCanvas(tester, mid), const Offset(0, -100));
    await tester.pumpAndSettle();

    expect(changes, greaterThan(0));
  });
}

LinkAnchors _anchorsFor(List<Asset> assets) => PageLinkAnchors(assets, _canvas);
