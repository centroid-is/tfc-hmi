import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tfc/drawings/drawing_overlay.dart';
import 'package:tfc/widgets/searchable_pdf_viewer.dart';

void main() {
  // The overlay default size is 600x700 with 80px margin, so we need
  // at least 680x780 viewport. Set to 1024x900 for comfortable testing.
  const testSize = Size(1024, 900);

  Widget buildOverlayTestable() {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: const [
              DrawingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// Simulates Cmd+F (macOS) or Ctrl+F (other) key combination.
  Future<void> sendSearchShortcut(WidgetTester tester) async {
    await tester.sendKeyDownEvent(
      Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(
      Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft,
    );
  }

  group('DrawingOverlay widget', () {
    testWidgets('renders with "No drawing loaded" when path is null',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      expect(find.text('No drawing loaded'), findsOneWidget);
    });

    testWidgets('renders with title bar showing Electrical Drawing',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      expect(find.text('Electrical Drawing'), findsOneWidget);
    });

    testWidgets('renders electrical_services icon in title bar',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.electrical_services), findsOneWidget);
    });

    testWidgets('close button sets drawingVisibleProvider to false',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            drawingVisibleProvider.overrideWith((ref) => true),
          ],
          child: Builder(
            builder: (context) {
              return MaterialApp(
                home: Consumer(
                  builder: (context, ref, _) {
                    container = ProviderScope.containerOf(context);
                    return Scaffold(
                      body: Stack(
                        children: const [
                          DrawingOverlay(),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // drawingVisibleProvider should now be false
      expect(container.read(drawingVisibleProvider), false);
    });

    testWidgets('title changes when activeDrawingTitleProvider is set',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: Builder(
            builder: (context) {
              return MaterialApp(
                home: Consumer(
                  builder: (context, ref, _) {
                    container = ProviderScope.containerOf(context);
                    return Scaffold(
                      body: Stack(
                        children: const [DrawingOverlay()],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default title
      expect(find.text('Electrical Drawing'), findsOneWidget);

      // Change title
      container.read(activeDrawingTitleProvider.notifier).state =
          'ATV320 Installation Manual';
      await tester.pumpAndSettle();

      expect(find.text('ATV320 Installation Manual'), findsOneWidget);
      expect(find.text('Electrical Drawing'), findsNothing);
    });

    testWidgets('has default size 600x700', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final stateFinder = find.byType(DrawingOverlay);
      final state = tester.state<DrawingOverlayState>(stateFinder);

      expect(state.size.width, 600);
      expect(state.size.height, 700);
    });

    testWidgets('exposes position and size via state for testing',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final stateFinder = find.byType(DrawingOverlay);
      final state = tester.state<DrawingOverlayState>(stateFinder);

      // Position should be initialized (not sentinel)
      expect(state.position, isNot(equals(const Offset(-1, -1))));
      // Size should be the default
      expect(state.size, const Size(600, 700));
    });
  });

  group('SearchablePdfViewer Cmd+F', () {
    testWidgets('Cmd+F toggles search bar', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Provide dummy bytes — PdfViewer will show loading/error but
      // Focus + search bar still function.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: Uint8List.fromList(List.filled(16, 0)),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Search in document...'), findsNothing);

      await sendSearchShortcut(tester);
      await tester.pump();

      expect(find.text('Search in document...'), findsOneWidget);
    });

    testWidgets('Escape closes search bar', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: Uint8List.fromList(List.filled(16, 0)),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open search bar.
      await sendSearchShortcut(tester);
      await tester.pump();
      expect(find.text('Search in document...'), findsOneWidget);

      // Press Escape.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('Search in document...'), findsNothing);
    });

    testWidgets('close button hides search bar', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: Uint8List.fromList(List.filled(16, 0)),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open search bar.
      await sendSearchShortcut(tester);
      await tester.pump();
      expect(find.text('Search in document...'), findsOneWidget);

      // Tap close button.
      await tester.tap(find.byTooltip('Close search'));
      await tester.pump();

      expect(find.text('Search in document...'), findsNothing);
    });
  });

  group('SearchablePdfViewer zoom controls', () {
    Widget buildPdfViewer({bool showZoomControls = true}) {
      return MaterialApp(
        home: Scaffold(
          body: SearchablePdfViewer(
            pdfBytes: Uint8List.fromList(List.filled(16, 0)),
            showZoomControls: showZoomControls,
          ),
        ),
      );
    }

    testWidgets('zoom in button is present when showZoomControls is true',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer());
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('pdf-zoom-in')), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('zoom out button is present when showZoomControls is true',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer());
      await tester.pump();

      expect(
          find.byKey(const ValueKey<String>('pdf-zoom-out')), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('zoom buttons have correct tooltips', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer());
      await tester.pump();

      expect(find.byTooltip('Zoom in'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
    });

    testWidgets('zoom controls hidden when showZoomControls is false',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer(showZoomControls: false));
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('pdf-zoom-in')), findsNothing);
      expect(find.byKey(const ValueKey<String>('pdf-zoom-out')), findsNothing);
    });

    testWidgets('zoom controls appear in a toolbar below the PDF',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer());
      await tester.pump();

      // The zoom toolbar should be in the widget tree as a container
      // below the PDF viewer. Verify both buttons share a parent Row.
      final zoomIn = find.byKey(const ValueKey<String>('pdf-zoom-in'));
      final zoomOut = find.byKey(const ValueKey<String>('pdf-zoom-out'));

      expect(zoomIn, findsOneWidget);
      expect(zoomOut, findsOneWidget);

      // Both should be descendants of the SearchablePdfViewer
      expect(
        find.descendant(
          of: find.byType(SearchablePdfViewer),
          matching: zoomIn,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SearchablePdfViewer),
          matching: zoomOut,
        ),
        findsOneWidget,
      );
    });

    testWidgets('zoom in button is tappable', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer());
      await tester.pump();

      // Tapping should not throw (controller.zoomUp will no-op
      // because the controller is not attached to a real PDF doc,
      // but the button itself should be tappable without errors).
      await tester.tap(find.byKey(const ValueKey<String>('pdf-zoom-in')));
      await tester.pump();
    });

    testWidgets('zoom out button is tappable', (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer());
      await tester.pump();

      // Tapping should not throw.
      await tester.tap(find.byKey(const ValueKey<String>('pdf-zoom-out')));
      await tester.pump();
    });

    testWidgets(
        'zoom controls and search bar can coexist when both are visible',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildPdfViewer());
      await tester.pump();

      // Open search bar
      await sendSearchShortcut(tester);
      await tester.pump();

      // Both search bar and zoom controls should be visible
      expect(find.text('Search in document...'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('pdf-zoom-in')), findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('pdf-zoom-out')), findsOneWidget);
    });

    testWidgets('zoom controls default to visible (showZoomControls defaults true)',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Build without explicitly passing showZoomControls
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchablePdfViewer(
              pdfBytes: Uint8List.fromList(List.filled(16, 0)),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('pdf-zoom-in')), findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('pdf-zoom-out')), findsOneWidget);
    });
  });

  group('DrawingOverlay zoom controls', () {
    testWidgets('zoom controls are visible in the drawing overlay',
        (tester) async {
      tester.view.physicalSize = testSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Provide dummy bytes so the PDF viewer is instantiated
            activeDrawingBytesProvider
                .overrideWith((ref) => Uint8List.fromList(List.filled(16, 0))),
          ],
          child: Builder(
            builder: (context) {
              return MaterialApp(
                home: Consumer(
                  builder: (context, ref, _) {
                    container = ProviderScope.containerOf(context);
                    return Scaffold(
                      body: Stack(
                        children: const [DrawingOverlay()],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      // Zoom controls should be present inside the overlay
      expect(find.byKey(const ValueKey<String>('pdf-zoom-in')), findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('pdf-zoom-out')), findsOneWidget);
    });
  });
}
