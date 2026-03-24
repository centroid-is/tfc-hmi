import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tfc/drawings/drawing_overlay.dart';
import 'package:tfc/widgets/resizable_overlay_frame.dart';

/// Tests for overlay bounds clamping — ensures the DrawingOverlay cannot be
/// dragged or resized outside the window/screen bounds.
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

  void setupViewport(WidgetTester tester) {
    tester.view.physicalSize = testSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('DrawingOverlay drag bounds clamping', () {
    testWidgets('dragging left beyond screen clamps position.dx to 0',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));
      final initialPosition = state.position;

      // Drag far to the left (beyond the screen edge)
      final titleBar = find.text('Electrical Drawing');
      await tester.drag(titleBar, Offset(-initialPosition.dx - 200, 0));
      await tester.pumpAndSettle();

      expect(state.position.dx, 0.0,
          reason: 'position.dx should be clamped to 0 (left edge)');
    });

    testWidgets('dragging up beyond screen clamps position.dy to 0',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));
      final initialPosition = state.position;

      // Drag far upward (beyond the screen top)
      final titleBar = find.text('Electrical Drawing');
      await tester.drag(titleBar, Offset(0, -initialPosition.dy - 200));
      await tester.pumpAndSettle();

      expect(state.position.dy, 0.0,
          reason: 'position.dy should be clamped to 0 (top edge)');
    });

    testWidgets(
        'dragging right beyond screen clamps so overlay stays within bounds',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));

      // Drag far to the right (beyond the screen right edge)
      final titleBar = find.text('Electrical Drawing');
      await tester.drag(titleBar, const Offset(2000, 0));
      await tester.pumpAndSettle();

      final maxX = testSize.width - state.size.width;
      expect(state.position.dx, maxX,
          reason:
              'position.dx should be clamped so right edge is at screen edge');
    });

    testWidgets(
        'dragging down beyond screen clamps so overlay stays within bounds',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));

      // Drag far downward (beyond the screen bottom edge)
      final titleBar = find.text('Electrical Drawing');
      await tester.drag(titleBar, const Offset(0, 2000));
      await tester.pumpAndSettle();

      final maxY = testSize.height - state.size.height;
      expect(state.position.dy, maxY,
          reason:
              'position.dy should be clamped so bottom edge is at screen edge');
    });
  });

  group('DrawingOverlay resize bounds clamping', () {
    testWidgets('resizing wider than screen is clamped to available space',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));
      final posX = state.position.dx;
      final maxAllowedWidth = testSize.width - posX;

      // Drag from the bottom-right corner of the overlay
      final bottomRight = Offset(
        state.position.dx + state.size.width - 4,
        state.position.dy + state.size.height - 4,
      );
      await tester.dragFrom(bottomRight, const Offset(2000, 0));
      await tester.pumpAndSettle();

      expect(state.size.width, maxAllowedWidth,
          reason:
              'Width should be clamped so right edge does not exceed screen');
    });

    testWidgets('resizing taller than screen is clamped to available space',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));
      final posY = state.position.dy;
      final maxAllowedHeight = testSize.height - posY;

      // Drag from the bottom-right corner of the overlay
      final bottomRight = Offset(
        state.position.dx + state.size.width - 4,
        state.position.dy + state.size.height - 4,
      );
      await tester.dragFrom(bottomRight, const Offset(0, 2000));
      await tester.pumpAndSettle();

      expect(state.size.height, maxAllowedHeight,
          reason:
              'Height should be clamped so bottom edge does not exceed screen');
    });

    testWidgets('resizing below minimum width is clamped',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));

      // Drag from the right edge of the overlay to the left
      final rightEdge = Offset(
        state.position.dx + state.size.width - 2,
        state.position.dy + state.size.height / 2,
      );
      await tester.dragFrom(rightEdge, const Offset(-2000, 0));
      await tester.pumpAndSettle();

      expect(state.size.width, DrawingOverlayState.minSize.width,
          reason: 'Width should not go below minSize.width');
    });

    testWidgets('resizing below minimum height is clamped',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));

      // Drag from the bottom edge of the overlay upward
      final bottomEdge = Offset(
        state.position.dx + state.size.width / 2,
        state.position.dy + state.size.height - 2,
      );
      await tester.dragFrom(bottomEdge, const Offset(0, -2000));
      await tester.pumpAndSettle();

      expect(state.size.height, DrawingOverlayState.minSize.height,
          reason: 'Height should not go below minSize.height');
    });
  });

  group('DrawingOverlay combined drag+resize bounds', () {
    testWidgets('after dragging to top-left corner, resize is bounded',
        (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(buildOverlayTestable());
      await tester.pumpAndSettle();

      final state =
          tester.state<DrawingOverlayState>(find.byType(DrawingOverlay));

      // First drag to top-left (0,0)
      final titleBar = find.text('Electrical Drawing');
      await tester.drag(titleBar, const Offset(-2000, -2000));
      await tester.pumpAndSettle();

      expect(state.position.dx, 0.0);
      expect(state.position.dy, 0.0);

      // Now resize from the bottom-right corner: max should be full screen
      final bottomRight = Offset(
        state.position.dx + state.size.width - 4,
        state.position.dy + state.size.height - 4,
      );
      await tester.dragFrom(bottomRight, const Offset(2000, 2000));
      await tester.pumpAndSettle();

      // The overlay's build() clamps max size to (screenSize - 16px margin),
      // so the resize handler may set full screen but the next build clamps it.
      const margin = 16.0;
      expect(state.size.width, testSize.width - margin,
          reason:
              'At position (0,0), max width should equal screen width minus build-time margin');
      expect(state.size.height, testSize.height - margin,
          reason:
              'At position (0,0), max height should equal screen height minus build-time margin');
    });
  });
}
