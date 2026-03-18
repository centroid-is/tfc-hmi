import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart';

import 'package:tfc/tech_docs/tech_doc_picker.dart';
import 'package:tfc/providers/tech_doc.dart';

void main() {
  final sampleDocs = [
    TechDocSummary(
      id: 1,
      name: 'ATV320 User Manual',
      pageCount: 120,
      sectionCount: 15,
      uploadedAt: DateTime(2026, 1, 1),
    ),
    TechDocSummary(
      id: 2,
      name: 'PT100 Sensor Datasheet',
      pageCount: 4,
      sectionCount: 3,
      uploadedAt: DateTime(2026, 1, 2),
    ),
    TechDocSummary(
      id: 3,
      name: 'Beckhoff CX5010 Quick Start',
      pageCount: 30,
      sectionCount: 8,
      uploadedAt: DateTime(2026, 1, 3),
    ),
  ];

  Widget buildTestWidget({
    int? selectedDocId,
    ValueChanged<int?>? onChanged,
    bool enabled = true,
    List<TechDocSummary> docs = const [],
  }) {
    return ProviderScope(
      overrides: [
        dbTechDocsProvider.overrideWith((_) async => docs),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TechDocPicker(
              selectedDocId: selectedDocId,
              onChanged: onChanged ?? (_) {},
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
  }

  group('TechDocPicker', () {
    testWidgets('shows "No documents uploaded" when document list is empty',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(docs: []));
      await tester.pumpAndSettle();

      expect(find.text('No documents uploaded'), findsOneWidget);
    });

    testWidgets('shows document names in dropdown', (tester) async {
      await tester.pumpWidget(buildTestWidget(docs: sampleDocs));
      await tester.pumpAndSettle();

      // Tap to open the dropdown
      await tester.tap(find.byType(TechDocPicker));
      await tester.pumpAndSettle();

      expect(find.text('ATV320 User Manual'), findsOneWidget);
      expect(find.text('PT100 Sensor Datasheet'), findsOneWidget);
      expect(find.text('Beckhoff CX5010 Quick Start'), findsOneWidget);
    });

    testWidgets('typing in search field filters document list',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(docs: sampleDocs));
      await tester.pumpAndSettle();

      // Tap to open the dropdown
      await tester.tap(find.byType(TechDocPicker));
      await tester.pumpAndSettle();

      // Type a search query to filter
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'ATV');
      await tester.pumpAndSettle();

      // Only ATV320 should remain visible
      expect(find.text('ATV320 User Manual'), findsOneWidget);
      expect(find.text('PT100 Sensor Datasheet'), findsNothing);
      expect(find.text('Beckhoff CX5010 Quick Start'), findsNothing);
    });

    testWidgets('selecting a document calls onChanged with doc ID',
        (tester) async {
      int? selectedId;
      await tester.pumpWidget(buildTestWidget(
        docs: sampleDocs,
        onChanged: (id) => selectedId = id,
      ));
      await tester.pumpAndSettle();

      // Tap to open
      await tester.tap(find.byType(TechDocPicker));
      await tester.pumpAndSettle();

      // Tap on the second document
      await tester.tap(find.text('PT100 Sensor Datasheet'));
      await tester.pumpAndSettle();

      expect(selectedId, equals(2));
    });

    testWidgets('shows "None" option to clear selection', (tester) async {
      int? selectedId = 1;
      await tester.pumpWidget(buildTestWidget(
        docs: sampleDocs,
        selectedDocId: 1,
        onChanged: (id) => selectedId = id,
      ));
      await tester.pumpAndSettle();

      // Tap to open
      await tester.tap(find.byType(TechDocPicker));
      await tester.pumpAndSettle();

      // "None" option should be present
      expect(find.text('None'), findsOneWidget);

      // Tap "None" to clear
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();

      expect(selectedId, isNull);
    });

    testWidgets('disabled state renders as non-interactive', (tester) async {
      bool changed = false;
      await tester.pumpWidget(buildTestWidget(
        docs: sampleDocs,
        enabled: false,
        onChanged: (_) => changed = true,
      ));
      await tester.pumpAndSettle();

      // Tap the picker -- should not open dropdown
      await tester.tap(find.byType(TechDocPicker));
      await tester.pumpAndSettle();

      // No document names should appear in an overlay
      expect(find.text('ATV320 User Manual'), findsNothing);
      expect(changed, isFalse);
    });

    testWidgets('shows selected document name when selectedDocId is set',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        docs: sampleDocs,
        selectedDocId: 2,
      ));
      await tester.pumpAndSettle();

      expect(find.text('PT100 Sensor Datasheet'), findsOneWidget);
    });

    testWidgets('shows placeholder when no document is selected',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(docs: sampleDocs));
      await tester.pumpAndSettle();

      expect(find.text('Select document...'), findsOneWidget);
    });
  });
}
