/// Shared scaffolding for end-to-end page editor tests.
///
/// The editor is pumpable, but only with a fair amount of setup: it sits
/// inside `BaseScaffold`, which reads the current Beamer location and the
/// route registry during build, and it loads and saves through a
/// [PreferencesApi]. Anything that drives the real editor needs all of it, so
/// it lives here rather than being copied per test file.
///
/// The save-and-read-back path is the useful part: [FakeEditorPreferences] is
/// what the editor persists into, so a test can assert on the JSON an operator
/// would actually get back on reload rather than on widget positions.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:beamer/beamer.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/secure_storage/secure_storage.dart';

import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/page_creator/assets/image_store.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/providers/page_images.dart';
import 'package:tfc/pages/page_editor.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/providers/alarm.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/page_manager.dart';
import 'package:tfc/route_registry.dart';

import 'test_helpers.dart' show FakeSecureStorage;

/// Minimal in-memory [PreferencesApi] so the editor can load and save.
/// Doubles as the read-back channel for [saveAndReadBack].
class FakeEditorPreferences implements PreferencesApi {
  final Map<String, Object> _store = {};

  @override
  Future<String?> getString(String key) async => _store[key] as String?;
  @override
  Future<void> setString(String key, String value) async => _store[key] = value;
  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      _store.keys.toSet();
  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) async =>
      Map.from(_store);
  @override
  Future<bool?> getBool(String key) async => _store[key] as bool?;
  @override
  Future<int?> getInt(String key) async => _store[key] as int?;
  @override
  Future<double?> getDouble(String key) async => _store[key] as double?;
  @override
  Future<List<String>?> getStringList(String key) async =>
      _store[key] as List<String>?;
  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);
  @override
  Future<void> setBool(String key, bool value) async => _store[key] = value;
  @override
  Future<void> setInt(String key, int value) async => _store[key] = value;
  @override
  Future<void> setDouble(String key, double value) async => _store[key] = value;
  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _store[key] = value;
  @override
  Future<void> remove(String key) async => _store.remove(key);
  @override
  Future<void> clear({Set<String>? allowList}) async {
    if (allowList == null) {
      _store.clear();
    } else {
      _store.removeWhere((k, _) => allowList.contains(k));
    }
  }
}

/// A box at ([x], [y]). Deliberately non-square, so orientation is visible in
/// the persisted extents and not just the coordinates.
DrawnBoxConfig editorBox(double x, double y, {double? angle}) {
  return DrawnBoxConfig.preview()
    ..coordinates = Coordinates(x: x, y: y, angle: angle)
    ..size = const RelativeSize(width: 0.12, height: 0.06);
}

/// A one-page manager holding [assets], saving into [prefs].
PageManager editorManagerWith(List<Asset> assets, FakeEditorPreferences prefs) {
  return PageManager(
    prefs: prefs,
    pages: {
      '/': AssetPage(
        menuItem: const MenuItem(label: 'Home', path: '/', icon: Icons.home),
        assets: assets,
        mirroringDisabled: true,
        navigationPriority: 0,
      ),
    },
  );
}

/// The editor lives inside `BaseScaffold`, which reads the current Beamer
/// location during build, so it needs a router above it.
class _EditorLocation extends BeamLocation<BeamState> {
  _EditorLocation()
      : super(RouteInformation(uri: Uri.parse('/advanced/page-editor')));

  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) => const [
        BeamPage(key: ValueKey('page-editor'), child: PageEditor()),
      ];

  @override
  List<Pattern> get pathPatterns => ['/advanced/page-editor'];
}

/// The real [PageEditor], wired up enough to pump.
///
/// [theme] is only worth passing for goldens, where the point is to review the
/// editor as the plant sees it; behaviour tests leave it null and get the
/// Material default.
Widget buildEditorUnderTest(PageManager manager, {ThemeData? theme}) {
  final routerDelegate = BeamerDelegate(
    locationBuilder: (routeInformation, _) => _EditorLocation(),
  );
  return ProviderScope(
    overrides: [
      pageManagerProvider.overrideWith((ref) async => manager),
      // Image blobs go where the pages go, so saveAndReadBack-style tests
      // see pages and their image bytes in one fake store.
      pageImageStoreProvider
          .overrideWith((ref) async => PageImageStore(manager.prefs)),
      // Keep the editor off the database / PLC / alarm stack: BaseScaffold
      // only needs these to decide between the clock and the alarm banner.
      databaseProvider.overrideWith((ref) async => null),
      alarmManProvider
          .overrideWith((ref) => throw StateError('No AlarmMan in tests')),
    ],
    child: BeamerProvider(
      routerDelegate: routerDelegate,
      child: MaterialApp.router(
        theme: theme,
        routerDelegate: routerDelegate,
        routeInformationParser: BeamerParser(),
      ),
    ),
  );
}

/// Per-test setup the editor needs before it will pump.
void setUpEditorEnvironment() {
  // The asset canvas constructs SharedPreferencesAsync directly.
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  // IO-module configs kick off stateManProvider, which builds the real
  // Preferences and asks for SecureStorage. Linux and macOS fall back to
  // AwsSecureStorage, but Windows throws unless main() has registered an
  // instance — so without this the exception lands asynchronously in
  // whichever test is running, on Windows only.
  SecureStorage.setInstance(FakeSecureStorage());

  // BaseScaffold renders a NavigationBar from the registry, which asserts on
  // fewer than two destinations.
  final registry = RouteRegistry();
  registry.menuItems.clear();
  registry
      .addMenuItem(const MenuItem(label: 'Home', path: '/', icon: Icons.home));
  registry.addMenuItem(const MenuItem(
      label: 'Advanced', path: '/advanced', icon: Icons.settings));
}

