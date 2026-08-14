/// Epoch global, sequence local, recovery always a snapshot.
///
/// Source: 04-RESEARCH Finding 3, which ships flagged **designed, not fully
/// executed** — the primitives were observed live (Finding 7), but no
/// multi-subscription flap run happened, so RESEARCH's assumption log carries
/// the algorithm as A1 with "a two-sub flap test in Wave 0 settles it".
/// `test/resync_test.dart` is that test, and its arm
/// `a gap on one page does not blank the other` is what upgraded A1 from
/// designed to executed.
///
/// **What this file decides, and what it does not.** Its only job is the
/// *resubscribe decision*. Whether a batch's values are applied or discarded
/// is already decided by `ValueStore.applyBatch`, and the two answers are
/// deliberately asymmetric: `BatchSeqGap` applies the values in hand because
/// they are newer than what is cached, while `BatchReplay` discards them
/// because they are older, which is the F18 rule against putting a reading
/// from two batches ago on a mimic under good quality. Re-implementing either
/// here would give the cache two owners.
///
/// **Why a store per subscription.** `ValueStore` holds one sequence counter,
/// and the whole point of Finding 3 is that the counter is per subscription:
/// `tfc_relay_server`'s `subscription_registry.dart:101-102` refuses a shared
/// one from its own side, because "a counter shared between two pages would
/// make each one resync every time the other moved". Handing this engine a
/// single store for several subscriptions would rebuild that exact hazard on
/// the client, one layer down and invisible — two pages numbering from zero
/// would interleave into a permanent false-gap loop. So the engine takes a
/// `storeFor(sub)` and the caches are separate by construction.
///
/// **What is not this file's business.** Per-subscription staleness. A
/// subscription whose tick `evaluatedAt` stops advancing while ticks keep
/// arriving is the dead-subscription-on-live-socket case (F25) — a plant-side
/// fault the client *reports*, not a stream fault the client heals. Nothing
/// here reads it and nothing here resyncs because of one; resyncing on it
/// would hide a dead sensor behind a busy-looking client.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'subscription_state.dart';

/// The `subscribe` call, injected: 04-07 passes in the deadline-wrapped `_call`
/// so that a subscribe which never answers fails the pass rather than hanging
/// the recovery.
typedef SubscribeCall = Future<DecodedSubscribeResult> Function(
    String sub, Set<String> keys);

/// Drives resubscription from epoch changes, sequence verdicts and
/// server-announced resyncs.
final class ResyncEngine {
  /// The value cache for one subscription. See the library doc for why this is
  /// per subscription rather than one store for all of them.
  final ValueStore Function(String sub) storeFor;

  /// How a subscription is re-established.
  final SubscribeCall subscribe;

  /// The live subscription registry, owned by the caller: this engine reads
  /// and updates the entries, it does not decide which pages exist.
  final Map<String, SubscriptionState> subscriptions;

  /// Configuration problems worth a log line — a rejected key, a snapshot
  /// entry naming a handle nobody announced. Recorded, never thrown: a page
  /// carries ~1500 hand-edited keys and one typo must cost one tag.
  final List<String> complaints = <String>[];

  /// Told when a subscription stops being established, so whoever keeps
  /// per-subscription state elsewhere can drop it. The freshness watchdog's
  /// `forgetSubscription` is the caller this exists for.
  final void Function(String subId)? forget;

  String? _lastKnownEpoch;

  ResyncEngine({
    required this.storeFor,
    required this.subscribe,
    required this.subscriptions,
    this.forget,
  });

  /// The epoch of the session the client currently believes it is in.
  String? get lastKnownEpoch => _lastKnownEpoch;

  /// A `hello` answered: adopt the epoch and re-establish every subscription.
  ///
  /// A *changed* epoch is global. The server's subscription-state instances
  /// are new, so every cache and every handle map the client holds describes a
  /// session that no longer exists — and a number left on screen from that
  /// session is precisely the lie this product exists to prevent.
  Future<void> onHello(String epoch) async {
    final previous = _lastKnownEpoch;
    if (previous != null && previous != epoch) {
      for (final sub in subscriptions.values) {
        _unestablish(sub);
      }
    }
    _lastKnownEpoch = epoch;
    await _resubscribeAll();
  }

  /// One update frame.
  ///
  /// [epoch] is the epoch the frame arrived under; when it disagrees with the
  /// subscription's own the frame is dropped **silently** and the sequence
  /// does not move — a late frame from the previous session must not advance
  /// a chain the next live frame will be measured against.
  ///
  /// [generation] is the same rule one level finer, and it is the one that
  /// actually bites (04-REVIEW CR-04). The hazard is a frame in flight from
  /// *before* a resync on the **same socket**: the epoch has not changed,
  /// because a server-announced resync or a gap-triggered resubscribe rebuilds
  /// one subscription while the session stays put. Applied, that frame lands
  /// as an in-sequence batch and takes the baseline, after which the genuine
  /// frame at the same sequence is discarded as a replay — the mimic keeps the
  /// old number, under good quality, and the new one is gone. Not advancing
  /// [SubscriptionState.lastSeq] is the half of the drop that stops that.
  Future<void> onUpdate(
    String sub, {
    required int seq,
    required Map<String, DynamicValue> changes,
    String? epoch,
    int? generation,
  }) async {
    final state = subscriptions[sub];
    // A subscription the client never opened is never auto-registered off an
    // inbound frame: that is a page appearing because a peer said so.
    if (state == null) return;
    if (epoch != null && state.epoch.isNotEmpty && epoch != state.epoch) {
      return;
    }
    if (generation != null && generation != state.generation) {
      // Silently, and without touching the sequence. Not a complaint either: a
      // frame crossing a re-establish is the ordinary shape of recovery, not a
      // configuration problem anyone can act on.
      return;
    }

    // Exhaustive, three arms, no fallthrough case: `BatchVerdict` is sealed so
    // that a fourth verdict is a compile error here rather than a frame that
    // quietly proceeds.
    final verdict = storeFor(sub).applyBatch(changes, seq: seq);
    switch (verdict) {
      case BatchOk():
        state.lastSeq = seq;
      case BatchSeqGap():
        // The values in hand were applied by the store; the snapshot is what
        // makes the cache whole again.
        await _recover(state);
      case BatchReplay():
        // The values were discarded by the store. The resubscribe is not about
        // them — a duplicate on the wire means the stream is not what the
        // client thought it was.
        await _recover(state);
    }
  }

