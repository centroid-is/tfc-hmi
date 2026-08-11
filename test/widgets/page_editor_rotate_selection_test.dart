/// End-to-end cover for rotating a multi-selection in the page editor.
///
/// The maths lives in `rotateGroup` and is unit-tested in
/// test/pages/page_editor_rotate_group_test.dart. What those tests cannot see
/// is the wiring: that the context menu offers the entries, that they act on
/// the whole marquee selection rather than the asset under the cursor, that
/// the canvas aspect ratio actually reaches the maths, and that the result is
/// what gets persisted.
///
/// So this drives the real editor: marquee-select a row of boxes, right-click,
/// pick "Rotate 3 assets 90° clockwise", then read the saved JSON back.
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

import 'package:tfc/models/menu_item.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/drawn_box.dart';
import 'package:tfc/page_creator/page.dart';
import 'package:tfc/pages/page_editor.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/providers/alarm.dart';
import 'package:tfc/providers/database.dart';
import 'package:tfc/providers/page_manager.dart';
import 'package:tfc/route_registry.dart';

/// Minimal in-memory [PreferencesApi] so the editor can load and save.
/// Doubles as the read-back channel: whatever the save button writes here is
/// what the operator would get on reload.
class _FakePreferences implements PreferencesApi {
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

/// A box at ([x], [y]). Deliberately non-square so a quarter turn is visible
/// in the persisted extents as well as the coordinates.
DrawnBoxConfig _box(double x, double y, {double? angle}) {
  return DrawnBoxConfig.preview()
    ..coordinates = Coordinates(x: x, y: y, angle: angle)
    ..size = const RelativeSize(width: 0.12, height: 0.06);
}

PageManager _managerWith(List<Asset> assets, _FakePreferences prefs) {
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

Widget _buildEditor(PageManager manager) {
  final routerDelegate = BeamerDelegate(
    locationBuilder: (routeInformation, _) => _EditorLocation(),
  );
  return ProviderScope(
    overrides: [
      pageManagerProvider.overrideWith((ref) async => manager),
      // Keep the editor off the database / PLC / alarm stack: BaseScaffold
      // only needs these to decide between the clock and the alarm banner.
      databaseProvider.overrideWith((ref) async => null),
      alarmManProvider
          .overrideWith((ref) => throw StateError('No AlarmMan in tests')),
    ],
    child: BeamerProvider(
      routerDelegate: routerDelegate,
      child: MaterialApp.router(
        routerDelegate: routerDelegate,
        routeInformationParser: BeamerParser(),
      ),
    ),
  );
}

/// A point at relative ([fx], [fy]) within the rendered canvas.
Offset _onCanvas(WidgetTester tester, double fx, double fy) {
  final r = tester.getRect(find.byType(AssetStack));
  return Offset(r.left + r.width * fx, r.top + r.height * fy);
}

/// The canvas's width / height — the aspect ratio the rotation has to correct
/// for, recovered from the live layout rather than assumed.
double _canvasAspect(WidgetTester tester) {
  final r = tester.getRect(find.byType(AssetStack));
  return r.width / r.height;
}

/// Switches the editor from pan mode into marquee-select mode.
Future<void> _enterSelectMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.pan_tool));
  await tester.pumpAndSettle();
  expect(find.byIcon(Icons.select_all), findsOneWidget,
      reason: 'the mode button should now show select mode');
}

/// Rubber-bands from ([x1], [y1]) to ([x2], [y2]) in canvas-relative units.
Future<void> _marquee(
    WidgetTester tester, double x1, double y1, double x2, double y2) async {
  final gesture = await tester.startGesture(_onCanvas(tester, x1, y1));
  await tester.pump();
  // Two moves: the first crosses the slop, the second lands on the corner.
  await gesture.moveTo(_onCanvas(tester, (x1 + x2) / 2, (y1 + y2) / 2));
  await tester.pump();
  await gesture.moveTo(_onCanvas(tester, x2, y2));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Presses the editor's undo shortcut. It is keyboard-only, and the editor
/// picks the modifier from `Platform`, so the test has to match.
Future<void> _pressUndo(WidgetTester tester) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

/// Saves, then returns the persisted assets of the home page in page order.
Future<List<Map<String, dynamic>>> _saveAndReadBack(
    WidgetTester tester, _FakePreferences prefs) async {
  await tester.tap(find.byIcon(Icons.save));
  await tester.pumpAndSettle();

  // The manager writes the whole page map under a single key; find the entry
  // that parses as one and contains our page.
  for (final value in prefs._store.values) {
    if (value is! String) continue;
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) continue;
    final page = decoded['/'];
    if (page is Map<String, dynamic> && page['assets'] is List) {
      return (page['assets'] as List).cast<Map<String, dynamic>>();
    }
  }
  fail('no saved page found in preferences: ${prefs._store.keys}');
}

Map<String, dynamic> _coords(Map<String, dynamic> asset) =>
    asset['coordinates'] as Map<String, dynamic>;

