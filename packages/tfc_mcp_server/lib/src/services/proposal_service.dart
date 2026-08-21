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
  ///
  /// [op] says what accepting the proposal does to its target: 'create',
  /// 'update', or 'delete'. The type alone cannot carry this -- 'alarm' and
  /// 'key_mapping' are used for both creates and updates -- so it is stamped
  /// into the JSON as `_op` for the notification banner to label each row.
  ///
  /// When the database write succeeds, the wrapped map also carries
  /// `_proposal_id` -- the mcp_proposal row id -- so the AI can look the
  /// proposal up later with `get_proposal_status`, and the UI can track the
  /// inline copy under its real id instead of a synthetic negative one.
  Future<Map<String, dynamic>> wrapProposal(
    String type,
    Map<String, dynamic> proposal, {
    String op = 'create',
  }) async {
    final wrapped = {
      ...proposal,
      '_proposal_type': type,
      '_op': op,
    };

    // Record the proposal in DB for cross-process notification. Awaited so
    // the row id can be handed back to the AI in the tool result.
    final id = await _recordProposal(type, proposal, wrapped);
    if (id != null) {
      wrapped['_proposal_id'] = id;
    }

    // Notify in-process listener (e.g., Flutter chat UI) immediately.
    _onProposal?.call(wrapped);

    return wrapped;
  }

  /// Reads back the operator's decision on recorded proposals.
  ///
  /// Returns rows newest-first as maps with `id`, `type`, `title`, `status`
  /// and `created_at`. When [ids] is given only those rows are returned;
  /// otherwise the most recent [limit] rows.
  Future<List<Map<String, dynamic>>> getProposalStatuses({
    List<int>? ids,
    int limit = 20,
  }) async {
    final db = _database;
    if (db == null) return const [];

    final String where;
    final List<Variable> vars;
    if (ids != null && ids.isNotEmpty) {
      where = 'WHERE id IN (${List.filled(ids.length, '?').join(', ')})';
      vars = [for (final id in ids) Variable.withInt(id)];
    } else {
      where = '';
      vars = [];
    }

    final rows = await db
        .customSelect(
          _sql(
            'SELECT id, proposal_type, title, status, created_at '
            'FROM mcp_proposal $where '
            'ORDER BY id DESC LIMIT ${limit.clamp(1, 100)}',
          ),
          variables: vars,
        )
        .get();

    return [
      for (final row in rows)
        {
          'id': row.read<int>('id'),
          'type': row.read<String>('proposal_type'),
          'title': row.read<String>('title'),
          'status': row.read<String>('status'),
          // Stored as ISO-8601 text on SQLite but as a native timestamp on
          // PostgreSQL, so stringify whatever comes back.
          'created_at': row.data['created_at']?.toString() ?? '',
        },
    ];
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

  /// Inserts the proposal row and returns its id, or null when there is no
  /// database or the write fails (notification is best-effort; the proposal
  /// tool must not fail on it).
  Future<int?> _recordProposal(
    String type,
    Map<String, dynamic> proposal,
    Map<String, dynamic> wrapped,
  ) async {
    final db = _database;
    if (db == null) return null;

    try {
      final title = _deriveTitle(type, proposal);
      final jsonStr = jsonEncode(wrapped);
      final now = DateTime.now().toUtc().toIso8601String();

      const insert = 'INSERT INTO mcp_proposal '
          '(proposal_type, title, proposal_json, operator_id, status, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?)';
      final values = [type, title, jsonStr, _operatorId, 'pending', now];

      if (_isPostgres) {
        final rows = await db.customSelect(
          _sql('$insert RETURNING id'),
          variables: [for (final v in values) Variable.withString(v)],
        ).get();
        return rows.isNotEmpty ? rows.first.read<int>('id') : null;
      }
      // SQLite: customInsert reports the generated rowid directly.
      return await db.customInsert(
        insert,
        variables: [for (final v in values) Variable.withString(v)],
      );
    } catch (e) {
      // ignore: avoid_print
      print('[ProposalService] DB write failed: $e');
      return null;
    }
  }
}
