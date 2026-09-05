/// Goldens for the commissioning window, open and closed.
///
/// * `access_first_user_open.png`   — the form: three fields, the one-shot
///   warning, the claimable warning, and the honesty line.
/// * `access_first_user_closed.png` — the window shut behind the first
///   account, pointing at the deployment doc.
///
/// **[FirstUserBody], never [FirstUserPage].** The page is a seven-line
/// `BaseScaffold` wrapper, and `BaseScaffold` calls
/// `context.currentBeamLocation`, so it cannot be pumped without a Beamer
/// ancestor — plan 01-09 split the two for exactly this. The app bar's own
/// states are `test/widgets/access_golden_test.dart`'s subject, not this
/// file's.
///
/// **The muted (ISA-101) palette**, matching the other four images in this
/// phase.
///
/// **Fonts are loaded here, twice.** `test/flutter_test_config.dart` — the one
/// that governs `test/pages/` — registers no font at all, and `lib/theme.dart`
/// names `'roboto-mono'` as the theme's family. Without both registrations
/// every themed `Text` captures as Ahem rectangles.
///
/// To update: flutter test test/pages/first_user_golden_test.dart --update-goldens --run-skipped
@Tags(['golden'])
library;

import 'dart:io' show File, Platform;
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/pages/first_user.dart';
import 'package:tfc/providers/access.dart';
import 'package:tfc/theme.dart' show muted;
import 'package:tfc_dart/core/access/access_repository.dart';

const _boundary = Key('access_first_user_golden');

/// A repository that is merely *present*.
///
/// The page distinguishes "no database" from "window closed" by null-checking
/// `accessRepositoryProvider`, so both images need a non-null repository. No
/// method is called while rendering, and the throwing `noSuchMethod` is the
/// tripwire that says so.
class _PresentRepository implements AccessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'A golden called AccessRepository.${invocation.memberName}; rendering '
        'the first-user page should touch no repository method.',
      );
}

Widget _host({required ThemeData theme, required bool windowOpen}) {
  return ProviderScope(
    overrides: [
      accessRepositoryProvider.overrideWith((ref) async => _PresentRepository()),
      firstUserWindowOpenProvider.overrideWith((ref) async => windowOpen),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        // The surface is painted *inside* the boundary, not left to the
        // Scaffold. A `RepaintBoundary` captures only its own subtree, and
        // the Scaffold paints its background behind the body — the first
        // pass of these two images came out 91% and 97% fully transparent,
        // which looks like a white page in any viewer and makes "no
        // off-scheme colours" impossible to judge.
        body: RepaintBoundary(
          key: _boundary,
          child: ColoredBox(
            color: theme.colorScheme.surface,
            child: const FirstUserBody(),
          ),
        ),
      ),
    ),
  );
}

/// Bounded settle — the open form autofocuses a `TextField`, and a blinking
/// caret schedules frames forever, so `pumpAndSettle` would time out.
/// [EditableText.debugDeterministicCursor] freezes the caret on instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _sizeView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  final (light, _) = muted();

  setUpAll(() async {
    Future<void> loadFont(String family, String path) async {
      final file = File(path);
      if (!file.existsSync()) return;
      await (FontLoader(family)
            ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer))))
          .load();
    }

    await loadFont('Roboto', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');
    await loadFont(
        'roboto-mono', 'lib/fonts/roboto-mono/RobotoMono-Regular.ttf');

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

    EditableText.debugDeterministicCursor = true;
  });

  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  group('first-user goldens',
      skip: !Platform.isMacOS ? 'Golden tests only run on macOS' : null, () {
    testWidgets('the commissioning window, open', (tester) async {
      _sizeView(tester, const Size(640, 800));
      await tester.pumpWidget(_host(theme: light, windowOpen: true));
      await _settle(tester);

      expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);

      await expectLater(
        find.byKey(_boundary),
        matchesGoldenFile('goldens/access_first_user_open.png'),
      );
    });

    testWidgets('the commissioning window, closed', (tester) async {
      _sizeView(tester, const Size(640, 320));
      await tester.pumpWidget(_host(theme: light, windowOpen: false));
      await _settle(tester);

      expect(find.byType(TextField), findsNothing);

      await expectLater(
        find.byKey(_boundary),
        matchesGoldenFile('goldens/access_first_user_closed.png'),
      );
    });
  });
}
