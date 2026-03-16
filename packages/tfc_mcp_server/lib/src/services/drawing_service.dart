import '../cache/ttl_cache.dart';
import '../interfaces/drawing_index.dart';

/// Service for searching electrical drawings by component or subsystem.
///
/// Wraps [DrawingIndex] with limit enforcement and result mapping.
/// Returns metadata-only maps -- never PDF bytes or binary content.
///
/// Search results and summaries are cached for 30 minutes since electrical
/// drawings are essentially static reference data that only change on
/// upload. Cache is invalidated explicitly after new uploads.
class DrawingService {
  /// Creates a [DrawingService] backed by the given [DrawingIndex].
  DrawingService(this._drawingIndex);

  final DrawingIndex _drawingIndex;

  /// Cache for search results (keyed by query:assetFilter:limit).
  final _searchCache = TtlCache<String, List<Map<String, dynamic>>>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 100,
  );

  /// Cache for drawing summaries (static reference data).
  final _summaryCache = TtlCache<String, List<DrawingSummary>>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 1,
  );

  /// Invalidate all drawing caches.
  void invalidateCache() {
    _searchCache.clear();
    _summaryCache.clear();
  }

  /// Whether the underlying index contains any drawings.
  Future<bool> get hasDrawings async => !(await _drawingIndex.isEmpty);

  /// Get a summary of all stored drawings.
  Future<List<DrawingSummary>> getDrawingSummary() {
    return _summaryCache.getOrCompute('summary', () {
      return _drawingIndex.getDrawingSummary();
    });
  }

  /// Search for drawing components matching [query].
  ///
  /// Returns a list of maps with keys: drawingName, pageNumber, assetKey,
  /// componentName. Results are limited to [limit] entries (default 50).
  ///
  /// If [assetFilter] is provided, only results for that asset are returned.
  Future<List<Map<String, dynamic>>> searchDrawings({
    required String query,
    String? assetFilter,
    int limit = 50,
  }) {
    final cacheKey = 'search:$query:${assetFilter ?? ''}:$limit';
    return _searchCache.getOrCompute(cacheKey, () async {
      final results =
          await _drawingIndex.search(query, assetFilter: assetFilter);

      return results.take(limit).map((r) => {
            'drawingName': r.drawingName,
            'pageNumber': r.pageNumber,
            'assetKey': r.assetKey,
            'componentName': r.componentName,
          }).toList();
    });
  }
}
