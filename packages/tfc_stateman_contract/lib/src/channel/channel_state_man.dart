/// A `StateManApi` whose values only ever arrive over a channel.
///
/// This is the implementation the contract suite is pointed at, and its
/// defining property is negative: it holds no source. Every value it can return
/// got into its [ValueStore] by way of an inbound [Methods.update]
/// notification, and there is no other path — which is exactly the claim
/// `test/channel/channel_bite_test.dart` exists to make honest, by cutting the
/// channel and showing the same named checks fail rather than pass from a
/// local object nobody noticed was there.
///
/// It is a rehearsal for Phase 4's `RemoteStateMan`, deliberately: same store,
/// same synchronous-answers-from-cache shape, same `subscribe` adapter over the
/// same node. What it is missing is everything a socket forces — reconnect,
/// resync, sequence gaps, per-request deadlines — and the missing pieces are
/// listed rather than stubbed, so nothing here can be mistaken for a client
/// that has already solved them.
///
/// ## Where each member gets its answer
///
/// **From the local store, synchronously:** [listen], [read], [keys],
/// [subscribe]. That is the interface's own design (`state_man_api.dart:90-96`:
/// `read` is "synchronous and never a round trip"), and it is what makes the
/// bite-proof meaningful — a store fed by nothing answers nothing.
///
/// **Over the channel, as a request:** [readFresh], [readMany], [write]. Each
/// is one message out and one back, which is what makes the served source's
/// round-trip counter a measurement of *this* object's wire behaviour.
///
/// **Over the channel, as a notification:** every `StateManHarness` lever. They
/// are `void` on the interface, so there is nothing to await; what makes a
/// lever-then-request sequence correct is the channel's ordering, not an
/// acknowledgement.
///
/// **Not over the channel at all:** [staleAfter], [roundTrips] and
/// [statusNotifications], which are read straight off the served instance.
/// `lib/src/harness.dart:16-25` explains why they exist and why they are not on
/// `StateManApi`: they are promises about a *count*, and putting them on the
/// wire surface would make them things a connected client may invoke, which is
/// an access-control decision rather than a testing convenience. There is
/// therefore nothing for a channel to carry, and mirroring them would be
/// inventing wire traffic to move a number that is already correct.
///
/// The last of those is worth stating as a property rather than an excuse.
/// Because the *served* source increments `roundTrips` once per answer it
/// gives, a client that wrongly issued one request per key instead of one
/// [readMany] still shows up as N. The counter lives on the server and measures
/// the client, which is the only arrangement that survives Phase 4, where the
/// counter genuinely will be on another host.
///
/// ## What is not implemented, and why it is not stubbed
///
/// The four data-service sub-APIs throw. They are a real part of the interface
/// and a real part of the contract suite, and carrying them over this channel
/// means serializing browse nodes, timeseries samples, history-view records and
/// preferences — twenty-five methods whose encodings this plan does not own. A
/// getter that returned an empty implementation would let
/// `runDataServicesContract` run against a channel that carries nothing and
/// report a colour; a getter that throws by name says which leg is missing to
/// whoever points the umbrella at this harness before that leg exists.
library;

import 'dart:async';

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../harness.dart';
import 'rpc_names.dart';

/// A state source on the far side of a message channel.
final class ChannelStateMan implements StateManApi, StateManHarness {
  /// Wraps the client end of a channel whose other end is a served source.
  ///
  /// [observables] is the served instance's control surface, read directly for
  /// the three counters the wire deliberately does not carry. [closeServed]
  /// releases whatever is on the other end; [dispose] calls it, so a driver
  /// that registers `api.dispose` with `addTearDown` — which every sub-suite
  /// does — tears down both halves without knowing there are two.
  ChannelStateMan({
    required StreamChannel<String> channel,
    required StateManHarness observables,
    required Future<void> Function() closeServed,
  })  : _observables = observables,
        _closeServed = closeServed,
        _peer = rpc.Peer(channel) {
    _peer.registerMethod(HarnessMethods.update, _applyUpdate);
    // Swallowed deliberately — see served_state_man.dart for the argument: a
    // channel failure must fail the check that named the property, not arrive
    // as an unhandled zone error attributed to an unrelated test.
    unawaited(_peer.listen().catchError((Object _) => null));
  }

