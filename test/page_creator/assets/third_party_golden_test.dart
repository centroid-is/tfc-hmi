import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/third_party.dart';
import 'package:tfc/page_creator/assets/third_party_painter.dart';

const _key = Key('third_party_golden');

/// Golden canvas size for a kind, at that machine's true plan aspect ratio.
///
/// Fitted into a 720 x 820 box rather than fixed-width, because the kinds run
/// from a 5.4:1 Multivac strip to a PORTRAIT SpeedBatcher — pinning the width
/// would run the SpeedBatcher off the bottom of the golden.
Size _canvasFor(ThirdPartyEquipmentKind kind, {int strapHeads = 3}) {
  const maxW = 720.0;
  const maxH = 820.0;
  final aspect = kind.aspectRatio(strapHeads: strapHeads);
  double w = maxW;
  double h = maxW / aspect;
  if (h > maxH) {
    h = maxH;
    w = maxH * aspect;
  }
  return Size(w, h);
}

/// Wraps the painted body in a minimal tree for golden capture.
///
/// Renders [ThirdPartyEquipmentBody] rather than [ThirdPartyEquipment] so no
/// `StateMan` is needed — the LED colour is passed directly, which is exactly
/// what the live widget resolves it to.
Widget buildBody({
  required ThirdPartyEquipmentKind kind,
  Color? ledColor = Colors.green,
  Color outlineColor = const Color(0xFF37474F),
  double strokeWidth = 2.5,
  int strapHeads = 3,
}) {
  final size = _canvasFor(kind, strapHeads: strapHeads);
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: RepaintBoundary(
          key: _key,
          child: ThirdPartyEquipmentBody(
            painter: thirdPartyPainterFor(
              kind,
              color: outlineColor,
              strokeWidth: strokeWidth,
              strapHeads: strapHeads,
            ),
            paintSize: size,
            ledColor: ledColor,
          ),
        ),
      ),
    ),
  );
}

/// Loads a real font for the populated golden.
///
/// Without this every glyph renders as a filled black box — the Flutter test
/// font draws no actual letterforms — which turns the readouts into bars and
/// makes the golden useless for judging whether a weight beside a belt is
/// legible. RobotoMono is already in the repo under `lib/fonts/`.
Future<void> loadRealFont() async {
  final data = File('lib/fonts/roboto-mono/RobotoMono-Regular.ttf')
      .readAsBytesSync()
      .buffer
      .asByteData();
  final loader = FontLoader('Roboto')..addFont(Future.value(data));
  await loader.load();
}

