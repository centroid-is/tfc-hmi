import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart'
    show PlcAssetSummary;

import 'package:tfc/plc/plc_code_picker.dart';
import 'package:tfc/providers/plc.dart';

void main() {
  final sampleSummaries = [
    PlcAssetSummary(
      assetKey: 'pump-001',
      blockCount: 3,
      variableCount: 10,
      lastIndexedAt: DateTime(2026, 1, 1),
      blockTypeCounts: {'FunctionBlock': 2, 'GVL': 1},
    ),
    PlcAssetSummary(
      assetKey: 'conveyor-002',
      blockCount: 5,
      variableCount: 22,
      lastIndexedAt: DateTime(2026, 1, 2),
      blockTypeCounts: {'FunctionBlock': 3, 'Program': 1, 'GVL': 1},
    ),
    PlcAssetSummary(
      assetKey: 'mixer-003',
      blockCount: 1,
      variableCount: 4,
      lastIndexedAt: DateTime(2026, 1, 3),
      blockTypeCounts: {'FunctionBlock': 1},
    ),
  ];

  Widget buildTestWidget({
    String? selectedAssetKey,
    ValueChanged<String?>? onChanged,
    bool enabled = true,
    List<PlcAssetSummary> summaries = const [],
  }) {
    return ProviderScope(
      overrides: [
        plcAssetSummaryProvider.overrideWith((_) async => summaries),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PlcCodePicker(
              selectedAssetKey: selectedAssetKey,
              onChanged: onChanged ?? (_) {},
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
  }

  group('PlcCodePicker', () {
    testWidgets('shows "No PLC code indexed" when summary list is empty',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(summaries: []));
      await tester.pumpAndSettle();

      expect(find.text('No PLC code indexed'), findsOneWidget);
    });

    testWidgets('shows available PLC assets in dropdown', (tester) async {
      await tester.pumpWidget(buildTestWidget(summaries: sampleSummaries));
      await tester.pumpAndSettle();

      // Tap to open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // All asset keys should be visible (each appears twice: in dropdown
      // button and in the menu overlay)
      expect(
        find.textContaining('pump-001'),
        findsWidgets,
      );
      expect(
        find.textContaining('conveyor-002'),
        findsWidgets,
      );
      expect(
        find.textContaining('mixer-003'),
        findsWidgets,
      );
    });

    testWidgets('selecting an asset calls onChanged with asset key',
        (tester) async {
      String? selectedKey;
      await tester.pumpWidget(buildTestWidget(
        summaries: sampleSummaries,
        onChanged: (key) => selectedKey = key,
      ));
      await tester.pumpAndSettle();

      // Open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Tap on conveyor-002 entry (the one in the overlay menu, last match)
      await tester.tap(find.textContaining('conveyor-002').last);
      await tester.pumpAndSettle();

      expect(selectedKey, equals('conveyor-002'));
    });

    testWidgets('shows "None" option to clear selection', (tester) async {
      String? selectedKey = 'pump-001';
      await tester.pumpWidget(buildTestWidget(
        summaries: sampleSummaries,
        selectedAssetKey: 'pump-001',
        onChanged: (key) => selectedKey = key,
      ));
      await tester.pumpAndSettle();

      // Open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // "None" option should be present
      expect(find.text('None'), findsOneWidget);

      // Tap "None" to clear
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

      expect(selectedKey, isNull);
    });

    testWidgets('shows selected asset key when selectedAssetKey is set',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        summaries: sampleSummaries,
        selectedAssetKey: 'conveyor-002',
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('conveyor-002'), findsOneWidget);
    });

    testWidgets('shows block and variable counts in dropdown items',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(summaries: sampleSummaries));
      await tester.pumpAndSettle();

      // Open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Verify detail text is shown
      expect(find.textContaining('3 blocks'), findsWidgets);
      expect(find.textContaining('10 vars'), findsWidgets);
      expect(find.textContaining('5 blocks'), findsWidgets);
      expect(find.textContaining('22 vars'), findsWidgets);
    });

    testWidgets('shows loading state', (tester) async {
      final completer = Completer<List<PlcAssetSummary>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plcAssetSummaryProvider
                .overrideWith((_) => completer.future),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: PlcCodePicker(
                  selectedAssetKey: null,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      // Only pump once — do NOT pumpAndSettle, so the future stays pending.
      await tester.pump();

      expect(find.text('Loading...'), findsOneWidget);

      // Complete to avoid dangling future.
      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('shows error state', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plcAssetSummaryProvider.overrideWith((_) async {
              throw Exception('DB error');
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: PlcCodePicker(
                  selectedAssetKey: null,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error loading PLC assets'), findsOneWidget);
    });
  });
}
