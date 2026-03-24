import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/chat/chat_overlay.dart';
import 'package:tfc/chat/chat_widget.dart';
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

  // ---- Chat Overlay keys ----

  group('Chat Overlay keys', () {
    Widget buildChatOverlay() {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Stack(children: const [ChatOverlay()]),
          ),
        ),
      );
    }

    testWidgets('chat-close-button key exists', (tester) async {
      await tester.pumpWidget(buildChatOverlay());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('chat-close-button')),
        findsOneWidget,
      );
    });

    testWidgets('chat-overflow-menu key exists', (tester) async {
      await tester.pumpWidget(buildChatOverlay());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('chat-overflow-menu')),
        findsOneWidget,
      );
    });
  });

  // ---- Chat Widget keys ----

  group('Chat Widget keys', () {
    Widget buildChatWidget() {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: const ChatWidget()),
        ),
      );
    }

    testWidgets('chat-provider-dropdown key exists', (tester) async {
      await tester.pumpWidget(buildChatWidget());
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('chat-provider-dropdown')),
        findsOneWidget,
      );
    });

    testWidgets('chat-message-input key exists', (tester) async {
      await tester.pumpWidget(buildChatWidget());
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('chat-message-input')),
        findsOneWidget,
      );
    });

    testWidgets('chat-send-button key exists', (tester) async {
      await tester.pumpWidget(buildChatWidget());
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('chat-send-button')),
        findsOneWidget,
      );
    });
  });

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
  // For widgets that are hard to pump in isolation (e.g., Chat FAB inside
  // MyApp with full Beamer/provider tree), verify keys via source grep.

  group('Source file key assertions', () {
    test('main.dart contains chat-fab ValueKey', () {
      final source =
          File(projectFile('centroid-hmi/lib/main.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-fab')"));
    });

    test('chat_overlay.dart contains chat-close-button ValueKey', () {
      final source = File(projectFile('lib/chat/chat_overlay.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-close-button')"));
    });

    test('chat_overlay.dart contains chat-overflow-menu ValueKey', () {
      final source = File(projectFile('lib/chat/chat_overlay.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-overflow-menu')"));
    });

    test('chat_overlay.dart does NOT contain chat-minimize-button', () {
      final source = File(projectFile('lib/chat/chat_overlay.dart')).readAsStringSync();
      expect(source, isNot(contains('chat-minimize-button')));
    });

    test('chat_widget.dart contains chat-provider-dropdown ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(
          source, contains("ValueKey<String>('chat-provider-dropdown')"));
    });

    test('chat_widget.dart contains chat-message-input ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-message-input')"));
    });

    test('chat_widget.dart contains chat-send-button ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-send-button')"));
    });

    test('chat_widget.dart contains chat-api-key-indicator ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(
          source, contains("ValueKey<String>('chat-api-key-indicator')"));
    });

    test('chat_widget.dart contains chat-api-key-field ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-api-key-field')"));
    });

    test('chat_widget.dart contains chat-base-url-field ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-base-url-field')"));
    });

    test('chat_widget.dart contains chat-api-key-cancel ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-api-key-cancel')"));
    });

    test('chat_widget.dart contains chat-api-key-save ValueKey', () {
      final source = File(projectFile('lib/chat/chat_widget.dart')).readAsStringSync();
      expect(source, contains("ValueKey<String>('chat-api-key-save')"));
    });

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
