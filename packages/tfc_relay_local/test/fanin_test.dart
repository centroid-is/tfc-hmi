/// The composer's value path, and the refcounted fan-in underneath it.
///
/// Two groups, from two tasks of 08-05. They share a file because the plan's
/// `files_modified` names exactly one test file for this half of the work, and
/// because they share a subject: `LocalStateMan`'s `listen`/`subscribe` are the
/// only way a client can attach a listener, so the composer's read path and the
/// fan-in's refcount are the same mechanism seen from two ends.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tfc_relay_local/tfc_relay_local.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'support/fake_upstream_link.dart';
import 'support/keymap_fixtures.dart';

/// A key no keymapping in this file contains, so the router refuses it.
const String unmappedKey = 'ST101.CN99.MOT01.speed';

/// One link, one router over it, one composer. Returned together because every
/// case needs the driver as well as the subject.
({LocalStateMan man, FakeUpstreamLink link}) buildOneLink({
  Iterable<String> keys = const [st101Key, st201Key],
  Duration linger = Duration.zero,
  Duration staleAfter = const Duration(seconds: 30),
}) {
  final link = FakeUpstreamLink(alias: st101Alias, keys: keys);
  final man = LocalStateMan(
    links: [link],
    router: KeyRouter.overLinks(
      [link],
      mappings: keyMappingsOf(keys, alias: st101Alias),
    ),
    linger: linger,
    staleAfter: staleAfter,
  );
  return (man: man, link: link);
}

