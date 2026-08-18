import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';

const _key = Key('conveyor_narrow_s');

/// A reported real-world setup (SVN, 2026-08-18): an S-conveyor — 60° down at
/// 20%, 60° back up at 55%, radius 1, belt width 2.5% of screen height — in a
/// box 14% of the screen wide and 40% tall (269x432 on a 1920x1080 canvas).
///
/// The box height must be climbed by the diagonal run between the two bends,
/// and a 60° diagonal drops only tan(60) = 1.73px per pixel of sideways
/// travel; the position sliders (0.20 / 0.55) additionally reserve ~65% of
/// the belt for the horizontal entry and exit runs, which consume pure
/// width. Filling 432px of height at 60° therefore needs roughly 22% of the
/// screen's width. Narrower than that, filling is impossible without
/// pinching the bends or crushing the slider proportions, so the fill solve
/// stands down and the fallback draws the S at its natural aspect fitted to
/// the box width — a short S floating in a tall box, which is the reported
/// "obscure" rendering.
///
/// The matrix pins the reported box, the ~22% width where 60° first fills,
/// and the steeper-bend alternative: at 75° the same S fills the original
/// 14% box completely, because a steeper zig climbs more height per width.
Widget _cell({
  required String label,
  required Size box,
  double angle = 60,
}) {
  final geometry = ConveyorPathGeometry.build(
    [
      ConveyorTurnEntry(position: 0.20, angle: angle, radius: 1),
      ConveyorTurnEntry(position: 0.55, angle: -angle, radius: 1),
    ],
    box,
    // The reported belt width: 2.5% of a 1080px-tall screen.
    beltWidthOverride: 0.025 * 1080,
  );
  return Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 10, fontFamily: 'Roboto')),
        const SizedBox(height: 2),
        Container(
          width: box.width,
          height: box.height,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF3DA9FC), width: 1),
          ),
          child: CustomPaint(
            size: box,
            painter: ConveyorPainter(
              color: Colors.green,
              batches: const {},
              angle: 0,
              geometry: geometry,
            ),
          ),
        ),
      ],
    ),
  );
}

void main() {
  group('Narrow-box S-conveyor',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    testWidgets('height a 60-degree S can climb per box width',
        (tester) async {
      tester.view.physicalSize = const Size(1900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const canvas = Size(1920, 1080);
      final cells = <Widget>[
        _cell(
            label: 'reported: 14% x 40%, 60deg — fallback, S cannot reach',
            box: Size(canvas.width * 0.14, canvas.height * 0.40)),
        _cell(
            label: '22% — narrowest width 60deg fills',
            box: Size(canvas.width * 0.22, canvas.height * 0.40)),
        _cell(
            label: '40% — the widened workaround',
            box: Size(canvas.width * 0.40, canvas.height * 0.40)),
        _cell(
            label: 'same 14% box, 75deg bends — fills without widening',
            box: Size(canvas.width * 0.14, canvas.height * 0.40),
            angle: 75),
      ];

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: RepaintBoundary(
            key: _key,
            child: Wrap(children: cells),
          ),
        ),
      ));

      await expectLater(
        find.byKey(_key),
        matchesGoldenFile('goldens/conveyor_narrow_s_width_sweep.png'),
      );
    });
  });
}
