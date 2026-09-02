// Test: History View header controls do not overflow on narrow widths.
//
// The top controls bar (Table/Graph toggle, Realtime/Historical toggle,
// Window selector) previously overflowed to the right on narrow screens
// (yellow/black hazard stripes, "RIGHT OVERFLOWED BY 73+13 pixels").
//
// This used to drive a hand-copied replica of _buildTopControls because the
// monolithic page could not be pumped without a live StateMan / OPC UA
// stack. It now drives the real [HistoryViewBody] through the fakes in
// history_view_harness.dart — a replica can silently drift from the layout
// it claims to guard, and this one had.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'history_view_harness.dart';

void main() {
  group('HistoryViewBody — no overflow at narrow widths', () {
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

    // 700 is the practical floor: below that the fixed-flex left pane gets
    // too narrow for its own buttons (it always has) and the collapse rail
    // is the intended escape hatch. Station screens start at 1024.
    for (final width in [700.0, 900.0, 1100.0]) {
      testWidgets('${width.toInt()}px wide: no overflow', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(buildHistoryView(
          keyMappings: historyKeyMappings(),
          appDb: inMemoryAppDatabase(),
        ));
        await settleHistory(tester);

        expect(overflowErrors, isEmpty,
            reason: 'history view must reflow at ${width.toInt()}px wide. '
                'Errors: ${overflowErrors.map((e) => e.exceptionAsString()).join('; ')}');
      });
    }

    testWidgets('all control groups are present', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildHistoryView(
        keyMappings: historyKeyMappings(),
        appDb: inMemoryAppDatabase(),
      ));
      await settleHistory(tester);

      expect(find.text('Table'), findsOneWidget);
      expect(find.text('Graph'), findsOneWidget);
      expect(find.text('Realtime'), findsOneWidget);
      expect(find.text('Historical'), findsOneWidget);
      expect(find.textContaining('Window:'), findsOneWidget);
      expect(find.byIcon(Icons.add_chart), findsOneWidget);
    });
  });
}
