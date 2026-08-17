import 'dart:io' show File, Platform;
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/alarm_visibility.dart';
import 'package:tfc/theme.dart' show solarized;
import 'package:tfc/widgets/alarm.dart' show alarmLevelColors;
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

const _beaconKey = Key('alarm_beacon_golden');

// ── Side pane fixtures ──────────────────────────────────────────────────────

AlarmConfig _alarmConfigFx({
  required String uid,
  required String title,
  required String description,
  AlarmLevel level = AlarmLevel.error,
  String formula = 'x',
}) {
  return AlarmConfig(
    uid: uid,
    title: title,
    description: description,
    rules: [
      AlarmRule(
        level: level,
        expression: ExpressionConfig(value: Expression(formula: formula)),
        acknowledgeRequired: false,
      ),
    ],
  );
}

AlarmActive _activeFx(AlarmConfig config, {required DateTime timestamp}) {
  final rule = config.rules.first;
  return AlarmActive(
    alarm: Alarm(config: config),
    notification: AlarmNotification(
      uid: config.uid,
      active: true,
      expression: rule.expression.value.formula,
      rule: rule,
      timestamp: timestamp,
    ),
  );
}

/// The pane at side-pane width (380, `SidePaneDefaults`), Solarized light —
/// rendered through the pure [AlarmVisibilityPaneView] so no `AlarmMan` is
/// needed.
Widget buildPane(AlarmVisibilityPaneView view, {required double height}) {
  final (light, _) = solarized();
  return ProviderScope(
    child: MaterialApp(
      theme: light,
      home: Scaffold(
        backgroundColor: light.colorScheme.surface,
        body: Center(
          child: RepaintBoundary(
            key: _beaconKey,
            child: SizedBox(width: 380, height: height, child: view),
          ),
        ),
      ),
    ),
  );
}

/// One beacon frame per [progress] value, side by side — a filmstrip of the
/// pulse cycle, so the golden reviews the *motion*, not just one pose.
///
/// Rendered with the app's real Solarized theme (`lib/theme.dart`), not the
/// Flutter default, so the goldens show the colours operators actually see —
/// warning is Solarized yellow because the theme sets `tertiary` and the
/// `*Container` roles fall back to the base role.
Widget buildFilmstrip({
  required AlarmLevel level,
  required List<double> progresses,
  bool dark = false,
}) {
  final (light, darkTheme) = solarized();
  final theme = dark ? darkTheme : light;
  return MaterialApp(
    theme: theme,
    home: Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: RepaintBoundary(
          key: _beaconKey,
          child: Builder(
            builder: (context) {
              final (fill, ring) = alarmLevelColors(context, level);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in progresses)
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CustomPaint(
                        painter: AlarmPulsePainter(
                          color: fill,
                          dotOutlineColor: ring,
                          progress: p,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

Widget buildIdleMarker({required double alpha}) {
  final (light, _) = solarized();
  return MaterialApp(
    theme: light,
    home: Scaffold(
      backgroundColor: light.colorScheme.surface,
      body: Center(
        child: RepaintBoundary(
          key: _beaconKey,
          child: Builder(
            builder: (context) => SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: AlarmIdlePainter(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: alpha),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Real glyphs for the pane goldens — without this the tests render the
/// block placeholder font. Same pattern as server_config_db_golden_test.
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
        .load();
  }

  // The Solarized theme sets fontFamily 'roboto-mono'; register the file
  // under the default family too so unthemed text matches.
  await load('Roboto', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');
  await load('roboto-mono', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await load('MaterialIcons',
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  }
}

void main() {
  const phases = [0.0, 0.2, 0.4, 0.6, 0.8];

  setUpAll(_loadFonts);

  group('Alarm beacon golden tests',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    testWidgets('error pulse cycle', (tester) async {
      await tester.pumpWidget(
          buildFilmstrip(level: AlarmLevel.error, progresses: phases));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_error_cycle.png'),
      );
    });

    testWidgets('warning pulse cycle', (tester) async {
      await tester.pumpWidget(
          buildFilmstrip(level: AlarmLevel.warning, progresses: phases));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_warning_cycle.png'),
      );
    });

    testWidgets('info pulse cycle', (tester) async {
      await tester.pumpWidget(
          buildFilmstrip(level: AlarmLevel.info, progresses: phases));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_info_cycle.png'),
      );
    });

    testWidgets('error pulse on dark mimic background', (tester) async {
      await tester.pumpWidget(buildFilmstrip(
        level: AlarmLevel.error,
        progresses: phases,
        dark: true,
      ));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_error_cycle_dark.png'),
      );
    });

    testWidgets('idle marker (runtime, faint)', (tester) async {
      await tester.pumpWidget(buildIdleMarker(alpha: 0.5));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_idle.png'),
      );
    });

    testWidgets('idle marker (editor placeholder)', (tester) async {
      await tester.pumpWidget(buildIdleMarker(alpha: 0.9));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_idle_editor.png'),
      );
    });

    // ── Side pane ─────────────────────────────────────────────────────────

    testWidgets('side pane with active alarms', (tester) async {
      // The default 800x600 test window clips an 810-tall pane.
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final error = _alarmConfigFx(
        uid: 'freezer-stop',
        title: 'Freezer conveyor stopped',
        description: 'CN21 drive reports a motor fault. Product will back up '
            'at the freezer infeed within two minutes.',
        level: AlarmLevel.error,
        formula: 'ST201.CN21.DEV01.motor_fault',
      );
      final warning = _alarmConfigFx(
        uid: 'belt-drift',
        title: 'CN12 belt drift',
        description: 'Belt tracking sensor intermittently blocked.',
        level: AlarmLevel.warning,
        formula: 'ST101.CN12.SUB03.tracking_blocked',
      );
      await tester.pumpWidget(buildPane(
        AlarmVisibilityPaneView(
          config: AlarmVisibilityConfig()..text = 'Freezer infeed',
          active: [
            _activeFx(error, timestamp: DateTime(2026, 8, 18, 9, 41, 12)),
            _activeFx(warning, timestamp: DateTime(2026, 8, 18, 9, 38, 55)),
          ],
        ),
        height: 810,
      ));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_pane_active.png'),
      );
    });

    testWidgets('side pane while idle lists watched alarms', (tester) async {
      final watched = [
        _alarmConfigFx(
          uid: 'freezer-stop',
          title: 'Freezer conveyor stopped',
          description: 'CN21 drive reports a motor fault.',
        ),
        _alarmConfigFx(
          uid: 'belt-drift',
          title: 'CN12 belt drift',
          description: 'Belt tracking sensor intermittently blocked.',
          level: AlarmLevel.warning,
        ),
      ];
      await tester.pumpWidget(buildPane(
        AlarmVisibilityPaneView(
          config: AlarmVisibilityConfig(
            alarmUids: ['freezer-stop', 'belt-drift'],
          )..text = 'Freezer infeed',
          allAlarms: watched,
        ),
        height: 420,
      ));
      await expectLater(
        find.byKey(_beaconKey),
        matchesGoldenFile('goldens/alarm_visibility_pane_idle.png'),
      );
    });
  });
}
