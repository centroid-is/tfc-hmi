import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';
import 'package:tfc_dart/core/database_drift.dart';

import 'package:tfc_mcp_server/src/services/proposal_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemoryForTest();
  });

  tearDown(() async {
    await db.close();
  });

  group('ProposalService', () {
    test('wrapProposal adds _proposal_type field', () async {
      final service = ProposalService();
      final result = await service.wrapProposal('alarm', {'title': 'Test'});

      expect(result['_proposal_type'], 'alarm');
      expect(result['title'], 'Test');
    });

    test('wrapProposal records proposal in database', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'testuser',
      );

      await service.wrapProposal('alarm', {
        'title': 'Pump Overcurrent',
        'key': 'pump3.overcurrent',
      });

      // Wait for async DB write
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final rows = await db
          .customSelect('SELECT * FROM mcp_proposal')
          .get();

      expect(rows, hasLength(1));
      expect(rows.first.read<String>('proposal_type'), 'alarm');
      expect(rows.first.read<String>('title'), 'Pump Overcurrent');
      expect(rows.first.read<String>('operator_id'), 'testuser');
      expect(rows.first.read<String>('status'), 'pending');
    });

    test('wrapProposal stamps _op create by default', () async {
      final service = ProposalService();
      final result = await service.wrapProposal('alarm', {'title': 'Test'});

      expect(result['_op'], 'create');
    });

    test('wrapProposal stamps the op it is given', () async {
      // 'alarm' and 'key_mapping' cover creates, updates and deletes alike,
      // so the type cannot tell the notification banner what accepting the
      // proposal does -- _op is what it labels each row with.
      final service = ProposalService();

      final updated =
          await service.wrapProposal('alarm', {'title': 'T'}, op: 'update');
      expect(updated['_op'], 'update');
      final deleted = await service
          .wrapProposal('key_mapping', {'key': 'k'}, op: 'delete');
      expect(deleted['_op'], 'delete');
    });

    test('wrapProposal without database does not throw', () async {
      final service = ProposalService();
      final result = await service.wrapProposal('page', {'title': 'My Page'});

      expect(result['_proposal_type'], 'page');
      expect(result.containsKey('_proposal_id'), isFalse);
    });

    test('derives title from proposal fields', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      // Alarm with title
      await service.wrapProposal('alarm', {'title': 'High Temp'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Key mapping with key
      await service.wrapProposal('key_mapping', {'key': 'pump3.speed'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final rows = await db
          .customSelect(
              'SELECT title FROM mcp_proposal ORDER BY id ASC')
          .get();

      expect(rows[0].read<String>('title'), 'High Temp');
      expect(rows[1].read<String>('title'), 'pump3.speed');
    });

    test('onProposal callback fires with wrapped proposal', () async {
      final captured = <Map<String, dynamic>>[];
      final service = ProposalService(
        onProposal: (wrapped) => captured.add(wrapped),
      );

      await service.wrapProposal('alarm', {
        'title': 'Test Alarm',
        'key': 'pump3.fault',
      });

      expect(captured, hasLength(1));
      expect(captured.first['_proposal_type'], 'alarm');
      expect(captured.first['title'], 'Test Alarm');
      expect(captured.first['key'], 'pump3.fault');
    });

    test('onProposal callback receives the same map as return value', () async {
      Map<String, dynamic>? callbackResult;
      final service = ProposalService(
        onProposal: (wrapped) => callbackResult = wrapped,
      );

      final returnValue = await service.wrapProposal('page', {'title': 'My Page'});

      expect(callbackResult, isNotNull);
      expect(callbackResult, equals(returnValue));
    });

    test('onProposal callback not invoked when null', () async {
      // No callback — should not throw
      final service = ProposalService();
      final result = await service.wrapProposal('alarm', {'title': 'Test'});
      expect(result['_proposal_type'], 'alarm');
    });

    test('derives fallback title for alarm with key but no title', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      await service.wrapProposal('alarm', {'key': 'pump3.overcurrent'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'pump3.overcurrent');
    });

    test('derives fallback title for alarm with no title or key', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      await service.wrapProposal('alarm', {'description': 'some desc'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'Alarm Proposal');
    });

    test('derives fallback title for page type', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      await service.wrapProposal('page', {'key': 'dashboard-main'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'dashboard-main');
    });

    test('derives fallback title for unknown type with title field', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      await service.wrapProposal('custom_type', {'title': 'Custom Title'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'Custom Title');
    });

    test('derives generic fallback title for unknown type with no fields',
        () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      await service.wrapProposal('custom_type', {'other': 'data'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'Proposal');
    });

    test('derives fallback title for asset type', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      await service.wrapProposal('asset', {'key': 'pump3'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'pump3');
    });

    test('operatorId defaults to unknown when not provided', () async {
      final service = ProposalService(database: db);

      await service.wrapProposal('alarm', {'title': 'Test'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows =
          await db.customSelect('SELECT operator_id FROM mcp_proposal').get();
      expect(rows.first.read<String>('operator_id'), 'unknown');
    });

    test('proposal_json contains wrapped data with _proposal_type', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      await service.wrapProposal('alarm', {'title': 'Test', 'uid': 'abc-123'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows =
          await db.customSelect('SELECT proposal_json FROM mcp_proposal').get();
      final json = rows.first.read<String>('proposal_json');
      expect(json, contains('"_proposal_type":"alarm"'));
      expect(json, contains('"uid":"abc-123"'));
    });

    test('wrapProposal returns the mcp_proposal row id as _proposal_id',
        () async {
      final service = ProposalService(database: db, operatorId: 'op');

      final first = await service.wrapProposal('alarm', {'title': 'A'});
      final second = await service.wrapProposal('page', {'title': 'B'});

      final rows = await db
          .customSelect('SELECT id, title FROM mcp_proposal ORDER BY id ASC')
          .get();
      expect(first['_proposal_id'], rows[0].read<int>('id'));
      expect(second['_proposal_id'], rows[1].read<int>('id'));
    });

    test('onProposal callback map carries _proposal_id', () async {
      Map<String, dynamic>? callbackResult;
      final service = ProposalService(
        database: db,
        operatorId: 'op',
        onProposal: (wrapped) => callbackResult = wrapped,
      );

      final result = await service.wrapProposal('alarm', {'title': 'A'});

      expect(callbackResult?['_proposal_id'], result['_proposal_id']);
      expect(result['_proposal_id'], isA<int>());
    });
  });

  group('ProposalService.getProposalStatuses', () {
    test('returns empty without a database', () async {
      final service = ProposalService();
      expect(await service.getProposalStatuses(), isEmpty);
    });

    test('lists recorded proposals newest-first with status', () async {
      final service = ProposalService(database: db, operatorId: 'op');
      await service.wrapProposal('alarm', {'title': 'High Temp'});
      await service.wrapProposal('page', {'title': 'Dashboard'});

      final statuses = await service.getProposalStatuses();

      expect(statuses, hasLength(2));
      expect(statuses[0]['title'], 'Dashboard');
      expect(statuses[0]['type'], 'page');
      expect(statuses[0]['status'], 'pending');
      expect(statuses[1]['title'], 'High Temp');
      expect(statuses[0]['created_at'], isNotEmpty);
    });

    test('filters by ids and reflects status updates', () async {
      final service = ProposalService(database: db, operatorId: 'op');
      final a = await service.wrapProposal('alarm', {'title': 'A'});
      await service.wrapProposal('alarm', {'title': 'B'});
      final aId = a['_proposal_id'] as int;

      await db.customStatement(
        'UPDATE mcp_proposal SET status = ? WHERE id = ?',
        ['accepted', aId],
      );

      final statuses = await service.getProposalStatuses(ids: [aId]);

      expect(statuses, hasLength(1));
      expect(statuses.first['id'], aId);
      expect(statuses.first['status'], 'accepted');
    });
  });

  group('ProposalService.formatCreateDiff', () {
    test('produces markdown table with correct structure', () {
      final service = ProposalService();
      final diff = service.formatCreateDiff('Alarm', 'Pump Fault', {
        'key': 'pump3.fault',
        'level': 'error',
      });

      expect(diff, contains('## Proposal: Create Alarm'));
      expect(diff, contains('**Pump Fault**'));
      expect(diff, contains('| Field | Value |'));
      expect(diff, contains('| key | pump3.fault |'));
      expect(diff, contains('| level | error |'));
    });
  });

  group('ProposalService.formatUpdateDiff', () {
    test('produces markdown before/after table', () {
      final service = ProposalService();
      final diff = service.formatUpdateDiff('Alarm', 'Pump Fault', {
        'level': 'warning -> error',
        'formula': 'x > 10 -> x > 20',
      });

      expect(diff, contains('## Proposal: Update Alarm'));
      expect(diff, contains('**Pump Fault**'));
      expect(diff, contains('| Field | Before | After |'));
      expect(diff, contains('| level | warning | error |'));
      expect(diff, contains('| formula | x > 10 | x > 20 |'));
    });
  });
}
