import 'package:drift/drift.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase, fuzzyMatch;

import '../database/server_database.dart'
    show
        $DrawingTableTable,
        $DrawingComponentTableTable,
        DrawingTableCompanion,
        DrawingComponentTableCompanion;
import '../interfaces/drawing_index.dart';

/// Database-backed implementation of [DrawingIndex] using Drift.
///
/// Stores drawing metadata in [DrawingTable] and per-page text in
/// [DrawingComponentTable]. Search uses case-insensitive substring matching
/// against fullPageText, with fuzzyMatch for line-level componentName
/// extraction.
///
/// Typical installations have 10-50 drawings with ~500 pages total,
/// so in-memory filtering after DB fetch is pragmatic and fast.
///
/// Accepts [McpDatabase] (not ServerDatabase) so it works with both
/// AppDatabase (Flutter in-process) and ServerDatabase (standalone binary).
/// Creates table references directly from generated table classes since
/// McpDatabase is a marker interface without typed table accessors.
class DriftDrawingIndex implements DrawingIndex {
  /// Creates a [DriftDrawingIndex] backed by the given [McpDatabase].
  DriftDrawingIndex(this._db)
      : _drawingTable = $DrawingTableTable(_db),
        _drawingComponentTable = $DrawingComponentTableTable(_db);

  final McpDatabase _db;
  final $DrawingTableTable _drawingTable;
  final $DrawingComponentTableTable _drawingComponentTable;

  @override
  Future<bool> get isEmpty async {
    final count = await (_db.selectOnly(_drawingTable)
          ..addColumns([_drawingTable.id.count()]))
        .map((row) => row.read(_drawingTable.id.count()))
        .getSingle();
    return (count ?? 0) == 0;
  }

  @override
  Future<void> storeDrawing({
    required String assetKey,
    required String drawingName,
    required String filePath,
    required List<DrawingPageText> pageTexts,
  }) async {
    // Idempotent re-upload: delete existing entry with same drawingName.
    await deleteDrawing(drawingName);

    // Insert drawing metadata.
    final drawingId = await _db.into(_drawingTable).insert(
          DrawingTableCompanion.insert(
            assetKey: assetKey,
            drawingName: drawingName,
            filePath: filePath,
            pageCount: pageTexts.length,
            uploadedAt: DateTime.now(),
          ),
        );

    // Insert one component row per page with the full text content.
    for (final page in pageTexts) {
      await _db.into(_drawingComponentTable).insert(
            DrawingComponentTableCompanion.insert(
              drawingId: drawingId,
              pageNumber: page.pageNumber,
              fullPageText: page.fullText,
            ),
          );
    }
  }

  @override
  Future<void> deleteDrawing(String drawingName) async {
    // Find drawing IDs for this name — use selectOnly to avoid fetching blobs.
    final idQuery = _db.selectOnly(_drawingTable)
      ..addColumns([_drawingTable.id])
      ..where(_drawingTable.drawingName.equals(drawingName));
    final idRows = await idQuery.get();
    final ids = idRows.map((r) => r.read(_drawingTable.id)!).toList();

    for (final id in ids) {
      // Delete component rows first (FK constraint).
      await (_db.delete(_drawingComponentTable)
            ..where((t) => t.drawingId.equals(id)))
          .go();
    }

    // Delete drawing rows.
    await (_db.delete(_drawingTable)
          ..where((t) => t.drawingName.equals(drawingName)))
        .go();
  }

  @override
  Future<List<DrawingSummary>> getDrawingSummary() async {
    // Use selectOnly to NEVER fetch pdfBytes blobs in a catalog query.
    final query = _db.selectOnly(_drawingTable)
      ..addColumns([
        _drawingTable.drawingName,
        _drawingTable.assetKey,
        _drawingTable.filePath,
        _drawingTable.pageCount,
        _drawingTable.uploadedAt,
      ]);

    final rows = await query.get();

    return rows
        .map((r) => DrawingSummary(
              drawingName: r.read(_drawingTable.drawingName)!,
              assetKey: r.read(_drawingTable.assetKey)!,
              filePath: r.read(_drawingTable.filePath)!,
              pageCount: r.read(_drawingTable.pageCount)!,
              uploadedAt: r.read(_drawingTable.uploadedAt)!,
            ))
        .toList();
  }

