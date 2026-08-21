import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor.dart';
import 'package:tfc/providers/collector.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/widgets/panes/pane_chrome.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../../helpers/golden_tolerance.dart';

/// Goldens of the conveyor pane's drive-status rows — the words an operator
/// reads instead of `rdY(2)` / `OCF(9)`, and the explanation panel behind
/// them.
///
/// Two scenarios, because they exercise opposite halves of the design: a trip
/// (fault row opens itself, red, with a reset class and a remedy) and a
/// healthy-but-puzzling state (closed until asked, no alarm ink on a belt
/// that is merely waiting).

/// Loads real fonts so labels render as letterforms and icons as glyphs
/// rather than the test font's boxes — same as the gate force pane golden.
Future<void> loadRealFont() async {
  Future<void> loadFont(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
  }

  await loadFont('Roboto', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  for (final candidate in <String>[
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
  ]) {
    if (File(candidate).existsSync()) {
      await loadFont('MaterialIcons', candidate);
      break;
    }
  }
}

class _DriveStateMan extends Fake implements StateMan {
  _DriveStateMan({required this.driveKey, required this.state, this.fault = 0});

  final String driveKey;
  final int state;
  final int fault;

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async {
    if (key != driveKey) return const Stream<DynamicValue>.empty();
    final dv = DynamicValue();
    dv['p_stat_State'] = state;
    dv['p_stat_LastFault'] = fault;
    dv['p_stat_Frequency'] = 0.0;
    dv['p_stat_Current'] = 0.0;
    dv['p_stat_RunMinutes'] = 0;
    dv['p_stat_JogFwd'] = false;
    dv['p_stat_JogBwd'] = false;
    dv['p_stat_ManualStopOnRelease'] = true;
    dv['p_cfg_ManualFreq'] = 20.0;
    dv['p_cfg_AutoFreq'] = 20.0;
    dv['p_cfg_CleaningFreq'] = 20.0;
    return Stream<DynamicValue>.value(dv);
  }

  @override
  Future<void> write(String key, DynamicValue value) async {}
}

void main() {
  // Full app surface with real text; same reasoning as the gate force pane
  // golden — the default tolerance is too tight for text antialiasing drift,
  // while a real regression moves far more than 0.2% of the frame.
  useTolerantGoldenComparator(tolerance: 0.002);

  group('conveyor drive status golden',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    setUpAll(loadRealFont);

    setUp(() {
      // A station panel, not the 800x600 default: the pinned action bar
      // otherwise sits on top of the very rows being goldened.
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      view.devicePixelRatio = 1.0;
      view.physicalSize = const Size(1200, 900);
    });

    tearDown(() {
      closeSidePane();
      TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
          .resetPhysicalSize();
    });

    Future<void> openPane(
      WidgetTester tester, {
      required int state,
      int fault = 0,
    }) async {
      const key = 'CN04.Belt.Drive';
      final config = ConveyorConfig(key: key)
        ..size = const RelativeSize(width: 1.0, height: 1.0);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          // The pane's trend tile resolves the collector, which builds a real
          // Database with periodic timers and leaves them pending past the test.
          // Nothing here is about the trend, so cut it off at the provider.
          collectorProvider.overrideWith((ref) async => null),
          stateManProvider.overrideWith(
            (ref) async =>
                _DriveStateMan(driveKey: key, state: state, fault: fault),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 400, height: 80, child: Conveyor(config)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Conveyor));
      // Not pumpAndSettle — the trend tile spins forever on a fake StateMan.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('tripped on overcurrent, explanation open', (tester) async {
      await openPane(tester, state: 23, fault: 9); // hmis_e.fault + lft_e.ocf

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conveyor_drive_status_fault.png'),
      );
    });

    testWidgets('freewheel stop, explanation opened by the operator',
        (tester) async {
      await openPane(tester, state: 3); // hmis_e.nst

      await tester.tap(find.descendant(
        of: find.byType(PaneExplainRow),
        matching: find.text('Freewheel stop'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Let the tap's ink highlight fade, so the golden shows the row at
      // rest rather than mid-splash.
      await tester.pump(const Duration(seconds: 1));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/conveyor_drive_status_freewheel.png'),
      );
    });
  });
}
