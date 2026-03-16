import 'dart:convert';
import 'dart:typed_data';

import 'package:tfc_mcp_server/tfc_mcp_server.dart' show TechDocIndex;

import 'section_detector.dart';

/// Progress update during a document upload operation.
class TechDocUploadProgress {
  /// Human-readable progress message.
  final String message;

  /// Progress fraction from 0.0 to 1.0.
  final double fraction;

  const TechDocUploadProgress(this.message, this.fraction);
}

/// Result of extracting a PDF — all data needed for display before DB sync.
class ExtractedDocument {
  final String name;
  final Uint8List pdfBytes;
  final int pageCount;
  final int sectionCount;
  final List<ParsedSection> sections;

  const ExtractedDocument({
    required this.name,
    required this.pdfBytes,
    required this.pageCount,
    required this.sectionCount,
    required this.sections,
  });
}

/// Abstraction over PDF text extraction for testability.
///
/// The real implementation uses pdfrx; tests inject a stub.
abstract class PdfTextExtractor {
  /// Get page count without extracting text. Fast — just opens PDF structure.
  Future<int> getPageCount(Uint8List pdfBytes);

  /// Extract text fragments from each page of a PDF.
  Future<List<PdfPageFragments>> extractFragments(Uint8List pdfBytes);
}

/// Fragments extracted from a single PDF page.
class PdfPageFragments {
  /// 1-based page number.
  final int pageNumber;

  /// Text fragments with their bounding box heights.
  final List<SizedFragment> fragments;

  const PdfPageFragments({
    required this.pageNumber,
    required this.fragments,
  });
}

/// Minimal interface for reading/writing preferences strings.
///
/// Allows testing without SharedPreferences native plugin.
abstract class PrefsReader {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
}

/// Service for uploading, replacing, and managing technical documents.
///
/// Pipeline: PDF bytes -> size check -> text extraction -> SectionDetector
/// -> TechDocIndex.storeDocument.
///
/// Extraction is abstracted behind [PdfTextExtractor] for testability.
/// In production, use [PdfrxTextExtractor] which wraps pdfrx.
class TechDocUploadService {
  final TechDocIndex _techDocIndex;
  final SectionDetector _sectionDetector;
  final PdfTextExtractor _pdfTextExtractor;

  TechDocUploadService(
    this._techDocIndex, {
    SectionDetector? sectionDetector,
    PdfTextExtractor? pdfTextExtractor,
  })  : _sectionDetector = sectionDetector ?? const SectionDetector(),
        _pdfTextExtractor = pdfTextExtractor ?? _NoOpExtractor();

  /// Get page count without extracting text. Fast — opens PDF structure only.
  Future<int> getPageCount(Uint8List pdfBytes) {
    return _pdfTextExtractor.getPageCount(pdfBytes);
  }

  /// Extract sections from a stored document and update in DB.
  ///
  /// This is the slow part (text extraction + section detection + DB write).
  /// Designed to run in background after [storeDocumentShell] returns.
  Future<void> extractAndStoreSections({
    required int docId,
    required Uint8List pdfBytes,
  }) async {
    final pageFragments = await _pdfTextExtractor.extractFragments(pdfBytes);
    final allFragments = pageFragments.expand((p) => p.fragments).toList();
    final sections = _sectionDetector.detectSections(allFragments);
    await _techDocIndex.updateSections(
      docId,
      sections,
      pageCount: pageFragments.length,
    );
  }

  /// Extract text and detect sections — CPU work only, no DB.
  ///
  /// Returns an [ExtractedDocument] with all data needed for display.
  /// Call [storeExtracted] afterwards to persist to database.
  Future<ExtractedDocument> extractDocument({
    required Uint8List pdfBytes,
    required String name,
    int maxFileSizeBytes = 50 * 1024 * 1024,
  }) async {
    if (pdfBytes.length > maxFileSizeBytes) {
      throw ArgumentError(
        'File size ${pdfBytes.length} bytes exceeds limit of $maxFileSizeBytes bytes',
      );
    }

    final pageFragments = await _pdfTextExtractor.extractFragments(pdfBytes);

    final allFragments = <SizedFragment>[];
    for (final page in pageFragments) {
      allFragments.addAll(page.fragments);
    }

    final sections = _sectionDetector.detectSections(allFragments);

    return ExtractedDocument(
      name: name,
      pdfBytes: pdfBytes,
      pageCount: pageFragments.length,
      sectionCount: sections.length,
      sections: sections,
    );
  }

