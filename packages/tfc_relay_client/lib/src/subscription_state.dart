/// One subscription's client-side state, and the decode that fills it.
///
/// The state is the mirror image of `tfc_relay_server`'s
/// `SubscriptionRegistry` entry: `subId`, the requested key set, `epoch`,
/// `lastSeq`, the handle→key map, and `lastEvaluatedAt`. Nothing else — this
/// object is read by the resync engine and the freshness watchdog, and the
/// moment it also holds a cache there are two answers to "what is this tag
/// reading" (the `ValueStore` is the one).
///
/// **Why the decode is tested against wire text.** Every trap below was
/// observed live (04-RESEARCH Finding 7, a real subscribe against
/// `relayFixture()`), and STATE.md records that Phase 1's defect cluster was
/// exactly this boundary — 5 of 5 Criticals at decode. None of these failures
/// throw:
///
/// - `snapshot` and `meta` are keyed by **handle as a JSON string** (`"1"`),
///   not by tag name. A decoder that used those keys raw caches every value
///   under a name no widget ever asks for, and the page reads "not yet known"
///   forever while the socket looks perfectly healthy.
/// - `rejected` arrives **absent** when nothing was rejected, not as `{}`.
/// - `jsonDecode('1e999')` yields `Infinity` in silence, and an `Infinity`
///   that reaches the cache renders as a plausible number and then detonates
///   the next `jsonEncode`.
///
/// **Rejections are recorded, never thrown** — the client half of the server's
/// argument at `session_handlers.dart:30-44`: a page config carries ~1500
/// hand-edited keys, so one typo must cost one tag rather than blank a
/// control-room screen.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

/// A decoded `subscribe` result, with every handle already resolved to the tag
/// name the rest of the client speaks in.
final class DecodedSubscribeResult {
  /// The subscription name every subsequent update frame is filed under.
  final String sub;

  /// The server's epoch for this subscription. A frame carrying any other
  /// epoch belongs to a session that no longer exists.
  final String epoch;

  /// The sequence this snapshot is atomic with — the baseline the delta chain
  /// counts from. Zero on a fresh subscribe.
  final int seq;

  /// Which establishment of this subscription the snapshot belongs to.
  ///
  /// Minted by the gateway and bumped on every (re-)establish, so a frame
  /// still in flight from before this snapshot can be told apart from a live
  /// one — including when the two share a socket, which is the case no epoch
  /// and no client-side connection counter can see (04-REVIEW CR-04).
  final int generation;

  /// handle → key. Inverted from the wire's key → handle, because every later
  /// frame arrives holding handles and has to answer with keys.
  final Map<int, String> handles;

  /// key → value, ready to hand to `ValueStore.applyBatch` unchanged.
  final Map<String, DynamicValue> values;

  /// key → the metadata sent once with the snapshot.
  final Map<String, Object?> meta;

  /// Per-key configuration failures. Populated, empty, or from an absent
  /// field — all three are ordinary outcomes.
  final Map<String, KeyReject> rejected;

  /// Entries the server sent that could not be filed anywhere: a snapshot or
  /// meta key naming a handle that was never announced.
  ///
  /// Recorded rather than dropped in silence, and never applied under a
  /// guessed name. A value on a mimic under a label the server never agreed
  /// to is worse than a value missing from it, and a page that goes half-blank
  /// with nothing in the log cannot be chased.
  final List<String> complaints;

  const DecodedSubscribeResult({
    required this.sub,
    required this.epoch,
    required this.seq,
    this.generation = 0,
    required this.handles,
    required this.values,
    required this.meta,
    required this.rejected,
    required this.complaints,
  });
}

/// Narrows a decoded JSON value to the map shape the decoders take.
///
/// Copied from `tfc_stateman_contract`'s `channel_state_man.dart:508-510`:
/// `json_rpc_2` hands back whatever `jsonDecode` produced, which is a
/// `Map<String, dynamic>` for an object and anything at all for a peer that is
/// lying. A [FormatException] is the honest outcome — the decoders this feeds
/// are documented to be tolerant of *fields*, not of being handed a list where
/// an object belongs.
Map<String, Object?> _asJson(Object? raw) => raw is Map
    ? {for (final entry in raw.entries) '${entry.key}': entry.value}
    : throw FormatException('expected a JSON object, got ${raw.runtimeType}');

/// Parses a handle key that may be an int or a JSON string, or null when it is
/// neither.
int? _handleKey(Object? raw) =>
    raw is int ? raw : (raw is num ? raw.toInt() : int.tryParse('$raw'));

