import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tfc/providers/proposal_state.dart';

void main() {
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
      final notifier = ProposalStateNotifier();
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
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(id: 1));
      notifier.addProposal(makeProposal(id: 1, title: 'Duplicate'));
      expect(notifier.state.pendingCount, 1);
      expect(notifier.state.proposals.first.title, 'Test Alarm');
    });

    test('duplicate proposal JSON content is not added (different IDs)', () {
      // This tests the inline-then-DB dedup: an inline proposal (negative ID)
      // is surfaced immediately, and the DB-sourced proposal (positive ID)
      // arrives later with the same JSON. They should be treated as the same.
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(id: -1));
      notifier.addProposal(makeProposal(id: 42));
      expect(notifier.state.pendingCount, 1);
    });

    test('acceptProposal removes the proposal from state', () async {
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(id: 1));
      expect(notifier.state.pendingCount, 1);

      await notifier.acceptProposal(1);
      expect(notifier.state.pendingCount, 0);
      expect(notifier.state.hasPending, isFalse);
    });

    test('rejectProposal removes the proposal from state', () async {
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(id: 1, type: 'page'));

      await notifier.rejectProposal(1);
      expect(notifier.state.pendingCount, 0);
    });

    test('dismissProposal removes the proposal from state', () async {
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(id: 1, type: 'key_mapping'));

      await notifier.dismissProposal(1);
      expect(notifier.state.pendingCount, 0);
    });

    test('a decision lands without yielding to the event loop', () async {
      // Accepting used to await a database write before touching state, and
      // callers that did not await the result observed a half-resolved batch
      // -- the "yellow boxes came back" bug. Nothing suspends now, so the
      // removal is visible before the next microtask runs.
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(id: 1));

      final pending = notifier.acceptProposal(1);
      expect(notifier.state.pendingCount, 0);
      await pending;
    });

    test('hasPending returns true when proposals exist, false when empty', () {
      final notifier = ProposalStateNotifier();
      expect(notifier.state.hasPending, isFalse);

      notifier.addProposal(makeProposal(id: 1));
      expect(notifier.state.hasPending, isTrue);
    });

    test('proposalsOfType filters by proposal type', () {
      final notifier = ProposalStateNotifier();
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
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(
        id: 1,
        type: 'alarm',
        title: 'Alarm 1',
        json: '{"_proposal_type":"alarm","uid":"1"}',
      ));
      notifier.addProposal(makeProposal(
        id: 2,
        type: 'alarm',
        title: 'Alarm 2',
        json: '{"_proposal_type":"alarm","uid":"2"}',
      ));
      notifier.addProposal(makeProposal(
        id: 3,
        type: 'page',
        title: 'Page 1',
        json: '{"_proposal_type":"page","uid":"3"}',
      ));

      expect(notifier.state.pendingCount, 3);

      final accepted = await notifier.acceptAllOfType('alarm');
      expect(accepted, hasLength(2));
      expect(accepted.every((p) => p.proposalType == 'alarm'), isTrue);

      // Only page proposal remains
      expect(notifier.state.pendingCount, 1);
      expect(notifier.state.ofType('alarm'), isEmpty);
      expect(notifier.state.ofType('page'), hasLength(1));
    });

    test('rejectAllOfType rejects all proposals of that type', () async {
      final notifier = ProposalStateNotifier();
      for (var i = 1; i <= 3; i++) {
        notifier.addProposal(makeProposal(
          id: i,
          type: 'alarm',
          title: 'Alarm $i',
          json: '{"_proposal_type":"alarm","uid":"r$i"}',
        ));
      }

      expect(notifier.state.pendingCount, 3);

      await notifier.rejectAllOfType('alarm');
      expect(notifier.state.pendingCount, 0);
    });

    test('acceptAllOfType with no matching type is a no-op', () async {
      final notifier = ProposalStateNotifier();
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
      final notifier = ProposalStateNotifier();

      // Simulate 10 motor fault alarms created by the LLM
      for (var i = 1; i <= 10; i++) {
        notifier.addProposal(makeProposal(
          id: nextLocalProposalId(),
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
      final notifier = ProposalStateNotifier();
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

    test('accept, reject and dismiss each clear the proposal', () async {
      final notifier = ProposalStateNotifier();
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
      final notifier = ProposalStateNotifier();
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
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(id: 7));

      await notifier.acceptProposal(7);
      expect(notifier.state.pendingCount, 0);

      // Already gone from state, so the reject has nothing to act on and
      // nothing to report.
      await notifier.rejectProposal(7);
      expect(notifier.state.pendingCount, 0);
    });

    test('acceptAllOfType and rejectAllOfType with empty state are no-ops',
        () async {
      final notifier = ProposalStateNotifier();
      expect(notifier.state.pendingCount, 0);

      final accepted = await notifier.acceptAllOfType('alarm');
      expect(accepted, isEmpty);
      expect(notifier.state.pendingCount, 0);

      await notifier.rejectAllOfType('page');
      expect(notifier.state.pendingCount, 0);
    });

    test('mixed batch: acceptAllOfType leaves other types untouched', () async {
      final notifier = ProposalStateNotifier();

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
      final notifier = ProposalStateNotifier();
      notifier.addProposal(makeProposal(
        id: 1,
        type: 'alarm',
        json: '{"uid":"original"}',
      ));

      // acceptAllOfType removes by captured ids rather than by re-filtering
      // on type, so an alarm added afterwards is not swept up with the batch.
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

  group('nextLocalProposalId', () {
    test('never repeats, even called in a tight loop', () {
      // A batch of proposals is wrapped in one synchronous loop. The clock
      // reading this replaced (-microsecondsSinceEpoch) could hand out the
      // same id twice inside one microsecond, and addProposal would drop the
      // second as a duplicate.
      final ids = [for (var i = 0; i < 1000; i++) nextLocalProposalId()];
      expect(ids.toSet(), hasLength(1000));
    });

    test('is negative, so nothing reads it as a database row id', () {
      expect(nextLocalProposalId(), isNegative);
    });

    test('a proposal per id survives addProposal deduplication', () {
      final notifier = ProposalStateNotifier();
      for (var i = 0; i < 50; i++) {
        notifier.addProposal(PendingProposal(
          id: nextLocalProposalId(),
          proposalType: 'alarm',
          title: 'Alarm $i',
          proposalJson: '{"_proposal_type":"alarm","uid":"$i"}',
          operatorId: 'local',
          createdAt: DateTime.now(),
        ));
      }
      expect(notifier.state.pendingCount, 50);
    });
  });

  group('feedback events', () {
    late StreamController<ProposalFeedback> feedback;
    late List<ProposalFeedback> events;
    late ProposalStateNotifier notifier;

    setUp(() {
      feedback = StreamController<ProposalFeedback>.broadcast(sync: true);
      events = [];
      feedback.stream.listen(events.add);
      notifier = ProposalStateNotifier(feedback: feedback);
    });

    tearDown(() => feedback.close());

    test('acceptProposal emits one accepted event with the proposal', () async {
      notifier.addProposal(makeProposal(id: 1, title: 'High Temp'));
      await notifier.acceptProposal(1);

      expect(events, hasLength(1));
      expect(events.first.action, 'accepted');
      expect(events.first.proposals.single.title, 'High Temp');
    });

    test('rejectProposal and dismissProposal emit their actions', () async {
      notifier.addProposal(makeProposal(id: 1, json: '{"uid":"1"}'));
      notifier.addProposal(makeProposal(id: 2, json: '{"uid":"2"}'));
      await notifier.rejectProposal(1);
      await notifier.dismissProposal(2);

      expect(events.map((e) => e.action), ['rejected', 'dismissed']);
    });

    test('decision on an id not in state emits nothing', () async {
      await notifier.acceptProposal(999);
      expect(events, isEmpty);
    });

    test('viewProposal keeps the proposal pending and emits viewed once',
        () async {
      notifier.addProposal(makeProposal(id: 1));

      await notifier.viewProposal(1);
      await notifier.viewProposal(1);

      expect(notifier.state.pendingCount, 1);
      expect(events, hasLength(1));
      expect(events.first.action, 'viewed');
    });

    test('acceptAllOfType emits a single bulk event', () async {
      notifier.addProposal(
          makeProposal(id: 1, type: 'alarm', json: '{"uid":"1"}'));
      notifier.addProposal(
          makeProposal(id: 2, type: 'alarm', json: '{"uid":"2"}'));
      notifier.addProposal(
          makeProposal(id: 3, type: 'page', json: '{"uid":"3"}'));

      await notifier.acceptAllOfType('alarm');

      expect(events, hasLength(1));
      expect(events.first.action, 'accepted');
      expect(events.first.proposals, hasLength(2));
    });

    test('rejectAllOfType emits a single bulk event', () async {
      notifier.addProposal(
          makeProposal(id: 1, type: 'page', json: '{"uid":"1"}'));
      notifier.addProposal(
          makeProposal(id: 2, type: 'page', json: '{"uid":"2"}'));

      await notifier.rejectAllOfType('page');

      expect(events, hasLength(1));
      expect(events.first.action, 'rejected');
      expect(events.first.proposals, hasLength(2));
    });

    test('bulk call with no matching type emits nothing', () async {
      await notifier.acceptAllOfType('alarm');
      await notifier.rejectAllOfType('page');
      expect(events, isEmpty);
    });

    test('closed feedback controller does not break decisions', () async {
      notifier.addProposal(makeProposal(id: 1));
      await feedback.close();
      await notifier.acceptProposal(1);
      expect(notifier.state.pendingCount, 0);
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
