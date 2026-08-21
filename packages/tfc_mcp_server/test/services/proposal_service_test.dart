import 'dart:convert';

import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/services/proposal_service.dart';

void main() {
  group('ProposalService', () {
    test('wrapProposal adds _proposal_type field', () async {
      final service = ProposalService();
      final result = await service.wrapProposal('alarm', {'title': 'Test'});

      expect(result['_proposal_type'], 'alarm');
      expect(result['title'], 'Test');
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

    test('wrapProposal stores nothing and stamps no row id', () async {
      // The proposal used to be inserted into mcp_proposal and the row id
      // handed back as _proposal_id. Nothing is persisted now, so there is no
      // id to hand back and the UI mints its own.
      final service = ProposalService();
      final result = await service.wrapProposal('page', {'title': 'My Page'});

      expect(result['_proposal_type'], 'page');
      expect(result.containsKey('_proposal_id'), isFalse);
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

    test('onProposal fires before wrapProposal completes', () async {
      // The callback is the only delivery path, and write tools return
      // immediately after wrapping. If it were deferred, a tool could return
      // before the operator's banner knew anything about the proposal.
      final captured = <Map<String, dynamic>>[];
      final service = ProposalService(onProposal: captured.add);

      final future = service.wrapProposal('alarm', {'title': 'Test'});
      expect(captured, hasLength(1));
      await future;
    });

    test('onProposal callback receives the same map as return value', () async {
      // Not merely equal: the tool result is jsonEncode of this very map, and
      // the UI deduplicates the two copies of a proposal by comparing that
      // encoding.
      Map<String, dynamic>? callbackResult;
      final service = ProposalService(
        onProposal: (wrapped) => callbackResult = wrapped,
      );

      final returnValue =
          await service.wrapProposal('page', {'title': 'My Page'});

      expect(callbackResult, same(returnValue));
      expect(jsonEncode(callbackResult), jsonEncode(returnValue));
    });

    test('onProposal callback not invoked when null', () async {
      // No callback — should not throw
      final service = ProposalService();
      final result = await service.wrapProposal('alarm', {'title': 'Test'});
      expect(result['_proposal_type'], 'alarm');
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
