import 'dart:async';

import 'package:mcp_dart/mcp_dart.dart' show BasicAbortController;
import 'package:test/test.dart';

import 'package:tfc_mcp_server/src/services/proposal_feedback_bus.dart';

/// The bus is the only thing standing between "the operator clicked Accept"
/// and an external MCP client that was not attached at that moment. Every
/// property tested here is one a client depends on to reason about what it
/// has and has not seen.
void main() {
  Map<String, dynamic> decision(int n) => {
        'title': 'Proposal $n',
        'type': 'asset_update',
        'op': 'update',
      };

  group('publish and since', () {
    test('sequence numbers start at 1 and never repeat', () {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);

      expect(bus.lastSeq, 0, reason: 'nothing published yet');

      final seqs = [
        for (var i = 0; i < 5; i++)
          bus.publish(
            action: 'accepted',
            summary: 'Accepted proposal $i',
            proposals: [decision(i)],
          )['seq'] as int,
      ];

      expect(seqs, [1, 2, 3, 4, 5]);
      expect(bus.lastSeq, 5);
    });

    test('since is strictly greater, so a returned cursor is safe to reuse',
        () {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);

      bus.publish(action: 'accepted', summary: 'one');
      bus.publish(action: 'rejected', summary: 'two');
      bus.publish(action: 'viewed', summary: 'three');

      final all = bus.since(null);
      expect(all.decisions.map((d) => d['summary']), ['one', 'two', 'three']);
      expect(all.lastSeq, 3);

      final afterFirst = bus.since(1);
      expect(afterFirst.decisions.map((d) => d['summary']), ['two', 'three']);

      // Handing the previous last_seq back must yield nothing, not a replay.
      expect(bus.since(all.lastSeq).decisions, isEmpty);
      expect(bus.since(all.lastSeq).lastSeq, 3,
          reason: 'the cursor still moves forward even on an empty slice');
    });

    test('a decision carries the readable summary and per-proposal detail',
        () {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);

      final entry = bus.publish(
        action: 'accepted',
        summary: 'Accepted 2 asset update proposals: '
            '"CVS02.CN01.PX01.Fault: server_alias -> st201", '
            '"Line 1: keys -> SPB01.Recipe".',
        proposals: [
          {
            'title': 'CVS02.CN01.PX01.Fault: server_alias -> st201',
            'type': 'asset_update',
            'op': 'update',
          },
          {
            'title': 'Line 1: keys -> SPB01.Recipe',
            'type': 'asset_update',
            'op': 'update',
          },
        ],
      );

      expect(entry['action'], 'accepted');
      expect(entry['count'], 2);
      expect(entry['summary'], contains('CVS02.CN01.PX01.Fault'));
      expect(entry['at'], isA<String>());
      final proposals = entry['proposals'] as List<dynamic>;
      expect(proposals, hasLength(2));
      expect((proposals.first as Map)['type'], 'asset_update');
      expect((proposals.first as Map)['op'], 'update');
    });

    test('publishing after close throws rather than silently dropping', () async {
      final bus = ProposalFeedbackBus();
      await bus.close();
      expect(
        () => bus.publish(action: 'accepted', summary: 'late'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ring buffer', () {
    test('evicts the oldest decisions past capacity', () {
      final bus = ProposalFeedbackBus(capacity: 3);
      addTearDown(bus.close);

      for (var i = 1; i <= 5; i++) {
        bus.publish(action: 'accepted', summary: 'decision $i');
      }

      final page = bus.since(null);
      expect(page.decisions.map((d) => d['seq']), [3, 4, 5]);
      expect(page.firstAvailableSeq, 3);
      expect(page.lastSeq, 5);
    });

    test('flags truncated when the caller fell behind the ring', () {
      final bus = ProposalFeedbackBus(capacity: 3);
      addTearDown(bus.close);

      for (var i = 1; i <= 5; i++) {
        bus.publish(action: 'accepted', summary: 'decision $i');
      }

      // Cursor 1 wanted decisions 2..5; 2 was evicted, so there is a hole.
      expect(bus.since(1).truncated, isTrue);
      // Cursor 2 wanted 3..5, all of which are still held.
      expect(bus.since(2).truncated, isFalse);
      // A first-time caller cannot have missed anything it knew about.
      expect(bus.since(null).truncated, isFalse);
    });

    test('no truncation flag while inside capacity', () {
      final bus = ProposalFeedbackBus(capacity: 10);
      addTearDown(bus.close);
      for (var i = 1; i <= 5; i++) {
        bus.publish(action: 'accepted', summary: 'decision $i');
      }
      expect(bus.since(1).truncated, isFalse);
      expect(bus.since(1).decisions, hasLength(4));
    });
  });

  group('waitFor', () {
    test('returns the backlog immediately when something is already newer',
        () async {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);
      bus.publish(action: 'accepted', summary: 'already here');

      final page = await bus
          .waitFor(timeout: const Duration(seconds: 30))
          .timeout(const Duration(seconds: 1));

      expect(page.timedOut, isFalse);
      expect(page.decisions.single['summary'], 'already here');
    });

    test('parks until a decision lands, then returns it', () async {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);

      final pending = bus.waitFor(timeout: const Duration(seconds: 30));
      // Give the waiter a chance to park before anything is published.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bus.waiterCount, 1);

      bus.publish(action: 'rejected', summary: 'no thanks');

      final page = await pending.timeout(const Duration(seconds: 2));
      expect(page.timedOut, isFalse);
      expect(page.decisions.single['summary'], 'no thanks');
      expect(bus.waiterCount, 0, reason: 'the waiter slot must be released');
    });

    test('a parked waiter only sees decisions newer than its own cursor',
        () async {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);
      bus.publish(action: 'accepted', summary: 'old news');

      final pending = bus.waitFor(
        since: bus.lastSeq,
        timeout: const Duration(seconds: 30),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bus.publish(action: 'accepted', summary: 'fresh');

      final page = await pending.timeout(const Duration(seconds: 2));
      expect(page.decisions.map((d) => d['summary']), ['fresh']);
    });

    test('times out with an empty page rather than hanging', () async {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);

      final page = await bus
          .waitFor(timeout: const Duration(milliseconds: 60))
          .timeout(const Duration(seconds: 2));

      expect(page.timedOut, isTrue);
      expect(page.decisions, isEmpty);
      expect(page.lastSeq, 0);
      expect(bus.waiterCount, 0);
    });

    test('a cancelled request releases its waiter immediately', () async {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);
      final controller = BasicAbortController();

      final pending = bus.waitFor(
        timeout: const Duration(seconds: 30),
        signal: controller.signal,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bus.waiterCount, 1);

      controller.abort('client went away');

      final page = await pending.timeout(const Duration(seconds: 2));
      expect(page.decisions, isEmpty);
      expect(page.timedOut, isFalse,
          reason: 'a cancel is not a timeout -- the client is gone');
      expect(bus.waiterCount, 0);
    });

    test('an already-aborted signal returns without parking', () async {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);
      final controller = BasicAbortController()..abort();

      final page = await bus
          .waitFor(
            timeout: const Duration(seconds: 30),
            signal: controller.signal,
          )
          .timeout(const Duration(seconds: 1));

      expect(page.decisions, isEmpty);
      expect(bus.waiterCount, 0);
    });

    test('refuses to park more than maxWaiters callers', () async {
      final bus = ProposalFeedbackBus(maxWaiters: 2);
      addTearDown(bus.close);

      final parked = [
        bus.waitFor(timeout: const Duration(seconds: 30)),
        bus.waitFor(timeout: const Duration(seconds: 30)),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bus.waiterCount, 2);

      await expectLater(
        bus.waitFor(timeout: const Duration(seconds: 30)),
        throwsA(isA<ProposalFeedbackBusyException>()),
      );

      bus.publish(action: 'accepted', summary: 'release them');
      await Future.wait(parked).timeout(const Duration(seconds: 2));
    });

    test('closing the bus wakes parked callers instead of stranding them',
        () async {
      final bus = ProposalFeedbackBus();

      final pending = bus.waitFor(timeout: const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await bus.close();

      final page = await pending.timeout(const Duration(seconds: 2));
      expect(page.decisions, isEmpty);
    });
  });

  group('stream', () {
    test('pushes each decision to live listeners', () async {
      final bus = ProposalFeedbackBus();
      addTearDown(bus.close);

      final seen = <Map<String, dynamic>>[];
      final sub = bus.stream.listen(seen.add);
      addTearDown(sub.cancel);

      bus.publish(action: 'accepted', summary: 'first');
      bus.publish(action: 'dismissed', summary: 'second');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(seen.map((e) => e['summary']), ['first', 'second']);
    });
  });
}
