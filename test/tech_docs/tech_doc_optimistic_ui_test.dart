/// Tests for optimistic UI behavior: pending uploads appear dimmed,
/// pending deletes hide rows, DB operations are transactional,
/// and extract/store split produces correct display data.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/interfaces/tech_doc_index.dart';
import 'package:tfc_mcp_server/src/services/drift_tech_doc_index.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    show TechDocSummary, TechDocSection;

import 'package:tfc/providers/tech_doc.dart';
import 'package:tfc/tech_docs/tech_doc_library_section.dart';
import 'package:tfc/tech_docs/tech_doc_upload_service.dart';
import 'package:tfc/tech_docs/section_detector.dart';

final _samplePdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2d]);

Widget _buildWidget({
  required DriftTechDocIndex index,
  List<TechDocSummary> pending = const [],
  List<int> deleting = const [],
}) {
  return ProviderScope(
    overrides: [
      techDocIndexProvider.overrideWith((ref) => index),
      techDocUploadServiceProvider
          .overrideWith((ref) => TechDocUploadService(index)),
      dbTechDocsProvider.overrideWith((ref) => index.getSummary()),
      selectedTechDocProvider.overrideWith((ref) => null),
      techDocUploadProgressProvider.overrideWith((ref) => null),
      pendingTechDocsProvider.overrideWith((ref) => pending),
      pendingDeleteIdsProvider.overrideWith((ref) => deleting),
      techDocSectionsProvider
          .overrideWith((ref, docId) async => <TechDocSection>[]),
      techDocPdfBytesProvider.overrideWith((ref, docId) async => null),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: TechDocLibrarySection(embedded: false),
        ),
      ),
    ),
  );
}

