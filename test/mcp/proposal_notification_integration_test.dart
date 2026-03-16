import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';

import 'package:tfc/providers/proposal_watcher.dart';

/// Integration test: verifies the full proposal notification flow.
///
/// MCP server ProposalService → DB insert → ProposalWatcher detects →
/// proposal data matches.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemoryForTest();
  });

  tearDown(() async {
    await db.close();
  });

  test('full flow: ProposalService writes → ProposalWatcher detects', () async {
    // 1. Server side: ProposalService writes proposal to DB (like MCP tool would)
    final service = ProposalService(
      database: db,
      operatorId: 'test-operator',
    );

    final wrapped = service.wrapProposal('alarm', {
      'uid': 'abc-123',
      'title': 'Pump Overcurrent',
      'key': 'pump3.overcurrent',
      'rules': [
        {'severity': 'warning', 'expression': 'pump3.current > 15'},
        {'severity': 'error', 'expression': 'pump3.current > 20'},
      ],
    });

    // Verify wrapping adds _proposal_type
    expect(wrapped['_proposal_type'], 'alarm');

    // Wait for async DB write
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // 2. Flutter side: ProposalWatcher detects the proposal
    final watcher = ProposalWatcher(db);
    addTearDown(watcher.dispose);

    // Wait for first poll cycle
    await Future<void>.delayed(const Duration(seconds: 4));

    // 3. Verify the watcher found it with correct data
    expect(watcher.pending, hasLength(1));

    final proposal = watcher.pending.first;
    expect(proposal.title, 'Pump Overcurrent');
    expect(proposal.proposalType, 'alarm');
    expect(proposal.operatorId, 'test-operator');
    expect(proposal.editorRoute, '/advanced/alarm-editor');
    expect(proposal.editorLabel, 'Alarm Editor');

    // Verify the full proposal JSON is preserved
    final parsed = jsonDecode(proposal.proposalJson) as Map<String, dynamic>;
    expect(parsed['uid'], 'abc-123');
    expect(parsed['key'], 'pump3.overcurrent');
    expect(parsed['_proposal_type'], 'alarm');
    expect((parsed['rules'] as List).length, 2);

    // 4. Mark as notified — should clear from pending
    await watcher.markNotified(proposal.id);
    expect(watcher.pending, isEmpty);

    // 5. Verify DB status updated
    final rows = await db
        .customSelect('SELECT status FROM mcp_proposal WHERE id = ?',
            variables: [Variable.withInt(proposal.id)])
        .get();
    expect(rows.first.read<String>('status'), 'notified');
  });

  test('multiple proposals from different tools detected in order', () async {
    final service = ProposalService(database: db, operatorId: 'op');

    service.wrapProposal('alarm', {'title': 'High Temp'});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    service.wrapProposal('page', {'title': 'Dashboard'});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    service.wrapProposal('key_mapping', {'key': 'pump3.speed'});
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final watcher = ProposalWatcher(db);
    addTearDown(watcher.dispose);

    await Future<void>.delayed(const Duration(seconds: 4));

    expect(watcher.pending, hasLength(3));
    expect(watcher.pending[0].proposalType, 'alarm');
    expect(watcher.pending[1].proposalType, 'page');
    expect(watcher.pending[2].proposalType, 'key_mapping');
    expect(watcher.pending[0].editorRoute, '/advanced/alarm-editor');
    expect(watcher.pending[1].editorRoute, '/advanced/page-editor');
    expect(watcher.pending[2].editorRoute, '/advanced/key-repository');
  });
}