  /// Persist an already-extracted document to the database.
  ///
  /// This is the slow part (blob write + section inserts). Designed to
  /// run in the background after [extractDocument] returns display data.
  Future<int> storeExtracted(ExtractedDocument doc) {
    return _techDocIndex.storeDocument(
      name: doc.name,
      pdfBytes: doc.pdfBytes,
      sections: doc.sections,
      pageCount: doc.pageCount,
    );
  }

  /// Upload a PDF document: extract text, detect sections, store.
  ///
  /// Convenience method that runs [extractDocument] + [storeExtracted]
  /// sequentially. For optimistic UI, call them separately instead.
  Future<int> uploadDocument({
    required Uint8List pdfBytes,
    required String name,
    void Function(TechDocUploadProgress)? onProgress,
    int maxFileSizeBytes = 50 * 1024 * 1024,
  }) async {
    onProgress?.call(
        const TechDocUploadProgress('Extracting text...', 0.0));

    final doc = await extractDocument(
      pdfBytes: pdfBytes,
      name: name,
      maxFileSizeBytes: maxFileSizeBytes,
    );

    onProgress?.call(TechDocUploadProgress(
        'Storing ${doc.pageCount} pages, ${doc.sectionCount} sections...',
        0.75));

    final docId = await storeExtracted(doc);

    onProgress?.call(const TechDocUploadProgress('Complete', 1.0));

    return docId;
  }

  /// Replace a document's PDF and sections by re-extracting from new PDF bytes.
  ///
  /// Keeps the same document ID. All asset links are preserved.
  /// Updates both the PDF blob and the extracted sections.
  Future<void> replaceDocument({
    required int docId,
    required Uint8List pdfBytes,
    void Function(TechDocUploadProgress)? onProgress,
    int maxFileSizeBytes = 50 * 1024 * 1024,
  }) async {
    if (pdfBytes.length > maxFileSizeBytes) {
      throw ArgumentError(
        'File size ${pdfBytes.length} bytes exceeds limit of $maxFileSizeBytes bytes',
      );
    }

    onProgress?.call(
        const TechDocUploadProgress('Extracting text from PDF...', 0.0));

    final pageFragments = await _pdfTextExtractor.extractFragments(pdfBytes);
    final allFragments = <SizedFragment>[];
    for (final page in pageFragments) {
      allFragments.addAll(page.fragments);
    }

    onProgress?.call(
        const TechDocUploadProgress('Detecting sections...', 0.5));

    final sections = _sectionDetector.detectSections(allFragments);

    onProgress?.call(
        const TechDocUploadProgress('Updating document...', 0.75));

    // Update PDF blob AND sections — replaceDocument must replace everything.
    await _techDocIndex.updatePdfBytes(docId, pdfBytes);
    await _techDocIndex.updateSections(
      docId,
      sections,
      pageCount: pageFragments.length,
    );

    onProgress?.call(const TechDocUploadProgress('Complete', 1.0));
  }

  /// Delete a document AND clear techDocId from all linked assets (TD-12).
  ///
  /// Scans page_editor_data from preferences, removes techDocId field from
  /// any asset JSON that references [docId], writes back, then deletes the
  /// document from the index.
  Future<void> deleteAndCleanAssets({
    required int docId,
    required PrefsReader prefsReader,
  }) async {
    // 1. Read page_editor_data.
    final raw = await prefsReader.getString('page_editor_data');
    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        var modified = false;

        // 2. Scan all pages and assets for techDocId == docId.
        for (final pageEntry in data.entries) {
          final pageMap = pageEntry.value;
          if (pageMap is! Map<String, dynamic>) continue;
          final assets = pageMap['assets'];
          if (assets is! Map<String, dynamic>) continue;

          for (final assetEntry in assets.entries) {
            final asset = assetEntry.value;
            if (asset is! Map<String, dynamic>) continue;

            if (asset['techDocId'] == docId) {
              asset.remove('techDocId');
              modified = true;
            }
          }
        }

        // 3. Write back if modified.
        if (modified) {
          await prefsReader.setString('page_editor_data', jsonEncode(data));
        }
      } catch (_) {
        // If page_editor_data isn't valid JSON, skip cleanup.
      }
    }

    // 4. Delete from index.
    await _techDocIndex.deleteDocument(docId);
  }
}

/// No-op extractor for when no real PDF extraction is available.
class _NoOpExtractor implements PdfTextExtractor {
  @override
  Future<int> getPageCount(Uint8List pdfBytes) async => 0;

  @override
  Future<List<PdfPageFragments>> extractFragments(Uint8List pdfBytes) async =>
      [];
}
