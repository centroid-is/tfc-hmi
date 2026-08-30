import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/theme.dart';

const _key = Key('roller_conveyor_golden');

/// Real glyphs instead of Ahem boxes, so the row labels in the golden are
/// readable. Registered as 'roboto-mono' because that is the family the app
/// theme asks for — see `conveyor_drive_status_golden_test.dart`.
Future<void> loadRealFont() async {
  final data = File('lib/fonts/roboto-mono/RobotoMono-Regular.ttf')
      .readAsBytesSync()
      .buffer
      .asByteData();
  final loader = FontLoader('roboto-mono')..addFont(Future.value(data));
  await loader.load();
}

/// One straight roller belt per equipment state, a turned roller belt, and
/// the two wagon variants (solid band and roller) — everything the new
/// painter styles add over the classic box, under a real app theme so every
/// colour flows through [HmiStateColors].
Widget buildRollerScenario(ThemeData theme) {
  const beltSize = Size(240, 24);
  const turnSize = Size(200, 120);
  const wagonSize = Size(240, 60);

  Widget belt(Size size, ConveyorPainter painter) => SizedBox.fromSize(
        size: size,
        child: CustomPaint(size: size, painter: painter),
      );

  return MaterialApp(
    theme: theme,
    home: Builder(builder: (context) {
      final states = HmiStateColors.of(context);
      final beltStates = {
        'auto': states.green,
        'manual': states.yellow,
        'clean': states.blue,
        'stopped': states.grey,
        'fault': states.red,
        'unknown': states.violet,
      };
      return Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: _key,
            child: Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in beltStates.entries) ...[
                        Text('roller ${entry.key}',
                            style: theme.textTheme.bodySmall),
                        belt(
                          beltSize,
                          ConveyorPainter(
                            color: entry.value,
                            batches: const {},
                            angle: 0,
                            style: ConveyorStyle.roller,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                  const SizedBox(width: 24),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('roller turned', style: theme.textTheme.bodySmall),
                      belt(
                        turnSize,
                        ConveyorPainter(
                          color: states.green,
                          batches: const {},
                          angle: 0,
                          style: ConveyorStyle.roller,
                          geometry: ConveyorPathGeometry.build(
                            [ConveyorTurnEntry(
                                position: 0.5, angle: 90, radius: 1.5)],
                            turnSize,
                            thicknessFactor: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('wagon (box)', style: theme.textTheme.bodySmall),
                      belt(
                        wagonSize,
                        ConveyorPainter(
                          color: states.green,
                          batches: const {},
                          angle: 0,
                          onRails: true,
                          railInk: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('wagon (roller)', style: theme.textTheme.bodySmall),
                      belt(
                        wagonSize,
                        ConveyorPainter(
                          color: states.grey,
                          batches: const {},
                          angle: 0,
                          style: ConveyorStyle.roller,
                          onRails: true,
                          railInk: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('wagon at 25% of rail',
                          style: theme.textTheme.bodySmall),
                      belt(
                        wagonSize,
                        ConveyorPainter(
                          color: states.green,
                          batches: const {},
                          angle: 0,
                          style: ConveyorStyle.roller,
                          onRails: true,
                          railInk: theme.colorScheme.onSurface,
                          wagonPosition: 0.25,
                          wagonFraction: 0.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }),
  );
}

void main() {
  group('Roller conveyor and wagon golden tests',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    setUpAll(loadRealFont);
    final cases = <String, ThemeData>{
      'solarized_light': solarized().$1,
      'solarized_dark': solarized().$2,
    };
    for (final entry in cases.entries) {
      testWidgets('roller belts and wagons under ${entry.key}',
          (tester) async {
        await tester.pumpWidget(buildRollerScenario(entry.value));
        await expectLater(
          find.byKey(_key),
          matchesGoldenFile('goldens/roller_conveyor_${entry.key}.png'),
        );
      });
    }
  });
}