void main() {
  group('the composer answers the value path from its own store', () {
    late LocalStateMan man;
    late FakeUpstreamLink link;

    setUp(() async {
      final built = buildOneLink();
      man = built.man;
      link = built.link;
      await man.start();
      addTearDown(man.dispose);
    });

    test('listen answers the same handle for the same key', () {
      expect(identical(man.listen(st101Key), man.listen(st101Key)), isTrue,
          reason: 'a widget holds the handle it was given. Two handles for one '
              'key means the second widget listens to a node the first one '
              'never updates');
    });

    test('listen never throws, and reads not-yet-known before anything arrives',
        () {
      final handle = man.listen(st101Key);
      expect(handle.value.quality, Quality.uncertainNotYetKnown);
      expect(handle.value.value, isNull);
    });

    test('subscribe is a plain Stream whose first event is the CURRENT value',
        () async {
      // Through the composer's own ingest seam and not through the link: the
      // fan-in that connects the two is task 2, and a task-1 case that reached
      // for it would be asserting a mechanism that does not exist yet.
      man.applyUpstreamBatch({st101Key: DynamicValue(value: 42)});

      final stream = man.subscribe(st101Key);
      expect(stream, isA<Stream<DynamicValue>>(),
          reason: 'never a Future<Stream<…>> — state_man_api.dart:80-84 names '
              'that shape as how a widget misses the first values of its own '
              'subscription');

      final first = await stream.first;
      expect(first.value, 42,
          reason: 'the first event is the value the store already holds, not '
              'the next change. A page opened on a slow-moving tank level '
              'would otherwise read blank until the level moved');
    });

    test('read is synchronous and null when nothing has arrived — never a throw',
        () {
      expect(man.read(st101Key), isNull);
    });

    test('read answers the cached value once one has arrived', () async {
      man.applyUpstreamBatch({st101Key: DynamicValue(value: 7)});
      expect(man.read(st101Key)!.value, 7);
      expect(man.read(st101Key)!.quality, Quality.good);
    });

    test('a key the router refuses reads NULL under errorConfig — never a zero',
        () {
      final answer = man.read(unmappedKey);
      expect(answer, isNotNull,
          reason: 'a refused key is a different fact from "nothing has arrived '
              'yet": the gateway has affirmatively established it cannot serve '
              'this name, and null would read as the transient case');
      expect(answer!.quality, Quality.errorConfig);
      expect(answer.value, isNull,
          reason: 'never zero and never false. On a plant floor a good-quality '
              '0 on a mistyped speed tag is a stopped conveyor, and a '
              'good-quality false on a mistyped permit is an interlock that '
              'reads satisfied — both are readings an operator acts on, and '
              'neither happened');
    });

    test('readFresh answers a bad-quality value when the upstream cannot supply '
        'one, and never throws', () async {
      link.disconnectUpstream();
      final answer = await man.readFresh(st101Key);
      expect(answer.quality, Quality.badCommFault);
      expect(answer.value, isNull);
    });

    test('readFresh on a refused key answers errorConfig rather than throwing',
        () async {
      final answer = await man.readFresh(unmappedKey);
      expect(answer.quality, Quality.errorConfig);
      expect(answer.value, isNull);
    });

    test('readMany answers EVERY key asked for, with per-key qualities',
        () async {
      link.setValue(st101Key, 11);
      link.dropKey(st201Key);

      final answers = await man.readMany([st101Key, st201Key, unmappedKey]);

      expect(answers.keys, containsAll([st101Key, st201Key, unmappedKey]),
          reason: 'a missing entry makes the caller render a blank where a '
              'fault belongs');
      expect(answers[st101Key]!.value, 11);
      expect(answers[st101Key]!.quality, Quality.good);
      expect(answers[st201Key]!.quality, Quality.errorConfig);
      expect(answers[unmappedKey]!.quality, Quality.errorConfig);
    });

    test('one bad key does not fail the batch — the good one still carries its '
        'number', () async {
      link.setValue(st101Key, 11);
      link.dropKey(st201Key);
      final answers = await man.readMany([st201Key, st101Key]);
      expect(answers[st101Key]!.value, 11,
          reason: 'asserted explicitly, because a check that only reads the '
              'bad key passes against an implementation that abandoned the '
              'batch');
    });

    test('keys is the router key set UNION the PIPE keys this instance produces',
        () {
      expect(man.keys, containsAll([st101Key, st201Key]));
      expect(man.keys, isNot(contains(PipeKeys.connected)));

      // 08-09 produces these; this plan proves the union rule is a union.
      man.applyUpstreamBatch({PipeKeys.connected: DynamicValue(value: true)});
      expect(man.keys, contains(PipeKeys.connected));
      expect(man.keys, containsAll([st101Key, st201Key]),
          reason: 'a union, not a replacement — cert_health_state_man.dart:'
              '317-320');
    });

    test('a key the router refuses is not offered back through keys', () {
      man.read(unmappedKey);
      expect(man.keys, isNot(contains(unmappedKey)),
          reason: 'offering a refused name back to a key picker launders a '
              'typo into an apparently valid binding');
    });

    test('nothing is spawned by the constructor: no clock runs until somebody '
        'is watching', () {
      expect(man.liveTimers, 0,
          reason: 'StateMan._ spawns two unawaited background loops per OPC UA '
              'client in its constructor (state_man.dart:1364, :1398) with a '
              'bare Logger() and no error seam. A supervised start() is the '
              'improvement, and this is the assertion that keeps it one');
    });

    test('start() connects every configured link', () {
      expect(link.state, UpstreamLinkState.connected);
      expect(link.birthCount, 1);
    });
  });

  group('the members this plan does not implement say so, and name their owner',
      () {
    late LocalStateMan man;

    setUp(() {
      man = buildOneLink().man;
      addTearDown(man.dispose);
    });

    /// Each entry is a member and the plan id whose message must name it.
    ///
    /// The list is the self-deleting ledger 07-01's `gateOutstanding` doctrine
    /// argues for: a phase whose own gate is red cannot tell a new failure
    /// from a known one, so an unwritten member throws with an owner rather
    /// than leaving a case failing until somebody writes it.
    void owes(String name, String plan, void Function() call) {
      test('$name is owed by $plan', () {
        expect(
            call,
            throwsA(isA<UnimplementedError>().having(
                (e) => e.message, 'message', allOf(contains(plan), contains(name)))),
            reason: 'a member that is not written yet must name the plan that '
                'owes it, so the count in freeze_test.dart can be decremented '
                'by the plan that closes it');
      });
    }

    // 08-06's three entries — `write`, `writeStatus`, `holdToRun` — came off
    // this ledger in the commits that closed them, which is the ledger being
    // self-deleting rather than merely honest. Their behaviour is
    // `write_test.dart`'s and `hold_test.dart`'s subject now. Four left, all
    // 08-11's and Phase 10's.
    owes('browse', '08-11', () => man.browse);
    owes('timeseries', '08-11', () => man.timeseries);
    owes('historyViews', '08-11', () => man.historyViews);
    owes('preferences', '08-11', () => man.preferences);
  });

  _faninGroup();
}

