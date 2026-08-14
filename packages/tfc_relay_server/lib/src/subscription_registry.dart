/// What one session is currently watching, in a form a test can read.
///
/// Pure state and listener bookkeeping: no clock, no I/O, no JSON. The handlers
/// in `session_handlers.dart` fill this in; the tick engine (03-07) walks it
/// every tick; the reaper (03-11) empties it.
///
/// **Two rules are frozen here, both of them from research rather than taste.**
///
///  * *The registry entry comes out **first** in teardown* (03-RESEARCH Finding
///    9's ordered checklist). The tick loop selects sessions out of the server
///    registry; a session removed last is a session the loop can still pick up
///    halfway through its own dismantling, and the value it pushes then goes
///    into a buffer nobody will ever drain. Remove from the registry, then
///    detach, then close the peer, then close the transport.
///  * *Handles are never released* (03-CONTEXT amendment). Unsubscribing frees
///    subscriptions and listeners; the key→handle table does not move. Reuse
///    would hand a reconnecting panel an integer that now means a different
///    tag, which is a wrong number on a screen rather than a missing one —
///    the worse of the two failures by a distance. `registry_test.dart` asserts
///    the table size across subscribe/unsubscribe, and 03-11 asserts it again
///    across real session churn.
///
/// **Why the listeners live in here and not beside the handler that made
/// them.** `served_state_man.dart:99-128` keeps one listener per key in a map
/// for exactly one reason: teardown has to be able to detach *every* one, and
/// a listener whose only reference is a closure in the frame that attached it
/// cannot be detached at all. The same map, the same reason. The alternative —
/// "the source will be disposed anyway" — is true for the fake and false for a
/// long-lived upstream serving a hundred panels, where the listener outlives
/// the session that wanted it and keeps a dead client's buffer filling.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'relay_server.dart' show SessionRegistry;

/// One attached listener, kept whole so it can be taken off again.
///
/// Both halves are needed: `removeListener` matches on the callback identity,
/// so a record holding only the listenable can never detach, and one holding
/// only the callback has nothing to detach it from.
final class _KeyListener {
  _KeyListener(this.key, this.handle, this.source, this.callback);
  final String key;
  final int handle;
  final ValueListenable<DynamicValue> source;
  final VoidCallback callback;
}

/// One live subscription: its identity, its counters and its listeners.
final class SubscriptionState {
  SubscriptionState({
    required this.sub,
    required this.epoch,
    this.maxRateHz,
  });

  /// The client-chosen name. Unique per session — two subscriptions under one
  /// name would make [seq] ambiguous, so the handler refuses the collision.
  final String sub;

  /// The epoch this subscription's sequence is counted within. A client that
  /// sees a new epoch knows its cached handles are from a previous life.
  final String epoch;

  /// The rate the client asked to be pushed at, if it asked. Advisory until
  /// 03-07, which is what reads it.
  final double? maxRateHz;

  /// This subscription's own monotonic counter, starting at zero.
  ///
  /// Per subscription and never shared: a gap in `seq` is the client's signal
  /// to throw its cache away and resync, so a counter shared between two pages
  /// would make each one resync every time the other moved.
  int get seq => _seq;
  int _seq = 0;

  /// Advances and returns the next sequence number.
  int nextSeq() => ++_seq;

  /// This subscription's name as an escaped JSON string literal, quotes
  /// included, computed with [escape] the first time it is asked for and kept.
  ///
  /// `FrameEncoder.subLiteral` is an encode, and the whole point of the
  /// encode-once path is that no per-client work in a tick is an encode
  /// (03-RESEARCH Finding 2: 69.6× when it is). The name is fixed for the life
  /// of the subscription, so escaping it once per subscription and splicing
  /// the result into every frame afterwards is exact rather than merely
  /// cheaper. Escaped rather than concatenated raw because the name is
  /// client-chosen text going into a frame this server builds by hand, which
  /// is an injection into its own output stream.
  String literal(String Function(String) escape) => _literal ??= escape(sub);
  String? _literal;

  /// handle → key, for everything this subscription watches.
  Map<int, String> get keysByHandle => Map.unmodifiable(_keysByHandle);
  final _keysByHandle = <int, String>{};

  /// The handles this subscription pushes under.
  Set<int> get handles => Set.unmodifiable(_keysByHandle.keys);

  final _listeners = <_KeyListener>[];

  /// Attaches one listener for [key] under [handle], calling [onChange] with
  /// the source's current value whenever it moves.
  ///
  /// The callback is built here rather than passed in already-closed, so that
  /// the identity `removeListener` needs is the identity this class holds.
  void watch(String key, int handle, ValueListenable<DynamicValue> source,
      void Function(DynamicValue value) onChange) {
    void callback() => onChange(source.value);
    source.addListener(callback);
    _keysByHandle[handle] = key;
    _listeners.add(_KeyListener(key, handle, source, callback));
  }

  /// Takes every listener back off its source. Idempotent — the list is
  /// emptied as it goes, so a second call detaches nothing rather than
  /// detaching some other subscription's listener that happened to reuse the
  /// callback.
  void detach() {
    for (final listener in _listeners) {
      listener.source.removeListener(listener.callback);
    }
    _listeners.clear();
  }

