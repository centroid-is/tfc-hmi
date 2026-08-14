/// Serving a `StateManApi` — and its test-only levers — over a message channel.
///
/// This is the source side of the harness: a `json_rpc_2.Peer` that answers the
/// value path from a real implementation and pushes that implementation's
/// changes outward as [Methods.update] notifications. Phase 3's session layer
/// will do the same job for real, over a socket, with authentication and
/// per-key subscription accounting in front of it. This is not that. It is the
/// channel the wire will run on, built now so that the contract suite can be
/// pointed across a message boundary a phase before there is a server to point
/// it at — and so that the boundary is proven to be load-bearing before
/// anything depends on it.
///
/// ## Three decisions worth the words
///
/// **The payload is `DynamicValue.toJson()`, not the slim `WireValue` form.**
/// The slim encoding drops quality, source time and metadata — it is the hot
/// path, and Phase 3's session will use it, because on a 1500-key page the
/// metadata rides once in the subscribe result rather than on every push. Here
/// the lossless form is required by what the suite measures: the store
/// contract's unchanged-value case is decided by `==` on `DynamicValue`, and
/// `dynamic_value.dart:687` documents `fromJson(toJson())` as equal to the
/// original. A slim payload would make every re-delivery of an unchanged value
/// compare unequal on the client, and the k-of-n rebuild property would fail
/// against a source that was behaving perfectly.
///
/// **Levers arrive as notifications, not as requests.** Every member of
/// `StateManHarness` that this forwards returns `void`, so there is nothing for
/// a client to await and a request-shaped lever would invent an
/// acknowledgement the interface does not have. What makes a lever-then-request
/// sequence correct is instead the ordering guarantee of a single channel:
/// messages are delivered in the order they were sent, so a `setValue` posted
/// before a `readFresh` is applied before that read is answered. That is a
/// property of the transport, and it is the same property a WebSocket has, so
/// the sequence transfers to Phase 4 unchanged.
///
/// **Change detection is a listener per key, plus a re-scan.** A listener
/// attached to `api.listen(key)` catches every change to a key that already
/// exists — including the ones no lever caused, which is the point: the
/// freshness watchdog degrading a value to `badStale` is a change the client
/// must see, and nothing on the inbound path would ever tell it. A key that a
/// lever *creates* has no listener at the moment its first value lands, so
/// every inbound lever is followed by a re-scan of `api.keys` that adopts the
/// newcomers and marks them changed. The two mechanisms together are what makes
/// "every value the client holds arrived over this channel" true rather than
/// approximately true.
///
/// Coalescing is by microtask: changes accumulate in a set and one notification
/// carries all of them. A lever applies its whole batch synchronously, so the
/// batch is still one batch when the flush runs — which is what the
/// notification-count promise (`lib/src/harness.dart:56-61`) is made about.
library;

import 'dart:async';

import 'package:json_rpc_2/error_code.dart' as error_code;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:stream_channel/stream_channel.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../harness.dart';
import '../write_contract.dart';
import 'rpc_names.dart';

/// Serves [api] over [channel] and starts listening immediately.
///
/// [api] must implement `StateManHarness` — a source with no control surface
/// cannot be driven by a contract case, and [harnessOf] says so by name rather
/// than through a cast error.
ServedStateMan serveStateMan(StateManApi api, StreamChannel<String> channel) =>
    ServedStateMan._(api, harnessOf(api), rpc.Peer(channel)).._start();

/// One served source: the peer, the registrations, and the outbound push.
final class ServedStateMan {
  ServedStateMan._(this.api, this.plant, this.peer);

  /// The implementation being served. Real, not a mock — the whole harness is
  /// worthless if the thing on the far end is a stand-in.
  final StateManApi api;

  /// Its test-only control surface.
  final StateManHarness plant;

  /// Its *write*-side control surface, resolved on first use.
  ///
  /// Lazily rather than in the constructor, because a source with no write
  /// levers is a legitimate thing to serve — an M2400 weigher adapter takes no
  /// writes at all — and the read, subscribe, store and freshness sub-suites
  /// judge it perfectly well without one. Resolving eagerly would refuse to
  /// serve it. Resolving here means the failure arrives when a case first
  /// pulls a write lever, naming what to add, which is the same bargain
  /// [writeHarnessOf] already strikes.
  late final StateManWriteHarness writePlant = writeHarnessOf(api);

  /// The JSON-RPC endpoint. Exposed so a test can assert on its state; nothing
  /// in the ordinary path needs it.
  final rpc.Peer peer;

  /// One listener per key being watched, kept so [close] can detach them.
  ///
  /// A listener left attached to a store the peer no longer serves keeps
  /// pushing into a closed channel, which is a leak that surfaces as an
  /// inexplicable failure in whichever case runs next.
  final _watchers = <String, void Function()>{};

  /// Keys changed since the last flush.
  final _pending = <String>{};

  var _flushScheduled = false;
  var _closed = false;

  /// Whether this peer has stopped serving, for whatever reason.
  bool get isClosed => _closed || peer.isClosed;

