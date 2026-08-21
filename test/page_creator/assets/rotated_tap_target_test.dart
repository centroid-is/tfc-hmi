// A rotated asset must be tappable along its whole painted visual, not just
// where that visual crosses its own unrotated layout rect.
//
// `AssetStack` lays every asset out in its unrotated w×h rect and lets the
// asset's internal `LayoutRotatedBox` paint out into the surrounding AABB
// (`_HitPermissiveSizedBox` keeps the page-level chain from clamping first).
// Anything the asset mounts OUTSIDE that rotated box hit-tests against the
// unrotated rect: `RenderBox.hitTest` rejects a position outside its own size
// before the child gets a say. A conveyor is the worst case for it — a long,
// thin box turned 90° paints a tall strip while its rect stays short and wide,
// so only the square where the two cross answered. On a wet-area strapper
// conveyor (0.05 × 0.03 of the canvas, turned 90°) that is the middle third of
// the belt, and the proximity sensors placed on the same spot cover most of
// what is left.
//
// The sensor was fixed for this once already; see sensor_rotated_hittest_test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/elevator.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc_dart/core/state_man.dart';

class _FakeStateMan extends Fake implements StateMan {
  @override
  Future<Stream<DynamicValue>> subscribe(String key) async =>
      Stream<DynamicValue>.value(DynamicValue());
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Widget stackApp(BaseAsset asset) {
    return ProviderScope(
      overrides: [
        stateManProvider.overrideWith((ref) async => _FakeStateMan()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) => AssetStack(
              assets: [asset],
              constraints: constraints,
              absorb: false,
              selectedAssets: const {},
              mirroringDisabled: true,
            ),
          ),
        ),
      ),
    );
  }

  /// Whether a hit test at [global] reaches the asset's own tap handler.
  bool hitsDetector(WidgetTester tester, Type assetWidget, Offset global) {
    final detector = find.descendant(
      of: find.byType(assetWidget),
      matching: find.byType(GestureDetector),
    );
    expect(detector, findsOneWidget,
        reason: 'a key is configured, so the tap handler must mount');
    final target = tester.renderObject(detector);
    return tester
        .hitTestOnBinding(global)
        .path
        .any((entry) => entry.target == target);
  }

  group('Conveyor', () {
    // The 800×600 test window makes the belt an 80×30 rect laid out
    // horizontally and, at 90°, painted as a 30×80 strip on the same centre.
    ConveyorConfig belt({double? angle}) => ConveyorConfig(key: 'AREA01.CN05')
      ..coordinates = Coordinates(x: 0.5, y: 0.5, angle: angle)
      ..size = const RelativeSize(width: 0.1, height: 0.05);

    testWidgets('turned 90°, the whole painted belt is tappable',
        (tester) async {
      await tester.pumpWidget(stackApp(belt(angle: 90)));
      await tester.pumpAndSettle();

      // ±30 px along the strip is well past the 15 px half-height of the
      // unrotated rect — the stretch of belt the old clamp swallowed.
      final center = tester.getCenter(find.byType(Conveyor));
      expect(hitsDetector(tester, Conveyor, center), isTrue,
          reason: 'middle of the belt must be tappable');
      expect(
          hitsDetector(tester, Conveyor, center + const Offset(0, -30)), isTrue,
          reason: 'upstream end of the rotated belt must be tappable');
      expect(
          hitsDetector(tester, Conveyor, center + const Offset(0, 30)), isTrue,
          reason: 'downstream end of the rotated belt must be tappable');
    });

    testWidgets('turned 90°, a narrow belt claims only the band it paints',
        (tester) async {
      // beltWidthRelative is a fraction of the canvas height, so 0.02 of a
      // 600 px canvas paints a 12 px band down the middle of the 30 px-wide
      // rotated box. Widening the tap target back out to the box would take
      // taps from whatever is parked alongside the belt.
      final config = belt(angle: 90)..beltWidthRelative = 0.02;
      await tester.pumpWidget(stackApp(config));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(Conveyor));
      expect(
          hitsDetector(tester, Conveyor, center + const Offset(0, 35)), isTrue,
          reason: 'far along the band is still the band');
      for (final beside in [const Offset(10, 0), const Offset(-10, 0)]) {
        expect(hitsDetector(tester, Conveyor, center + beside), isFalse,
            reason: 'beside the band, still inside the box: must fall through');
      }
    });

    testWidgets('unrotated, the belt fills its box and the box is the belt',
        (tester) async {
      await tester.pumpWidget(stackApp(belt()));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(Conveyor));
      expect(
          hitsDetector(tester, Conveyor, center + const Offset(35, 0)), isTrue);
      expect(hitsDetector(tester, Conveyor, center + const Offset(-35, 0)),
          isTrue);
    });
  });

  group('Elevator', () {
    // Same root cause, same shape of fix: the elevator's detector was mounted
    // outside its LayoutRotatedBox, so a turned elevator answered only where
    // its visual crossed the unrotated rect.
    ElevatorConfig lift({double? angle}) => ElevatorConfig(positionKey: '')
      ..coordinates = Coordinates(x: 0.5, y: 0.5, angle: angle)
      ..size = const RelativeSize(width: 0.1, height: 0.05);

    testWidgets('turned 90°, the whole rotated visual is tappable',
        (tester) async {
      await tester.pumpWidget(stackApp(lift(angle: 90)));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(Elevator));
      expect(hitsDetector(tester, Elevator, center), isTrue);
      expect(
          hitsDetector(tester, Elevator, center + const Offset(0, -30)), isTrue,
          reason: 'the rotated visual runs along y, so its ends must answer');
      expect(
          hitsDetector(tester, Elevator, center + const Offset(0, 30)), isTrue);
    });
  });
}
