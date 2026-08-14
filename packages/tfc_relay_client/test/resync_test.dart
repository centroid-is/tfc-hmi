/// The resync discipline: epoch global, sequence local, snapshot only.
///
/// Source: 04-RESEARCH Finding 3, which is flagged **designed, not fully
/// executed** — the primitives were verified live (Finding 7) but no multi-sub
/// flap run happened, and RESEARCH's assumption log carries it as A1 with
/// "a two-sub flap test in Wave 0 settles it". This file is that test.
///
/// The arm that settles it is `a gap on one page does not blank the other`.
/// The server makes the same argument from its own side —
/// `subscription_registry.dart:101-102`: a sequence counter shared between two
/// subscriptions "would make each one resync every time the other moved".
///
/// What breaks in the plant without it: a control room runs several panels off
/// one gateway. If a dropped frame on the packing-hall page blanked the
/// freezer page too, one lost UDP-sized hiccup would take every screen in the
/// factory to "not yet known" at once, and the resulting resubscribe storm is
/// self-sustaining. And an engine that resynced everything on any gap passes
/// every single-subscription case in this file — which is why the two-sub arm
/// carries an anti-vacuity check that the other page held values at all.
library;

import 'package:tfc_relay_client/src/resync_engine.dart';
import 'package:tfc_relay_client/src/subscription_state.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';
import 'package:test/test.dart';

/// A scripted stand-in for the deadline-wrapped `subscribe` call: it records
/// what was asked for and answers from a canned script. No socket, no server —
/// the sequence discipline is a pure state machine and is tested as one.
final class _ScriptedSubscribe {
  /// Sub names in call order, so "s2 issued no subscribe" is a readable fact.
  final calls = <String>[];

  /// sub → the snapshot each resubscribe answers with.
  final Map<String, Map<String, DynamicValue>> snapshots;

  /// sub → epoch each resubscribe answers with.
  final Map<String, String> epochs;

  /// Sub names whose next subscribe throws, standing in for a call that fails
  /// partway through re-establishing N subscriptions.
  final Set<String> failing;

  _ScriptedSubscribe({
    Map<String, Map<String, DynamicValue>>? snapshots,
    Map<String, String>? epochs,
    Set<String>? failing,
  })  : snapshots = snapshots ?? {},
        epochs = epochs ?? {},
        failing = failing ?? {};

  Future<DecodedSubscribeResult> call(String sub, Set<String> keys) async {
    calls.add(sub);
    if (failing.contains(sub)) {
      throw StateError('subscribe($sub) refused');
    }
    final values = snapshots[sub] ?? const <String, DynamicValue>{};
    return DecodedSubscribeResult(
      sub: sub,
      epoch: epochs[sub] ?? 'E1',
      seq: 0,
      handles: {
        for (final (index, key) in keys.indexed) index + 1: key,
      },
      values: values,
      meta: const {},
      rejected: const {},
      complaints: const [],
    );
  }
}

DynamicValue _v(Object? value) => DynamicValue(value: value);