/// The fan-in: SRV-07 measured as a delta, released at zero.
///
/// **Every assertion here is on the DELTA of
/// [UpstreamLink.upstreamSubscriptionsCreated], never on a literal count of
/// monitored items and never on a balance.** One logical OPC UA key is *four*
/// monitored items — `monitor()` requests DataType, Value, Description and
/// DisplayName (`packages/tfc_dart/lib/core/state_man.dart:848-861`) — so the
/// absolute number never equals the number of keys and no case should expect it
/// to. And there is deliberately **no delete counter**: the binding's `onCancel`
/// is a block body that discards the inner future, so a cancel completes
/// locally the moment it is requested and never when the server acknowledges
/// the delete. A counter fed from that would read healthy during exactly the
/// leak it was added to catch, which is why a balance assertion is untestable
/// by construction here.
///
/// So: do not add a delete counter to make the arithmetic tidier. The release
/// is observed through [LocalStateMan.openUpstreamSubscriptions] — a fact about
/// this gateway's own bookkeeping — and the *creates* are observed through the
/// link's delta. Those are two independent witnesses, which is the point.
void _faninGroup() {
  group('the fan-in costs the PLC one subscription per key, released at zero',
      () {
    late LocalStateMan man;
    late FakeUpstreamLink link;

    setUp(() async {
      final built = buildOneLink();
      man = built.man;
      link = built.link;
      await man.start();
      addTearDown(man.dispose);
    });

    test('five client subscriptions to one key cost ONE upstream subscription',
        () async {
      final before = link.upstreamSubscriptionsCreated;
      final subs = <StreamSubscription<DynamicValue>>[
        for (var i = 0; i < 5; i++) man.subscribe(st101Key).listen((_) {}),
      ];
      addTearDown(() async {
        for (final sub in subs) {
          await sub.cancel();
        }
      });
      await pumpUpstream();

      expect(link.upstreamSubscriptionsCreated - before, 1,
          reason: 'thirty panels on one key is one monitored item on the PLC. '
              'A delta, because the absolute count is four per logical key');
      expect(man.listenerCount(st101Key), 5);
    });

    test('cancelling four of the five changes nothing upstream; the fifth '
        'releases immediately at linger zero', () async {
      final before = link.upstreamSubscriptionsCreated;
      final subs = <StreamSubscription<DynamicValue>>[
        for (var i = 0; i < 5; i++) man.subscribe(st101Key).listen((_) {}),
      ];
      await pumpUpstream();

      for (var i = 0; i < 4; i++) {
        await subs[i].cancel();
      }
      expect(link.upstreamSubscriptionsCreated - before, 1);
      expect(man.openUpstreamSubscriptions, 1);
      expect(man.listenerCount(st101Key), 1);

      await subs[4].cancel();
      expect(man.openUpstreamSubscriptions, 0,
          reason: 'SRV-07: released when the LAST subscriber unsubscribes. The '
              'incumbent releases on a ten-minute idle timer instead '
              '(state_man.dart:2674-2676), so a page close keeps costing the '
              'PLC a monitored item for ten minutes');
      expect(man.listenerCount(st101Key), 0);
    });

    test('re-subscribing after a completed release creates a SECOND upstream '
        'subscription — the delta is 2, which is what proves the first 1 was '
        'measured and not assumed', () async {
      final before = link.upstreamSubscriptionsCreated;

      var sub = man.subscribe(st101Key).listen((_) {});
      await pumpUpstream();
      await sub.cancel();
      expect(man.openUpstreamSubscriptions, 0);

      sub = man.subscribe(st101Key).listen((_) {});
      await pumpUpstream();
      addTearDown(sub.cancel);

      expect(link.upstreamSubscriptionsCreated - before, 2,
          reason: 'a fan-in that never released would report 1 here, and a '
              'fan-in that never fanned in would report 6 in the case above. '
              'Only both numbers together say the mechanism works');
    });

    test('a cancelled subscriber stops receiving values; the others keep '
        'receiving', () async {
      final first = <Object?>[];
      final second = <Object?>[];
      final subA = man.subscribe(st101Key).listen((v) => first.add(v.value));
      final subB = man.subscribe(st101Key).listen((v) => second.add(v.value));
      await pumpUpstream();

      link.setValue(st101Key, 1);
      await pumpUpstream();
      await subA.cancel();
      addTearDown(subB.cancel);

      link.setValue(st101Key, 2);
      await pumpUpstream();

      expect(first.last, 1, reason: 'a cancelled subscription is cancelled');
      expect(second.last, 2,
          reason: 'and the shared upstream subscription is still feeding the '
              'ones that remain — a release triggered by the wrong refcount '
              'would take this one dark too');
    });

    test('an upstream stream that ENDS marks the key badCommFault and leaves '
        'the node alive', () async {
      final sub = man.subscribe(st101Key).listen((_) {});
      await pumpUpstream();
      man.applyUpstreamBatch({st101Key: DynamicValue(value: 9)});

      // An upstream that went away ends the streams it was feeding.
      await link.dispose();
      await pumpUpstream();

      expect(man.read(st101Key)!.quality, Quality.badCommFault);
      expect(man.read(st101Key)!.value, 9,
          reason: 'the number is preserved. The news is that it can no longer '
              'be trusted, not that it never existed');

      final seen = <Object?>[];
      var done = false;
      final again = man
          .subscribe(st101Key)
          .listen((v) => seen.add(v.value), onDone: () => done = true);
      await pumpUpstream();
      addTearDown(again.cancel);
      addTearDown(sub.cancel);

      expect(seen.first, 9);
      expect(done, isFalse,
          reason: 'AutoDisposingStream closes its subject when the raw stream '
              'ends (state_man.dart:2691) and then hands the next listener the '
              'replay buffer followed by done — which to a widget is '
              'indistinguishable from a key that simply stopped updating. '
              'ValueStore has no equivalent and must not grow one');
    });

    test('a listener attached through listen() refcounts too, and taking the '
        'handle alone costs the PLC nothing', () async {
      final before = link.upstreamSubscriptionsCreated;
      final handle = man.listen(st101Key);
      expect(man.openUpstreamSubscriptions, 0,
          reason: 'listen() returns a handle. Taking one must not cost a '
              'monitored item, or a diagnostics page that enumerates keys '
              'would subscribe the whole plant');

      void noop() {}
      handle.addListener(noop);
      await pumpUpstream();
      expect(link.upstreamSubscriptionsCreated - before, 1,
          reason: 'removeListener reaching zero is the ONLY observable release '
              'point on the listen() path — there is no unlisten on the '
              'interface — so that is where the refcount has to live');
      expect(man.listenerCount(st101Key), 1);

      handle.removeListener(noop);
      expect(man.openUpstreamSubscriptions, 0);
    });
  });

  group('the linger is a knob, and its timer never evicts a live entry', () {
    const linger = Duration(milliseconds: 40);

    test('the release waits the linger out', () async {
      final built = buildOneLink(linger: linger);
      final man = built.man;
      await man.start();
      addTearDown(man.dispose);

      final sub = man.subscribe(st101Key).listen((_) {});
      await pumpUpstream();
      await sub.cancel();

      expect(man.openUpstreamSubscriptions, 1,
          reason: 'still open, because the operator may be flipping between '
              'two pages that share this key');
      expect(man.liveLingerTimers, 1);

      await Future<void>.delayed(linger * 3);
      expect(man.openUpstreamSubscriptions, 0);
      expect(man.liveLingerTimers, 0);
    });

    test('a subscribe INSIDE the linger window cancels the timer and reuses '
        'the live subscription', () async {
      final built = buildOneLink(linger: linger);
      final man = built.man;
      final link = built.link;
      await man.start();
      addTearDown(man.dispose);

      final before = link.upstreamSubscriptionsCreated;
      final first = man.subscribe(st101Key).listen((_) {});
      await pumpUpstream();
      await first.cancel();
      expect(man.liveLingerTimers, 1);

      final second = man.subscribe(st101Key).listen((_) {});
      await pumpUpstream();
      addTearDown(second.cancel);

      expect(man.liveLingerTimers, 0,
          reason: 'the armed timer is cancelled by the new subscribe. The '
              'shipped implementation names the opposite bug in its own '
              'comment (state_man.dart:2736-2739): the timer removes BY KEY, '
              'so one surviving into the next subscription evicts the live '
              'entry that replaced it');

      await Future<void>.delayed(linger * 3);
      expect(man.openUpstreamSubscriptions, 1,
          reason: 'and the reused subscription is still there after the '
              'window the cancelled timer would have fired in');
      expect(link.upstreamSubscriptionsCreated - before, 1,
          reason: 'reused, not re-created — that is what the linger is for');
    });
  });
}

/// Lets the microtask queue drain, which is all an in-memory upstream needs.
///
/// Not a `Duration` delay: this suite is pure Dart with no sockets in it, and a
/// wall-clock wait would be a measurement of the machine rather than of the
/// code (08-03 kept this package port-free and this file spends none of it).
Future<void> pumpUpstream() => Future<void>.delayed(Duration.zero);