  final StateManHarness _observables;
  final Future<void> Function() _closeServed;
  final rpc.Peer _peer;

  /// The client-side cache — the same [ValueStore] the real client will use, so
  /// the k-of-n rebuild property is satisfied here by production code rather
  /// than by harness scaffolding.
  final _store = ValueStore();

  /// Closers for the streams [subscribe] handed out that are still open.
  ///
  /// The shape is `FakeStateMan`'s (`fake_state_man.dart:119-130`), including
  /// the self-deregistering closer: a registry that only grows is a leak, and
  /// this object is built once per contract case.
  final _closeHandedOutStreams = <Future<void> Function()>{};

  var _disposed = false;

  // ------------------------------------------------- answers from the store

  @override
  ValueListenable<DynamicValue> listen(String key) => _store.node(key);

  @override
  DynamicValue? read(String key) => _store.peek(key);

  /// The keys an update has actually arrived for.
  ///
  /// Filtered on a value having arrived, exactly as the reference
  /// implementation filters (`fake_state_man.dart:267-277`): `listen` creates a
  /// node for any key asked of it, including one mistyped into a page config,
  /// and offering that back to the picker would launder a typo into a valid
  /// binding.
  @override
  List<String> get keys => [
        for (final key in _store.keys)
          if (_store.peek(key) != null) key,
      ];

  /// A broadcast view of the same node, for stream-consuming code.
  ///
  /// A view and never a second source of truth. Returned synchronously so
  /// taking the stream and listening to it happen in one turn, which is what
  /// stops a widget missing the first values of its own subscription.
  @override
  Stream<DynamicValue> subscribe(String key) {
    final node = _store.node(key);
    late final StreamController<DynamicValue> controller;
    void push() => controller.add(node.value);
    late final Future<void> Function() close;
    close = () async {
      _closeHandedOutStreams.remove(close);
      await controller.close();
    };
    controller = StreamController<DynamicValue>.broadcast(
      onListen: () {
        node.addListener(push);
        _closeHandedOutStreams.add(close);
      },
      onCancel: () {
        node.removeListener(push);
        _closeHandedOutStreams.remove(close);
      },
    );
    _closeHandedOutStreams.add(close);
    return controller.stream;
  }

  // --------------------------------------------------- answers over the wire

