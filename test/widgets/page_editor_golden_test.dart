/// Golden images of the page editor, for design review.
///
/// Each golden renders the real editor on a 1920×1080 operator panel — the
/// size the plant actually runs — in the app's own theme, so what is under
/// review is how the surface sits on a real screen rather than a widget in
/// isolation.
///
/// Two things are being reviewed here:
///
///   * **The asset config pane.** It replaced a modal dialog, so the thing to
///     look at is what stays visible and reachable beside it: the canvas, the
///     asset being edited, the page selector and the mode buttons.
///   * **Unpublished pages.** A draft has to be obvious in two places — the
///     Pages dialog where it is toggled, and the canvas where the page is
///     built — or it gets left switched off.
///
/// The dense-editor golden is deliberately a Beckhoff bus coupler: a
/// two-column subdevice manager is the widest config editor there is, and it
/// is the one that decided the pane's default width.
///
/// To update: flutter test test/widgets/page_editor_golden_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/assets/beckhoff.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/text.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/theme.dart';

import '../helpers/page_editor_harness.dart';

/// A 1080p operator panel.
const Size _screen = Size(1920, 1080);

/// Pumps the real editor at panel size with [pages] on it.
Future<void> _pumpEditor(
  WidgetTester tester, {
  required ThemeData theme,
  required Map<String, AssetPage> pages,
  String? select,
}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(buildEditorUnderTest(
    PageManager(prefs: FakeEditorPreferences(), pages: pages),
    theme: theme,
  ));
  await tester.pumpAndSettle();

  if (select != null) {
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    await tester.tap(find.text(select));
    await tester.pumpAndSettle();
  }
}

/// A one-page map holding [assets].
Map<String, AssetPage> _onePage(List<Asset> assets) => {
      '/': AssetPage(
        menuItem: const MenuItem(label: 'Chiller', path: '/', icon: Icons.home),
        assets: assets,
        mirroringDisabled: true,
        navigationPriority: 0,
      ),
    };

/// A section holding a published page and a draft, so the Pages dialog shows
/// both states side by side.
Map<String, AssetPage> _pagesWithADraft() => {
      '/': AssetPage(
        menuItem: const MenuItem(label: 'Overview', path: '/', icon: Icons.home),
        assets: [],
        mirroringDisabled: true,
        navigationPriority: 0,
      ),
      '/lines': AssetPage(
        menuItem: const MenuItem(
          label: 'Lines',
          path: '/lines',
          icon: Icons.account_tree,
          isSection: true,
          children: [
            MenuItem(label: 'Line 1', path: '/lines/one', icon: Icons.conveyor_belt),
            MenuItem(label: 'Chiller', path: '/lines/chiller', icon: Icons.ac_unit),
          ],
        ),
        assets: [],
        mirroringDisabled: true,
        navigationPriority: 1,
      ),
      '/lines/one': AssetPage(
        menuItem: const MenuItem(
            label: 'Line 1', path: '/lines/one', icon: Icons.conveyor_belt),
        assets: [],
        mirroringDisabled: true,
        navigationPriority: 0,
      ),
      '/lines/chiller': AssetPage(
        menuItem: const MenuItem(
            label: 'Chiller', path: '/lines/chiller', icon: Icons.ac_unit),
        assets: [],
        mirroringDisabled: true,
        navigationPriority: 1,
        published: false,
      ),
    };

/// Opens the config pane for the asset drawn at canvas-relative ([fx], [fy]).
Future<void> _openConfigPane(
    WidgetTester tester, double fx, double fy) async {
  await tester.tapAt(onCanvas(tester, fx, fy));
  await tester.pumpAndSettle();
}

Asset _textAsset() => TextAssetConfig.preview()
  ..coordinates = Coordinates(x: 0.22, y: 0.35)
  ..size = const RelativeSize(width: 0.16, height: 0.09)
  ..text = 'Brine temperature';

Asset _busCoupler() => BeckhoffEK1100Config()
  ..coordinates = Coordinates(x: 0.22, y: 0.4)
  ..size = const RelativeSize(width: 0.22, height: 0.28);

void main() {
  final (light, dark) = solarized();

  // Same font wiring as `panes_golden_test.dart`: the themes ask for
  // 'roboto-mono' by name, and MaterialIcons is not registered in the test
  // environment — without both, the goldens render as Ahem blocks.
  setUpAll(() async {
    Future<void> loadFont(String family, String path) async {
      final bytes = File(path).readAsBytesSync();
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }

    await loadFont(
        'roboto-mono', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
        (Platform.resolvedExecutable.contains('flutter')
            ? null
            : File(Platform.resolvedExecutable).parent.path);
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
  });

  setUp(setUpEditorEnvironment);

  group('asset config pane', () {
    testWidgets('editor with no pane — the canvas as it was', (tester) async {
      await _pumpEditor(tester, theme: dark, pages: _onePage([_textAsset()]));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_editor_canvas_dark.png'),
      );
    });

    testWidgets('text asset — dark', (tester) async {
      await _pumpEditor(tester, theme: dark, pages: _onePage([_textAsset()]));
      await _openConfigPane(tester, 0.22, 0.35);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_editor_config_pane_text_dark.png'),
      );
    });

    testWidgets('text asset — light', (tester) async {
      await _pumpEditor(tester, theme: light, pages: _onePage([_textAsset()]));
      await _openConfigPane(tester, 0.22, 0.35);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_editor_config_pane_text_light.png'),
      );
    });

    // The widest editor in the registry: two columns, a subdevice list and a
    // dropdown. If the pane's default width is wrong, it shows here first.
    testWidgets('bus coupler — the densest editor', (tester) async {
      await _pumpEditor(tester, theme: dark, pages: _onePage([_busCoupler()]));
      await _openConfigPane(tester, 0.22, 0.4);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_editor_config_pane_dense_dark.png'),
      );
    });
  });

  group('unpublished pages', () {
    testWidgets('Pages dialog — a draft beside a published page',
        (tester) async {
      await _pumpEditor(tester, theme: dark, pages: _pagesWithADraft());
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_editor_pages_draft_dark.png'),
      );
    });

    testWidgets('canvas — editing a draft page', (tester) async {
      await _pumpEditor(
        tester,
        theme: dark,
        pages: _pagesWithADraft(),
        select: 'Chiller',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/page_editor_draft_badge_dark.png'),
      );
    });
  });
}
