/// A search result from the drawing index.
///
/// Contains metadata only -- never PDF bytes or binary content.
/// Phase 6 will add actual PDF retrieval; this class is intentionally
/// limited to metadata for search result display.
class DrawingSearchResult {
  /// Creates a [DrawingSearchResult] with the required metadata fields.
  const DrawingSearchResult({
    required this.drawingName,
    required this.pageNumber,
    required this.assetKey,
    required this.componentName,
  });

  /// Name of the electrical drawing (e.g. "Panel-A Main Wiring").
  final String drawingName;

  /// Page number within the drawing where the component appears.
  final int pageNumber;

  /// Asset key identifying the equipment (e.g. "panel-A").
  final String assetKey;

  /// Human-readable component name (e.g. "relay K3", "motor M1").
  final String componentName;
}

/// Summary metadata for a stored drawing.
///
/// Returned by [DrawingIndex.getDrawingSummary] for catalog/inventory views.
class DrawingSummary {
  /// Creates a [DrawingSummary] with the required metadata fields.
  const DrawingSummary({
    required this.drawingName,
    required this.assetKey,
    required this.filePath,
    required this.pageCount,
    required this.uploadedAt,
  });

  /// Name of the electrical drawing (e.g. "Panel-A Main Wiring").
  final String drawingName;

  /// Asset key identifying the equipment (e.g. "panel-A").
  final String assetKey;

  /// Filesystem path to the PDF file.
  final String filePath;

  /// Number of pages in the drawing PDF.
  final int pageCount;

  /// When the drawing was uploaded/indexed.
  final DateTime uploadedAt;
}

/// Page text extracted from a drawing PDF for indexing.
///
/// Used as input to [DrawingIndex.storeDrawing] to provide the OCR/text
/// content of each page for full-text search.
class DrawingPageText {
  /// Creates a [DrawingPageText] with the required fields.
  const DrawingPageText({
    required this.pageNumber,
    required this.fullText,
  });

  /// Page number within the drawing PDF (1-based).
  final int pageNumber;

  /// Full text content extracted from this page.
  final String fullText;
}

/// Read-write interface for searching and storing indexed electrical drawings.
///
/// In Phase 2, [MockDrawingIndex] provides an in-memory implementation
/// for testing. Phase 6 adds [DriftDrawingIndex] backed by PostgreSQL.
abstract class DrawingIndex {
  /// Search for drawing components matching [query].
  ///
  /// The search is fuzzy -- each character of [query] must appear in
  /// the component name in order, but not necessarily consecutively.
  ///
  /// If [assetFilter] is provided, only results for that asset are returned.
  ///
  /// Returns an empty list if no matches are found or no drawings are indexed.
  Future<List<DrawingSearchResult>> search(String query,
      {String? assetFilter});

  /// Whether the index contains any drawings at all.
  ///
  /// Used to distinguish "no matches for query" from "no drawings indexed".
  Future<bool> get isEmpty;

  /// Store a drawing with its page text for indexing.
  ///
  /// If a drawing with the same [drawingName] already exists, it is replaced
  /// (idempotent re-upload).
  Future<void> storeDrawing({
    required String assetKey,
    required String drawingName,
    required String filePath,
    required List<DrawingPageText> pageTexts,
  });

  /// Delete a drawing and all its indexed page text.
  Future<void> deleteDrawing(String drawingName);

  /// Get a summary of all stored drawings.
  Future<List<DrawingSummary>> getDrawingSummary();
}
