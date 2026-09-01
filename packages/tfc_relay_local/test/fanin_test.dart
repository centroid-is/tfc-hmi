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

    owes('write', '08-06', () => man.write(st101Key, 1));
    owes('writeStatus', '08-06', () => man.writeStatus(const ['cmd']));
    owes('holdToRun', '08-06', () => man.holdToRun(st101Key));
    owes('browse', '08-11', () => man.browse);
    owes('timeseries', '08-11', () => man.timeseries);
    owes('historyViews', '08-11', () => man.historyViews);
    owes('preferences', '08-11', () => man.preferences);
  });
}

/// Lets the microtask queue drain, which is all an in-memory upstream needs.
///
/// Not a `Duration` delay: this suite is pure Dart with no sockets in it, and a
/// wall-clock wait would be a measurement of the machine rather than of the
/// code (08-03 kept this package port-free and this file spends none of it).
Future<void> pumpUpstream() => Future<void>.delayed(Duration.zero);
