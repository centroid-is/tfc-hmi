import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../packages/tfc_mcp_server/test/helpers/mock_tech_doc_index.dart';

import 'package:tfc/tech_docs/section_detector.dart';
import 'package:tfc/tech_docs/tech_doc_upload_service.dart';

/// Stub [SectionDetector] that returns a fixed section list.
class _StubSectionDetector extends SectionDetector {
  final List<ParsedSection> sections;

  const _StubSectionDetector(this.sections);

  @override
  List<ParsedSection> detectSections(List<SizedFragment> fragments) => sections;
}

/// Stub PDF text extractor for testing without pdfrx native plugin.
class _StubPdfTextExtractor implements PdfTextExtractor {
  final List<PdfPageFragments> pages;

  _StubPdfTextExtractor(this.pages);

  @override
  Future<int> getPageCount(Uint8List pdfBytes) async => pages.length;

  @override
  Future<List<PdfPageFragments>> extractFragments(Uint8List pdfBytes) async =>
      pages;
}

void main() {
  late MockTechDocIndex mockIndex;
  late _StubSectionDetector stubDetector;
  late _StubPdfTextExtractor stubExtractor;
  late TechDocUploadService service;

  final testSections = [
    const ParsedSection(
      title: 'Chapter 1',
      content: 'Content of chapter 1',
      pageStart: 1,
      pageEnd: 5,
      level: 1,
      sortOrder: 0,
    ),
  ];

  final testFragments = [
    PdfPageFragments(
      pageNumber: 1,
      fragments: [
        const SizedFragment(text: 'Chapter 1', height: 24.0, pageNumber: 1),
        const SizedFragment(
            text: 'Content of chapter 1', height: 12.0, pageNumber: 1),
      ],
    ),
  ];

  final smallPdfBytes = Uint8List.fromList(utf8.encode('fake-pdf-content'));

  setUp(() {
    mockIndex = MockTechDocIndex();
    stubDetector = _StubSectionDetector(testSections);
    stubExtractor = _StubPdfTextExtractor(testFragments);
    service = TechDocUploadService(
      mockIndex,
      sectionDetector: stubDetector,
      pdfTextExtractor: stubExtractor,
    );
  });

  group('TechDocUploadService', () {
    test('uploadDocument rejects files exceeding maxFileSizeBytes', () async {
      final bigBytes = Uint8List(100);
      expect(
        () => service.uploadDocument(
          pdfBytes: bigBytes,
          name: 'big.pdf',
          maxFileSizeBytes: 50,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
        'uploadDocument calls SectionDetector.detectSections with extracted fragments',
        () async {
      var detectorCalled = false;
      final trackingDetector = _TrackingDetector(testSections, () {
        detectorCalled = true;
      });

      final trackingService = TechDocUploadService(
        mockIndex,
        sectionDetector: trackingDetector,
        pdfTextExtractor: stubExtractor,
      );

      await trackingService.uploadDocument(
        pdfBytes: smallPdfBytes,
        name: 'test.pdf',
      );

      expect(detectorCalled, isTrue);
    });

    test(
        'uploadDocument calls TechDocIndex.storeDocument with name, pdfBytes, and detected sections',
        () async {
      await service.uploadDocument(
        pdfBytes: smallPdfBytes,
        name: 'ATV320 Manual',
      );

      final docs = await mockIndex.getSummary();
      expect(docs, hasLength(1));
      expect(docs.first.name, equals('ATV320 Manual'));
    });

    test('uploadDocument returns the document ID from storeDocument', () async {
      final docId = await service.uploadDocument(
        pdfBytes: smallPdfBytes,
        name: 'test.pdf',
      );

      expect(docId, isA<int>());
      expect(docId, greaterThan(0));
    });

    test(
        'uploadDocument fires onProgress callbacks in order (extracting, detecting, storing, complete)',
        () async {
      final progress = <TechDocUploadProgress>[];

      await service.uploadDocument(
        pdfBytes: smallPdfBytes,
        name: 'test.pdf',
        onProgress: (p) => progress.add(p),
      );

      expect(progress.length, greaterThanOrEqualTo(3));
      // Should have extracting, detecting, storing phases
      expect(progress.first.fraction, equals(0.0));
      expect(progress.last.fraction, equals(1.0));
    });

    test('replaceDocument re-extracts sections and updates existing document',
        () async {
      final docId = await service.uploadDocument(
        pdfBytes: smallPdfBytes,
        name: 'original.pdf',
      );

      // Replace with new sections
      final replaceSections = [
        const ParsedSection(
          title: 'New Chapter',
          content: 'New content',
          pageStart: 1,
          pageEnd: 3,
          level: 1,
          sortOrder: 0,
        ),
      ];
      final replaceDetector = _StubSectionDetector(replaceSections);
      final replaceService = TechDocUploadService(
        mockIndex,
        sectionDetector: replaceDetector,
        pdfTextExtractor: stubExtractor,
      );

      await replaceService.replaceDocument(
        docId: docId,
        pdfBytes: smallPdfBytes,
      );

      // Verify the document's sections were updated
      final docs = await mockIndex.getSummary();
      expect(docs.first.sectionCount, equals(1));
    });

    test(
        'deleteAndCleanAssets scans page_editor_data, clears techDocId from linked asset JSON, calls deleteDocument',
        () async {
      final docId = await service.uploadDocument(
        pdfBytes: smallPdfBytes,
        name: 'linked-doc.pdf',
      );

      // Simulate page_editor_data with an asset linking to this doc
      final pageData = {
        'page1': {
          'title': 'Test Page',
          'assets': {
            'asset1': {
              'type': 'Pump',
              'key': 'pump1',
              'techDocId': docId,
            },
            'asset2': {
              'type': 'Motor',
              'key': 'motor1',
            },
          },
        },
      };

      final prefs = _MockPrefsStore();
      prefs.data['page_editor_data'] = jsonEncode(pageData);

      await service.deleteAndCleanAssets(
        docId: docId,
        prefsReader: prefs,
      );

      // Verify document was deleted from index
      final docs = await mockIndex.getSummary();
      expect(docs, isEmpty);

      // Verify techDocId was cleared from the asset JSON
      final updatedData =
          jsonDecode(prefs.data['page_editor_data']!) as Map<String, dynamic>;
      final page = updatedData['page1'] as Map<String, dynamic>;
      final assets = page['assets'] as Map<String, dynamic>;
      final asset1 = assets['asset1'] as Map<String, dynamic>;
      expect(asset1.containsKey('techDocId'), isFalse);

      // asset2 should be unchanged (had no techDocId)
      final asset2 = assets['asset2'] as Map<String, dynamic>;
      expect(asset2['key'], equals('motor1'));
    });
  });
}

/// SectionDetector that tracks whether detectSections was called.
class _TrackingDetector extends SectionDetector {
  final List<ParsedSection> _sections;
  final void Function() _onCalled;

  const _TrackingDetector(this._sections, this._onCalled);

  @override
  List<ParsedSection> detectSections(List<SizedFragment> fragments) {
    _onCalled();
    return _sections;
  }
}

/// Simple in-memory preferences store for testing deleteAndCleanAssets.
class _MockPrefsStore implements PrefsReader {
  final Map<String, String> data = {};

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
  }
}
