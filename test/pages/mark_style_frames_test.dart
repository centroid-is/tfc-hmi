/// Throwaway: films the open-pane mark so the style in use can be chosen by
/// looking at it move rather than by reading numbers.
///
/// Run with the wanted style wired into `HitBoundaryStyle.selection`, then
/// assemble the PNGs with ffmpeg. Delete once the choice is made.
///
///   flutter test test/pages/mark_style_frames_test.dart --run-skipped
@Tags(['golden'])
library;

import 'dart:io' show Directory, File, Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart'
    show DynamicValue, EnumField, LocalizedText;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/theme.dart';
import 'package:tfc/widgets/hit_boundary.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

/// Where the frames land. Set `MARK_FRAMES_OUT` to the run's directory.
String get _outDir =>
    Platform.environment['MARK_FRAMES_OUT'] ?? 'build/mark-frames';

const _sceneKey = ValueKey('mark-frames-scene');

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
        .load();
  }

  for (final family in ['Roboto', 'roboto-mono']) {
    await load(family, 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');
  }
}

void main() {
  group('mark frames',
      skip: !Platform.isMacOS ? 'only filmed on macOS' : null, () {
    setUpAll(_loadFonts);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    tearDown(() => closeSidePane(immediate: true));

    Future<void> film(WidgetTester tester, String name,
        {required bool dark}) async {
      const surface = Size(700, 320);
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fake = _FakeStateMan()..pushValue('cn/drive', _runningDrive());
      final themes = themesForScheme(AppColorScheme.muted);

      await tester.pumpWidget(ProviderScope(
        overrides: [stateManProvider.overrideWith((_) async => fake)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? themes.$2 : themes.$1,
          home: Scaffold(
            body: RepaintBoundary(
              key: _sceneKey,
              // The stack paints no background of its own, so without one
              // here every frame comes out on white and the dark theme films
              // identically to the light one.
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: LayoutBuilder(
                    builder: (context, constraints) => AssetStack(
                  assets: [
                        ConveyorConfig(key: 'cn/drive', turns: [
                          ConveyorTurnEntry(
                              position: 0.5, angle: 60, radius: 1.4),
                        ])
                          ..coordinates = Coordinates(x: 0.5, y: 0.5)
                          ..size =
                              const RelativeSize(width: 0.7, height: 0.5),
                      ],
                      constraints: constraints,
                      selectedAssets: const {},
                      mirroringDisabled: true,
                      absorb: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open the belt's pane by finding a point that is actually on the belt.
      final rect = tester.getRect(find.byType(Conveyor));
      for (var y = 0.1; y < 1 && !isSidePaneOpen(); y += 0.05) {
        for (var x = 0.05; x < 1; x += 0.05) {
          await tester
              .tapAt(Offset(rect.left + rect.width * x, rect.top + rect.height * y));
          await tester.pump();
          if (isSidePaneOpen()) break;
        }
      }
      expect(isSidePaneOpen(), isTrue);

      // Past the trace and the fade, so every frame is the ring at full
      // opacity and only the dashes are moving.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 400));

      final dir = Directory('$_outDir/$name')..createSync(recursive: true);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_sceneKey));

      // 18 frames at 15fps: 1200ms, which is one turn of the slow styles and
      // two of the brisk one, so every clip is the same length and loops.
      const frames = 18;
      const step = Duration(microseconds: 1200000 ~/ frames);
      for (var i = 0; i < frames; i++) {
        await tester.runAsync(() async {
          final ui.Image image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/${i.toString().padLeft(3, '0')}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pump(step);
      }
      // ignore: avoid_print
      print('MARK FRAMES: ${dir.path}');
    }

    testWidgets('light', (tester) async {
      await film(tester, 'light', dark: false);
    });

    testWidgets('dark', (tester) async {
      await film(tester, 'dark', dark: true);
    });

    test('style in use', () {
      // ignore: avoid_print
      print('MARK STYLE: ${HitBoundaryStyle.selection}');
    });
  });
}

DynamicValue _runningDrive() {
  const modes = ['stopped', 'auto', 'manual', 'clean', 'fault'];
  final runMode = DynamicValue(value: modes.indexOf('auto'));
  runMode.enumFields = {
    for (var i = 0; i < modes.length; i++)
      i: EnumField(i, modes[i], LocalizedText(modes[i], 'en'),
          LocalizedText('', 'en')),
  };

  final drive = DynamicValue();
  drive['p_stat_State'] = 0;
  drive['p_stat_LastFault'] = 0;
  drive['p_stat_RunMode'] = runMode;
  drive['p_stat_Frequency'] = 42.0;
  drive['p_stat_Current'] = 3.2;
  drive['p_stat_RunMinutes'] = 128;
  drive['p_stat_JogFwd'] = false;
  drive['p_stat_JogBwd'] = false;
  drive['p_stat_ManualStopOnRelease'] = true;
  drive['p_cfg_ManualFreq'] = 20.0;
  drive['p_cfg_AutoFreq'] = 50.0;
  drive['p_cfg_CleaningFreq'] = 20.0;
  return drive;
}

class _FakeStateMan implements StateMan {
  final Map<String, BehaviorSubject<DynamicValue>> _streams = {};

  void pushValue(String key, DynamicValue value) {
    _streams.putIfAbsent(key, () => BehaviorSubject<DynamicValue>()).add(value);
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async =>
      _streams.putIfAbsent(key, () => BehaviorSubject<DynamicValue>()).stream;

  @override
  Future<void> write(String key, DynamicValue value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('_FakeStateMan: ${invocation.memberName}');
  }
}