  /// Completes when the peer is done — because [close] was called, or because
  /// the channel went away underneath it.
  Future<void> get closed => _done.future;
  final _done = Completer<void>();

  void _start() {
    peer
      ..registerMethod(HarnessMethods.readFresh, _readFresh)
      ..registerMethod(HarnessMethods.readMany, _readMany)
      ..registerMethod(HarnessMethods.keys, (rpc.Parameters _) => api.keys)
      ..registerMethod(HarnessMethods.write, _write)
      ..registerMethod(HarnessMethods.setValue, _setValue)
      ..registerMethod(HarnessMethods.setValues, _setValues)
      ..registerMethod(HarnessMethods.setQuality, _setQuality)
      ..registerMethod(HarnessMethods.dropKey, _dropKey)
      ..registerMethod(HarnessMethods.disconnectUpstream, _disconnectUpstream)
      ..registerMethod(HarnessMethods.reconnectUpstream, _reconnectUpstream)
      ..registerMethod(HarnessMethods.failNextWrite, _failNextWrite)
      ..registerMethod(HarnessMethods.clampNextWrite, _clampNextWrite)
      ..registerMethod(HarnessMethods.stallWrites, _stallWrites)
      ..registerMethod(HarnessMethods.releaseWrites, _releaseWrites)
      ..registerMethod(HarnessMethods.setReadOnly, _setReadOnly);

    // Swallowed on purpose. A channel that fails must fail the check that named
    // the property it broke; an unhandled zone error would instead be
    // attributed to whichever test happened to be running when it landed, which
    // is exactly the misattribution `test/suite_integrity_test.dart:78-85`
    // collects zone errors to avoid.
    unawaited(peer.listen().catchError((Object _) => null).whenComplete(() {
      _closed = true;
      if (!_done.isCompleted) _done.complete();
    }));

    // The opening snapshot: recovery — and connection — is always a snapshot
    // and never a delta replay (CLI-03), so a client that attaches to a source
    // which already holds values learns them at once rather than waiting until
    // each next happens to change.
    _adoptNewKeys();
  }

  // ------------------------------------------------------------- value path

  Future<Object?> _readFresh(rpc.Parameters params) async =>
      (await api.readFresh(params['key'].asString)).toJson();

  Future<Object?> _readMany(rpc.Parameters params) async {
    final keys = [for (final key in params['keys'].asList) '$key'];
    final values = await api.readMany(keys);
    return {
      for (final entry in values.entries) entry.key: entry.value.toJson(),
    };
  }

  Future<Object?> _write(rpc.Parameters params) async {
    final key = params['key'].asString;
    final value = params['value'].valueOr(null);
    // Absent and null are the same thing here, deliberately: the reference
    // implementation's compare-and-set is itself keyed on `expected != null`
    // (`fake_state_man.dart:676`), so a wire that distinguished them would be
    // carrying a distinction the source cannot act on.
    final expected = params['expect'].valueOr(null);

    // The same refusal `WriteParams` makes (`messages.dart:373-401`), made
    // here because this harness does not carry a `WriteParams` — the `cmd` is
    // minted by the served implementation, not by the caller, so there is no
    // client-minted id to build one around.
    //
    // Reachable only from a raw frame, and reachable nonetheless: `jsonEncode`
    // refuses to *emit* a non-finite, but `1e999` silently *decodes* to
    // Infinity, so the decoder is where poison enters from outside. Both
    // losses it prevents are silent — a nulled value actuates the device with
    // something nobody chose, and a nulled `expect` is this path's encoding of
    // "no compare-and-set guard", which turns a guarded write into an
    // unconditional one.
    //
    // An error answer rather than a silent one: on a write, a JSON-RPC error
    // means "definitively no effect", which is the one outcome it is safe to
    // re-send — and, more immediately, it means the caller's request settles.
    // There is no per-request deadline on this path (Phase 4 owns that), so
    // anything that does not answer hangs forever (RESEARCH Finding 15).
    //
    // An [rpc.RpcException] carrying its own `data.request`, rather than the
    // plain `FormatException` this obviously wants to be, and the reason is
    // the trap that makes this whole guard nearly self-defeating:
    // `RpcException.serialize` copies the offending **request** into the error
    // it sends back unless `data` already has a `request` key
    // (`json_rpc_2-4.1.0/lib/src/exception.dart:46-57`). A request carrying
    // Infinity therefore produces an error response carrying Infinity, which
    // `jsonEncode` refuses on the way out — so the refusal is thrown away
    // inside the peer and the caller waits forever. The failure the guard
    // exists to prevent is exactly the failure the guard would have caused.
    // The substitute string is what keeps the answer encodable.
    if (sanitize(value).hadNonFinite || sanitize(expected).hadNonFinite) {
      throw rpc.RpcException(
        error_code.INVALID_PARAMS,
        'write params carry a non-finite number: nulling a value would '
            'actuate the device with something the operator did not choose, '
            'and nulling an expect would turn a guarded write into an '
            'unconditional one',
        data: {
          'key': key,
          'request': 'omitted: it carries a non-finite number, and echoing it '
              'here is what makes the error itself unencodable',
        },
      );
    }

    final result = await api.write(key, value, expect: expected);
    return result.toJson();
  }