/// Decodes a `subscribe` result into [DecodedSubscribeResult].
///
/// Throws [FormatException] when [raw] is not a JSON object. Everything
/// narrower than that — an unmapped handle, a rejected key, a poison number —
/// is recorded and the call still succeeds.
DecodedSubscribeResult decodeSubscribeResult(Object? raw) {
  final json = _asJson(raw);

  // Sanitize before decode, every time, on every ingress path:
  // `jsonDecode('1e999')` yields Infinity in silence, and an Infinity that
  // reaches an error response makes the *error* unencodable (the 02-05 hang).
  //
  // The snapshot is deliberately held out and sanitized per value below,
  // through `WireValue.of`. Sanitizing it here would work — the Infinity would
  // become null — but the null would carry *good* quality, which reads as an
  // absent value rather than a bad one. `Quality.badNonFinite` can only be
  // attached where the replacement happens, so that is where it happens.
  final snapshot = json['snapshot'];
  final envelope = sanitize({...json}..remove('snapshot')).value as Map;

  final complaints = <String>[];

  final wireHandles = envelope['handles'];
  final handles = <int, String>{};
  if (wireHandles is Map) {
    for (final entry in wireHandles.entries) {
      final handle = _handleKey(entry.value);
      if (handle == null) {
        complaints.add('handle for "${entry.key}" is not a number: '
            '${entry.value}');
        continue;
      }
      handles[handle] = '${entry.key}';
    }
  }

  /// Re-keys a handle-keyed wire map to tag names, complaining about entries
  /// that name a handle nobody announced.
  Map<String, T> byKey<T>(Object? wire, String what, T Function(Object?) decode) {
    final out = <String, T>{};
    if (wire is! Map) return out;
    for (final entry in wire.entries) {
      final handle = _handleKey(entry.key);
      final key = handle == null ? null : handles[handle];
      if (key == null) {
        complaints.add('$what entry for handle ${entry.key} has no announced '
            'key and was dropped rather than filed under a guess');
        continue;
      }
      out[key] = decode(entry.value);
    }
    return out;
  }

  final values = byKey(snapshot, 'snapshot', (v) {
    // `WireValue.fromJson` sanitizes the value and composes
    // `Quality.badNonFinite` over `Quality.fromWire`'s clamp, so neither the
    // poison nor an out-of-band code is range-checked by hand here.
    // `toDynamicValue` carries the source timestamp across; building the
    // `DynamicValue` by hand here is how it used to get dropped.
    return WireValue.fromJson(_asJson(v)).toDynamicValue();
  });

  final meta = byKey<Object?>(envelope['meta'], 'meta', (v) => v);

  // Absent, null and `{}` all mean the same thing: nothing was rejected.
  // Finding 7 observed the live server omitting the field entirely.
  final wireRejected = envelope['rejected'];
  final rejected = <String, KeyReject>{};
  if (wireRejected is Map) {
    for (final entry in wireRejected.entries) {
      rejected['${entry.key}'] = KeyReject.fromJson(_asJson(entry.value));
    }
  }

  final seq = envelope['seq'];
  // Absent from a gateway that predates the generation, and zero is then what
  // every one of its frames carries too — so the client's comparison passes
  // rather than silently dropping the whole stream.
  final generation = envelope['generation'];
  return DecodedSubscribeResult(
    sub: '${envelope['sub']}',
    epoch: '${envelope['epoch']}',
    seq: seq is num && seq.isFinite ? seq.toInt() : 0,
    generation:
        generation is num && generation.isFinite ? generation.toInt() : 0,
    handles: handles,
    values: values,
    meta: meta,
    rejected: rejected,
    complaints: complaints,
  );
}

/// What the client remembers about one subscription between frames.
final class SubscriptionState {
  /// The subscription name, minted by the client and echoed by the server.
  final String subId;

  /// The keys this subscription asked for — re-sent verbatim on every
  /// resubscribe, which is why they are held rather than recomputed from the
  /// handle map (a rejected key has no handle, and dropping it here would
  /// mean the page never asks for it again).
  final Set<String> keys;

  /// The epoch the last accepted snapshot carried. Empty until one has.
  String epoch;

  /// The last sequence number applied, or null when no numbered frame has
  /// been. Null rather than zero: zero is a real sequence, and a baseline of
  /// zero before the snapshot would make the server's first frame read as a
  /// replay.
  int? lastSeq;

  /// handle → key, from the last snapshot.
  Map<int, String> handles;

  /// The generation the last accepted snapshot carried; zero until one has.
  ///
  /// Every update frame is measured against it. A frame from an earlier
  /// establishment is dropped without advancing [lastSeq] — advancing it would
  /// be the poisoning itself, because the genuine frame at that sequence then
  /// reads as a replay and is discarded.
  ///
  /// There is deliberately no `lastEvaluatedAt` beside it. The field used to
  /// exist and claimed in its own doc to be "read by the freshness watchdog",
  /// which was false in both halves — nothing assigned it and the watchdog
  /// keeps its own map (04-REVIEW WR-09). Two homes for one fact is what the
  /// class doc above says this object exists to avoid.
  int generation;

  SubscriptionState({
    required this.subId,
    required this.keys,
    this.epoch = '',
    this.lastSeq,
    Map<int, String>? handles,
    this.generation = 0,
  }) : handles = handles ?? <int, String>{};

  /// Takes on the epoch, baseline sequence and handle map from a fresh
  /// snapshot. The values themselves go to the `ValueStore`, not here.
  void adopt(DecodedSubscribeResult result) {
    epoch = result.epoch;
    lastSeq = result.seq;
    handles = result.handles;
    generation = result.generation;
  }

  @override
  String toString() =>
      'SubscriptionState($subId, epoch: $epoch, generation: $generation, '
      'lastSeq: $lastSeq, ${keys.length} keys)';
}
