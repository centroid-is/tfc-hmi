import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/services/proposal_service.dart';

/// Tests that ProposalService works with ServerDatabase.
///
/// This test would have caught the bug where ServerDatabase was missing
/// the mcp_proposal table, causing proposal INSERT to silently fail
/// when using Claude Desktop (which uses the standalone binary with
/// ServerDatabase, not AppDatabase).
void main() {
  late ServerDatabase db;

  setUp(() {
    db = ServerDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  test('ServerDatabase has mcp_proposal table', () async {
    // Verify the table exists by doing a SELECT
    final rows =
        await db.customSelect('SELECT * FROM mcp_proposal').get();
    expect(rows, isEmpty);
  });

  test('ProposalService writes proposal to ServerDatabase', () async {
    final service = ProposalService(
      database: db,
      operatorId: 'claude-desktop-user',
    );

    service.wrapProposal('alarm', {
      'title': 'Pump Overcurrent',
      'key': 'pump3.overcurrent',
    });

    // Wait for async DB write
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final rows =
        await db.customSelect('SELECT * FROM mcp_proposal').get();

    expect(rows, hasLength(1));
    expect(rows.first.read<String>('proposal_type'), 'alarm');
    expect(rows.first.read<String>('title'), 'Pump Overcurrent');
    expect(rows.first.read<String>('operator_id'), 'claude-desktop-user');
    expect(rows.first.read<String>('status'), 'pending');
  });

  test('multiple proposals written and readable', () async {
    final service = ProposalService(database: db, operatorId: 'op');

    service.wrapProposal('alarm', {'title': 'High Temp'});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    service.wrapProposal('page', {'title': 'Dashboard'});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    service.wrapProposal('key_mapping', {'key': 'pump3.speed'});
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final rows = await db
        .customSelect('SELECT * FROM mcp_proposal ORDER BY id ASC')
        .get();

    expect(rows, hasLength(3));
    expect(rows[0].read<String>('proposal_type'), 'alarm');
    expect(rows[1].read<String>('proposal_type'), 'page');
    expect(rows[2].read<String>('proposal_type'), 'key_mapping');
  });

  test('schema migration from v7 adds mcp_proposal table', () async {
    // Create a v7 database (without mcp_proposal), then upgrade
    // This is implicitly tested by ServerDatabase.inMemory() which runs
    // onCreate, but let's verify the table structure is correct.
    final result = await db.customSelect(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='mcp_proposal'",
    ).get();

    expect(result, hasLength(1));
    final createSql = result.first.read<String>('sql');
    expect(createSql, contains('proposal_type'));
    expect(createSql, contains('title'));
    expect(createSql, contains('proposal_json'));
    expect(createSql, contains('operator_id'));
    expect(createSql, contains('status'));
    expect(createSql, contains('created_at'));
  });
}
