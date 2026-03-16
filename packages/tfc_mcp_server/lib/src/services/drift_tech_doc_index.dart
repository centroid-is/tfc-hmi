import 'package:drift/drift.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase, fuzzyMatch;

import '../database/server_database.dart'
    show
        $TechDocTableTable,
        $TechDocSectionTableTable,
        TechDocTableCompanion,
        TechDocSectionTableCompanion;
import '../interfaces/tech_doc_index.dart';

/// Database-backed implementation of [TechDocIndex] using Drift.
///
/// Stores document metadata and PDF bytes in [TechDocTable] and extracted
/// sections in [TechDocSectionTable]. Search uses in-Dart fuzzyMatch
/// filtering after DB fetch, following the [DriftDrawingIndex] pattern.
///
/// Key design decisions:
/// - [getSummary] uses selectOnly with explicit columns to NEVER fetch
///   the pdfBytes blob. This is critical for performance with 50MB PDFs.
/// - [getPdfBytes] fetches only the blob column for a single doc.
/// - Sections are flattened from the [ParsedSection] tree with parentId
///   references to preserve hierarchy.
///
/// Accepts [McpDatabase] (not ServerDatabase) so it works with both
/// AppDatabase (Flutter in-process) and ServerDatabase (standalone binary).
/// Creates table references directly from generated table classes since
/// McpDatabase is a marker interface without typed table accessors.
class DriftTechDocIndex implements TechDocIndex {
  /// Creates a [DriftTechDocIndex] backed by the given [McpDatabase].
  DriftTechDocIndex(this._db)
      : _techDocTable = $TechDocTableTable(_db),
        _techDocSectionTable = $TechDocSectionTableTable(_db);

  final McpDatabase _db;
  final $TechDocTableTable _techDocTable;
  final $TechDocSectionTableTable _techDocSectionTable;

  @override
  Future<bool> get isEmpty async {
    final count = await (_db.selectOnly(_techDocTable)
          ..addColumns([_techDocTable.id.count()]))
        .map((row) => row.read(_techDocTable.id.count()))
        .getSingle();
    return (count ?? 0) == 0;
  }

  @override
  Future<int> storeDocument({
    required String name,
    required Uint8List pdfBytes,
    required List<ParsedSection> sections,
    int? pageCount,
  }) async {
    // Compute metadata from sections.
    final flatSections = _flattenParsedSections(sections);
    // Use explicit pageCount when available (from PdfDocument.pages.length),
    // falling back to the max page referenced in sections.
    final maxPage = pageCount ?? _maxPageEnd(sections);

    // Wrap blob insert + all section inserts in a single transaction
    // for dramatically faster writes (one commit instead of N+1).
    return _db.transaction(() async {
      // Insert the document row.
      final docId = await _db.into(_techDocTable).insert(
            TechDocTableCompanion.insert(
              name: name,
              pdfBytes: pdfBytes,
              pageCount: maxPage,
              sectionCount: flatSections.length,
              uploadedAt: DateTime.now(),
            ),
          );

      // Insert sections with parentId references.
      await _insertSections(docId, sections, null);

      return docId;
    });
  }

  @override
  Future<List<TechDocSummary>> getSummary() async {
    // CRITICAL: Use selectOnly with explicit columns to NEVER fetch pdfBytes.
    // With 50MB PDFs, fetching blobs in a catalog query would be catastrophic.
    final query = _db.selectOnly(_techDocTable)
      ..addColumns([
        _techDocTable.id,
        _techDocTable.name,
        _techDocTable.pageCount,
        _techDocTable.sectionCount,
        _techDocTable.uploadedAt,
      ]);

    final rows = await query.get();

    return rows.map((row) {
      return TechDocSummary(
        id: row.read(_techDocTable.id)!,
        name: row.read(_techDocTable.name)!,
        pageCount: row.read(_techDocTable.pageCount)!,
        sectionCount: row.read(_techDocTable.sectionCount)!,
        uploadedAt: row.read(_techDocTable.uploadedAt)!,
      );
    }).toList();
  }

