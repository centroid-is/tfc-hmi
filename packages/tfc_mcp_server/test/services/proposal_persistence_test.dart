import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';

void main() {
  late ServerDatabase db;

  setUp(() {
    db = ServerDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('ProposalService with ServerDatabase', () {
    test('BUG-A: mcp_proposal table exists after migration', () async {
      // Verify the table was created by the migration.
      // This will throw if the table doesn't exist.
      final rows =
          await db.customSelect('SELECT * FROM mcp_proposal').get();
      expect(rows, isEmpty);
    });

    test('BUG-B: _recordProposal inserts into ServerDatabase', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'testuser',
      );

      service.wrapProposal('alarm', {
        'title': 'Pump Overcurrent',
        'key': 'pump3.overcurrent',
      });

      // Wait for async fire-and-forget DB write
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final rows =
          await db.customSelect('SELECT * FROM mcp_proposal').get();

      expect(rows, hasLength(1));
      expect(rows.first.read<String>('proposal_type'), 'alarm');
      expect(rows.first.read<String>('title'), 'Pump Overcurrent');
      expect(rows.first.read<String>('operator_id'), 'testuser');
      expect(rows.first.read<String>('status'), 'pending');
    });

    test('BUG-B: multiple proposals insert correctly', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op1',
      );

      service.wrapProposal('alarm', {'title': 'High Temp'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      service.wrapProposal('page', {'title': 'Dashboard'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      service.wrapProposal('key_mapping', {'key': 'pump3.speed'});
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final rows = await db
          .customSelect('SELECT * FROM mcp_proposal ORDER BY id ASC')
          .get();

      expect(rows, hasLength(3));
      expect(rows[0].read<String>('proposal_type'), 'alarm');
      expect(rows[1].read<String>('proposal_type'), 'page');
      expect(rows[2].read<String>('proposal_type'), 'key_mapping');
    });

    test('proposal_json contains full wrapped payload', () async {
      final service = ProposalService(
        database: db,
        operatorId: 'op',
      );

      service.wrapProposal('alarm', {
        'title': 'Test',
        'uid': 'abc-123',
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final rows = await db
          .customSelect('SELECT proposal_json FROM mcp_proposal')
          .get();

      final json = rows.first.read<String>('proposal_json');
      expect(json, contains('"_proposal_type":"alarm"'));
      expect(json, contains('"uid":"abc-123"'));
    });
  });
}
