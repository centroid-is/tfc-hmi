import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart';

import '../drawings/drawing_upload_service.dart';
import 'server_database.dart';

/// Provider for the [DrawingUploadService].
///
/// Wired with [DriftDrawingIndex] from the shared [mcpDatabaseProvider].
/// Returns null when database is not available (upload FAB shows error).
final drawingUploadServiceProvider = Provider<DrawingUploadService?>((ref) {
  final db = ref.watch(mcpDatabaseProvider);
  if (db == null) return null;
  return DrawingUploadService(DriftDrawingIndex(db));
});

/// Provider for the [DrawingIndex] interface.
///
/// Returns null when the database is not available.
/// Used by the debug asset pipeline to pre-fetch relevant electrical drawings.
final drawingIndexProvider = Provider<DrawingIndex?>((ref) {
  final db = ref.watch(mcpDatabaseProvider);
  if (db == null) return null;
  return DriftDrawingIndex(db);
});

/// Provider for the list of uploaded drawings.
final drawingListProvider = FutureProvider<List<DrawingSummary>>((ref) async {
  final service = ref.watch(drawingUploadServiceProvider);
  if (service == null) return [];
  return service.getDrawings();
});
