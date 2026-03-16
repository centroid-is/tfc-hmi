import 'package:logger/logger.dart';

/// Actions that can be audited on the technical document library.
enum TechDocAuditAction { upload, rename, delete, replace, editSections }

/// Generic reusable audit wrapper for all document library operations.
///
/// All library write operations MUST go through this -- not per-operation
/// audit calls. Logs the action, user identity, document ID, and timestamp
/// before and after the operation.
///
/// Rethrows any exception from [operation] after logging the failure.
Future<T> auditTechDocOperation<T>({
  required TechDocAuditAction action,
  required String user,
  required int? docId,
  required String? docName,
  required Future<T> Function() operation,
  required Logger logger,
}) async {
  logger.i(
      'TechDoc audit: $action by $user on doc=$docId ($docName) at ${DateTime.now().toIso8601String()}');
  try {
    final result = await operation();
    logger.i('TechDoc audit: $action completed successfully');
    return result;
  } catch (e) {
    logger.w('TechDoc audit: $action FAILED: $e');
    rethrow;
  }
}