  @override
  Future<List<TechDocSearchResult>> search(String query,
      {int limit = 20}) async {
    // CRITICAL: Use selectOnly with explicit columns to NEVER fetch pdfBytes.
    // The old code used select().join() + readTable() which fetches ALL columns
    // including the 50MB blob, causing massive memory usage and slow queries.
    final joinQuery = _db.selectOnly(_techDocSectionTable).join([
      innerJoin(
        _techDocTable,
        _techDocTable.id.equalsExp(_techDocSectionTable.docId),
      ),
    ])
      ..addColumns([
        // From tech_doc: only id and name (NO pdfBytes).
        _techDocTable.id,
        _techDocTable.name,
        // From tech_doc_section: all columns needed for matching and results.
        _techDocSectionTable.id,
        _techDocSectionTable.title,
        _techDocSectionTable.content,
        _techDocSectionTable.pageStart,
        _techDocSectionTable.pageEnd,
        _techDocSectionTable.level,
      ]);

    final rows = await joinQuery.get();

    final q = query.toLowerCase();
    final results = <TechDocSearchResult>[];

    for (final row in rows) {
      final docId = row.read(_techDocTable.id)!;
      final docName = row.read(_techDocTable.name)!;
      final sectionId = row.read(_techDocSectionTable.id)!;
      final sectionTitle = row.read(_techDocSectionTable.title)!;
      final sectionContent = row.read(_techDocSectionTable.content)!;
      final pageStart = row.read(_techDocSectionTable.pageStart)!;
      final pageEnd = row.read(_techDocSectionTable.pageEnd)!;
      final level = row.read(_techDocSectionTable.level)!;

      final docNameLower = docName.toLowerCase();
      final sectionTitleLower = sectionTitle.toLowerCase();
      final sectionContentLower = sectionContent.toLowerCase();

      // Match against document name, section title, AND section content.
      // Use both fuzzyMatch (subsequence) and contains (exact substring)
      // to catch cases where one method misses but the other hits.
      final docNameMatch =
          fuzzyMatch(docNameLower, q) || docNameLower.contains(q);
      final titleMatch =
          fuzzyMatch(sectionTitleLower, q) || sectionTitleLower.contains(q);
      final contentMatch =
          fuzzyMatch(sectionContentLower, q) || sectionContentLower.contains(q);

      if (docNameMatch || titleMatch || contentMatch) {
        // Build a snippet — prefer title match, then content match,
        // then fall back to document name context for doc-name-only matches.
        String snippet;
        if (titleMatch) {
          snippet = sectionTitle;
        } else if (contentMatch) {
          final idx =
              sectionContentLower.indexOf(q.isNotEmpty ? q[0] : '');
          if (idx >= 0) {
            final start = idx > 40 ? idx - 40 : 0;
            final end = idx + 80 < sectionContent.length
                ? idx + 80
                : sectionContent.length;
            snippet = sectionContent.substring(start, end);
          } else {
            snippet = sectionContent.length > 80
                ? sectionContent.substring(0, 80)
                : sectionContent;
          }
        } else {
          // Doc-name-only match: show section title as context.
          snippet = '[$docName] $sectionTitle';
        }

        results.add(TechDocSearchResult(
          docId: docId,
          docName: docName,
          sectionId: sectionId,
          sectionTitle: sectionTitle,
          pageStart: pageStart,
          pageEnd: pageEnd,
          level: level,
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
    final row = await (_db.select(_techDocSectionTable)
          ..where((t) => t.id.equals(sectionId)))
        .getSingleOrNull();
    if (row == null) return null;

    return TechDocSection(
      id: row.id,
      docId: row.docId,
      parentId: row.parentId,
      title: row.title,
      content: row.content,
      pageStart: row.pageStart,
      pageEnd: row.pageEnd,
      level: row.level,
      sortOrder: row.sortOrder,
    );
  }

  @override
  Future<void> deleteDocument(int docId) async {
    await _db.transaction(() async {
      // Delete sections first (FK constraint).
      await (_db.delete(_techDocSectionTable)
            ..where((t) => t.docId.equals(docId)))
          .go();

      // Delete the document (including blob).
      await (_db.delete(_techDocTable)..where((t) => t.id.equals(docId)))
          .go();
    });
  }

  @override
  Future<void> renameDocument(int docId, String newName) async {
    await (_db.update(_techDocTable)..where((t) => t.id.equals(docId)))
        .write(TechDocTableCompanion(name: Value(newName)));
  }

  @override
  Future<void> updateSections(int docId, List<ParsedSection> sections,
      {int? pageCount}) async {
    await _db.transaction(() async {
      // Delete old sections.
      await (_db.delete(_techDocSectionTable)
            ..where((t) => t.docId.equals(docId)))
          .go();

      // Insert new sections.
      await _insertSections(docId, sections, null);

      // Update section count (and optionally page count) on the document.
      final newCount = _flattenParsedSections(sections).length;
      await (_db.update(_techDocTable)..where((t) => t.id.equals(docId)))
          .write(TechDocTableCompanion(
        sectionCount: Value(newCount),
        pageCount:
            pageCount != null ? Value(pageCount) : const Value.absent(),
      ));
    });
  }

  @override
  Future<Uint8List?> getPdfBytes(int docId) async {
    // Fetch only the pdfBytes column for this specific doc.
    final query = _db.selectOnly(_techDocTable)
      ..addColumns([_techDocTable.pdfBytes])
      ..where(_techDocTable.id.equals(docId));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return row.read(_techDocTable.pdfBytes);
  }

  @override
  Future<List<TechDocSection>> getSectionsForDoc(int docId) async {
    final rows = await (_db.select(_techDocSectionTable)
          ..where((t) => t.docId.equals(docId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();

    return rows
        .map((row) => TechDocSection(
              id: row.id,
              docId: row.docId,
              parentId: row.parentId,
              title: row.title,
              content: row.content,
              pageStart: row.pageStart,
              pageEnd: row.pageEnd,
              level: row.level,
              sortOrder: row.sortOrder,
            ))
        .toList();
  }

  @override
  Future<void> updatePdfBytes(int docId, Uint8List pdfBytes) async {
    await (_db.update(_techDocTable)..where((t) => t.id.equals(docId)))
        .write(TechDocTableCompanion(pdfBytes: Value(pdfBytes)));
  }

  @override
  Future<List<TechDocLink>> getLinkedAssets(int docId) async {
    // V1: links stored in asset JSON, not DB table.
    return [];
  }

  // ---- Helpers ----

  /// Insert sections recursively, tracking parentId references.
  Future<void> _insertSections(
      int docId, List<ParsedSection> sections, int? parentId) async {
    for (final section in sections) {
      final sectionId = await _db.into(_techDocSectionTable).insert(
            TechDocSectionTableCompanion.insert(
              docId: docId,
              parentId: Value(parentId),
              title: section.title,
              content: section.content,
              pageStart: section.pageStart,
              pageEnd: section.pageEnd,
              level: section.level,
              sortOrder: section.sortOrder,
            ),
          );

      // Recurse into children with this section's ID as parentId.
      if (section.children.isNotEmpty) {
        await _insertSections(docId, section.children, sectionId);
      }
    }
  }

  /// Flatten a tree of [ParsedSection]s into a flat list for counting.
  List<ParsedSection> _flattenParsedSections(List<ParsedSection> sections) {
    final result = <ParsedSection>[];
    for (final section in sections) {
      result.add(section);
      result.addAll(_flattenParsedSections(section.children));
    }
    return result;
  }

  /// Compute the maximum page end from a section tree.
  int _maxPageEnd(List<ParsedSection> sections) {
    int max = 0;
    for (final s in sections) {
      if (s.pageEnd > max) max = s.pageEnd;
      final childMax = _maxPageEnd(s.children);
      if (childMax > max) max = childMax;
    }
    return max;
  }
}
