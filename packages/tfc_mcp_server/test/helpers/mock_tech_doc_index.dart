import 'dart:typed_data';

import 'package:tfc_dart/tfc_dart_core.dart' show fuzzyMatch;
import 'package:tfc_mcp_server/src/interfaces/tech_doc_index.dart';

/// In-memory implementation of [TechDocIndex] for testing.
///
/// Use [storeDocument] to populate test data and [deleteDocument] to remove.
/// Search uses [fuzzyMatch] from tfc_dart to match against section titles
/// and content.
class MockTechDocIndex implements TechDocIndex {
  final Map<int, _StoredDoc> _docs = {};
  final List<TechDocSection> _sections = [];
  int _nextDocId = 1;
  int _nextSectionId = 1;

  /// Remove all stored data.
  void clear() {
    _docs.clear();
    _sections.clear();
    _nextDocId = 1;
    _nextSectionId = 1;
  }

  @override
  Future<bool> get isEmpty async => _docs.isEmpty;

  @override
  Future<int> storeDocument({
    required String name,
    required Uint8List pdfBytes,
    required List<ParsedSection> sections,
    int? pageCount,
  }) async {
    final docId = _nextDocId++;
    final flatSections = _flattenSections(docId, sections, null);
    _sections.addAll(flatSections);

    _docs[docId] = _StoredDoc(
      id: docId,
      name: name,
      pdfBytes: pdfBytes,
      pageCount: pageCount ?? _maxPage(sections),
      sectionCount: flatSections.length,
      uploadedAt: DateTime.now(),
    );

    return docId;
  }

  @override
  Future<List<TechDocSummary>> getSummary() async {
    return _docs.values
        .map((d) => TechDocSummary(
              id: d.id,
              name: d.name,
              pageCount: d.pageCount,
              sectionCount: d.sectionCount,
              uploadedAt: d.uploadedAt,
            ))
        .toList();
  }

  @override
  Future<List<TechDocSearchResult>> search(String query,
      {int limit = 20}) async {
    if (_sections.isEmpty) return [];

    final q = query.toLowerCase();
    final results = <TechDocSearchResult>[];

    for (final section in _sections) {
      final titleMatch = fuzzyMatch(section.title.toLowerCase(), q);
      final contentMatch = fuzzyMatch(section.content.toLowerCase(), q);

      if (titleMatch || contentMatch) {
        final doc = _docs[section.docId];
        if (doc == null) continue;

        // Build a snippet from the match.
        String snippet;
        if (titleMatch) {
          snippet = section.title;
        } else {
          // Extract a snippet around the first occurrence.
          final idx = section.content.toLowerCase().indexOf(q.isNotEmpty ? q[0] : '');
          if (idx >= 0) {
            final start = idx > 40 ? idx - 40 : 0;
            final end =
                idx + 80 < section.content.length ? idx + 80 : section.content.length;
            snippet = section.content.substring(start, end);
          } else {
            snippet = section.content.length > 80
                ? section.content.substring(0, 80)
                : section.content;
          }
        }

        results.add(TechDocSearchResult(
          docId: section.docId,
          docName: doc.name,
          sectionId: section.id,
          sectionTitle: section.title,
          pageStart: section.pageStart,
          pageEnd: section.pageEnd,
          level: section.level,
          matchSnippet: snippet,
        ));
      }
    }

    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  @override
  Future<TechDocSection?> getSection(int sectionId) async {
    for (final section in _sections) {
      if (section.id == sectionId) return section;
    }
    return null;
  }

  @override
  Future<void> deleteDocument(int docId) async {
    _docs.remove(docId);
    _sections.removeWhere((s) => s.docId == docId);
  }

  @override
  Future<void> renameDocument(int docId, String newName) async {
    final doc = _docs[docId];
    if (doc == null) return;
    _docs[docId] = _StoredDoc(
      id: doc.id,
      name: newName,
      pdfBytes: doc.pdfBytes,
      pageCount: doc.pageCount,
      sectionCount: doc.sectionCount,
      uploadedAt: doc.uploadedAt,
    );
  }

  @override
  Future<void> updateSections(int docId, List<ParsedSection> sections,
      {int? pageCount}) async {
    _sections.removeWhere((s) => s.docId == docId);
    final flatSections = _flattenSections(docId, sections, null);
    _sections.addAll(flatSections);

    final doc = _docs[docId];
    if (doc != null) {
      _docs[docId] = _StoredDoc(
        id: doc.id,
        name: doc.name,
        pdfBytes: doc.pdfBytes,
        pageCount: pageCount ?? doc.pageCount,
        sectionCount: flatSections.length,
        uploadedAt: doc.uploadedAt,
      );
    }
  }

  @override
  Future<Uint8List?> getPdfBytes(int docId) async {
    return _docs[docId]?.pdfBytes;
  }

  @override
  Future<List<TechDocSection>> getSectionsForDoc(int docId) async {
    return _sections
        .where((s) => s.docId == docId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<void> updatePdfBytes(int docId, Uint8List pdfBytes) async {
    final doc = _docs[docId];
    if (doc == null) return;
    _docs[docId] = _StoredDoc(
      id: doc.id,
      name: doc.name,
      pdfBytes: pdfBytes,
      pageCount: doc.pageCount,
      sectionCount: doc.sectionCount,
      uploadedAt: doc.uploadedAt,
    );
  }

  @override
  Future<List<TechDocLink>> getLinkedAssets(int docId) async {
    // V1: links stored in asset JSON, not DB table.
    return [];
  }

  // ---- Helpers ----

  /// Flatten a tree of [ParsedSection]s into a list of [TechDocSection]s
  /// with parentId references.
  List<TechDocSection> _flattenSections(
      int docId, List<ParsedSection> sections, int? parentId) {
    final result = <TechDocSection>[];
    for (final section in sections) {
      final id = _nextSectionId++;
      result.add(TechDocSection(
        id: id,
        docId: docId,
        parentId: parentId,
        title: section.title,
        content: section.content,
        pageStart: section.pageStart,
        pageEnd: section.pageEnd,
        level: section.level,
        sortOrder: section.sortOrder,
      ));
      // Recurse into children.
      result.addAll(_flattenSections(docId, section.children, id));
    }
    return result;
  }

  /// Compute the maximum page number from a section tree.
  int _maxPage(List<ParsedSection> sections) {
    int max = 0;
    for (final s in sections) {
      if (s.pageEnd > max) max = s.pageEnd;
      final childMax = _maxPage(s.children);
      if (childMax > max) max = childMax;
    }
    return max;
  }
}

/// Internal storage for a document's metadata and bytes.
class _StoredDoc {
  const _StoredDoc({
    required this.id,
    required this.name,
    required this.pdfBytes,
    required this.pageCount,
    required this.sectionCount,
    required this.uploadedAt,
  });

  final int id;
  final String name;
  final Uint8List pdfBytes;
  final int pageCount;
  final int sectionCount;
  final DateTime uploadedAt;
}
