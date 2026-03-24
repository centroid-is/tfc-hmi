import 'dart:async';

import 'package:beamer/beamer.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_dart/core/mcp_database.dart';

import 'database.dart' show databaseProvider;

/// Routes proposal types to editor paths.
const proposalRoutes = <String, String>{
  'alarm': '/advanced/alarm-editor',
  'alarm_create': '/advanced/alarm-editor',
  'alarm_update': '/advanced/alarm-editor',
  'key_mapping': '/advanced/key-repository',
  'page': '/advanced/page-editor',
  'asset': '/advanced/page-editor',
};

/// A pending proposal notification from the MCP server.
class PendingProposal {
  final int id;
  final String proposalType;
  final String title;
  final String proposalJson;
  final String operatorId;
  final DateTime createdAt;

  const PendingProposal({
    required this.id,
    required this.proposalType,
    required this.title,
    required this.proposalJson,
    required this.operatorId,
    required this.createdAt,
  });

  String get editorLabel {
    switch (proposalType) {
      case 'alarm':
      case 'alarm_create':
      case 'alarm_update':
        return 'Alarm Editor';
      case 'key_mapping':
        return 'Key Repository';
      case 'page':
        return 'Page Editor';
      case 'asset':
        return 'Page Editor';
      default:
        return 'Editor';
    }
  }

  String? get editorRoute => proposalRoutes[proposalType];
}

/// Polls the database for new MCP proposals and notifies the UI.
class ProposalWatcher extends ChangeNotifier {
  ProposalWatcher(this._db) {
    _startPolling();
  }

  final McpDatabase _db;
  Timer? _timer;
  int _lastSeenId = 0;
  bool _polling = false;
  bool _disposed = false;
  final List<PendingProposal> _pending = [];

  List<PendingProposal> get pending => List.unmodifiable(_pending);

  void _startPolling() {
    // Initial poll immediately
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    // Re-entrancy guard: if a previous poll is still in-flight (e.g., slow DB),
    // skip this tick to avoid duplicate proposals from overlapping queries.
    if (_polling) return;
    _polling = true;
    try {
      final rows = await _db.customSelect(
        'SELECT id, proposal_type, title, proposal_json, operator_id, created_at '
        'FROM mcp_proposal WHERE id > ? AND status = ? ORDER BY id ASC',
        variables: [
          Variable.withInt(_lastSeenId),
          Variable.withString('pending'),
        ],
      ).get();

      if (_disposed) return;
      if (rows.isEmpty) return;

      for (final row in rows) {
        final id = row.read<int>('id');
        _lastSeenId = id;
        _pending.add(PendingProposal(
          id: id,
          proposalType: row.read<String>('proposal_type'),
          title: row.read<String>('title'),
          proposalJson: row.read<String>('proposal_json'),
          operatorId: row.read<String>('operator_id'),
          createdAt: DateTime.tryParse(row.read<String>('created_at')) ??
              DateTime.now(),
        ));
      }

      if (_disposed) return;
      notifyListeners();
    } catch (_) {
      // Best-effort polling; don't crash on transient DB errors.
    } finally {
      _polling = false;
    }
  }

  /// Remove a proposal from the pending list and mark it notified in DB.
  Future<void> markNotified(int proposalId) async {
    _pending.removeWhere((p) => p.id == proposalId);
    if (_disposed) return;
    notifyListeners();

    try {
      await _db.customUpdate(
        'UPDATE mcp_proposal SET status = ? WHERE id = ?',
        variables: [
          Variable.withString('notified'),
          Variable.withInt(proposalId),
        ],
        updates: {},
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Provider for the proposal watcher. Only active when database is connected.
final proposalWatcherProvider =
    ChangeNotifierProvider.autoDispose<ProposalWatcher?>((ref) {
  final dbAsync = ref.watch(databaseProvider);
  final dbWrapper = dbAsync.valueOrNull;
  if (dbWrapper == null) return null;

  final watcher = ProposalWatcher(dbWrapper.db);
  return watcher;
});

/// Shows a floating SnackBar toast for a new proposal.
///
/// - If the user is already on the relevant editor page: auto-dismiss
///   after 5 seconds with a brief "review below" message.
/// - If the user is elsewhere: persist until dismissed, with an OPEN
///   button to navigate to the editor.
///
/// [context] is the builder-level context used for `ScaffoldMessenger`.
/// [navigatorContext] is a context that is a descendant of the app
/// `Navigator`, needed for `Beamer.of`.  When called from
/// `MaterialApp.builder`, pass the navigator key's context here.
void showProposalToast(
  BuildContext context,
  PendingProposal proposal,
  ProposalWatcher watcher, {
  BuildContext? navigatorContext,
}) {
  final route = proposal.editorRoute;
  final navCtx = navigatorContext ?? context;
  final messenger = ScaffoldMessenger.of(context);

  watcher.markNotified(proposal.id);

  // Detect if user is already on the target editor page.
  bool onEditorPage = false;
  if (route != null) {
    try {
      final currentPath = Beamer.of(navCtx)
          .currentBeamLocation
          .state
          .routeInformation
          .uri
          .path;
      onEditorPage = currentPath.contains(route);
    } catch (_) {}
  }

  if (onEditorPage) {
    // User is already looking at the editor — brief auto-dismiss toast.
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        width: 380,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Row(
          children: [
            const Icon(Icons.lightbulb, color: Colors.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${proposal.title} — review below',
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  } else {
    // User is elsewhere — persist until dismissed.
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(hours: 24),
        width: 400,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        showCloseIcon: true,
        content: Row(
          children: [
            const Icon(Icons.lightbulb, color: Colors.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'AI Proposal: ${proposal.title}',
                style: const TextStyle(fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        action: route != null
            ? SnackBarAction(
                label: 'OPEN',
                onPressed: () {
                  try {
                    Beamer.of(navCtx).beamToNamed(
                      route,
                      data: proposal.proposalJson,
                    );
                  } catch (_) {}
                },
              )
            : null,
      ),
    );
  }
}
