import 'dart:io' show File, Platform;
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/theme.dart' show solarized;
import 'package:tfc/widgets/alarm.dart';
import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

import '../helpers/golden_tolerance.dart';

const _formKey = Key('alarm_form_golden');

AlarmConfig _configFx({required bool navigationIndicator}) => AlarmConfig(
      uid: 'a1',
      title: 'Freezer over temperature',
      description: 'CN14 freezer outfeed above set point for 5 minutes.',
      rules: [
        AlarmRule(
          level: AlarmLevel.error,
          expression: ExpressionConfig(value: Expression(formula: 'x')),
          acknowledgeRequired: false,
        ),
      ],
      navigationIndicator: navigationIndicator,
    );

/// The top of the alarm editor form — title, description, and the
/// navigation-bar switch. Clipped to the switch's neighbourhood: the rules
/// below it are the expression builder's business and have their own coverage.
Widget buildForm({required bool navigationIndicator}) {
  final (light, _) = solarized();
  return ProviderScope(
    child: MaterialApp(
      theme: light,
      home: Scaffold(
        backgroundColor: light.colorScheme.surface,
        body: Center(
          child: RepaintBoundary(
            key: _formKey,
            child: SizedBox(
              width: 560,
              height: 300,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: 1200,
                  child: AlarmForm(
                    initialConfig:
                        _configFx(navigationIndicator: navigationIndicator),
                    editable: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Real glyphs — same pattern as alarm_visibility_golden_test.
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
        .load();
  }

  await load('Roboto', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');
  await load('roboto-mono', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await load('MaterialIcons',
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  }
}

void main() {
  // These two are a text-heavy form surface, not the small painter drawings the
  // default 0.01% is calibrated for: four text fields' worth of glyphs across
  // 560x300. CI pins a different Flutter than local, and its text rasterisation
  // differs by ~18 px — 0.0107%, a hair over the default and nothing to do with
  // the switch these goldens exist to show. Same reasoning and value as
  // conveyor_gate_force_pane_golden_test.
  useTolerantGoldenComparator(tolerance: 0.002);

  setUpAll(_loadFonts);

  group('Alarm editor golden tests',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    testWidgets('navigation-bar switch off', (tester) async {
      await tester.pumpWidget(buildForm(navigationIndicator: false));
      await expectLater(
        find.byKey(_formKey),
        matchesGoldenFile('goldens/alarm_form_navigation_off.png'),
      );
    });

    testWidgets('navigation-bar switch on', (tester) async {
      await tester.pumpWidget(buildForm(navigationIndicator: true));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(_formKey),
        matchesGoldenFile('goldens/alarm_form_navigation_on.png'),
      );
    });
  });
}
