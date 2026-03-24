import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tfc_dart/tfc_dart_core.dart' show McpDatabase;
import 'package:tfc_mcp_server/src/database/server_database.dart'
    show $AuditLogTable, AuditLogCompanion;
import 'package:tfc_mcp_server/src/safety/proposal_declined_exception.dart';

/// Status of an audit log entry.
enum AuditStatus { pending, success, failed, declined }

/// Service for recording audit trails of MCP tool invocations.
///
/// Implements the pre-log/post-log pattern: every tool call creates a
/// "pending" record before execution, then updates to success/failed/declined
/// after completion. This ensures that if a tool handler crashes, the pending
/// record survives in the database as evidence of the attempt.
///
/// Accepts [McpDatabase] (not ServerDatabase) so it works with both
/// AppDatabase (Flutter in-process) and ServerDatabase (standalone binary).
/// Creates table references directly from the generated [$AuditLogTable] class
/// since McpDatabase is a marker interface without typed table accessors.
class AuditLogService {
  /// Creates an [AuditLogService] backed by the given [McpDatabase].
  AuditLogService(this._db) : _auditLog = $AuditLogTable(_db);

  final McpDatabase _db;
  final $AuditLogTable _auditLog;

  /// Records an intent to invoke a tool. Creates a "pending" audit record.
  ///
  /// The [arguments] map is JSON-encoded before storage. If [timestamp] is
  /// not provided, the current UTC time is used.
  ///
  /// Returns the auto-increment ID of the new audit record, or -1 if the
  /// DB write failed (e.g., connection temporarily down). Audit logging is
  /// best-effort — failures here should not prevent tool execution.
  Future<int> logIntent({
    required String operatorId,
    required String tool,
    required Map<String, dynamic> arguments,
    String? reasoning,
    DateTime? timestamp,
  }) async {
    try {
      final now = timestamp ?? DateTime.now().toUtc();
      final id = await _db.into(_auditLog).insert(
            AuditLogCompanion.insert(
              operatorId: operatorId,
              tool: tool,
              arguments: jsonEncode(arguments),
              reasoning: reasoning != null
                  ? Value(reasoning)
                  : const Value.absent(),
              status: AuditStatus.pending.name,
              createdAt: now,
            ),
          );
      return id;
    } catch (_) {
      // Best-effort: DB may be temporarily unreachable.
      return -1;
    }
  }

  /// Updates an existing audit record with the outcome of the tool invocation.
  ///
  /// Sets the [status] and [completedAt] timestamp. If [error] is provided
  /// (typically for [AuditStatus.failed]), it is stored on the record.
  ///
  /// Best-effort: silently swallows DB errors so audit failures don't
  /// propagate to tool callers.
  Future<void> updateOutcome(
    int auditId,
    AuditStatus status, {
    String? error,
  }) async {
    if (auditId < 0) return; // No audit record was created (DB was down).
    try {
      final companion = AuditLogCompanion(
        status: Value(status.name),
        completedAt: Value(DateTime.now().toUtc()),
        error: error != null ? Value(error) : const Value.absent(),
      );
      await (_db.update(_auditLog)..where((t) => t.id.equals(auditId)))
          .write(companion);
    } catch (_) {
      // Best-effort: DB may be temporarily unreachable.
    }
  }

  /// Convenience wrapper that logs intent, runs handler, and updates outcome.
  ///
  /// On success: updates to [AuditStatus.success] and returns the handler result.
  /// On failure: updates to [AuditStatus.failed] with the error message, then
  /// rethrows the exception so the caller can handle it.
  ///
  /// Audit logging is best-effort — if the DB is temporarily down, the tool
  /// handler still executes. The pg pool's built-in keepalive will restore
  /// the connection for subsequent calls.
  Future<T> executeWithAudit<T>({
    required String operatorId,
    required String tool,
    required Map<String, dynamic> arguments,
    String? reasoning,
    required Future<T> Function() handler,
  }) async {
    final auditId = await logIntent(
      operatorId: operatorId,
      tool: tool,
      arguments: arguments,
      reasoning: reasoning,
    );
    try {
      final result = await handler();
      await updateOutcome(auditId, AuditStatus.success);
      return result;
    } on ProposalDeclinedException catch (e) {
      await updateOutcome(auditId, AuditStatus.declined, error: e.message);
      rethrow;
    } on Exception catch (e) {
      await updateOutcome(auditId, AuditStatus.failed, error: e.toString());
      rethrow;
    }
  }
}
