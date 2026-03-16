import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Technical Documentation Index interface and data models.
//
// Defines the contract for technical document storage, search, retrieval,
// and management. Following the DrawingIndex/PlcCodeIndex pattern: abstract
// interface injected into TfcMcpServer, optional (null until connected).
// ---------------------------------------------------------------------------

/// A search result from the technical documentation index.
///
/// Contains metadata and a snippet -- never PDF bytes or full content.
/// Use [TechDocIndex.getSection] with [sectionId] to retrieve full content.
class TechDocSearchResult {
  /// Creates a [TechDocSearchResult] with the required fields.
  const TechDocSearchResult({
    required this.docId,
    required this.docName,
    required this.sectionId,
    required this.sectionTitle,
    required this.pageStart,
    required this.pageEnd,
    required this.level,
    required this.matchSnippet,
  });

  /// Database ID of the containing document.
  final int docId;

  /// Name of the document (e.g. "ATV320 Installation Manual").
  final String docName;

  /// Database ID of the matching section.
  final int sectionId;

  /// Title of the matching section.
  final String sectionTitle;

  /// Starting page number of the section.
  final int pageStart;

  /// Ending page number of the section.
  final int pageEnd;

  /// Heading level (1 = chapter, 2 = section, 3 = subsection).
  final int level;

  /// Short snippet of matched text for search result display.
  final String matchSnippet;
}

/// A section within a technical document.
///
/// Represents a chapter, section, or subsection with its full content.
/// Returned by [TechDocIndex.getSection] for detailed reading.
class TechDocSection {
  /// Creates a [TechDocSection] with all fields.
  const TechDocSection({
    required this.id,
    required this.docId,
    this.parentId,
    required this.title,
    required this.content,
    required this.pageStart,
    required this.pageEnd,
    required this.level,
    required this.sortOrder,
  });

  /// Database ID of this section.
  final int id;

  /// Database ID of the containing document.
  final int docId;

  /// Database ID of the parent section (null for top-level sections).
  final int? parentId;

  /// Section title (e.g. "3.2 Wiring Diagram").
  final String title;

  /// Full text content of the section.
  final String content;

  /// Starting page number.
  final int pageStart;

  /// Ending page number.
  final int pageEnd;

  /// Heading level (1 = chapter, 2 = section, 3 = subsection).
  final int level;

  /// Sort order within the document (for ordered traversal).
  final int sortOrder;
}

/// Summary metadata for a stored technical document.
///
/// Returned by [TechDocIndex.getSummary] for catalog/inventory views.
/// Never includes PDF bytes to avoid TOAST decompression overhead.
class TechDocSummary {
  /// Creates a [TechDocSummary] with the required metadata fields.
  const TechDocSummary({
    required this.id,
    required this.name,
    required this.pageCount,
    required this.sectionCount,
    required this.uploadedAt,
  });

  /// Database ID of the document.
  final int id;

  /// Human-readable document name (e.g. "ATV320 Installation Manual").
  final String name;

  /// Total number of pages in the PDF.
  final int pageCount;

  /// Number of sections extracted from the document.
  final int sectionCount;

  /// When the document was uploaded/indexed.
  final DateTime uploadedAt;
}

/// Link between a technical document and an asset.
///
/// Represents an asset that references this document. In v1, links are
/// stored in asset JSON config (not a DB table), so this is populated
/// by scanning asset configuration.
class TechDocLink {
  /// Creates a [TechDocLink] with the required fields.
  const TechDocLink({
    required this.assetKey,
    required this.assetTitle,
  });

  /// Asset key identifying the linked equipment.
  final String assetKey;

  /// Human-readable asset title for display.
  final String assetTitle;
}

/// Parser output for a document section before database storage.
///
/// Represents a section extracted from a PDF with its content and
/// hierarchical position. [children] allows recursive nesting for
/// chapter > section > subsection structure.
class ParsedSection {
  /// Creates a [ParsedSection] with all fields.
  const ParsedSection({
    required this.title,
    required this.content,
    required this.pageStart,
    required this.pageEnd,
    required this.level,
    required this.sortOrder,
    this.children = const [],
  });