  @override
  Future<DynamicValue> readFresh(String key) async {
    final raw = await _peer.sendRequest(HarnessMethods.readFresh, {'key': key});
    return DynamicValue.fromJson(_asJson(raw));
  }

  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    // One request for however many keys, which is the promise the interface
    // makes (`state_man_api.dart:104-109`) and the thing the served source's
    // round-trip counter is watching for.
    final raw = await _peer.sendRequest(HarnessMethods.readMany, {'keys': keys});
    return {
      for (final entry in _asJson(raw).entries)
        entry.key: DynamicValue.fromJson(_asJson(entry.value)),
    };
  }

  @override
  Future<WriteResult> write(String key, Object? value, {Object? expect}) async {
    final raw = await _peer.sendRequest(HarnessMethods.write, {
      'key': key,
      'value': value,
      if (expect != null) 'expect': expect,
    });
    return WriteResult.fromJson(_asJson(raw));
  }

  // ------------------------------------------------------- levers, one-way

  @override
  void setValue(String key, Object? value,
          {Quality quality = Quality.good, DateTime? sourceTime}) =>
      _lever(HarnessMethods.setValue, {
        'key': key,
        'value': value,
        'q': quality.code,
        if (sourceTime != null) 't': sourceTime.millisecondsSinceEpoch,
      });

  @override
  void setValues(Map<String, Object?> values) =>
      _lever(HarnessMethods.setValues, {'values': values});

  @override
  void setQuality(String key, Quality quality) => _lever(
      HarnessMethods.setQuality, {'key': key, 'q': quality.code});

  @override
  void dropKey(String key) => _lever(HarnessMethods.dropKey, {'key': key});

  @override
  void disconnectUpstream() =>
      _lever(HarnessMethods.disconnectUpstream, const {});

  @override
  void reconnectUpstream() =>
      _lever(HarnessMethods.reconnectUpstream, const {});

  /// Posts one lever, unless this source is gone.
  ///
  /// The guard is not defensive tidiness. `checkDisposeStopsNotifications`
  /// disposes the source and *then* pulls a lever, which is the whole point of
  /// the case; over a channel that lever would otherwise be a
  /// `sendNotification` on a closed peer, and the case would die of a
  /// `StateError` from inside `json_rpc_2` instead of asserting the property.
  /// A disposed source cannot make a value arrive, so dropping the lever is
  /// also the honest behaviour.
  void _lever(String method, Map<String, Object?> params) {
    if (_disposed || _peer.isClosed) return;
    _peer.sendNotification(method, params);
  }

  // ------------------------------------------- observables, off the source

  @override
  Duration get staleAfter => _observables.staleAfter;

  @override
  int get roundTrips => _observables.roundTrips;

  @override
  int get statusNotifications => _observables.statusNotifications;

  // ------------------------------------------------------------- the inbound

  /// The only way a value gets into this object.
  ///
  /// Applied with no sequence number: numbering, gap detection and the resync
  /// that follows one are Phase 3's session and Phase 4's client, and a harness
  /// that invented a sequence here would be asserting a property nothing has
  /// implemented yet. [ValueStore.applyBatch] treats an unnumbered batch as
  /// out-of-band and leaves the bookkeeping alone, which is the correct meaning
  /// of "this harness does not speak sequences".
  void _applyUpdate(rpc.Parameters params) {
    if (_disposed) return;
    final raw = params['changes'].asMap;
    final changes = <String, DynamicValue>{
      for (final entry in raw.entries)
        '${entry.key}': DynamicValue.fromJson(_asJson(entry.value)),
    };
    if (changes.isEmpty) return;
    _store.applyBatch(changes);
  }

  // ---------------------------------------------------------------- teardown

  /// Drops every listener, closes every handed-out stream, closes the channel,
  /// and releases the served source. Idempotent.
  ///
  /// Both halves, because the driver only knows about one: every sub-suite
  /// registers `api.dispose` with `addTearDown` and nothing else, so a served
  /// source left running here is a freshness watchdog ticking for the rest of
  /// the session against a store nobody is watching.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _store.dispose();
    for (final close in List.of(_closeHandedOutStreams)) {
      await close();
    }
    _closeHandedOutStreams.clear();
    await _peer.close();
    await _closeServed();
  }

  // ------------------------------------------------------ the missing legs

  @override
  BrowseApi get browse => throw UnsupportedError(_notCarried('browse'));

  @override
  TimeseriesApi get timeseries => throw UnsupportedError(_notCarried('timeseries'));

  @override
  HistoryViewApi get historyViews =>
      throw UnsupportedError(_notCarried('historyViews'));

  @override
  PreferencesApi get preferences =>
      throw UnsupportedError(_notCarried('preferences'));

  static String _notCarried(String member) =>
      'ChannelStateMan does not carry $member over the channel yet. This '
      'harness covers the value path — subscribe, store, and the read and '
      'write round trips — which is what plan 02-03 built it for. Pointing '
      'runStateManContract at it will reach this getter; run the value-path '
      'sub-suites directly, or serialize the data services first.';

  /// Narrows a decoded JSON value to the map shape the protocol decoders take.
  ///
  /// `json_rpc_2` hands back whatever `jsonDecode` produced, which is a
  /// `Map<String, dynamic>` for an object and anything at all for a peer that
  /// is lying. A `FormatException` here is the honest outcome — the decoders
  /// this feeds are documented to be tolerant of *fields*, not of being handed
  /// a list where an object belongs — and it is what plan 02-10's corruption
  /// catalogue will be aimed at.
  static Map<String, Object?> _asJson(Object? raw) => raw is Map
      ? {for (final entry in raw.entries) '${entry.key}': entry.value}
      : throw FormatException('expected a JSON object, got ${raw.runtimeType}');
}
