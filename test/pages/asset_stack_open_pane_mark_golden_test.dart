/// Goldens of the mark the plant view puts on the asset whose pane is open.
///
/// Three gates in a row — the case the mark exists for, since the pane's
/// header cannot say which of them an operator is about to force. One frame
/// with no pane open, for what the page normally looks like, and one with the
/// middle gate's pane up. The third gate is turned 35° so the golden also
/// answers whether the ring turns with the asset instead of sitting square
/// across it.
///
/// The bar to clear is a narrow one: the mark has to be findable at a glance
/// and still not read as equipment state. Compare the two images side by side
/// — nothing about the gates themselves may change between them.
///
/// To update: flutter test test/pages/asset_stack_open_pane_mark_golden_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor_gate.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/theme.dart';
import 'package:tfc/widgets/panes/side_pane.dart';
import 'package:tfc_dart/core/state_man.dart';

import '../helpers/golden_tolerance.dart';

/// Real letterforms and glyphs; the test font draws every label as a box,
/// which for an image about how loud a mark is would be misleading.
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
        .load();
  }

  // Both names: Material's default family, and the one the app's theme asks
  // for — a themed golden that only registers 'Roboto' draws every label as a
  // test-font block.
  for (final family in ['Roboto', 'roboto-mono']) {
    await load(family, 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  for (final candidate in <String>[
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
  ]) {
    if (File(candidate).existsSync()) {
      await load('MaterialIcons', candidate);
      break;
    }
  }
}

ConveyorGateConfig _gate(String label, {required double x, double? angle}) =>
    ConveyorGateConfig(
      gateVariant: GateVariant.pneumatic,
      stateKey: 'gate/state',
      forceOpenKey: 'gate/force_open',
      forceCloseKey: 'gate/force_close',
      forceOpenFeedbackKey: 'gate/fo_fb',
      forceCloseFeedbackKey: 'gate/fc_fb',
    )
      ..text = label
      ..textPos = TextPos.below
      // Small enough that the label under it stays a label: `AssetStack`
      // scales label text with the asset's box, and a gate half the height of
      // the page comes with lettering to match.
      ..coordinates = Coordinates(x: x, y: 0.4, angle: angle)
      ..size = const RelativeSize(width: 0.06, height: 0.09);

void main() {
  // A full 800×600 app surface with real text: the same cross-version
  // antialiasing drift the gate pane golden allows for applies here.
  useTolerantGoldenComparator(tolerance: 0.002);

  group('open-pane mark golden',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    setUpAll(_loadFonts);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    tearDown(() => closeSidePane(immediate: true));

    Future<List<Asset>> pumpPage(WidgetTester tester) async {
      final assets = <Asset>[
        // Left of the docked pane, all three of them: a gate under the pane
        // would be a picture of the inset instead of a picture of the mark.
        _gate('CN-04', x: 0.1),
        _gate('CN-05', x: 0.25),
        _gate('CN-06', x: 0.4, angle: 35),
      ];
      final fake = _FakeStateMan()..push('gate/state', true);

      await tester.pumpWidget(ProviderScope(
        overrides: [stateManProvider.overrideWith((_) async => fake)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themesForScheme(AppColorScheme.muted).$1,
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) => AssetStack(
                assets: assets,
                constraints: constraints,
                selectedAssets: const {},
                mirroringDisabled: true,
                absorb: false,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return assets;
    }

    testWidgets('no pane open — the page carries no mark', (tester) async {
      await pumpPage(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/open_pane_mark_none.png'),
      );
    });

    testWidgets('the gate whose pane is open wears a ring', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byType(ConveyorGate).at(1));
      await tester.pumpAndSettle();

      expect(isSidePaneOpen(), isTrue);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/open_pane_mark_upright.png'),
      );
    });

    testWidgets('the ring turns with a rotated asset', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byType(ConveyorGate).at(2));
      await tester.pumpAndSettle();

      expect(isSidePaneOpen(), isTrue);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/open_pane_mark_rotated.png'),
      );
    });
  });
}

class _FakeStateMan implements StateMan {
  final Map<String, BehaviorSubject<DynamicValue>> _streams = {};

  void push(String key, bool value) {
    _streams
        .putIfAbsent(key, () => BehaviorSubject<DynamicValue>())
        .add(DynamicValue(value: value, typeId: NodeId.boolean));
  }

  @override
  Future<Stream<DynamicValue>> subscribe(String key) async =>
      _streams.putIfAbsent(key, () => BehaviorSubject<DynamicValue>()).stream;

  @override
  Future<void> write(String key, DynamicValue value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeStateMan: ${invocation.memberName} not implemented in test scope',
    );
  }
}