  /// Section title (e.g. "Chapter 3: Installation").
  final String title;

  /// Full text content of the section.
  final String content;

  /// Starting page number.
  final int pageStart;

  /// Ending page number.
  final int pageEnd;

  /// Heading level (1 = chapter, 2 = section, 3 = subsection).
  final int level;

  /// Sort order within the document (for ordered traversal).
  final int sortOrder;

  /// Child sections (e.g. sections within a chapter).
  final List<ParsedSection> children;
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

/// Read-write interface for the technical documentation index.
///
/// Provides storage, search, retrieval, and management of technical
/// documents (manuals, datasheets, etc.) with their extracted sections.
/// Following the [DrawingIndex]/[PlcCodeIndex] pattern: injected into
/// [TfcMcpServer] as an optional dependency.
///
/// Key design decisions:
/// - PDF bytes stored as blob in DB (not filesystem path) for portability
/// - [getSummary] never fetches blob bytes (performance with 50MB PDFs)
/// - Sections are hierarchical (parent-child) for TOC navigation
/// - Asset links are in asset JSON config, not a separate DB table (v1)
abstract class TechDocIndex {
  /// Search technical document sections by query string.
  ///
  /// Returns metadata-only results with match snippets. Use [getSection]
  /// with the result's [TechDocSearchResult.sectionId] to retrieve full
  /// content.
  ///
  /// [limit] caps the number of results returned (default 20).
  Future<List<TechDocSearchResult>> search(String query, {int limit = 20});

  /// Get a single section by its database ID.
  ///
  /// Returns null if no section exists with the given [sectionId].
  Future<TechDocSection?> getSection(int sectionId);

  /// Get summary metadata for all stored documents.
  ///
  /// Returns [TechDocSummary] with counts and timestamps, but never
  /// PDF bytes. This is safe to call frequently for catalog views.
  Future<List<TechDocSummary>> getSummary();

  /// Whether any documents have been stored.
  ///
  /// Used to distinguish "no matches for query" from "no documents indexed".
  Future<bool> get isEmpty;

  /// Store a document with its PDF bytes and extracted sections.
  ///
  /// [name] is the human-readable document name.
  /// [pdfBytes] is the raw PDF file content.
  /// [sections] is the parsed section tree from PDF extraction.
  ///
  /// Returns the auto-increment database ID of the stored document.
  Future<int> storeDocument({
    required String name,
    required Uint8List pdfBytes,
    required List<ParsedSection> sections,
    int? pageCount,
  });

  /// Replace all sections for a document.
  ///
  /// Deletes existing sections and inserts the new ones. Used when
  /// re-parsing a document with improved extraction.
  Future<void> updateSections(int docId, List<ParsedSection> sections,
      {int? pageCount});

  /// Rename a document.
  Future<void> renameDocument(int docId, String newName);

  /// Delete a document and all its sections.
  Future<void> deleteDocument(int docId);

  /// Get the raw PDF bytes for a document.
  ///
  /// Returns null if no document exists with the given [docId].
  /// Only fetches the blob column -- no section data.
  Future<Uint8List?> getPdfBytes(int docId);

  /// Get all sections for a specific document.
  ///
  /// Returns sections ordered by [sortOrder]. This is the efficient path
  /// for the detail panel — single query with WHERE doc_id = ?.
  /// Use this instead of search('') + filter + N getSection() calls.
  Future<List<TechDocSection>> getSectionsForDoc(int docId);

  /// Update the PDF bytes for an existing document.
  ///
  /// Used by [replaceDocument] to store the new PDF alongside updated sections.
  Future<void> updatePdfBytes(int docId, Uint8List pdfBytes);

  /// Get assets linked to this document.
  ///
  /// In v1, returns an empty list since asset-document links are stored
  /// in asset JSON configuration, not a separate database table.
  Future<List<TechDocLink>> getLinkedAssets(int docId);
}
