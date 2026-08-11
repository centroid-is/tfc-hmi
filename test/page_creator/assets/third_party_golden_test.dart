import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/page_creator/assets/number.dart';
import 'package:tfc/page_creator/assets/third_party.dart';

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

/// The scaffolded station with its children switched to the assets' own
/// preview keys, so they render real values without a `StateMan`.
///
/// This is the honest limit of a widget test: placement, sizes, fonts and
/// units are exactly what ships, and each readout shows the sample value
/// `NumberWidget` renders for its preview key. The belts draw grey rather
/// than running, because a moving belt needs a live drive frequency and there
/// is no PLC here.
Widget buildPopulated() {
  final children = buildSpeedBatcherStationChildren(acceptWindowMinutes: 30);
  for (final entry in children) {
    final child = entry.child;
    if (child is ConveyorConfig) child.key = ConveyorConfig.previewStr;
    if (child is NumberConfig) child.key = 'Number preview';
  }

  final size = _canvasFor(ThirdPartyEquipmentKind.speedBatcher);
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: _key,
            child: ThirdPartyEquipmentBody(
              painter: thirdPartyPainterFor(
                ThirdPartyEquipmentKind.speedBatcher,
                color: const Color(0xFF37474F),
                strokeWidth: 2.5,
              ),
              paintSize: size,
              ledColor: Colors.green,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
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

    // The SpeedBatcher station with "Build checkweighers" applied: a live
    // conveyor on each weigh belt, weight to the right, accept rate to the
    // left. This is the golden to look at when judging whether the layout
    // works in use, rather than the empty drawing above.
    testWidgets('speedBatcher — checkweighers populated', (tester) async {
      await loadRealFont();
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildPopulated());
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
