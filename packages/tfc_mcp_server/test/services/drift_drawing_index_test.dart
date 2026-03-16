import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/interfaces/drawing_index.dart';
import 'package:tfc_mcp_server/src/services/drift_drawing_index.dart';

void main() {
  group('DriftDrawingIndex', () {
    late ServerDatabase db;
    late DriftDrawingIndex index;

    setUp(() async {
      db = ServerDatabase.inMemory();
      // Ensure tables are created.
      await db.customStatement('SELECT 1');
      index = DriftDrawingIndex(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('storeDrawing persists drawing metadata and returns without error',
        () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'Title page'),
          const DrawingPageText(
              pageNumber: 2, fullText: 'relay K3 on terminal block X1'),
        ],
      );

      final summaries = await index.getDrawingSummary();
      expect(summaries, hasLength(1));
      expect(summaries.first.drawingName, equals('Panel-A Main Wiring'));
      expect(summaries.first.assetKey, equals('panel-A'));
      expect(summaries.first.filePath, equals('/drawings/panel-a-main.pdf'));
      expect(summaries.first.pageCount, equals(2));
    });

    test('storeDrawing with pageTexts indexes component text per page',
        () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'Title page\nDrawing number 12345'),
          const DrawingPageText(
              pageNumber: 2, fullText: 'relay K3 on terminal block X1'),
          const DrawingPageText(
              pageNumber: 3, fullText: 'motor M1 VFD wiring diagram'),
        ],
      );

      // Search for relay K3 -- should find page 2
      final results = await index.search('relay K3');
      expect(results, isNotEmpty);
      expect(results.first.pageNumber, equals(2));
      expect(results.first.drawingName, equals('Panel-A Main Wiring'));
    });

    test('search returns matches using fuzzy matching against fullPageText',
        () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 5,
              fullText: 'relay K3 on terminal block X1\nfuse F2 rated 10A'),
        ],
      );

      final results = await index.search('relay');
      expect(results, isNotEmpty);
      expect(results.first.drawingName, equals('Panel-A Main Wiring'));
      expect(results.first.pageNumber, equals(5));
      expect(results.first.assetKey, equals('panel-A'));
    });

    test('search with assetFilter returns only results for that asset',
        () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'relay K3 on terminal block X1'),
        ],
      );
      await index.storeDrawing(
        assetKey: 'panel-B',
        drawingName: 'Panel-B Motor Control',
        filePath: '/drawings/panel-b-motor.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'relay K5 on terminal block X2'),
        ],
      );

      final results = await index.search('relay', assetFilter: 'panel-A');
      expect(results, hasLength(1));
      expect(results.first.assetKey, equals('panel-A'));
      expect(results.first.drawingName, equals('Panel-A Main Wiring'));
    });

    test('search returns empty list when no matches found', () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'relay K3 on terminal block X1'),
        ],
      );

      final results = await index.search('nonexistent');
      expect(results, isEmpty);
    });

    test('isEmpty returns true when no drawings stored', () async {
      expect(await index.isEmpty, isTrue);
    });

    test('isEmpty returns false after store', () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'test content'),
        ],
      );

      expect(await index.isEmpty, isFalse);
    });

    test('deleteDrawing removes drawing and its component entries', () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'relay K3 on terminal block X1'),
        ],
      );

      // Verify it exists
      expect(await index.isEmpty, isFalse);
      final resultsBefore = await index.search('relay');
      expect(resultsBefore, isNotEmpty);

      // Delete it
      await index.deleteDrawing('Panel-A Main Wiring');

      // Verify it is gone
      expect(await index.isEmpty, isTrue);
      final resultsAfter = await index.search('relay');
      expect(resultsAfter, isEmpty);
      final summaries = await index.getDrawingSummary();
      expect(summaries, isEmpty);
    });

    test('getDrawingSummary returns all stored drawings with metadata',
        () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'page 1 content'),
          const DrawingPageText(pageNumber: 2, fullText: 'page 2 content'),
        ],
      );
      await index.storeDrawing(
        assetKey: 'panel-B',
        drawingName: 'Panel-B Motor Control',
        filePath: '/drawings/panel-b-motor.pdf',
        pageTexts: [
          const DrawingPageText(pageNumber: 1, fullText: 'motor M1 wiring'),
        ],
      );

      final summaries = await index.getDrawingSummary();
      expect(summaries, hasLength(2));

      final names = summaries.map((s) => s.drawingName).toSet();
      expect(names,
          containsAll(['Panel-A Main Wiring', 'Panel-B Motor Control']));

      final panelA = summaries.firstWhere(
          (s) => s.drawingName == 'Panel-A Main Wiring');
      expect(panelA.pageCount, equals(2));
      expect(panelA.assetKey, equals('panel-A'));
      expect(panelA.filePath, equals('/drawings/panel-a-main.pdf'));

      final panelB = summaries.firstWhere(
          (s) => s.drawingName == 'Panel-B Motor Control');
      expect(panelB.pageCount, equals(1));
    });

    test('storeDrawing for same drawingName replaces existing entry (re-upload)',
        () async {
      // First upload
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main-v1.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'relay K3 on terminal block X1'),
        ],
      );

      // Re-upload with same name but different content
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main-v2.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'contactor Q1 main power'),
          const DrawingPageText(
              pageNumber: 2, fullText: 'updated wiring for relay K3'),
        ],
      );

      // Should only have one drawing entry
      final summaries = await index.getDrawingSummary();
      expect(summaries, hasLength(1));
      expect(summaries.first.filePath, equals('/drawings/panel-a-main-v2.pdf'));
      expect(summaries.first.pageCount, equals(2));

      // Old content should not be searchable
      final oldResults = await index.search('terminal block X1');
      // The old page with "relay K3 on terminal block X1" was on a single page;
      // the new upload doesn't have "terminal block X1" alone, so old should be gone
      // Actually "terminal block X1" does not appear in the new content at all
      expect(oldResults, isEmpty);

      // New content should be searchable
      final newResults = await index.search('contactor');
      expect(newResults, isNotEmpty);
      expect(newResults.first.drawingName, equals('Panel-A Main Wiring'));
    });

    test('search with empty query returns results from all pages', () async {
      await index.storeDrawing(
        assetKey: 'panel-A',
        drawingName: 'Panel-A Main Wiring',
        filePath: '/drawings/panel-a-main.pdf',
        pageTexts: [
          const DrawingPageText(
              pageNumber: 1, fullText: 'relay K3 on terminal block X1'),
          const DrawingPageText(
              pageNumber: 2, fullText: 'motor M1 VFD wiring'),
        ],
      );

      // Empty query should match everything (used by drawings_index_resource)
      final results = await index.search('');
      expect(results, isNotEmpty);
    });

    // ── Dual-mode blob tests (TD-10) ────────────────────────────────────

    group('dual-mode blob support', () {
      test('storeDrawingWithBytes stores PDF blob in DB', () async {
        final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF

        await index.storeDrawingWithBytes(
          assetKey: 'panel-A',
          drawingName: 'Panel-A Blob',
          filePath: '/drawings/panel-a.pdf',
          pageTexts: [
            const DrawingPageText(pageNumber: 1, fullText: 'blob test'),
          ],
          pdfBytes: pdfBytes,
        );

        final summaries = await index.getDrawingSummary();
        expect(summaries, hasLength(1));
        expect(summaries.first.drawingName, equals('Panel-A Blob'));
      });

      test('getDrawingBytes retrieves stored blob', () async {
        final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]);

        await index.storeDrawingWithBytes(
          assetKey: 'panel-A',
          drawingName: 'Panel-A Blob',
          filePath: '/drawings/panel-a.pdf',
          pageTexts: [
            const DrawingPageText(pageNumber: 1, fullText: 'blob test'),
          ],
          pdfBytes: pdfBytes,
        );

        final retrieved = await index.getDrawingBytes('Panel-A Blob');
        expect(retrieved, isNotNull);
        expect(retrieved, equals(pdfBytes));
      });

      test('storeDrawing without pdfBytes still works (backward compat)',
          () async {
        // Standard storeDrawing (no blob) should still work.
        await index.storeDrawing(
          assetKey: 'panel-B',
          drawingName: 'Panel-B FilePath Only',
          filePath: '/drawings/panel-b.pdf',
          pageTexts: [
            const DrawingPageText(
                pageNumber: 1, fullText: 'filePath only test'),
          ],
        );

        final summaries = await index.getDrawingSummary();
        expect(summaries, hasLength(1));
        expect(summaries.first.drawingName, equals('Panel-B FilePath Only'));
      });

      test('getDrawingBytes returns null for filePath-only drawings',
          () async {
        await index.storeDrawing(
          assetKey: 'panel-B',
          drawingName: 'Panel-B FilePath Only',
          filePath: '/drawings/panel-b.pdf',
          pageTexts: [
            const DrawingPageText(
                pageNumber: 1, fullText: 'filePath only test'),
          ],
        );

        final retrieved = await index.getDrawingBytes('Panel-B FilePath Only');
        expect(retrieved, isNull);
      });
    });
  });
}