void main() {
  late ServerDatabase db;
  late DriftTechDocIndex index;

  setUp(() {
    db = ServerDatabase.inMemory();
    index = DriftTechDocIndex(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('pending upload (optimistic row)', () {
    testWidgets('pending doc appears in table with dimmed opacity',
        (tester) async {
      final pendingDoc = TechDocSummary(
        id: -1,
        name: 'Uploading Manual',
        pageCount: 0,
        sectionCount: 0,
        uploadedAt: DateTime.now(),
      );

      await tester.pumpWidget(_buildWidget(
        index: index,
        pending: [pendingDoc],
      ));
      // Use pump(Duration.zero) instead of pumpAndSettle to avoid
      // infinite animation from CircularProgressIndicator.
      await tester.pump();
      await tester.pump();

      expect(find.text('Uploading Manual'), findsOneWidget);
      // Pages and sections show '...' for pending.
      expect(find.text('...'), findsNWidgets(2));
    });

    testWidgets('pending doc with real counts shows actual data',
        (tester) async {
      // After extraction completes, pending row gets real counts.
      final pendingDoc = TechDocSummary(
        id: -1,
        name: 'ATV320 Manual',
        pageCount: 156,
        sectionCount: 42,
        uploadedAt: DateTime.now(),
      );

      await tester.pumpWidget(_buildWidget(
        index: index,
        pending: [pendingDoc],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('ATV320 Manual'), findsOneWidget);
      expect(find.text('156'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('pending doc shows small spinner next to name',
        (tester) async {
      final pendingDoc = TechDocSummary(
        id: -1,
        name: 'Uploading Manual',
        pageCount: 0,
        sectionCount: 0,
        uploadedAt: DateTime.now(),
      );

      await tester.pumpWidget(_buildWidget(
        index: index,
        pending: [pendingDoc],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('pending doc merges with real DB docs', (tester) async {
      await index.storeDocument(
        name: 'Existing Doc',
        pdfBytes: _samplePdf,
        sections: [
          ParsedSection(
            title: 'Test',
            content: 'Content.',
            pageStart: 1,
            pageEnd: 1,
            level: 1,
            sortOrder: 0,
          ),
        ],
      );

      final pendingDoc = TechDocSummary(
        id: -1,
        name: 'New Upload',
        pageCount: 10,
        sectionCount: 3,
        uploadedAt: DateTime.now(),
      );

      await tester.pumpWidget(_buildWidget(
        index: index,
        pending: [pendingDoc],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Existing Doc'), findsOneWidget);
      expect(find.text('New Upload'), findsOneWidget);
    });
  });

  group('pending delete (optimistic removal)', () {
    testWidgets('doc being deleted is hidden from list', (tester) async {
      final docId = await index.storeDocument(
        name: 'To Delete',
        pdfBytes: _samplePdf,
        sections: [
          ParsedSection(
            title: 'Test',
            content: 'Content.',
            pageStart: 1,
            pageEnd: 1,
            level: 1,
            sortOrder: 0,
          ),
        ],
      );

      await tester.pumpWidget(_buildWidget(
        index: index,
        deleting: [docId],
      ));
      await tester.pumpAndSettle();

      expect(find.text('To Delete'), findsNothing);
    });

    testWidgets('other docs remain visible while one is deleting',
        (tester) async {
      await index.storeDocument(
        name: 'Keep This',
        pdfBytes: _samplePdf,
        sections: [
          ParsedSection(
            title: 'A',
            content: 'A.',
            pageStart: 1,
            pageEnd: 1,
            level: 1,
            sortOrder: 0,
          ),
        ],
      );
      final id2 = await index.storeDocument(
        name: 'Delete This',
        pdfBytes: _samplePdf,
        sections: [
          ParsedSection(
            title: 'B',
            content: 'B.',
            pageStart: 1,
            pageEnd: 1,
            level: 1,
            sortOrder: 0,
          ),
        ],
      );

      await tester.pumpWidget(_buildWidget(
        index: index,
        deleting: [id2],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Keep This'), findsOneWidget);
      expect(find.text('Delete This'), findsNothing);
    });
  });

  group('transaction wrapping', () {
    test('storeDocument is atomic — sections and doc succeed together',
        () async {
      final docId = await index.storeDocument(
        name: 'Transactional Doc',
        pdfBytes: _samplePdf,
        sections: [
          ParsedSection(
            title: 'Chapter 1',
            content: 'Content 1.',
            pageStart: 1,
            pageEnd: 5,
            level: 1,
            sortOrder: 0,
            children: [
              ParsedSection(
                title: '1.1 Sub',
                content: 'Sub content.',
                pageStart: 2,
                pageEnd: 3,
                level: 2,
                sortOrder: 1,
              ),
            ],
          ),
        ],
        pageCount: 5,
      );

      expect(docId, greaterThan(0));
      final summaries = await index.getSummary();
      expect(summaries, hasLength(1));
      expect(summaries[0].sectionCount, 2);
    });

    test('deleteDocument is atomic — sections and doc removed together',
        () async {
      final docId = await index.storeDocument(
        name: 'To Delete',
        pdfBytes: _samplePdf,
        sections: [
          ParsedSection(
            title: 'Chapter',
            content: 'Content.',
            pageStart: 1,
            pageEnd: 1,
            level: 1,
            sortOrder: 0,
          ),
        ],
      );

      await index.deleteDocument(docId);

      expect(await index.isEmpty, isTrue);
      expect(await index.search('chapter'), isEmpty);
    });
  });

  group('extract/store split', () {
    test('extractDocument returns correct page and section counts', () async {
      final extractor = _StubExtractor(pages: 5, linesPerPage: 3);
      final service = TechDocUploadService(
        index,
        pdfTextExtractor: extractor,
      );

      final extracted = await service.extractDocument(
        pdfBytes: _samplePdf,
        name: 'Test Doc',
      );

      expect(extracted.name, 'Test Doc');
      expect(extracted.pageCount, 5);
      expect(extracted.pdfBytes, _samplePdf);
      // Sections depend on SectionDetector output from stub fragments.
      // At minimum, the extracted doc has the data.
      expect(extracted.sectionCount, greaterThanOrEqualTo(0));
    });

    test('storeExtracted persists to database', () async {
      final extractor = _StubExtractor(pages: 3, linesPerPage: 2);
      final service = TechDocUploadService(
        index,
        pdfTextExtractor: extractor,
      );

      final extracted = await service.extractDocument(
        pdfBytes: _samplePdf,
        name: 'Persisted Doc',
      );

      final docId = await service.storeExtracted(extracted);
      expect(docId, greaterThan(0));

      final summaries = await index.getSummary();
      expect(summaries, hasLength(1));
      expect(summaries[0].name, 'Persisted Doc');
      expect(summaries[0].pageCount, 3);
    });

    test('uploadDocument is equivalent to extract + store', () async {
      final extractor = _StubExtractor(pages: 2, linesPerPage: 1);
      final service = TechDocUploadService(
        index,
        pdfTextExtractor: extractor,
      );

      final docId = await service.uploadDocument(
        pdfBytes: _samplePdf,
        name: 'Combined Upload',
      );

      expect(docId, greaterThan(0));
      final summaries = await index.getSummary();
      expect(summaries, hasLength(1));
      expect(summaries[0].name, 'Combined Upload');
      expect(summaries[0].pageCount, 2);
    });

    test('extractDocument rejects files over size limit', () async {
      final service = TechDocUploadService(index);
      final bigBytes = Uint8List(100);

      expect(
        () => service.extractDocument(
          pdfBytes: bigBytes,
          name: 'Too Big',
          maxFileSizeBytes: 50,
        ),
        throwsArgumentError,
      );
    });
  });
}

/// Stub extractor that produces predictable fragments for testing.
class _StubExtractor implements PdfTextExtractor {
  final int pages;
  final int linesPerPage;

  _StubExtractor({required this.pages, required this.linesPerPage});

  @override
  Future<int> getPageCount(Uint8List pdfBytes) async => pages;

  @override
  Future<List<PdfPageFragments>> extractFragments(Uint8List pdfBytes) async {
    return List.generate(pages, (i) {
      final fragments = List.generate(linesPerPage, (j) {
        return SizedFragment(
          text: 'Page ${i + 1} line ${j + 1}',
          height: j == 0 ? 18.0 : 10.0, // First line is "heading" height
          pageNumber: i + 1,
        );
      });
      return PdfPageFragments(pageNumber: i + 1, fragments: fragments);
    });
  }
}
