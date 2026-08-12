import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/drawings/drawing_overlay.dart';

/// Regression tests for Marionette semantic keys.
///
/// Marionette's KeyMatcher uses ValueKey<String> to reliably target widgets.
/// These tests ensure that all critical interactive widgets have their
/// semantic keys annotated. If someone removes a key, the test fails.
void main() {
  // Resolve the project root directory. Tests run from centroid-hmi/, so
  // source files at lib/ are actually at ../lib/ relative to cwd.
  // We detect the root by looking for the pubspec.yaml in the parent dir.
  final cwd = Directory.current.path;
  final projectRoot = cwd.endsWith('centroid-hmi')
      ? Directory.current.parent.path
      : cwd;

  String projectFile(String relativePath) =>
      '$projectRoot/$relativePath';

  // Drawing overlay needs a large viewport (default 600x700 + 80px margin).
  const testSize = Size(1024, 900);

  // ---- Drawing Overlay keys ----

  group('Drawing Overlay keys', () {
    Widget buildDrawingOverlay() {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Stack(children: const [DrawingOverlay()]),
          ),
        ),
      );
    }

    testWidgets('drawing-close-button key exists', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildDrawingOverlay());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('drawing-close-button')),
        findsOneWidget,
      );
    });

  });

  // ---- Source file key assertions ----
  // For widgets that are hard to pump in isolation, verify keys via
  // source grep.

  group('Source file key assertions', () {
    test('drawing_overlay.dart contains drawing-close-button ValueKey',
        () {
      final source =
          File(projectFile('lib/drawings/drawing_overlay.dart')).readAsStringSync();
      expect(
          source, contains("ValueKey<String>('drawing-close-button')"));
    });

    test('drawing_overlay.dart does NOT contain drawing-minimize-button', () {
      final source =
          File(projectFile('lib/drawings/drawing_overlay.dart')).readAsStringSync();
      expect(source, isNot(contains('drawing-minimize-button')));
    });
  });
}