void main() {
  setUp(() {
    // The asset canvas constructs SharedPreferencesAsync directly.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    // BaseScaffold renders a NavigationBar from the registry, which asserts on
    // fewer than two destinations.
    final registry = RouteRegistry();
    registry.menuItems.clear();
    registry.addMenuItem(
        const MenuItem(label: 'Home', path: '/', icon: Icons.home));
    registry.addMenuItem(const MenuItem(
        label: 'Advanced', path: '/advanced', icon: Icons.settings));
  });

  /// A row of three boxes across the middle of the canvas.
  Future<_FakePreferences> pumpRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final prefs = _FakePreferences();
    await tester.pumpWidget(_buildEditor(_managerWith(
      [_box(0.3, 0.5), _box(0.5, 0.5), _box(0.7, 0.5)],
      prefs,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(DrawnBox), findsNWidgets(3));
    return prefs;
  }

  testWidgets('rotates a marquee selection as a group', (tester) async {
    final prefs = await pumpRow(tester);
    final aspect = _canvasAspect(tester);
    // The spacing assertion below is only meaningful on a non-square canvas —
    // on a square one it would pass with the aspect handling ripped out.
    expect(aspect, greaterThan(1.5),
        reason: 'the editor canvas should be wide (it renders 16:9)');

    await _enterSelectMode(tester);
    await _marquee(tester, 0.15, 0.3, 0.85, 0.7);

    // Right-click the middle box. The label proves all three are selected —
    // if the marquee had missed, this would read "Rotate 90° clockwise".
    await tester.tapAt(_onCanvas(tester, 0.5, 0.5), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Rotate 3 assets 90° clockwise'), findsOneWidget);

    await tester.tap(find.text('Rotate 3 assets 90° clockwise'));
    await tester.pumpAndSettle();

    final saved = await _saveAndReadBack(tester, prefs);
    expect(saved, hasLength(3));

    // The row is now a column through the group's centre.
    for (final asset in saved) {
      expect(_coords(asset)['x'] as double, closeTo(0.5, 1e-9));
    }

    // Clockwise: the leftmost box is now the topmost.
    final ys = [for (final a in saved) _coords(a)['y'] as double];
    expect(ys[0], lessThan(ys[1]));
    expect(ys[1], lessThan(ys[2]));

    // The spacing is preserved *in pixels*, which is the whole point of the
    // aspect correction: 0.2 of the canvas width has to become 0.2 * aspect
    // of its height. Without the correction this would come out as 0.2.
    expect(ys[1] - ys[0], closeTo(0.2 * aspect, 1e-9));
    expect(ys[2] - ys[1], closeTo(0.2 * aspect, 1e-9));

    // ...and every box spun, not just orbited.
    for (final asset in saved) {
      expect(_coords(asset)['angle'], 90);
    }
  });

  testWidgets('rotating back restores the original layout', (tester) async {
    final prefs = await pumpRow(tester);

    await _enterSelectMode(tester);
    await _marquee(tester, 0.15, 0.3, 0.85, 0.7);

    Future<void> rotate(String label) async {
      await tester.tapAt(_onCanvas(tester, 0.5, 0.5),
          buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await rotate('Rotate 3 assets 90° clockwise');
    // The selection survives the rotation, so the second turn hits the same
    // three assets — worth asserting, since losing it would silently make the
    // menu act on one box.
    await rotate('Rotate 3 assets 90° counter-clockwise');

    final saved = await _saveAndReadBack(tester, prefs);
    final xs = [for (final a in saved) _coords(a)['x'] as double];
    final ys = [for (final a in saved) _coords(a)['y'] as double];

    expect(xs[0], closeTo(0.3, 1e-9));
    expect(xs[1], closeTo(0.5, 1e-9));
    expect(xs[2], closeTo(0.7, 1e-9));
    for (final y in ys) {
      expect(y, closeTo(0.5, 1e-9));
    }
    // Back to "never rotated", so mirrored pages behave as they did before.
    for (final asset in saved) {
      expect(_coords(asset)['angle'], isNull);
    }
  });

  testWidgets('undo reverts a group rotation in one step', (tester) async {
    final prefs = await pumpRow(tester);

    await _enterSelectMode(tester);
    await _marquee(tester, 0.15, 0.3, 0.85, 0.7);

    await tester.tapAt(_onCanvas(tester, 0.5, 0.5), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate 3 assets 90° clockwise'));
    await tester.pumpAndSettle();

    await _pressUndo(tester);

    final saved = await _saveAndReadBack(tester, prefs);
    expect([for (final a in saved) _coords(a)['x'] as double],
        [closeTo(0.3, 1e-9), closeTo(0.5, 1e-9), closeTo(0.7, 1e-9)]);
    for (final asset in saved) {
      expect(_coords(asset)['angle'], isNull);
    }
  });

  testWidgets('an unselected asset rotates on its own', (tester) async {
    // Outside select mode there is no selection, so the menu acts on just the
    // asset under the cursor — and a single asset spins in place.
    final prefs = await pumpRow(tester);

    await tester.tapAt(_onCanvas(tester, 0.3, 0.5), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Rotate 90° clockwise'), findsOneWidget,
        reason: 'no selection, so the label should be singular');

    await tester.tap(find.text('Rotate 90° clockwise'));
    await tester.pumpAndSettle();

    final saved = await _saveAndReadBack(tester, prefs);
    expect(_coords(saved[0])['angle'], 90);
    expect(_coords(saved[0])['x'] as double, closeTo(0.3, 1e-9));
    expect(_coords(saved[0])['y'] as double, closeTo(0.5, 1e-9));

    // The other two are untouched.
    expect(_coords(saved[1])['angle'], isNull);
    expect(_coords(saved[2])['angle'], isNull);
  });
}