/// Pumps the editor with [assets] on the home page, at 1400x1000 unless
/// [size] says otherwise — the goldens use a real 1080p panel instead.
Future<FakeEditorPreferences> pumpEditorWith(
  WidgetTester tester,
  List<Asset> assets, {
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final prefs = FakeEditorPreferences();
  await tester
      .pumpWidget(buildEditorUnderTest(editorManagerWith(assets, prefs)));
  await tester.pumpAndSettle();
  return prefs;
}

/// A point at relative ([fx], [fy]) within the rendered canvas.
Offset onCanvas(WidgetTester tester, double fx, double fy) {
  final r = tester.getRect(find.byType(AssetStack));
  return Offset(r.left + r.width * fx, r.top + r.height * fy);
}

/// The canvas's width / height, recovered from the live layout.
double canvasAspect(WidgetTester tester) {
  final r = tester.getRect(find.byType(AssetStack));
  return r.width / r.height;
}

/// Rubber-bands from ([x1], [y1]) to ([x2], [y2]) in canvas-relative units.
///
/// No mode to enter first: the editor rubber-bands on any drag that starts on
/// empty canvas.
Future<void> marquee(
    WidgetTester tester, double x1, double y1, double x2, double y2) async {
  final gesture = await tester.startGesture(onCanvas(tester, x1, y1));
  await tester.pump();
  // Two moves: the first crosses the slop, the second lands on the corner.
  await gesture.moveTo(onCanvas(tester, (x1 + x2) / 2, (y1 + y2) / 2));
  await tester.pump();
  await gesture.moveTo(onCanvas(tester, x2, y2));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Opens the canvas context menu over the asset at relative ([fx], [fy]) and
/// taps the entry labelled [label].
Future<void> chooseFromAssetMenu(
    WidgetTester tester, double fx, double fy, String label) async {
  await tester.tapAt(onCanvas(tester, fx, fy), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  expect(find.text(label), findsOneWidget,
      reason: 'the context menu should offer "$label"');
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// The multi-select / shortcut modifier, which the editor picks from
/// `Platform` — Cmd on macOS, Ctrl elsewhere — so the test has to match.
LogicalKeyboardKey get editorModifier => Platform.isMacOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

/// Presses the editor's undo shortcut.
Future<void> pressUndo(WidgetTester tester) async {
  await tester.sendKeyDownEvent(editorModifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(editorModifier);
  await tester.pumpAndSettle();
}

/// Taps [key] on the canvas, optionally with Shift held.
Future<void> pressEditorKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

/// Rotates the selection a quarter turn from the keyboard.
Future<void> pressRotate(WidgetTester tester,
        {bool counterClockwise = false}) =>
    pressEditorKey(tester, LogicalKeyboardKey.keyR, shift: counterClockwise);

/// Clicks the asset at relative ([fx], [fy]) to select it. With
/// [addToSelection] the modifier is held, which toggles it into or out of the
/// existing selection instead of replacing it.
Future<void> tapAsset(
  WidgetTester tester,
  double fx,
  double fy, {
  bool addToSelection = false,
}) async {
  if (addToSelection) await tester.sendKeyDownEvent(editorModifier);
  await tester.tapAt(onCanvas(tester, fx, fy));
  if (addToSelection) await tester.sendKeyUpEvent(editorModifier);
  await tester.pumpAndSettle();
}

/// How many assets the editor currently has selected, counted off the
/// selection borders the canvas paints. `AssetStack` wraps exactly the
/// selected assets in a bordered container, so this reads the same state the
/// operator sees.
int selectedCount(WidgetTester tester) {
  return find
      .descendant(
        of: find.byType(AssetStack),
        matching: find.byKey(selectionBorderKey),
      )
      .evaluate()
      .length;
}

/// Saves, then returns the persisted assets of the home page in page order.
Future<List<Map<String, dynamic>>> saveAndReadBack(
    WidgetTester tester, FakeEditorPreferences prefs) async {
  await tester.tap(find.byIcon(Icons.save));
  await tester.pumpAndSettle();

  // The manager writes the whole page map under a single key; find the entry
  // that parses as one and contains our page.
  for (final value in prefs._store.values) {
    if (value is! String) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      continue; // e.g. a base64 image blob
    }
    if (decoded is! Map<String, dynamic>) continue;
    final page = decoded['/'];
    if (page is Map<String, dynamic> && page['assets'] is List) {
      return (page['assets'] as List).cast<Map<String, dynamic>>();
    }
  }
  fail('no saved page found in preferences: ${prefs._store.keys}');
}

/// The `coordinates` block of a persisted asset.
Map<String, dynamic> coordsOf(Map<String, dynamic> asset) =>
    asset['coordinates'] as Map<String, dynamic>;

/// The persisted x of each asset, in page order.
List<double> savedXs(List<Map<String, dynamic>> saved) =>
    [for (final a in saved) coordsOf(a)['x'] as double];

/// The persisted y of each asset, in page order.
List<double> savedYs(List<Map<String, dynamic>> saved) =>
    [for (final a in saved) coordsOf(a)['y'] as double];