/// The scaffolded station with both checkweigher belts RUNNING.
///
/// The readouts are the real `NumberConfig` children the scaffold creates, on
/// their real anchors, switched to the preview key so they show a value
/// without a PLC.
///
/// The belts are the real [ConveyorPainter] the `Conveyor` asset paints with,
/// given the same arguments the asset would pass — bidirectional, geometry
/// from `ConveyorPathGeometry.build` — plus a frequency the test supplies.
/// That last part is the one thing a widget test cannot get honestly: the
/// frequency arrives over a `StateMan` subscription, and `StateMan` has a
/// private constructor that spins real OPC UA client loops, so there is no
/// test double to hand. Feeding the painter directly is what makes the
/// run-direction arrow visible here.
Widget buildRunningStation({double frequency = 50.0}) {
  final children = buildSpeedBatcherStationChildren(acceptWindowMinutes: 30);
  // Readouts stay as real children; the belts are painted below so they can
  // be shown running.
  final readouts = children.where((e) => e.child is NumberConfig).toList();
  for (final entry in readouts) {
    (entry.child as NumberConfig).key = 'Number preview';
  }

  final size = _canvasFor(ThirdPartyEquipmentKind.speedBatcher);
  final area = thirdPartyMachineArea(size);

  Widget belt(Rect frame) {
    final deck = SpeedBatcherPainter.deckOf(frame);
    final rect = Rect.fromLTRB(
      area.left + deck.left * area.width,
      area.top + deck.top * area.height,
      area.left + deck.right * area.width,
      area.top + deck.bottom * area.height,
    );
    final beltSize = Size(rect.width, rect.height);
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: CustomPaint(
        size: beltSize,
        painter: ConveyorPainter(
          color: Colors.green,
          bidirectional: true,
          reverseDirection: false,
          showFrequency: false,
          frequency: frequency,
          batches: const {},
          angle: 0,
          geometry: ConveyorPathGeometry.build(const [], beltSize),
        ),
      ),
    );
  }

  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: _key,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: thirdPartyPainterFor(
                        ThirdPartyEquipmentKind.speedBatcher,
                        color: const Color(0xFF37474F),
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                  belt(SpeedBatcherPainter.checkweigher1Frame),
                  belt(SpeedBatcherPainter.checkweigher2Frame),
                  // Readouts on top of the belts, via the real body so their
                  // anchors and sizing come from production code.
                  Positioned.fill(
                    child: ThirdPartyEquipmentBody(
                      painter: _NoopPainter(),
                      paintSize: size,
                      ledColor: Colors.green,
                      children: readouts,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Draws nothing — lets the body be reused purely to place children over an
/// already-painted machine.
class _NoopPainter extends ThirdPartyMachinePainter {
  const _NoopPainter() : super(color: const Color(0x00000000), strokeWidth: 0);
  @override
  void paintMachine(Canvas canvas, UnitSpace u, Paint stroke, Paint detail) {}
  @override
  void paint(Canvas canvas, Size size) {}
}

void main() {
  group('ThirdPartyEquipment plan-view goldens',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    // One golden per equipment kind, running. These are the drawings to
    // review — each is a simplified plan view of the real machine, sourced
    // from the manufacturer photos and spec sheets cited at the top of
    // `third_party_painter.dart`.
    for (final kind in ThirdPartyEquipmentKind.values) {
      testWidgets('${kind.name} — running', (tester) async {
        tester.view.physicalSize = const Size(1400, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildBody(kind: kind));
        await expectLater(
          find.byKey(_key),
          matchesGoldenFile('goldens/third_party_${kind.name}_running.png'),
        );
      });
    }

    // The SpeedBatcher station with "Build checkweighers" applied and both
    // belts RUNNING: full-width conveyor per checkweigher, run-direction
    // arrow mid-belt, live weight right of the arrow, accept rate left. This
    // is the golden to judge the layout by.
    // testWidgets name kept stable so the golden file name does not churn.
    testWidgets('speedBatcher — checkweighers populated', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildRunningStation());
      await tester.pump(const Duration(milliseconds: 16));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_speedBatcher_populated.png'),
      );
    });

    // The strapping line ships as SL-15-1, -2 and -3. Head count changes both
    // the number of arches and the machine's proportions, so each variant
    // gets its own golden. (-3 is covered by the per-kind loop above.)
    for (final heads in const [1, 2]) {
      testWidgets('strappingLine — $heads head(s)', (tester) async {
        tester.view.physicalSize = const Size(1400, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildBody(
          kind: ThirdPartyEquipmentKind.strappingLine,
          strapHeads: heads,
        ));
        await expectLater(
          find.byKey(_key),
          matchesGoldenFile('goldens/third_party_strappingLine_${heads}head.png'),
        );
      });
    }

    // LED states, captured on one kind. The machine drawing is identical
    // across states by design — only the run LED changes — so there is no
    // value in a stopped/unknown pair for all four.
    testWidgets('strappingLine — stopped', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildBody(
        kind: ThirdPartyEquipmentKind.strappingLine,
        ledColor: Colors.red,
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_strappingLine_stopped.png'),
      );
    });

    testWidgets('strappingLine — unknown (no key / stale)', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // A null LED colour is the stale path — `LEDPainter` renders grey with
      // its `!` glyph, the same as every other unresolved LED on the page.
      await tester.pumpWidget(buildBody(
        kind: ThirdPartyEquipmentKind.strappingLine,
        ledColor: null,
      ));
      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/third_party_strappingLine_unknown.png'),
      );
    });
  });
}