  @override
  Future<List<DrawingSearchResult>> search(String query,
      {String? assetFilter}) async {
    // CRITICAL: Use selectOnly with explicit columns to NEVER fetch pdfBytes.
    // The old code used select().join() + readTable() which fetches ALL columns
    // including the potentially large blob.
    final joinQuery = _db.selectOnly(_drawingComponentTable).join([
      innerJoin(
        _drawingTable,
        _drawingTable.id
            .equalsExp(_drawingComponentTable.drawingId),
      ),
    ])
      ..addColumns([
        // From drawing: only metadata columns (NO pdfBytes).
        _drawingTable.drawingName,
        _drawingTable.assetKey,
        // From drawing_component: all needed columns.
        _drawingComponentTable.pageNumber,
        _drawingComponentTable.fullPageText,
      ]);

    // Apply asset filter if provided.
    if (assetFilter != null) {
      joinQuery
          .where(_drawingTable.assetKey.equals(assetFilter));
    }

    final rows = await joinQuery.get();

    final results = <DrawingSearchResult>[];
    final q = query.toLowerCase();

    for (final row in rows) {
      final drawingName = row.read(_drawingTable.drawingName)!;
      final assetKey = row.read(_drawingTable.assetKey)!;
      final pageNumber = row.read(_drawingComponentTable.pageNumber)!;
      final fullText = row.read(_drawingComponentTable.fullPageText)!;

      // For empty query, return one result per page (catalog listing).
      if (q.isEmpty) {
        // Use the first non-empty line as component name.
        final firstLine = _firstNonEmptyLine(fullText);
        results.add(DrawingSearchResult(
          drawingName: drawingName,
          pageNumber: pageNumber,
          assetKey: assetKey,
          componentName: firstLine,
        ));
        continue;
      }

      // Split fullText into lines and check each for a fuzzy match.
      final lines = fullText.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        if (fuzzyMatch(trimmed.toLowerCase(), q)) {
          results.add(DrawingSearchResult(
            drawingName: drawingName,
            pageNumber: pageNumber,
            assetKey: assetKey,
            componentName: trimmed,
          ));
          // One match per page is enough to surface this page in results.
          break;
        }
      }
    }

    return results;
  }

  /// Store a drawing with optional PDF blob bytes.
  ///
  /// This is the dual-mode variant of [storeDrawing]. When [pdfBytes] is
  /// provided, the PDF content is stored as a blob in the `pdfBytes` column
  /// of [DrawingTable]. When omitted, the drawing is stored with filesystem
  /// path only (backward compatible).
  ///
  /// This enables gradual migration: new uploads can store blobs while
  /// existing drawings keep using filesystem paths.
  Future<void> storeDrawingWithBytes({
    required String assetKey,
    required String drawingName,
    required String filePath,
    required List<DrawingPageText> pageTexts,
    Uint8List? pdfBytes,
  }) async {
    // Idempotent re-upload: delete existing entry with same drawingName.
    await deleteDrawing(drawingName);

    // Insert drawing metadata with optional blob.
    final drawingId = await _db.into(_drawingTable).insert(
          DrawingTableCompanion.insert(
            assetKey: assetKey,
            drawingName: drawingName,
            filePath: filePath,
            pageCount: pageTexts.length,
            uploadedAt: DateTime.now(),
            pdfBytes: Value(pdfBytes),
          ),
        );

    // Insert one component row per page with the full text content.
    for (final page in pageTexts) {
      await _db.into(_drawingComponentTable).insert(
            DrawingComponentTableCompanion.insert(
              drawingId: drawingId,
              pageNumber: page.pageNumber,
              fullPageText: page.fullText,
            ),
          );
    }
  }

  /// Retrieve the stored PDF blob bytes for a drawing by name.
  ///
  /// Returns null if the drawing does not exist or was stored with
  /// filesystem path only (no blob).
  Future<Uint8List?> getDrawingBytes(String drawingName) async {
    final query = _db.selectOnly(_drawingTable)
      ..addColumns([_drawingTable.pdfBytes])
      ..where(_drawingTable.drawingName.equals(drawingName));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return row.read(_drawingTable.pdfBytes);
  }

  /// Returns the first non-empty line from [text], or 'Page content'
  /// if all lines are empty.
  String _firstNonEmptyLine(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Page content';
  }
}