  /// A server-announced `resync` notification: that subscription only.
  Future<void> onResync(String sub) async {
    final state = subscriptions[sub];
    if (state == null) return;
    await _recover(state);
  }

  /// Re-establishes every subscription, rolling the whole pass back if any of
  /// them fails.
  ///
  /// The shape is the server's, at `session_handlers.dart:176-235`: a throw
  /// partway through left listeners attached with nothing able to reach them,
  /// "a permanent leak per failure, once per failure, forever". The client's
  /// version of that leak is a page the client believes is live and the server
  /// may never have registered, so a failed pass leaves nothing established.
  Future<void> _resubscribeAll() async {
    final established = <SubscriptionState>[];
    try {
      for (final sub in subscriptions.values.toList(growable: false)) {
        await _resubscribe(sub);
        established.add(sub);
      }
    } catch (_) {
      for (final sub in established) {
        _unestablish(sub);
      }
      rethrow;
    }
  }

  /// One subscription, re-established from a snapshot — and if that cannot be
  /// done, said out loud and left unestablished.
  ///
  /// The recovery paths ([onUpdate], [onResync]) have nowhere to throw: they
  /// are driven from notification handlers, where an exception unwinds into
  /// `json_rpc_2` on a message that has no reply, and is dropped. So a refused
  /// recovery used to be invisible — nothing logged, nothing in [complaints]
  /// (04-REVIEW CR-03).
  ///
  /// [_unestablish] rather than leaving the baseline standing, for the reason
  /// that method's own doc gives: a surviving `lastSeq` makes the next frame a
  /// false gap, which triggers the next failed recovery, for as long as the
  /// socket lives.
  ///
  /// [_resubscribeAll] deliberately does **not** come through here — it needs
  /// the throw, because its whole shape is "roll the pass back and let the
  /// supervisor treat the connection as failed".
  Future<void> _recover(SubscriptionState sub) async {
    try {
      await _resubscribe(sub);
    } catch (error) {
      complaints.add('"${sub.subId}" could not be re-established and is now '
          'unestablished: $error. Its values are gone from the cache rather '
          'than left on screen under good quality');
      _unestablish(sub);
    }
  }

  /// One subscription, re-established from a snapshot.
  ///
  /// **One at a time per subscription** (04-REVIEW WR-04). [onUpdate] (gap or
  /// replay), [onResync] and [onHello] can each start one for the same name
  /// with no coordination between them, and two re-establishes racing
  /// interleave `store.clear()`, `adopt` and `applyBatch` — blanking a
  /// snapshot that has just been applied and leaving `lastSeq` describing a
  /// generation that is already gone. A second caller gets the first's future,
  /// which is also the right answer semantically: it asked for the page to be
  /// current, and it is about to be.
  /// The cleanup is a **block** body, and that is not a style preference:
  /// `Map.remove` returns the value it removed, `whenComplete` waits on a
  /// callback that returns a future, and the value removed here *is* the
  /// future `whenComplete` is attached to. An arrow body deadlocks every
  /// resubscribe this client will ever make.
  Future<void> _resubscribe(SubscriptionState sub) =>
      _inFlight[sub.subId] ??= _establish(sub).whenComplete(() {
        _inFlight.remove(sub.subId);
      });

  final _inFlight = <String, Future<void>>{};

  Future<void> _establish(SubscriptionState sub) async {
    final result = await subscribe(sub.subId, sub.keys);
    final store = storeFor(sub.subId);

    // Recovery is a snapshot, never a delta replay: the old cache goes first
    // so a key the new session no longer sends cannot survive as a stale
    // number, and so the sequence baseline restarts with the server's.
    store.clear();
    sub.adopt(result);
    store.applyBatch(result.values, seq: result.seq);

    for (final entry in result.rejected.entries) {
      complaints.add('"${entry.key}" was rejected by the gateway '
          '(${entry.value.kind}): ${entry.value.message ?? 'no detail'}');
    }
    complaints.addAll(result.complaints);
  }

  /// Returns a subscription to "not established": no cache, no handles, no
  /// baseline. A surviving baseline would turn the next attempt's first frame
  /// into a false gap.
  ///
  /// The generation goes back to zero with the rest of it. That is not a
  /// number any live gateway mints — [SubscriptionRegistry.nextGeneration]
  /// starts at one — so an in-flight frame from the establishment being
  /// abandoned cannot match on the way past.
  void _unestablish(SubscriptionState sub) {
    storeFor(sub.subId).clear();
    sub.handles = <int, String>{};
    sub.lastSeq = null;
    sub.epoch = '';
    sub.generation = 0;
    // The freshness watchdog keeps an `evaluatedAt` per subscription id, and
    // an id nobody re-establishes goes on raising a fault about a value no
    // screen displays (04-REVIEW WR-10). This is the one place a subscription
    // stops being live, so it is the one place that can say so.
    forget?.call(sub.subId);
  }
}
