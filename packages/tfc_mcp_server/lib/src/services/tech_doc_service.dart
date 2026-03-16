// ---------------------------------------------------------------------------
// Tech doc service: wraps TechDocIndex for MCP tool access.
//
// Provides search, section retrieval, and summary methods that return
// Map<String, dynamic> results suitable for MCP tool text formatting.
// ---------------------------------------------------------------------------

import '../cache/ttl_cache.dart';
import '../interfaces/tech_doc_index.dart';

/// Service wrapping [TechDocIndex] for MCP tool access.
///
/// Converts [TechDocIndex] model objects into maps suitable for tool
/// response formatting. This layer decouples MCP tools from the
/// database-backed index implementation.
///
/// Search results, section content, and summaries are cached for 30 minutes
/// since technical documents are essentially static reference data that only
/// changes on upload. Cache is invalidated explicitly after new uploads.
class TechDocService {
  /// Creates a [TechDocService] backed by the given [TechDocIndex].
  TechDocService(this._techDocIndex);

  final TechDocIndex _techDocIndex;

  /// Cache for search results (keyed by query:limit).
  final _searchCache = TtlCache<String, List<Map<String, dynamic>>>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 100,
  );

  /// Cache for section content (keyed by sectionId).
  final _sectionCache = TtlCache<int, Map<String, dynamic>?>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 50,
  );

  /// Cache for document summaries (static reference data).
  final _summaryCache = TtlCache<String, List<Map<String, dynamic>>>(
    defaultTtl: const Duration(minutes: 30),
    maxEntries: 1,
  );

  /// Invalidate all tech doc caches.
  void invalidateCache() {
    _searchCache.clear();
    _sectionCache.clear();
    _summaryCache.clear();
  }

  /// Whether any technical documents have been uploaded.
  Future<bool> get isEmpty => _techDocIndex.isEmpty;

  /// Search technical documentation sections by [query].
  ///
  /// Returns a list of maps with metadata fields: docName, sectionTitle,
  /// pageStart, pageEnd, level, sectionId, docId. No full content is
  /// included (progressive discovery pattern).
  Future<List<Map<String, dynamic>>> searchDocs(String query,
      {int limit = 20}) {
    final cacheKey = 'search:$query:$limit';
    return _searchCache.getOrCompute(cacheKey, () async {
      final results = await _techDocIndex.search(query, limit: limit);

      return results
          .map((r) => <String, dynamic>{
                'docName': r.docName,
                'sectionTitle': r.sectionTitle,
                'pageStart': r.pageStart,
                'pageEnd': r.pageEnd,
                'level': r.level,
                'sectionId': r.sectionId,
                'docId': r.docId,
              })
          .toList();
    });
  }

  /// Get full section content by [sectionId].
  ///
  /// Returns a map with title, content, pageStart, pageEnd, level, docId,
  /// sectionId, and docName. Returns null if no section found.
  Future<Map<String, dynamic>?> getSection(int sectionId) {
    return _sectionCache.getOrCompute(sectionId, () async {
      final section = await _techDocIndex.getSection(sectionId);
      if (section == null) return null;

      // Look up the document name from summary
      final summaries = await _techDocIndex.getSummary();
      final docName = summaries
          .where((s) => s.id == section.docId)
          .map((s) => s.name)
          .firstOrNull;

      return <String, dynamic>{
        'title': section.title,
        'content': section.content,
        'pageStart': section.pageStart,
        'pageEnd': section.pageEnd,
        'level': section.level,
        'docId': section.docId,
        'sectionId': section.id,
        'docName': docName ?? 'Unknown Document',
      };
    });
  }

  /// Get summary of all stored documents.
  ///
  /// Returns a list of maps with id, name, pageCount, sectionCount,
  /// uploadedAt fields.
  Future<List<Map<String, dynamic>>> getSummary() {
    return _summaryCache.getOrCompute('summary', () async {
      final summaries = await _techDocIndex.getSummary();

      return summaries
          .map((s) => <String, dynamic>{
                'id': s.id,
                'name': s.name,
                'pageCount': s.pageCount,
                'sectionCount': s.sectionCount,
                'uploadedAt': s.uploadedAt.toIso8601String(),
              })
          .toList();
    });
  }
}
