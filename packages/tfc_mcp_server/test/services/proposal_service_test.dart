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
    test('wrapProposal adds _proposal_type field', () {
      final service = ProposalService();
      final result = service.wrapProposal('alarm', {'title': 'Test'});

      expect(result['_proposal_type'], 'alarm');
      expect(result['title'], 'Test');
    });

    test('wrapProposal records proposal in database', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'testuser',
      );

      service.wrapProposal('alarm', {
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

    test('wrapProposal without database does not throw', () {
      final service = ProposalService();
      final result = service.wrapProposal('page', {'title': 'My Page'});

      expect(result['_proposal_type'], 'page');
    });

    test('derives title from proposal fields', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      // Alarm with title
      service.wrapProposal('alarm', {'title': 'High Temp'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Key mapping with key
      service.wrapProposal('key_mapping', {'key': 'pump3.speed'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final rows = await db
          .customSelect(
              'SELECT title FROM mcp_proposal ORDER BY id ASC')
          .get();

      expect(rows[0].read<String>('title'), 'High Temp');
      expect(rows[1].read<String>('title'), 'pump3.speed');
    });

    test('onProposal callback fires synchronously with wrapped proposal', () {
      final captured = <Map<String, dynamic>>[];
      final service = ProposalService(
        onProposal: (wrapped) => captured.add(wrapped),
      );

      service.wrapProposal('alarm', {
        'title': 'Test Alarm',
        'key': 'pump3.fault',
      });

      // Callback should have fired synchronously (no await needed)
      expect(captured, hasLength(1));
      expect(captured.first['_proposal_type'], 'alarm');
      expect(captured.first['title'], 'Test Alarm');
      expect(captured.first['key'], 'pump3.fault');
    });

    test('onProposal callback receives the same map as return value', () {
      Map<String, dynamic>? callbackResult;
      final service = ProposalService(
        onProposal: (wrapped) => callbackResult = wrapped,
      );

      final returnValue = service.wrapProposal('page', {'title': 'My Page'});

      expect(callbackResult, isNotNull);
      expect(callbackResult, equals(returnValue));
    });

    test('onProposal callback not invoked when null', () {
      // No callback — should not throw
      final service = ProposalService();
      final result = service.wrapProposal('alarm', {'title': 'Test'});
      expect(result['_proposal_type'], 'alarm');
    });

    test('derives fallback title for alarm with key but no title', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      service.wrapProposal('alarm', {'key': 'pump3.overcurrent'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'pump3.overcurrent');
    });

    test('derives fallback title for alarm with no title or key', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      service.wrapProposal('alarm', {'description': 'some desc'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'Alarm Proposal');
    });

    test('derives fallback title for page type', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      service.wrapProposal('page', {'key': 'dashboard-main'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'dashboard-main');
    });

    test('derives fallback title for unknown type with title field', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      service.wrapProposal('custom_type', {'title': 'Custom Title'});
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

      service.wrapProposal('custom_type', {'other': 'data'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'Proposal');
    });

    test('derives fallback title for asset type', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      service.wrapProposal('asset', {'key': 'pump3'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db.customSelect('SELECT title FROM mcp_proposal').get();
      expect(rows.first.read<String>('title'), 'pump3');
    });

    test('operatorId defaults to unknown when not provided', () async {
      final service = ProposalService(database: db);

      service.wrapProposal('alarm', {'title': 'Test'});
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

      service.wrapProposal('alarm', {'title': 'Test', 'uid': 'abc-123'});
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows =
          await db.customSelect('SELECT proposal_json FROM mcp_proposal').get();
      final json = rows.first.read<String>('proposal_json');
      expect(json, contains('"_proposal_type":"alarm"'));
      expect(json, contains('"uid":"abc-123"'));
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