void main() {
  late _ScriptedSubscribe script;
  late Map<String, ValueStore> stores;
  late Map<String, SubscriptionState> subs;
  late ResyncEngine engine;

  ValueStore storeFor(String sub) =>
      stores.putIfAbsent(sub, () {
        final store = ValueStore();
        addTearDown(store.dispose);
        return store;
      });

  setUp(() {
    script = _ScriptedSubscribe();
    stores = {};
    subs = {};
    engine = ResyncEngine(
      storeFor: storeFor,
      subscribe: script.call,
      subscriptions: subs,
    );
  });

  /// Registers a subscription and gives it a snapshot to come back with.
  SubscriptionState register(String sub, Map<String, Object?> snapshot) {
    final state = SubscriptionState(subId: sub, keys: snapshot.keys.toSet());
    subs[sub] = state;
    script.snapshots[sub] = {
      for (final entry in snapshot.entries) entry.key: _v(entry.value)
    };
    return state;
  }

  group('two subscriptions, one gaps', () {
    test('a gap on one page does not blank the other', () async {
      register('s1', {'PACK.rate': 10});
      register('s2', {'FREEZER.temp': -24});
      await engine.onHello('E1');
      script.calls.clear();

      // Anti-vacuity: the other page must actually be holding values, or
      // "unchanged" is a statement about an empty map.
      expect(storeFor('s2').keys.length, greaterThan(0),
          reason: 'if the freezer page never cached anything, the assertion '
              'below that it survived the packing-hall gap proves nothing');
      final before = storeFor('s2').peek('FREEZER.temp');
      expect(before?.value, -24);

      // s1 skips a sequence number.
      await engine.onUpdate('s1',
          seq: 7, epoch: 'E1', changes: {'PACK.rate': _v(11)});

      expect(script.calls, ['s1'],
          reason: 'a dropped frame on the packing-hall page is that page\'s '
              'problem; resubscribing the freezer page too is how one hiccup '
              'becomes a factory-wide resubscribe storm');
      expect(storeFor('s2').peek('FREEZER.temp')?.value, -24,
          reason: 'the freezer reading never went unknown, so the operator '
              'never saw it blank');
      expect(storeFor('s2').peek('FREEZER.temp'), before,
          reason: 'byte-identical, not merely re-fetched to the same number');
    });
  });

  group('sequence discipline', () {
    test('an in-sequence batch advances lastSeq and issues no subscribe',
        () async {
      final s1 = register('s1', {'PACK.rate': 10});
      await engine.onHello('E1');
      script.calls.clear();

      await engine.onUpdate('s1',
          seq: 1, epoch: 'E1', changes: {'PACK.rate': _v(11)});

      expect(s1.lastSeq, 1,
          reason: 'the chain has to count on, or the next frame reads as a '
              'gap and the page resyncs for nothing');
      expect(script.calls, isEmpty,
          reason: 'an intact stream costs no round trip');
      expect(storeFor('s1').peek('PACK.rate')?.value, 11);
    });

    test('a sequence gap resubscribes that subscription and keeps the values '
        'in hand', () async {
      register('s1', {'PACK.rate': 10});
      await engine.onHello('E1');
      script.calls.clear();
      // What the resubscribe will answer with, so the snapshot is
      // distinguishable from the gapped frame's own values.
      script.snapshots['s1'] = {'PACK.rate': _v(12)};

      await engine.onUpdate('s1',
          seq: 9, epoch: 'E1', changes: {'PACK.rate': _v(11)});

      expect(script.calls, ['s1'],
          reason: 'recovery is a snapshot, never a delta replay');
      expect(storeFor('s1').peek('PACK.rate')?.value, 12,
          reason: 'the snapshot is the newest truth and lands last');
    });

    test('a replayed batch resyncs and leaves the cache unpolluted', () async {
      register('s1', {'PACK.rate': 10});
      await engine.onHello('E1');
      await engine.onUpdate('s1',
          seq: 5, epoch: 'E1', changes: {'PACK.rate': _v(50)});
      script.calls.clear();
      // The resubscribe answers with what is already cached, so any change
      // below can only have come from the replayed frame.
      script.snapshots['s1'] = {'PACK.rate': _v(50)};

      await engine.onUpdate('s1',
          seq: 3, epoch: 'E1', changes: {'PACK.rate': _v(30)});

      expect(storeFor('s1').peek('PACK.rate')?.value, 50,
          reason: 'F18: a re-delivered batch is older than what is cached, '
              'and applying it puts a reading from two batches ago on the '
              'mimic under good quality');
      expect(script.calls, ['s1'],
          reason: 'a duplicate on the wire means the stream is not what the '
              'client thought it was, so it resyncs on it too');
    });

    test('an update naming an unknown subscription is dropped', () async {
      register('s1', {'PACK.rate': 10});
      await engine.onHello('E1');
      script.calls.clear();

      await engine.onUpdate('ghost',
          seq: 1, epoch: 'E1', changes: {'PACK.rate': _v(99)});

      expect(script.calls, isEmpty,
          reason: 'a subscription the client never opened must never be '
              'auto-registered off an inbound frame');
      expect(storeFor('s1').peek('PACK.rate')?.value, 10,
          reason: 'and its values must not reach a page');
    });

    test('an old-epoch frame is dropped and does not advance seq', () async {
      final s1 = register('s1', {'PACK.rate': 10});
      await engine.onHello('E1');
      script.calls.clear();
      final seqBefore = s1.lastSeq;

      await engine.onUpdate('s1',
          seq: 4, epoch: 'E0', changes: {'PACK.rate': _v(99)});

      expect(s1.lastSeq, seqBefore,
          reason: 'a frame from a session that no longer exists must not '
              'move the chain, or the next live frame reads as a gap');
      expect(storeFor('s1').peek('PACK.rate')?.value, 10,
          reason: 'a value from the previous epoch applied late is the F18 '
              'stale-reading-under-good-quality failure');
      expect(script.calls, isEmpty,
          reason: 'dropped in silence: the epoch already changed, and the '
              'hello path is what heals that');
    });
  });

  group('epoch', () {
    test('an epoch change at hello discards every cache and every handle map',
        () async {
      final s1 = register('s1', {'PACK.rate': 10});
      final s2 = register('s2', {'FREEZER.temp': -24});
      await engine.onHello('E1');
      expect(storeFor('s1').peek('PACK.rate')?.value, 10);
      expect(s1.handles, isNotEmpty);

      // The gateway restarted: new server-side subscription state, new epoch.
      script.snapshots['s1'] = {'PACK.rate': _v(77)};
      script.snapshots['s2'] = {};
      script.epochs['s1'] = 'E2';
      script.epochs['s2'] = 'E2';
      script.calls.clear();
      await engine.onHello('E2');

      expect(storeFor('s2').peek('FREEZER.temp'), isNull,
          reason: 'the new epoch did not re-send this tag, and a number left '
              'on screen from the previous session is exactly the lie this '
              'product exists to prevent');
      expect(storeFor('s1').peek('PACK.rate')?.value, 77,
          reason: 'what the new session did send replaces what was there');
      expect(s2.handles, isNotEmpty,
          reason: 'handles are re-minted per epoch; the old map is dropped '
              'and the fresh one adopted');
      expect(script.calls.toSet(), {'s1', 's2'},
          reason: 'an epoch change is global — every subscription comes back');
    });

    test('the same epoch at hello keeps the caches and still resubscribes',
        () async {
      register('s1', {'PACK.rate': 10});
      await engine.onHello('E1');
      script.calls.clear();
      script.snapshots['s1'] = {'PACK.rate': _v(10)};

      await engine.onHello('E1');

      expect(script.calls, ['s1'],
          reason: 'a reconnect always re-establishes the subscription, '
              'because the socket is new even when the session survived');
      expect(storeFor('s1').peek('PACK.rate')?.value, 10);
    });
  });

  group('server-announced resync', () {
    test('resubscribes the named subscription only', () async {
      register('s1', {'PACK.rate': 10});
      register('s2', {'FREEZER.temp': -24});
      await engine.onHello('E1');
      script.calls.clear();

      await engine.onResync('s2');

      expect(script.calls, ['s2'],
          reason: 'the server named one subscription; touching the other is '
              'the same factory-wide storm by another route');
    });

    test('a resync for an unknown subscription is dropped', () async {
      await engine.onHello('E1');
      script.calls.clear();

      await engine.onResync('ghost');

      expect(script.calls, isEmpty);
    });
  });

  group('rollback', () {
    test('a resubscribe that throws partway leaves no half-registered '
        'subscription', () async {
      register('s1', {'PACK.rate': 10});
      register('s2', {'FREEZER.temp': -24});
      script.failing.add('s2');

      await expectLater(engine.onHello('E1'), throwsA(isA<StateError>()),
          reason: 'the failure must surface to the supervisor, which is what '
              'schedules the next attempt');

      expect(subs['s1']!.handles, isEmpty,
          reason: 'the server-side rollback argument, client side: a '
              'subscription established in a pass that failed is a page the '
              'client believes is live and the server may not be feeding');
      expect(subs['s1']!.lastSeq, isNull,
          reason: 'a surviving baseline would turn the next attempt\'s first '
              'frame into a false gap');
      expect(storeFor('s1').peek('PACK.rate'), isNull,
          reason: 'and its values must not stay on screen as if fresh');
    });
  });
}
