import 'dart:convert';

import 'package:test/test.dart';
import 'package:tfc_mcp_server/src/audit/audit_log_service.dart';
import 'package:tfc_mcp_server/src/database/server_database.dart';
import 'package:tfc_mcp_server/src/safety/proposal_declined_exception.dart';

import '../helpers/test_database.dart';

void main() {
  late ServerDatabase db;
  late AuditLogService service;

  setUp(() {
    db = createTestDatabase();
    service = AuditLogService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('AuditLogService', () {
    group('logIntent', () {
      test('creates a record with status pending and returns the audit ID',
          () async {
        final now = DateTime.utc(2026, 3, 6, 12, 0, 0);
        final id = await service.logIntent(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: {'asset': 'pump3'},
          timestamp: now,
        );

        expect(id, isPositive);

        // Query the DB to verify the record
        final record =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id)))
                .getSingle();

        expect(record.operatorId, equals('op1'));
        expect(record.tool, equals('get_alarms'));
        expect(record.status, equals('pending'));
        expect(record.completedAt, isNull);
        expect(record.createdAt, equals(now));
      });

      test('stores full JSON-encoded arguments', () async {
        final args = {
          'asset': 'pump3',
          'threshold': 15.0,
          'delay': '5s',
        };
        final id = await service.logIntent(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: args,
        );

        final record =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id)))
                .getSingle();

        // The arguments field should be valid JSON that round-trips
        final decoded =
            jsonDecode(record.arguments) as Map<String, dynamic>;
        expect(decoded['asset'], equals('pump3'));
        expect(decoded['threshold'], equals(15.0));
        expect(decoded['delay'], equals('5s'));
      });

      test('stores AI reasoning when provided', () async {
        final id = await service.logIntent(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: {'asset': 'pump3'},
          reasoning:
              'User wants to check pump3 status because of recent high-temp alarm',
        );

        final record =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id)))
                .getSingle();

        expect(
          record.reasoning,
          equals(
              'User wants to check pump3 status because of recent high-temp alarm'),
        );
      });
    });

    group('updateOutcome', () {
      test('changes status from pending to success and sets completedAt',
          () async {
        final id = await service.logIntent(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: {'asset': 'pump3'},
        );

        await service.updateOutcome(id, AuditStatus.success);

        final record =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id)))
                .getSingle();

        expect(record.status, equals('success'));
        expect(record.completedAt, isNotNull);
      });

      test('changes status to failed with error message', () async {
        final id = await service.logIntent(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: {'asset': 'pump3'},
        );

        await service.updateOutcome(
          id,
          AuditStatus.failed,
          error: 'Connection timeout',
        );

        final record =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id)))
                .getSingle();

        expect(record.status, equals('failed'));
        expect(record.error, equals('Connection timeout'));
        expect(record.completedAt, isNotNull);
      });

      test('changes status to declined', () async {
        final id = await service.logIntent(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: {'asset': 'pump3'},
        );

        await service.updateOutcome(id, AuditStatus.declined);

        final record =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id)))
                .getSingle();

        expect(record.status, equals('declined'));
        expect(record.completedAt, isNotNull);
      });
    });

    group('executeWithAudit', () {
      test('wraps a successful handler and updates to success', () async {
        final result = await service.executeWithAudit<String>(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: {'asset': 'pump3'},
          handler: () async => 'alarm_data',
        );

        expect(result, equals('alarm_data'));

        // Verify audit record exists and is marked success
        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        expect(records.first.status, equals('success'));
        expect(records.first.completedAt, isNotNull);
      });

      test(
          'wraps a failing handler: updates to failed and rethrows exception',
          () async {
        await expectLater(
          service.executeWithAudit<String>(
            operatorId: 'op1',
            tool: 'get_alarms',
            arguments: {'asset': 'pump3'},
            handler: () async => throw Exception('boom'),
          ),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('boom'),
          )),
        );

        // Verify audit record exists and is marked failed with error
        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        expect(records.first.status, equals('failed'));
        expect(records.first.error, contains('boom'));
        expect(records.first.completedAt, isNotNull);
      });

      test(
          'wraps a ProposalDeclinedException: updates to declined and rethrows',
          () async {
        await expectLater(
          service.executeWithAudit<String>(
            operatorId: 'op1',
            tool: 'create_alarm',
            arguments: {'name': 'pump3.high_temp'},
            handler: () async =>
                throw ProposalDeclinedException('Proposal declined by operator.'),
          ),
          throwsA(isA<ProposalDeclinedException>()),
        );

        // Verify audit record exists and is marked declined with error message
        final records = await db.select(db.auditLog).get();
        expect(records, hasLength(1));
        expect(records.first.status, equals('declined'));
        expect(records.first.error, equals('Proposal declined by operator.'));
        expect(records.first.completedAt, isNotNull);
      });

      test('pending record survives even if handler crashes', () async {
        // The pending record is created before the handler runs.
        // Even if we don't call updateOutcome (simulating a crash
        // scenario where the process dies mid-handler), the pending
        // record is already in the database.
        final id = await service.logIntent(
          operatorId: 'op1',
          tool: 'dangerous_tool',
          arguments: {'action': 'risky'},
        );

        // Don't call updateOutcome -- simulating a crash
        final record =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id)))
                .getSingle();

        expect(record.status, equals('pending'));
        expect(record.completedAt, isNull);
        // The record survives -- this is the key property
      });
    });

    group('independence', () {
      test('multiple audit records are independent', () async {
        final id1 = await service.logIntent(
          operatorId: 'op1',
          tool: 'get_alarms',
          arguments: {'asset': 'pump1'},
        );
        final id2 = await service.logIntent(
          operatorId: 'op2',
          tool: 'get_tags',
          arguments: {'key': 'speed'},
        );
        final id3 = await service.logIntent(
          operatorId: 'op3',
          tool: 'list_assets',
          arguments: {},
        );

        await service.updateOutcome(id1, AuditStatus.success);
        await service.updateOutcome(id2, AuditStatus.failed,
            error: 'timeout');
        await service.updateOutcome(id3, AuditStatus.declined);

        final r1 =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id1)))
                .getSingle();
        final r2 =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id2)))
                .getSingle();
        final r3 =
            await (db.select(db.auditLog)..where((t) => t.id.equals(id3)))
                .getSingle();

        expect(r1.status, equals('success'));
        expect(r1.operatorId, equals('op1'));

        expect(r2.status, equals('failed'));
        expect(r2.error, equals('timeout'));
        expect(r2.operatorId, equals('op2'));

        expect(r3.status, equals('declined'));
        expect(r3.operatorId, equals('op3'));
      });
    });
  });
}
