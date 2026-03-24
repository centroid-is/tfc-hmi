import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:tfc_dart/core/mcp_database.dart';

import 'sql_dialect.dart';

/// Callback type for proposal notifications.
///
/// Invoked synchronously when [ProposalService.wrapProposal] produces a
/// wrapped proposal map (with `_proposal_type` set). Used by the Flutter
/// layer to inject proposals into the chat UI without waiting for database
/// polling.
typedef ProposalCallback = void Function(Map<String, dynamic> wrapped);

/// Shared proposal diff formatting, tagging, and persistence for write tools.
///
/// Every write tool produces a "proposal" (a preview of what the AI wants
/// to create or modify) that is presented to the operator for confirmation.
/// This service provides consistent markdown formatting for those proposals
/// and optionally records them in the database for cross-process notification.
///
/// Uses raw SQL via [customStatement] for DB writes because the
/// mcp_proposal table is a shared table defined in both AppDatabase
/// (tfc_dart) and ServerDatabase (tfc_mcp_server) with different generated
/// Drift types. Typed Drift operations (e.g. `db.into(table).insert(...)`)
/// fail with a type error when the database is AppDatabase but the table
/// class comes from ServerDatabase's codegen.
class ProposalService {
  ProposalService({
    McpDatabase? database,
    String? operatorId,
    ProposalCallback? onProposal,
  })  : _database = database,
        _isPostgres = database != null ? isPostgresDb(database) : false,
        _operatorId = operatorId ?? 'unknown',
        _onProposal = onProposal;

  final McpDatabase? _database;
  final bool _isPostgres;
  final String _operatorId;
  final ProposalCallback? _onProposal;

  /// Adapts SQL with `?` placeholders to `$N` for PostgreSQL.
  String _sql(String query) => adaptSql(query, isPostgres: _isPostgres);

  /// Formats a markdown diff for a "create" proposal.
  ///
  /// Produces a human-readable table showing the fields and values
  /// of the object to be created.
  String formatCreateDiff(
    String type,
    String title,
    Map<String, dynamic> fields,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('## Proposal: Create $type');
    buffer.writeln();
    buffer.writeln('**$title**');
    buffer.writeln();
    buffer.writeln('| Field | Value |');
    buffer.writeln('|-------|-------|');
    for (final entry in fields.entries) {
      buffer.writeln('| ${entry.key} | ${entry.value} |');
    }
    return buffer.toString().trimRight();
  }

  /// Formats a markdown diff for an "update" proposal.
  ///
  /// Produces a human-readable before/after table showing what fields
  /// will change.
  ///
  /// The [changes] map keys are field names and values are strings
  /// in the format "before -> after".
  String formatUpdateDiff(
    String type,
    String title,
    Map<String, String> changes,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('## Proposal: Update $type');
    buffer.writeln();
    buffer.writeln('**$title**');
    buffer.writeln();
    buffer.writeln('| Field | Before | After |');
    buffer.writeln('|-------|--------|-------|');
    for (final entry in changes.entries) {
      final parts = entry.value.split(' -> ');
      final before = parts.isNotEmpty ? parts[0] : '';
      final after = parts.length > 1 ? parts[1] : '';
      buffer.writeln('| ${entry.key} | $before | $after |');
    }
    return buffer.toString().trimRight();
  }

  /// Adds a `_proposal_type` field to [proposal] for Phase 5 routing,
  /// and records the proposal in the database for HMI notification.
  ///
  /// The `_proposal_type` field allows the Flutter UI to identify what
  /// kind of proposal this is (e.g., 'alarm', 'page') and route to the
  /// appropriate editor.
  Map<String, dynamic> wrapProposal(
    String type,
    Map<String, dynamic> proposal,
  ) {
    final wrapped = {
      ...proposal,
      '_proposal_type': type,
    };

    // Fire-and-forget: record proposal in DB for cross-process notification.
    _recordProposal(type, proposal, wrapped);

    // Notify in-process listener (e.g., Flutter chat UI) immediately.
    _onProposal?.call(wrapped);

    return wrapped;
  }

  /// Derives a human-readable title from the proposal based on type.
  String _deriveTitle(String type, Map<String, dynamic> proposal) {
    switch (type) {
      case 'alarm':
        return proposal['title'] as String? ??
            proposal['key'] as String? ??
            'Alarm Proposal';
      case 'page':
        return proposal['title'] as String? ??
            proposal['key'] as String? ??
            'Page Proposal';
      case 'asset':
        return proposal['title'] as String? ??
            proposal['key'] as String? ??
            'Asset Proposal';
      case 'key_mapping':
        return proposal['key'] as String? ?? 'Key Mapping Proposal';
      default:
        return proposal['title'] as String? ?? 'Proposal';
    }
  }

  Future<void> _recordProposal(
    String type,
    Map<String, dynamic> proposal,
    Map<String, dynamic> wrapped,
  ) async {
    final db = _database;
    if (db == null) return;

    try {
      final title = _deriveTitle(type, proposal);
      final jsonStr = jsonEncode(wrapped);
      final now = DateTime.now().toUtc().toIso8601String();

      await db.customStatement(
        _sql(
          'INSERT INTO mcp_proposal '
          '(proposal_type, title, proposal_json, operator_id, status, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
        ),
        [type, title, jsonStr, _operatorId, 'pending', now],
      );
    } catch (e) {
      // Notification is best-effort; don't fail the proposal tool.
      // ignore: avoid_print
      print('[ProposalService] DB write failed: $e');
    }
  }
}
