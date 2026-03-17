import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/widgets/searchable_pdf_viewer.dart';

void main() {
  const testSize = Size(1024, 900);

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

  /// Dispatches a [PointerScrollEvent] at the center of the given finder.
  ///
  /// [scrollDelta] is the scroll amount (positive Y = scroll down).
  Future<void> sendScrollEvent(
    WidgetTester tester,
    Finder target, {
    Offset scrollDelta = const Offset(0, -100),
  }) async {
    final center = tester.getCenter(target);
    final event = PointerScrollEvent(
      position: center,
      scrollDelta: scrollDelta,
    );
    GestureBinding.instance.handlePointerEvent(event);
    await tester.pump();
  }

  group('SearchablePdfViewer Cmd/Ctrl+scroll wheel zoom', () {
    testWidgets(
      'has a dedicated scroll-zoom Listener with ValueKey',
      (tester) async {
        tester.view.physicalSize = testSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildPdfViewer());
        await tester.pump();

        // The SearchablePdfViewer should have a Listener widget keyed
        // 'pdf-scroll-zoom-listener' that intercepts Cmd+scroll on macOS.
        expect(
          find.byKey(const ValueKey<String>('pdf-scroll-zoom-listener')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'on macOS, Meta+scroll down triggers zoom out (does not throw)',
      (tester) async {
        tester.view.physicalSize = testSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildPdfViewer());
        await tester.pump();

        // Hold down Meta (Cmd on macOS)
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);

        // Send scroll down event (positive dy = scroll down = zoom out).
        // This should not throw even though the controller is not attached
        // to a real PDF document.
        await sendScrollEvent(
          tester,
          find.byType(SearchablePdfViewer),
          scrollDelta: const Offset(0, 100),
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();

        // If we got here without an exception, the Listener correctly
        // handled the Cmd+scroll event (the controller's zoomDown
        // is a no-op when not attached to a real PDF).
      },
      skip: !Platform.isMacOS,
    );

    testWidgets(
      'on macOS, Meta+scroll up triggers zoom in (does not throw)',
      (tester) async {
        tester.view.physicalSize = testSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildPdfViewer());
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);

        // Send scroll up event (negative dy = scroll up = zoom in)
        await sendScrollEvent(
          tester,
          find.byType(SearchablePdfViewer),
          scrollDelta: const Offset(0, -100),
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      },
      skip: !Platform.isMacOS,
    );

    testWidgets(
      'scroll without modifier key does not trigger zoom (normal scroll)',
      (tester) async {
        tester.view.physicalSize = testSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildPdfViewer());
        await tester.pump();

        // Send scroll event without any modifier key -- should not crash
        // and should pass through to pdfrx for normal scrolling.
        await sendScrollEvent(
          tester,
          find.byType(SearchablePdfViewer),
          scrollDelta: const Offset(0, 100),
        );
      },
    );

    testWidgets(
      'Ctrl+scroll on any platform triggers pdfrx built-in zoom (no crash)',
      (tester) async {
        tester.view.physicalSize = testSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildPdfViewer());
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);

        // pdfrx handles Ctrl+scroll natively. Verify no crash.
        await sendScrollEvent(
          tester,
          find.byType(SearchablePdfViewer),
          scrollDelta: const Offset(0, -100),
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      },
    );

    testWidgets(
      'zoom via Cmd+scroll and zoom toolbar buttons can coexist',
      (tester) async {
        tester.view.physicalSize = testSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildPdfViewer());
        await tester.pump();

        // Zoom toolbar buttons should be present
        expect(
          find.byKey(const ValueKey<String>('pdf-zoom-in')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('pdf-zoom-out')),
          findsOneWidget,
        );

        // Tapping zoom buttons should still work
        await tester.tap(find.byKey(const ValueKey<String>('pdf-zoom-in')));
        await tester.pump();

        if (Platform.isMacOS) {
          // Cmd+scroll should also work without conflict
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await sendScrollEvent(
            tester,
            find.byType(SearchablePdfViewer),
            scrollDelta: const Offset(0, -100),
          );
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
        }
      },
    );

    testWidgets(
      'zoom via scroll and search bar can coexist',
      (tester) async {
        tester.view.physicalSize = testSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(buildPdfViewer());
        await tester.pump();

        // Open search bar with Cmd/Ctrl+F
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
        await tester.pump();

        expect(find.text('Search in document...'), findsOneWidget);

        // Zoom should still work with search bar open
        if (Platform.isMacOS) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await sendScrollEvent(
            tester,
            find.byType(SearchablePdfViewer),
            scrollDelta: const Offset(0, -100),
          );
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
        }

        // Search bar should still be visible
        expect(find.text('Search in document...'), findsOneWidget);
      },
    );
  });
}
