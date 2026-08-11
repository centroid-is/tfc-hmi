import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/third_party.dart';

const _key = Key('third_party_golden');

/// Golden canvas size for a kind, at that machine's true plan aspect ratio.
///
/// Every kind gets the same 720 px length so the goldens sit side by side in a
/// review; the height follows the real footprint. The Multivac is 5.4:1, so it
/// comes out as a long strip — that is the machine, not a bug.
Size _canvasFor(ThirdPartyEquipmentKind kind) {
  const length = 720.0;
  return Size(length, length / kind.aspectRatio);
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
}) {
  final size = _canvasFor(kind);
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
            ),
            paintSize: size,
            ledColor: ledColor,
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
