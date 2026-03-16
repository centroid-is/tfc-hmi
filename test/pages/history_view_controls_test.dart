// Test: History View header controls do not overflow on narrow widths.
//
// The top controls bar (Table/Graph toggle, Realtime/Historical toggle,
// Window selector) previously overflowed to the right on narrow screens
// (yellow/black hazard stripes, "RIGHT OVERFLOWED BY 73+13 pixels").
//
// These tests use a reproduction widget that mirrors the exact layout of
// _buildTopControls so they can run without the heavyweight HistoryViewPage
// provider graph (which requires a live StateMan / OPC UA stack).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Reproduction of the BROKEN layout (Row with fixed-size children, no Wrap).
// Used to confirm the test *detects* overflow before the fix.
// ---------------------------------------------------------------------------
Widget _buildBrokenControls({required double width}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          // Mirrors _buildTopControls exactly — Row, no Flexible/Wrap.
          child: Row(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Table')),
                  ButtonSegment(value: 0, label: Text('Graph')),
                ],
                selected: const {0},
                onSelectionChanged: (_) {},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              // add graph icon button (graph mode only)
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add_chart, size: 20),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Realtime')),
                  ButtonSegment(value: false, label: Text('Historical')),
                ],
                selected: const {true},
                onSelectionChanged: (_) {},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              // Window chip — InkWell with fixed content.
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {},
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withAlpha(80)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 14),
                      SizedBox(width: 6),
                      Text('Window: 10m 00s',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Fixed layout: uses Wrap instead of Row so controls reflow on narrow widths.
// ---------------------------------------------------------------------------
Widget _buildFixedControls({required double width}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Table')),
                  ButtonSegment(value: 0, label: Text('Graph')),
                ],
                selected: const {0},
                onSelectionChanged: (_) {},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add_chart, size: 20),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Realtime')),
                  ButtonSegment(value: false, label: Text('Historical')),
                ],
                selected: const {true},
                onSelectionChanged: (_) {},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              // Window chip.
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {},
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withAlpha(80)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 14),
                      SizedBox(width: 6),
                      Text('Window: 10m 00s',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Collect RenderFlex overflow errors during a test.
List<FlutterErrorDetails> _collectOverflowErrors(
    void Function() testBody) {
  // Not used directly; we use a tearUp/tearDown pattern instead.
  throw UnimplementedError();
}

void main() {
  group('HistoryViewPage header controls — overflow regression', () {
    final List<FlutterErrorDetails> overflowErrors = [];

    setUp(() {
      overflowErrors.clear();
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          overflowErrors.add(details);
        }
        // Don't re-throw; we're detecting, not crashing.
      };
    });

    tearDown(() {
      FlutterError.onError = FlutterError.presentError;
    });

    // ------------------------------------------------------------------
    // Tests for the FIXED layout — these should always pass.
    // ------------------------------------------------------------------
    group('fixed layout (Wrap) — no overflow expected', () {
      testWidgets('400px wide: no overflow', (tester) async {
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildFixedControls(width: 400));
        await tester.pump();

        expect(overflowErrors, isEmpty,
            reason:
                'Wrap-based layout must not overflow at 400px wide. '
                'Errors: ${overflowErrors.map((e) => e.exceptionAsString()).join('; ')}');
      });

      testWidgets('600px wide: no overflow', (tester) async {
        tester.view.physicalSize = const Size(600, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildFixedControls(width: 600));
        await tester.pump();

        expect(overflowErrors, isEmpty,
            reason:
                'Wrap-based layout must not overflow at 600px wide. '
                'Errors: ${overflowErrors.map((e) => e.exceptionAsString()).join('; ')}');
      });

      testWidgets('800px wide: no overflow', (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildFixedControls(width: 800));
        await tester.pump();

        expect(overflowErrors, isEmpty,
            reason:
                'Wrap-based layout must not overflow at 800px wide. '
                'Errors: ${overflowErrors.map((e) => e.exceptionAsString()).join('; ')}');
      });

      testWidgets('all four control groups are present in widget tree',
          (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildFixedControls(width: 800));
        await tester.pump();

        // Table/Graph toggle.
        expect(find.text('Table'), findsOneWidget);
        expect(find.text('Graph'), findsOneWidget);

        // Realtime/Historical toggle.
        expect(find.text('Realtime'), findsOneWidget);
        expect(find.text('Historical'), findsOneWidget);

        // Window chip.
        expect(find.textContaining('Window:'), findsOneWidget);

        // Add graph icon.
        expect(find.byIcon(Icons.add_chart), findsOneWidget);
      });
    });

    // ------------------------------------------------------------------
    // Regression documentation: the BROKEN Row layout overflows at 400px.
    // This test confirms the test infrastructure detects overflow correctly.
    // Flutter test binding captures overflow assertions as exceptions on the
    // tester; we use tester.takeException() to read them.
    // (The broken layout is NOT the production code after the fix.)
    // ------------------------------------------------------------------
    group('broken layout (Row) — overflow detection sanity check', () {
      testWidgets('400px wide: broken Row layout overflows (expected failure)',
          (tester) async {
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildBrokenControls(width: 400));
        await tester.pump();

        // The overflow renders as a FlutterError assertion captured by
        // the test binding. tester.takeException() returns it.
        final exception = tester.takeException();
        expect(exception, isNotNull,
            reason:
                'The pre-fix Row layout was expected to overflow at 400px '
                '(yellow/black hazard stripes). If this is null, the sanity '
                'check layout must be adjusted.');
        expect(exception.toString(), contains('overflowed'),
            reason: 'Exception should be a RenderFlex overflow, got: $exception');
      });
    });
  });
}
