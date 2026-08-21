import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level assertions for alarm_editor.dart proposal handling.
///
/// AlarmEditorPage depends on the alarmManProvider and preferences chains,
/// which is why these are source assertions rather than widget tests.
///
/// The shape they pin changed on 2026-08-19. Proposals used to be staged one
/// at a time and accepted from an inline amber bar in this page. An MCP client
/// fires create_alarm one call per alarm, so a set of 38 arrived as 38
/// proposals and cost 38 reviews and 38 saves — and the inline bar was a
/// second place to act on a proposal, competing with the black banner. Both
/// are gone: the page stages the whole queue and publishes commit/discard to
/// the banner.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/pages/alarm_editor.dart').readAsStringSync();
  });

  group('AlarmEditorPage proposal support', () {
    test('has proposalData parameter', () {
      expect(source, contains('proposalData'));
    });

    test('stages proposals in initState', () {
      expect(source, contains('_stageAlarmProposals()'));
    });
  });

  group('proposals are staged as a batch, not one at a time', () {
    test('keeps a list of staged alarms and their proposal ids', () {
      expect(source, contains('_proposedAlarms'));
      expect(source, contains('_proposalIds'));
    });

    test('_isProposal is derived from the batch, not a separate flag', () {
      expect(source,
          contains('bool get _isProposal => _proposedAlarms.isNotEmpty'));
    });

    test('skips ids already staged so re-entry cannot double-apply', () {
      expect(source, contains('_proposalIds.contains(p.id)'));
    });

    test('accepts all three alarm proposal types', () {
      expect(source, contains("p.proposalType != 'alarm'"));
      expect(source, contains("p.proposalType != 'alarm_create'"));
      expect(source, contains("p.proposalType != 'alarm_update'"));
    });

    test('strips _proposal_type before building the AlarmConfig', () {
      expect(source, contains("remove('_proposal_type')"));
      expect(source, contains('AlarmConfig.fromJson(map)'));
    });

    test('tolerates a malformed proposal without dropping the batch', () {
      expect(source, contains('jsonDecode(p.proposalJson)'));
      expect(source, contains('is! Map<String, dynamic>'));
    });
  });

  group('the banner owns accept/reject — nothing inline', () {
    test('publishes commit and discard to the banner', () {
      expect(source, contains('proposalCommitProvider'));
      expect(source, contains('proposalDiscardProvider'));
      expect(source, contains('_commitProposals'));
      expect(source, contains('_discardProposals'));
    });

    test('no inline Accept/Reject buttons remain', () {
      // The amber bar carried an ElevatedButton 'Accept' and an
      // OutlinedButton 'Reject', keyed alarm-proposal-accept/reject. Two
      // competing controls meant an operator could accept in one place while
      // the other still showed the change as pending.
      expect(source, isNot(contains('alarm-proposal-accept')));
      expect(source, isNot(contains('alarm-proposal-reject')));
      expect(source, isNot(contains("child: const Text('Accept')")));
      expect(source, isNot(contains("child: const Text('Reject')")));
    });

    test('a staged batch is still announced in the page', () {
      expect(source, contains('AI alarm proposals'));
    });
  });

  group('commit applies before it accepts', () {
    test('writes the alarms, then marks the proposals accepted', () {
      final commit = source.substring(source.indexOf('_commitProposals() async'));
      final write = commit.indexOf('alarmMan.updateAlarm(a)');
      final accept = commit.indexOf('acceptProposal');
      expect(write, greaterThan(-1));
      expect(accept, greaterThan(-1));
      expect(write, lessThan(accept),
          reason: 'acceptProposal marks the row accepted in the database, so '
              'doing it first would lose the alarms if the write failed');
    });

    test('awaits each accept rather than firing and forgetting', () {
      expect(source, contains('await notifier.acceptProposal(id)'));
    });

    test('rebuilds the alarm list after applying', () {
      expect(source, contains('ref.invalidate(alarmManProvider)'));
    });
  });

  group('a delete proposal removes the alarm', () {
    test('recognises the delete op', () {
      expect(source, contains("'_op'"));
      expect(source, contains("'delete'"));
    });

    test('tracks which staged alarms are removals', () {
      expect(source, contains('_proposedDeleteUids'));
    });

    test('commits a removal through removeAlarm, not updateAlarm', () {
      // updateAlarm removes then re-adds, so routing a delete through it
      // would write the alarm straight back and delete nothing.
      final commit =
          source.substring(source.indexOf('_commitProposals() async'));
      expect(commit, contains('alarmMan.removeAlarm('));
    });

    test('the removal branch is chosen per alarm, not per batch', () {
      // A batch can mix creates, updates and deletes -- they arrive as
      // separate MCP calls and stage together.
      expect(source, contains('_proposedDeleteUids.contains('));
    });

    test('a removal proposal is not offered as an editable form', () {
      // Editing the fields of an alarm you are about to delete is
      // meaningless, and submitting that form used to re-add it.
      expect(source, contains('alarm-removal-form'));
    });
  });

  group('editing a single proposal still works', () {
    test('the form keeps its own Accept Proposal submit', () {
      expect(source, contains("submitText: 'Accept Proposal'"));
      expect(source, contains('_acceptProposalWithConfig'));
    });

    test('accepting one edited alarm leaves the rest of the batch staged', () {
      expect(source, contains('_proposalIds.removeAt(0)'));
      expect(source, contains('_proposedAlarms.removeAt(0)'));
    });
  });
}