  // ----------------------------------------------------------------- levers

  void _setValue(rpc.Parameters params) => _afterLever(() => plant.setValue(
        params['key'].asString,
        params['value'].valueOr(null),
        quality: Quality.fromWire(params['q'].valueOr(null)),
        sourceTime: _timeOf(params['t'].valueOr(null)),
      ));

  void _setValues(rpc.Parameters params) => _afterLever(() {
        final raw = params['values'].asMap;
        plant.setValues({
          for (final entry in raw.entries) '${entry.key}': entry.value,
        });
      });

  void _setQuality(rpc.Parameters params) => _afterLever(() => plant.setQuality(
        params['key'].asString,
        Quality.fromWire(params['q'].valueOr(null)),
      ));

  void _dropKey(rpc.Parameters params) =>
      _afterLever(() => plant.dropKey(params['key'].asString));

  void _disconnectUpstream(rpc.Parameters _) =>
      _afterLever(plant.disconnectUpstream);

  void _reconnectUpstream(rpc.Parameters _) =>
      _afterLever(plant.reconnectUpstream);

  // ----------------------------------------------------------- write levers

  /// The write levers, in the same one-way lane as the value levers.
  ///
  /// All five are `void` on `StateManWriteHarness`, so there is nothing for a
  /// caller to await and a request-shaped lever would invent an
  /// acknowledgement the interface does not have. What makes
  /// `stallWrites()` → `write(…)` correct across the channel is instead the
  /// ordering guarantee: the notification was posted first, so it is applied
  /// before the request that follows it is answered. That is a property of the
  /// transport rather than of this file, and a WebSocket has it too, which is
  /// why the sequence transfers to Phase 4 unchanged.
  void _failNextWrite(rpc.Parameters params) => _afterLever(() {
        final raw = params['reason'].asMap;
        writePlant.failNextWrite(
          WriteReason.fromJson({
            for (final entry in raw.entries) '${entry.key}': entry.value,
          }),
          unknown: params['unknown'].asBoolOr(false),
        );
      });

  void _clampNextWrite(rpc.Parameters params) =>
      _afterLever(() => writePlant.clampNextWrite(params['readback'].valueOr(null)));

  void _stallWrites(rpc.Parameters _) => _afterLever(writePlant.stallWrites);

  void _releaseWrites(rpc.Parameters params) => _afterLever(
      () => writePlant.releaseWrites(applied: params['applied'].asBoolOr(true)));

  void _setReadOnly(rpc.Parameters params) => _afterLever(() => writePlant
      .setReadOnly(params['key'].asString, params['readOnly'].asBoolOr(true)));

  /// Applies a lever, then adopts whatever keys it brought into existence.
  ///
  /// The re-scan is not an optimisation and cannot be dropped: `setValue` on a
  /// key nothing has been heard about creates that key, and the value lands
  /// before any listener could have been attached to it. Without this, the
  /// first value of every new key would be the one value that never crosses the
  /// channel — and the first value of a key is precisely what a page opening
  /// shows an operator.
  void _afterLever(void Function() lever) {
    if (_closed) return;
    lever();
    _adoptNewKeys();
  }

  void _adoptNewKeys() {
    for (final key in api.keys) {
      if (_watchers.containsKey(key)) continue;
      void watch() => _changed(key);
      _watchers[key] = watch;
      api.listen(key).addListener(watch);
      // A key adopted here has just acquired a value, by definition — `keys` is
      // filtered on one having arrived — so it is a change the client has not
      // seen.
      _pending.add(key);
    }
    if (_pending.isNotEmpty) _scheduleFlush();
  }

  void _changed(String key) {
    _pending.add(key);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled || _closed) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  /// One notification per flush, however many keys moved.
  ///
  /// A microtask rather than a timer: a lever applies its whole batch
  /// synchronously, so by the time the microtask queue drains, every key that
  /// batch touched is in [_pending] and one message carries all of them. A
  /// timer would coalesce *across* levers too, which would make the count this
  /// promises depend on how fast the test ran.
  void _flush() {
    _flushScheduled = false;
    if (_closed || _pending.isEmpty) return;
    final changes = <String, Object?>{};
    for (final key in _pending) {
      final value = api.read(key);
      if (value == null) continue;
      changes[key] = value.toJson();
    }
    _pending.clear();
    if (changes.isEmpty) return;
    peer.sendNotification(HarnessMethods.update, {'changes': changes});
  }

  /// Detaches every listener and closes the peer. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final entry in _watchers.entries) {
      api.listen(entry.key).removeListener(entry.value);
    }
    _watchers.clear();
    _pending.clear();
    await peer.close();
    if (!_done.isCompleted) _done.complete();
  }

  static DateTime? _timeOf(Object? raw) => raw is num
      ? DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true)
      : null;
}
