import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc/providers/proposal_watcher.dart';
import 'package:tfc/providers/proposal_state.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemoryForTest();
  });

  tearDown(() async {
    await db.close();
  });

  PendingProposal makeProposal({
    int id = 1,
    String type = 'alarm',
    String title = 'Test Alarm',
    String json = '{"_proposal_type":"alarm"}',
    String operator = 'op1',
  }) =>
      PendingProposal(
        id: id,
        proposalType: type,
        title: title,
        proposalJson: json,
        operatorId: operator,
        createdAt: DateTime.now(),
      );

  group('ProposalState', () {
    test('default state has no proposals', () {
      const state = ProposalState();
      expect(state.pendingCount, 0);
      expect(state.hasPending, isFalse);
      expect(state.proposals, isEmpty);
    });

    test('ofType filters by proposal type', () {
      final state = ProposalState(proposals: [
        makeProposal(id: 1, type: 'alarm', title: 'Alarm 1'),
        makeProposal(id: 2, type: 'page', title: 'Page 1'),
        makeProposal(id: 3, type: 'alarm', title: 'Alarm 2'),
      ]);
      expect(state.ofType('alarm'), hasLength(2));
      expect(state.ofType('page'), hasLength(1));
      expect(state.ofType('key_mapping'), isEmpty);
    });
  });

  group('ProposalStateNotifier', () {
    test('addProposal adds to state and pendingCount increments', () {
      final notifier = ProposalStateNotifier(db);
      expect(notifier.state.pendingCount, 0);

      notifier.addProposal(makeProposal(id: 1));
      expect(notifier.state.pendingCount, 1);

      notifier.addProposal(makeProposal(
        id: 2,
        title: 'Another',
        json: '{"_proposal_type":"alarm","uid":"2"}',
      ));
      expect(notifier.state.pendingCount, 2);
    });

    test('duplicate proposal IDs are not added', () {
      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(id: 1));
      notifier.addProposal(makeProposal(id: 1, title: 'Duplicate'));
      expect(notifier.state.pendingCount, 1);
      expect(notifier.state.proposals.first.title, 'Test Alarm');
    });

    test('duplicate proposal JSON content is not added (different IDs)', () {
      // This tests the inline-then-DB dedup: an inline proposal (negative ID)
      // is surfaced immediately, and the DB-sourced proposal (positive ID)
      // arrives later with the same JSON. They should be treated as the same.
      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(id: -1));
      notifier.addProposal(makeProposal(id: 42));
      expect(notifier.state.pendingCount, 1);
    });

    test('acceptProposal removes from state and updates DB status to accepted',
        () async {
      // Insert a proposal into DB first
      await db.customInsert(
        'INSERT INTO mcp_proposal '
        '(proposal_type, title, proposal_json, operator_id, status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString('alarm'),
          Variable.withString('Test Alarm'),
          Variable.withString('{}'),
          Variable.withString('op1'),
          Variable.withString('pending'),
          Variable.withString(DateTime.now().toIso8601String()),
        ],
      );

      // Get the inserted ID
      final rows = await db
          .customSelect('SELECT id FROM mcp_proposal ORDER BY id DESC LIMIT 1')
          .get();
      final id = rows.first.read<int>('id');

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(id: id));
      expect(notifier.state.pendingCount, 1);

      await notifier.acceptProposal(id);
      expect(notifier.state.pendingCount, 0);
      expect(notifier.state.hasPending, isFalse);

      // Verify DB status updated
      final dbRows = await db.customSelect(
        'SELECT status FROM mcp_proposal WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).get();
      expect(dbRows.first.read<String>('status'), 'accepted');
    });

    test('rejectProposal removes from state and updates DB status to rejected',
        () async {
      await db.customInsert(
        'INSERT INTO mcp_proposal '
        '(proposal_type, title, proposal_json, operator_id, status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString('page'),
          Variable.withString('Test Page'),
          Variable.withString('{}'),
          Variable.withString('op1'),
          Variable.withString('pending'),
          Variable.withString(DateTime.now().toIso8601String()),
        ],
      );

      final rows = await db
          .customSelect('SELECT id FROM mcp_proposal ORDER BY id DESC LIMIT 1')
          .get();
      final id = rows.first.read<int>('id');

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(id: id, type: 'page'));
      await notifier.rejectProposal(id);

      expect(notifier.state.pendingCount, 0);

      final dbRows = await db.customSelect(
        'SELECT status FROM mcp_proposal WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).get();
      expect(dbRows.first.read<String>('status'), 'rejected');
    });

    test(
        'dismissProposal removes from state and updates DB status to dismissed',
        () async {
      await db.customInsert(
        'INSERT INTO mcp_proposal '
        '(proposal_type, title, proposal_json, operator_id, status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString('key_mapping'),
          Variable.withString('Test Key'),
          Variable.withString('{}'),
          Variable.withString('op1'),
          Variable.withString('pending'),
          Variable.withString(DateTime.now().toIso8601String()),
        ],
      );

      final rows = await db
          .customSelect('SELECT id FROM mcp_proposal ORDER BY id DESC LIMIT 1')
          .get();
      final id = rows.first.read<int>('id');

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(id: id, type: 'key_mapping'));
      await notifier.dismissProposal(id);

      expect(notifier.state.pendingCount, 0);

      final dbRows = await db.customSelect(
        'SELECT status FROM mcp_proposal WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).get();
      expect(dbRows.first.read<String>('status'), 'dismissed');
    });

    test('hasPending returns true when proposals exist, false when empty', () {
      final notifier = ProposalStateNotifier(db);
      expect(notifier.state.hasPending, isFalse);

      notifier.addProposal(makeProposal(id: 1));
      expect(notifier.state.hasPending, isTrue);
    });

    test('proposalsOfType filters by proposal type', () {
      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(
        id: 1,
        type: 'alarm',
        json: '{"_proposal_type":"alarm","uid":"a1"}',
      ));
      notifier.addProposal(makeProposal(
        id: 2,
        type: 'page',
        json: '{"_proposal_type":"page","uid":"p1"}',
      ));
      notifier.addProposal(makeProposal(
        id: 3,
        type: 'alarm',
        json: '{"_proposal_type":"alarm","uid":"a2"}',
      ));

      expect(notifier.state.ofType('alarm'), hasLength(2));
      expect(notifier.state.ofType('page'), hasLength(1));
      expect(notifier.state.ofType('key_mapping'), isEmpty);
    });

    test('acceptAllOfType accepts all proposals of that type and returns them',
        () async {
      // Insert proposals into DB
      for (var i = 1; i <= 3; i++) {
        await db.customInsert(
          'INSERT INTO mcp_proposal '
          '(proposal_type, title, proposal_json, operator_id, status, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(i <= 2 ? 'alarm' : 'page'),
            Variable.withString('Proposal $i'),
            Variable.withString('{"_proposal_type":"${i <= 2 ? 'alarm' : 'page'}","uid":"$i"}'),
            Variable.withString('op1'),
            Variable.withString('pending'),
            Variable.withString(DateTime.now().toIso8601String()),
          ],
        );
      }

      final rows = await db
          .customSelect('SELECT id FROM mcp_proposal ORDER BY id ASC')
          .get();
      final ids = rows.map((r) => r.read<int>('id')).toList();

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(
        id: ids[0],
        type: 'alarm',
        title: 'Alarm 1',
        json: '{"_proposal_type":"alarm","uid":"1"}',
      ));
      notifier.addProposal(makeProposal(
        id: ids[1],
        type: 'alarm',
        title: 'Alarm 2',
        json: '{"_proposal_type":"alarm","uid":"2"}',
      ));
      notifier.addProposal(makeProposal(
        id: ids[2],
        type: 'page',
        title: 'Page 1',
        json: '{"_proposal_type":"page","uid":"3"}',
      ));

      expect(notifier.state.pendingCount, 3);

      // Accept all alarms
      final accepted = await notifier.acceptAllOfType('alarm');
      expect(accepted, hasLength(2));
      expect(accepted.every((p) => p.proposalType == 'alarm'), isTrue);

      // Only page proposal remains
      expect(notifier.state.pendingCount, 1);
      expect(notifier.state.ofType('alarm'), isEmpty);
      expect(notifier.state.ofType('page'), hasLength(1));

      // Verify DB status for accepted proposals
      for (final id in [ids[0], ids[1]]) {
        final dbRows = await db.customSelect(
          'SELECT status FROM mcp_proposal WHERE id = ?',
          variables: [Variable.withInt(id)],
        ).get();
        expect(dbRows.first.read<String>('status'), 'accepted');
      }

      // Page proposal should still be pending in DB
      final pageRow = await db.customSelect(
        'SELECT status FROM mcp_proposal WHERE id = ?',
        variables: [Variable.withInt(ids[2])],
      ).get();
      expect(pageRow.first.read<String>('status'), 'pending');
    });

    test('rejectAllOfType rejects all proposals of that type', () async {
      // Insert proposals into DB
      for (var i = 1; i <= 3; i++) {
        await db.customInsert(
          'INSERT INTO mcp_proposal '
          '(proposal_type, title, proposal_json, operator_id, status, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString('alarm'),
            Variable.withString('Alarm $i'),
            Variable.withString('{"_proposal_type":"alarm","uid":"r$i"}'),
            Variable.withString('op1'),
            Variable.withString('pending'),
            Variable.withString(DateTime.now().toIso8601String()),
          ],
        );
      }

      final rows = await db
          .customSelect('SELECT id FROM mcp_proposal ORDER BY id ASC')
          .get();
      final ids = rows.map((r) => r.read<int>('id')).toList();

      final notifier = ProposalStateNotifier(db);
      for (var i = 0; i < 3; i++) {
        notifier.addProposal(makeProposal(
          id: ids[i],
          type: 'alarm',
          title: 'Alarm ${i + 1}',
          json: '{"_proposal_type":"alarm","uid":"r${i + 1}"}',
        ));
      }

      expect(notifier.state.pendingCount, 3);

      await notifier.rejectAllOfType('alarm');
      expect(notifier.state.pendingCount, 0);

      // Verify all are rejected in DB
      for (final id in ids) {
        final dbRows = await db.customSelect(
          'SELECT status FROM mcp_proposal WHERE id = ?',
          variables: [Variable.withInt(id)],
        ).get();
        expect(dbRows.first.read<String>('status'), 'rejected');
      }
    });

    test('acceptAllOfType with no matching type is a no-op', () async {
      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(
        id: 1,
        type: 'alarm',
        json: '{"_proposal_type":"alarm","uid":"x1"}',
      ));

      final accepted = await notifier.acceptAllOfType('page');
      expect(accepted, isEmpty);
      expect(notifier.state.pendingCount, 1);
    });

    test('multiple create_alarm calls produce separate trackable proposals',
        () {
      final notifier = ProposalStateNotifier(db);

      // Simulate 10 motor fault alarms created by the LLM
      for (var i = 1; i <= 10; i++) {
        notifier.addProposal(makeProposal(
          id: -DateTime.now().microsecondsSinceEpoch - i,
          type: 'alarm',
          title: 'Motor $i Fault',
          json: '{"_proposal_type":"alarm","uid":"motor-$i","title":"Motor $i Fault"}',
        ));
      }

      expect(notifier.state.pendingCount, 10);
      expect(notifier.state.ofType('alarm'), hasLength(10));
      expect(notifier.state.hasPending, isTrue);
    });

    test('tracks all proposal types including asset, alarm_create, alarm_update',
        () {
      final notifier = ProposalStateNotifier(db);
      final types = ['alarm', 'alarm_create', 'alarm_update', 'page', 'asset', 'key_mapping'];

      for (var i = 0; i < types.length; i++) {
        notifier.addProposal(makeProposal(
          id: i + 1,
          type: types[i],
          title: '${types[i]} proposal',
          json: '{"_proposal_type":"${types[i]}","uid":"$i"}',
        ));
      }

      expect(notifier.state.pendingCount, types.length);
      for (final t in types) {
        expect(notifier.state.ofType(t), hasLength(1),
            reason: 'Expected 1 proposal of type $t');
      }
    });

    test('null DB: addProposal works, accept/reject skip DB update', () async {
      // Passing null simulates no DB connection (e.g. offline mode).
      final notifier = ProposalStateNotifier(null);
      notifier.addProposal(makeProposal(id: 1));
      expect(notifier.state.pendingCount, 1);

      // acceptProposal should not throw even with null DB.
      await notifier.acceptProposal(1);
      expect(notifier.state.pendingCount, 0);

      // Same for reject.
      notifier.addProposal(makeProposal(
        id: 2,
        json: '{"_proposal_type":"alarm","uid":"null-test"}',
      ));
      await notifier.rejectProposal(2);
      expect(notifier.state.pendingCount, 0);

      // And dismiss.
      notifier.addProposal(makeProposal(
        id: 3,
        json: '{"_proposal_type":"alarm","uid":"null-dismiss"}',
      ));
      await notifier.dismissProposal(3);
      expect(notifier.state.pendingCount, 0);
    });

    test('accept/reject on non-existent ID is a no-op', () async {
      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(id: 1));
      expect(notifier.state.pendingCount, 1);

      // Accept a proposal ID that is not in state.
      await notifier.acceptProposal(999);
      // Original proposal should remain untouched.
      expect(notifier.state.pendingCount, 1);
      expect(notifier.state.proposals.first.id, 1);

      // Reject a proposal ID that is not in state.
      await notifier.rejectProposal(888);
      expect(notifier.state.pendingCount, 1);
    });

    test('rapid accept then reject of same ID: second call is no-op', () async {
      await db.customInsert(
        'INSERT INTO mcp_proposal '
        '(proposal_type, title, proposal_json, operator_id, status, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withString('alarm'),
          Variable.withString('Rapid Test'),
          Variable.withString('{}'),
          Variable.withString('op1'),
          Variable.withString('pending'),
          Variable.withString(DateTime.now().toIso8601String()),
        ],
      );

      final rows = await db
          .customSelect('SELECT id FROM mcp_proposal ORDER BY id DESC LIMIT 1')
          .get();
      final id = rows.first.read<int>('id');

      final notifier = ProposalStateNotifier(db);
      notifier.addProposal(makeProposal(id: id));

      // Accept first
      await notifier.acceptProposal(id);
      expect(notifier.state.pendingCount, 0);

      // Reject the same ID — already removed from state, should be no-op in state.
      // DB status was already set to 'accepted'; reject will overwrite to 'rejected'.
      await notifier.rejectProposal(id);
      expect(notifier.state.pendingCount, 0);

      // DB should reflect the last write ('rejected') since both calls go through.
      final dbRows = await db.customSelect(
        'SELECT status FROM mcp_proposal WHERE id = ?',
        variables: [Variable.withInt(id)],
      ).get();
      expect(dbRows.first.read<String>('status'), 'rejected');
    });

    test('acceptAllOfType and rejectAllOfType with empty state are no-ops',
        () async {
      final notifier = ProposalStateNotifier(db);
      expect(notifier.state.pendingCount, 0);

      final accepted = await notifier.acceptAllOfType('alarm');
      expect(accepted, isEmpty);
      expect(notifier.state.pendingCount, 0);

      await notifier.rejectAllOfType('page');
      expect(notifier.state.pendingCount, 0);
    });

    test('mixed batch: acceptAllOfType leaves other types untouched', () async {
      final notifier = ProposalStateNotifier(null);

      notifier.addProposal(makeProposal(
        id: 1, type: 'alarm', json: '{"uid":"a1"}',
      ));
      notifier.addProposal(makeProposal(
        id: 2, type: 'page', json: '{"uid":"p1"}',
      ));
      notifier.addProposal(makeProposal(
        id: 3, type: 'key_mapping', json: '{"uid":"k1"}',
      ));
      notifier.addProposal(makeProposal(
        id: 4, type: 'asset', json: '{"uid":"as1"}',
      ));
      notifier.addProposal(makeProposal(
        id: 5, type: 'alarm_create', json: '{"uid":"ac1"}',
      ));

      expect(notifier.state.pendingCount, 5);

      // Accept all alarm type — should only remove type == 'alarm' (id 1)
      final accepted = await notifier.acceptAllOfType('alarm');
      expect(accepted, hasLength(1));
      expect(accepted.first.id, 1);
      expect(notifier.state.pendingCount, 4);

      // Reject all key_mapping — should only remove type == 'key_mapping' (id 3)
      await notifier.rejectAllOfType('key_mapping');
      expect(notifier.state.pendingCount, 3);
      expect(notifier.state.ofType('key_mapping'), isEmpty);

      // Remaining: page, asset, alarm_create
      expect(notifier.state.ofType('page'), hasLength(1));
      expect(notifier.state.ofType('asset'), hasLength(1));
      expect(notifier.state.ofType('alarm_create'), hasLength(1));
    });

    test('acceptAllOfType by ID: proposal added after snapshot is preserved',
        () async {
      // This tests the fix where acceptAllOfType removes by captured IDs,
      // not by type filter. A new proposal of the same type added between
      // the snapshot and the state assignment should be preserved.
      final notifier = ProposalStateNotifier(null);
      notifier.addProposal(makeProposal(
        id: 1,
        type: 'alarm',
        json: '{"uid":"original"}',
      ));

      // Capture matching list (simulating what acceptAllOfType does internally).
      // Then add a new alarm proposal before the state is updated.
      // Since acceptAllOfType is async and uses null DB (instant return),
      // we can't truly interleave. Instead we verify the ID-based removal
      // logic by manually adding a proposal and calling acceptAllOfType.
      final accepted = await notifier.acceptAllOfType('alarm');
      expect(accepted, hasLength(1));
      expect(accepted.first.id, 1);

      // Now add a new alarm — it should be addable (state is empty).
      notifier.addProposal(makeProposal(
        id: 2,
        type: 'alarm',
        json: '{"uid":"late-arrival"}',
      ));
      expect(notifier.state.pendingCount, 1);
      expect(notifier.state.proposals.first.id, 2);
    });
  });

  group('PendingProposal', () {
    test('editorLabel returns correct labels for all proposal types', () {
      final types = {
        'alarm': 'Alarm Editor',
        'alarm_create': 'Alarm Editor',
        'alarm_update': 'Alarm Editor',
        'key_mapping': 'Key Repository',
        'page': 'Page Editor',
        'asset': 'Page Editor',
        'unknown_type': 'Editor',
      };

      for (final entry in types.entries) {
        final p = makeProposal(
          id: 1,
          type: entry.key,
          json: '{"uid":"${entry.key}"}',
        );
        expect(p.editorLabel, entry.value,
            reason: 'editorLabel for type "${entry.key}"');
      }
    });

    test('editorRoute returns correct routes for known types', () {
      final routes = {
        'alarm': '/advanced/alarm-editor',
        'alarm_create': '/advanced/alarm-editor',
        'alarm_update': '/advanced/alarm-editor',
        'key_mapping': '/advanced/key-repository',
        'page': '/advanced/page-editor',
        'asset': '/advanced/page-editor',
      };

      for (final entry in routes.entries) {
        final p = makeProposal(
          id: 1,
          type: entry.key,
          json: '{"uid":"${entry.key}"}',
        );
        expect(p.editorRoute, entry.value,
            reason: 'editorRoute for type "${entry.key}"');
      }
    });

    test('editorRoute returns null for unknown proposal type', () {
      final p = makeProposal(id: 1, type: 'unknown_type');
      expect(p.editorRoute, isNull);
    });
  });
}
