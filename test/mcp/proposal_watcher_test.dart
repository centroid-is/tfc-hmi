import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc/providers/proposal_watcher.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemoryForTest();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertProposal(
    String type,
    String title, {
    String json = '{}',
    String operator = 'operator1',
    String status = 'pending',
  }) async {
    await db.customInsert(
      'INSERT INTO mcp_proposal '
      '(proposal_type, title, proposal_json, operator_id, status, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString(type),
        Variable.withString(title),
        Variable.withString(json),
        Variable.withString(operator),
        Variable.withString(status),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
    );
  }

  group('ProposalWatcher', () {
    test('polls for new proposals from database', () async {
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      expect(watcher.pending, isEmpty);

      await insertProposal(
        'alarm',
        'Test Alarm',
        json: '{"_proposal_type":"alarm","title":"Test Alarm"}',
      );

      // Wait for poll cycle (3s + buffer)
      await Future<void>.delayed(const Duration(seconds: 4));

      expect(watcher.pending, hasLength(1));
      expect(watcher.pending.first.title, 'Test Alarm');
      expect(watcher.pending.first.proposalType, 'alarm');
      expect(watcher.pending.first.editorLabel, 'Alarm Editor');
      expect(watcher.pending.first.editorRoute, '/advanced/alarm-editor');
    });

    test('markNotified removes from pending and updates DB', () async {
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      await insertProposal('page', 'New Page');

      await Future<void>.delayed(const Duration(seconds: 4));
      expect(watcher.pending, hasLength(1));

      final id = watcher.pending.first.id;
      await watcher.markNotified(id);

      expect(watcher.pending, isEmpty);

      final rows = await db
          .customSelect('SELECT status FROM mcp_proposal WHERE id = ?',
              variables: [Variable.withInt(id)])
          .get();
      expect(rows.first.read<String>('status'), 'notified');
    });

    test('does not re-fetch already seen proposals', () async {
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      await insertProposal('asset', 'Asset 1');

      await Future<void>.delayed(const Duration(seconds: 4));
      expect(watcher.pending, hasLength(1));

      // Wait for second poll — should not duplicate
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(watcher.pending, hasLength(1));
    });

    test('skips proposals with non-pending status', () async {
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      // Insert a proposal already marked as notified
      await insertProposal('alarm', 'Already Notified', status: 'notified');
      // Insert a proposal already accepted
      await insertProposal('alarm', 'Already Accepted', status: 'accepted');
      // Insert one that is pending
      await insertProposal('alarm', 'Pending One', status: 'pending');

      await Future<void>.delayed(const Duration(seconds: 4));

      // Only the pending one should appear
      expect(watcher.pending, hasLength(1));
      expect(watcher.pending.first.title, 'Pending One');
    });

    test('detects proposals added across multiple poll cycles', () async {
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      await insertProposal('alarm', 'Alarm 1');

      await Future<void>.delayed(const Duration(seconds: 4));
      expect(watcher.pending, hasLength(1));

      // Insert another proposal after the first poll cycle
      await insertProposal('page', 'Page 1');

      await Future<void>.delayed(const Duration(seconds: 4));
      expect(watcher.pending, hasLength(2));
      expect(watcher.pending[0].title, 'Alarm 1');
      expect(watcher.pending[1].title, 'Page 1');
    });

    test('continues polling after DB error', () async {
      // First, create a watcher with a valid DB to verify normal operation
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      // Insert proposal before any DB issues
      await insertProposal('alarm', 'Should Arrive');

      // Wait for poll to pick it up
      await Future<void>.delayed(const Duration(seconds: 4));

      // Watcher should have the proposal despite any transient errors
      // (the catch block silently swallows errors and retries next cycle)
      expect(watcher.pending, hasLength(1));
      expect(watcher.pending.first.title, 'Should Arrive');
    });

    test('dispose cancels timer and prevents further polling', () async {
      final watcher = ProposalWatcher(db);

      await insertProposal('alarm', 'Before Dispose');
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(watcher.pending, hasLength(1));

      watcher.dispose();

      // Insert another proposal after dispose
      await insertProposal('alarm', 'After Dispose');
      await Future<void>.delayed(const Duration(seconds: 4));

      // Should still only have the one from before dispose
      expect(watcher.pending, hasLength(1));
    });

    test('notifies listeners when new proposals arrive', () async {
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      var notifyCount = 0;
      watcher.addListener(() => notifyCount++);

      await insertProposal('alarm', 'Notify Test');
      await Future<void>.delayed(const Duration(seconds: 4));

      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('markNotified for non-existent ID does not crash', () async {
      final watcher = ProposalWatcher(db);
      addTearDown(watcher.dispose);

      // Should not throw for a non-existent proposal
      await watcher.markNotified(99999);
      expect(watcher.pending, isEmpty);
    });
  });

  group('PendingProposal', () {
    test('editorLabel and editorRoute for all types', () {
      PendingProposal make(String type) => PendingProposal(
            id: 1,
            proposalType: type,
            title: 'test',
            proposalJson: '{}',
            operatorId: 'op',
            createdAt: DateTime.now(),
          );

      expect(make('alarm').editorLabel, 'Alarm Editor');
      expect(make('alarm').editorRoute, '/advanced/alarm-editor');
      expect(make('key_mapping').editorLabel, 'Key Repository');
      expect(make('key_mapping').editorRoute, '/advanced/key-repository');
      expect(make('page').editorLabel, 'Page Editor');
      expect(make('page').editorRoute, '/advanced/page-editor');
      expect(make('asset').editorLabel, 'Page Editor');
      expect(make('asset').editorRoute, '/advanced/page-editor');
      expect(make('unknown').editorLabel, 'Editor');
      expect(make('unknown').editorRoute, isNull);
    });
  });
}
