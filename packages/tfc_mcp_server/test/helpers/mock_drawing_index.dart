import 'package:tfc_dart/tfc_dart_core.dart' show fuzzyMatch;
import 'package:tfc_mcp_server/src/interfaces/drawing_index.dart';

/// In-memory implementation of [DrawingIndex] for testing.
///
/// Use [addResult] to populate test data and [clear] to reset between tests.
/// Search uses [fuzzyMatch] from tfc_dart to match against component names.
class MockDrawingIndex implements DrawingIndex {
  final List<DrawingSearchResult> _results = [];
  final List<DrawingSummary> _summaries = [];

  /// Add a drawing search result for testing.
  void addResult(DrawingSearchResult result) {
    _results.add(result);
  }

  /// Remove all results.
  void clear() {
    _results.clear();
    _summaries.clear();
  }

  @override
  Future<bool> get isEmpty async => _results.isEmpty && _summaries.isEmpty;

  @override
  Future<List<DrawingSearchResult>> search(String query,
      {String? assetFilter}) async {
    if (_results.isEmpty) return [];

    final q = query.toLowerCase();
    var matches = _results.where(
      (r) => fuzzyMatch(r.componentName.toLowerCase(), q),
    );

    if (assetFilter != null) {
      matches = matches.where((r) => r.assetKey == assetFilter);
    }

    return matches.toList();
  }

  @override
  Future<void> storeDrawing({
    required String assetKey,
    required String drawingName,
    required String filePath,
    required List<DrawingPageText> pageTexts,
  }) async {
    // Remove existing entry with same drawingName (idempotent re-upload).
    _summaries.removeWhere((s) => s.drawingName == drawingName);
    _results.removeWhere((r) => r.drawingName == drawingName);

    _summaries.add(DrawingSummary(
      drawingName: drawingName,
      assetKey: assetKey,
      filePath: filePath,
      pageCount: pageTexts.length,
      uploadedAt: DateTime.now(),
    ));

    // Index each page's text as search results (split lines as components).
    for (final page in pageTexts) {
      for (final line in page.fullText.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          _results.add(DrawingSearchResult(
            drawingName: drawingName,
            pageNumber: page.pageNumber,
            assetKey: assetKey,
            componentName: trimmed,
          ));
        }
      }
    }
  }

  @override
  Future<void> deleteDrawing(String drawingName) async {
    _summaries.removeWhere((s) => s.drawingName == drawingName);
    _results.removeWhere((r) => r.drawingName == drawingName);
  }

  @override
  Future<List<DrawingSummary>> getDrawingSummary() async {
    return List.unmodifiable(_summaries);
  }
}
