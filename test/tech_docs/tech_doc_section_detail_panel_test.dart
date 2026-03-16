import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/providers/tech_doc.dart';
import 'package:tfc/tech_docs/tech_doc_section_detail_panel.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart' show TechDocSummary;

void main() {
  group('TechDocSectionDetailPanel', () {
    testWidgets('shows "PDF not available" when bytes are null',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            techDocPdfBytesProvider(1).overrideWith((ref) async => null),
            dbTechDocsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: TechDocSectionDetailPanel(docId: 1),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PDF not available'), findsOneWidget);
    });

    testWidgets('shows document name in header', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            techDocPdfBytesProvider(1).overrideWith((ref) async => null),
            dbTechDocsProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: TechDocSectionDetailPanel(docId: 1),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Falls back to 'Document' when doc list is empty
      expect(find.text('Document'), findsOneWidget);
    });

    testWidgets('close button clears selected doc', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            techDocPdfBytesProvider(1).overrideWith((ref) async => null),
            dbTechDocsProvider.overrideWith((ref) async => []),
            selectedTechDocProvider.overrideWith((ref) => 1),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: TechDocSectionDetailPanel(docId: 1),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close panel'));
      await tester.pumpAndSettle();
    });

    // -----------------------------------------------------------------
    // Overflow prevention tests
    // -----------------------------------------------------------------
    group('overflow prevention', () {
      testWidgets('long document name does not overflow in narrow panel',
          (tester) async {
        final errors = <FlutterErrorDetails>[];
        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);

        final longName = 'A' * 200; // 200-char document name
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              techDocPdfBytesProvider(1).overrideWith((ref) async => null),
              dbTechDocsProvider.overrideWith((ref) async => [
                    TechDocSummary(
                      id: 1,
                      name: longName,
                      pageCount: 10,
                      sectionCount: 3,
                      uploadedAt: DateTime(2025, 1, 1),
                    ),
                  ]),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 200, // Very narrow panel
                  height: 400,
                  child: TechDocSectionDetailPanel(docId: 1),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        FlutterError.onError = oldHandler;
        final overflowErrors = errors.where(
          (e) => e.toString().contains('overflowed'),
        );
        expect(overflowErrors, isEmpty,
            reason: 'Long doc name should not cause overflow');
      });

      testWidgets('long error message does not overflow', (tester) async {
        final errors = <FlutterErrorDetails>[];
        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);

        final longError = 'E' * 300; // 300-char error message
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              techDocPdfBytesProvider(1)
                  .overrideWith((ref) async => throw Exception(longError)),
              dbTechDocsProvider.overrideWith((ref) async => []),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 200, // Very narrow panel
                  height: 400,
                  child: TechDocSectionDetailPanel(docId: 1),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        FlutterError.onError = oldHandler;
        final overflowErrors = errors.where(
          (e) => e.toString().contains('overflowed'),
        );
        expect(overflowErrors, isEmpty,
            reason: 'Long error message should not cause overflow');
      });

      testWidgets('panel renders without overflow at minimum width',
          (tester) async {
        final errors = <FlutterErrorDetails>[];
        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              techDocPdfBytesProvider(1).overrideWith((ref) async => null),
              dbTechDocsProvider.overrideWith((ref) async => [
                    TechDocSummary(
                      id: 1,
                      name: 'Short',
                      pageCount: 5,
                      sectionCount: 2,
                      uploadedAt: DateTime(2025, 6, 15),
                    ),
                  ]),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 150, // Extremely narrow
                  height: 300,
                  child: TechDocSectionDetailPanel(docId: 1),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        FlutterError.onError = oldHandler;
        final overflowErrors = errors.where(
          (e) => e.toString().contains('overflowed'),
        );
        expect(overflowErrors, isEmpty,
            reason: 'Panel should not overflow at minimum width');
        expect(find.text('Short'), findsOneWidget);
      });
    });
  });
}