  /// How many listeners are currently attached. Read by teardown assertions.
  int get listenerCount => _listeners.length;
}

/// Raised when a session asks for more subscriptions than its ceiling allows.
///
/// A typed error rather than a bare `StateError`, because the handler turns it
/// into a JSON-RPC refusal that names the limit, and a client that is told the
/// number can stay under it.
final class SubscriptionLimitExceeded implements Exception {
  const SubscriptionLimitExceeded(this.limit);
  final int limit;

  @override
  String toString() => 'subscription limit ($limit) reached for this session';
}

/// Every subscription one session holds.
final class SubscriptionRegistry {
  SubscriptionRegistry({required this.maxSubscriptions});

  /// The ceiling from `ServerConfig` (threat T-03-14: one authenticated client
  /// opening subscriptions until the server's memory is gone).
  final int maxSubscriptions;

  final _bySub = <String, SubscriptionState>{};

  /// How many subscriptions are live.
  int get count => _bySub.length;

  /// True when one more would exceed [maxSubscriptions].
  bool get atCapacity => _bySub.length >= maxSubscriptions;

  /// Whether [sub] is already taken on this session.
  bool contains(String sub) => _bySub.containsKey(sub);

  /// The live subscription named [sub], or null.
  SubscriptionState? get(String sub) => _bySub[sub];

  /// Every live subscription, for the tick engine's sweep.
  Iterable<SubscriptionState> get subscriptions => _bySub.values;

  /// The live names — an unmodifiable view, in `registeredMethods`' spirit: an
  /// inspection must not be able to become a mutation by accident.
  Set<String> get names => Set.unmodifiable(_bySub.keys);

  /// The union of every handle under every subscription, deduplicated. One key
  /// watched by two subscriptions is one handle, because the handle is the
  /// key's identity and not the subscription's.
  Set<int> get handles =>
      Set.unmodifiable({for (final s in _bySub.values) ...s.handles});

  /// Records [state]. Throws [SubscriptionLimitExceeded] at the ceiling and
  /// [StateError] on a name collision — a silent replace would strand the
  /// listeners of whatever it replaced.
  void put(SubscriptionState state) {
    if (_bySub.containsKey(state.sub)) {
      throw StateError('subscription "${state.sub}" already exists on this '
          'session; replacing it would strand its listeners and make its seq '
          'ambiguous');
    }
    if (atCapacity) throw SubscriptionLimitExceeded(maxSubscriptions);
    _bySub[state.sub] = state;
  }

  /// Detaches [sub]'s listeners and drops it. Returns false when there was
  /// nothing to remove — an unsubscribe for a name the server has never heard
  /// of is a client that is confused, not an error condition in here.
  bool remove(String sub) {
    final state = _bySub.remove(sub);
    if (state == null) return false;
    state.detach();
    return true;
  }

  /// How many listeners this session currently holds on the backing source,
  /// across every subscription.
  ///
  /// Derived on read rather than tallied, for the reason
  /// [SessionSubscriptionCounts] gives: a maintained count can drift from the
  /// thing it counts, and a teardown assertion reading a drifted tally is an
  /// assertion that passes while the listeners are still attached. Note that
  /// this is the session's own bookkeeping — the *source's* count
  /// (`ValueStoreNode.listenerCount`) is the independent one, and
  /// `teardown_test.dart` reads both because either alone can be right while
  /// the other is wrong.
  int get listenerCount =>
      _bySub.values.fold(0, (n, state) => n + state.listenerCount);

  /// Empties the registry, detaching everything. Called by session teardown,
  /// and the single place teardown detaches through — the alternative, a loop
  /// in `RelaySession.close` beside this one, is two implementations of "every
  /// listener comes off" that only have to disagree once.
  ///
  /// Idempotent, because teardown is: [SubscriptionState.detach] empties its
  /// own list as it goes, and the map is cleared here, so a second call
  /// detaches nothing rather than reaching for a source it has already let go
  /// of.
  void clear() {
    for (final state in _bySub.values) {
      state.detach();
    }
    _bySub.clear();
  }
}

/// The server-wide view: what every live session adds up to.
///
/// An extension rather than a field on `SessionRegistry`, because the holder in
/// `relay_server.dart` is about connections and this is about what those
/// connections are watching — and because a count derived on read cannot drift
/// from the sessions it counts, which a maintained tally can.
extension SessionSubscriptionCounts on SessionRegistry {
  /// The sum of every live session's subscription count. Reaches zero when the
  /// last session goes, which is what 03-11's kill cycle asserts.
  int get subscriptionCount =>
      sessions.fold(0, (n, session) => n + session.subscriptions.count);

  /// Every handle any live session is watching, deduplicated.
  Set<int> get watchedHandles =>
      {for (final session in sessions) ...session.subscriptions.handles};

  /// The sum of every live session's attached listeners. Reaches zero when the
  /// last session goes — the resource the ~37 second ping window of
  /// 03-RESEARCH Finding 7 is expensive about, and the one a registry count
  /// alone cannot see: a session can leave the registry with its listeners
  /// still on the plant.
  int get listenerCount =>
      sessions.fold(0, (n, session) => n + session.subscriptions.listenerCount);
}
