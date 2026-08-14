/// Message parameter/result shapes. json_rpc_2 owns the envelope; these are
/// the `params`/`result` payloads only. Decoders read known keys and ignore
/// everything else (forward compatibility); encoders omit absent optionals.
library;

import 'quality.dart';
import 'sanitize.dart';
import 'wire_value.dart';

final class PeerInfo {
  final String name;
  final String version;
  const PeerInfo(this.name, this.version);

  factory PeerInfo.fromJson(Map<String, Object?> json) =>
      PeerInfo(json['name'] as String, json['version'] as String);

  Map<String, Object?> toJson() => {'name': name, 'version': version};
}

/// Client → server, first message on the socket. Server rejects every other
/// method until it has been accepted.
final class HelloParams {
  final String protocol;
  final List<String> supported;
  final PeerInfo client;
  final Map<String, Object?> capabilities;

  /// Present when attempting to resume: previous session id + epoch and the
  /// last seen sequence per subscription.
  final SessionResume? session;

  const HelloParams({
    required this.protocol,
    required this.supported,
    required this.client,
    this.capabilities = const {},
    this.session,
  });

  factory HelloParams.fromJson(Map<String, Object?> json) => HelloParams(
        protocol: json['protocol'] as String,
        supported:
            (json['supported'] as List? ?? const []).cast<String>(),
        client: PeerInfo.fromJson((json['client'] as Map).cast()),
        capabilities:
            (json['capabilities'] as Map? ?? const {}).cast<String, Object?>(),
        session: json['session'] == null
            ? null
            : SessionResume.fromJson((json['session'] as Map).cast()),
      );

  Map<String, Object?> toJson() => {
        'protocol': protocol,
        'supported': supported,
        'client': client.toJson(),
        if (capabilities.isNotEmpty) 'capabilities': capabilities,
        if (session != null) 'session': session!.toJson(),
      };
}

final class SessionResume {
  final String id;
  final String epoch;
  final Map<String, int> lastSeq;
  const SessionResume(
      {required this.id, required this.epoch, this.lastSeq = const {}});

  factory SessionResume.fromJson(Map<String, Object?> json) => SessionResume(
        id: json['id'] as String,
        epoch: json['epoch'] as String,
        lastSeq: (json['lastSeq'] as Map? ?? const {}).cast<String, int>(),
      );

  Map<String, Object?> toJson() =>
      {'id': id, 'epoch': epoch, if (lastSeq.isNotEmpty) 'lastSeq': lastSeq};
}

final class HelloResult {
  final String protocol;
  final PeerInfo server;
  final Map<String, Object?> capabilities;
  final String sessionId;
  final String epoch;

  /// False ⇒ the client's cache means nothing: resubscribe from scratch.
  final bool resumed;

  /// Server wall clock at handshake (UTC epoch ms) — the client derives its
  /// clock offset from this so staleness is measured against one clock.
  final int serverTime;

  const HelloResult({
    required this.protocol,
    required this.server,
    this.capabilities = const {},
    required this.sessionId,
    required this.epoch,
    required this.resumed,
    required this.serverTime,
  });

  factory HelloResult.fromJson(Map<String, Object?> json) {
    final session = (json['session'] as Map).cast<String, Object?>();
    final clock = (json['clock'] as Map).cast<String, Object?>();
    return HelloResult(
      protocol: json['protocol'] as String,
      server: PeerInfo.fromJson((json['server'] as Map).cast()),
      capabilities:
          (json['capabilities'] as Map? ?? const {}).cast<String, Object?>(),
      sessionId: session['id'] as String,
      epoch: session['epoch'] as String,
      resumed: session['resumed'] as bool,
      serverTime: (clock['serverTime'] as num).toInt(),
    );
  }

  Map<String, Object?> toJson() => {
        'protocol': protocol,
        'server': server.toJson(),
        if (capabilities.isNotEmpty) 'capabilities': capabilities,
        'session': {'id': sessionId, 'epoch': epoch, 'resumed': resumed},
        'clock': {'serverTime': serverTime},
      };
}

final class SubscribeParams {
  final String sub;
  final List<String> keys;
  final double? maxRateHz;
  const SubscribeParams(
      {required this.sub, required this.keys, this.maxRateHz});

  factory SubscribeParams.fromJson(Map<String, Object?> json) =>
      SubscribeParams(
        sub: json['sub'] as String,
        keys: (json['keys'] as List).cast<String>(),
        maxRateHz: (json['maxRateHz'] as num?)?.toDouble(),
      );

  Map<String, Object?> toJson() => {
        'sub': sub,
        'keys': keys,
        if (maxRateHz != null) 'maxRateHz': maxRateHz,
      };
}

final class KeyReject {
  final String kind;
  final String? message;
  const KeyReject(this.kind, {this.message});

  factory KeyReject.fromJson(Map<String, Object?> json) =>
      KeyReject(json['kind'] as String, message: json['message'] as String?);

  Map<String, Object?> toJson() =>
      {'kind': kind, if (message != null) 'message': message};
}

final class SubscribeResult {
  final String sub;
  final String epoch;
  final int seq;

  /// Which establishment of this `sub` the answer belongs to, minted by the
  /// gateway and bumped every time the name is (re-)established.
  ///
  /// **The epoch is not enough, and neither is a client-side connection
  /// counter** (04-REVIEW CR-04). Both change per *session*, and the frame that
  /// poisons a cache is the one still in flight from before a resync on the
  /// **same socket** — a server-announced resync or a gap-triggered
  /// resubscribe rebuilds one subscription while the session epoch stays put.
  /// The stale frame is then applied as an in-sequence batch and takes the
  /// baseline, after which the genuine frame at the same `seq` is discarded as
  /// a replay: the mimic shows the old number, under good quality, and the new
  /// one is gone. One integer per subscription covers that case and the
  /// cross-reconnect case with one mechanism.
  final int generation;

  /// key → integer handle used in every subsequent push.
  final Map<String, int> handles;

  /// handle → full metadata (typeId/displayName/enums…), sent once here.
  final Map<int, Object?> meta;

  /// handle → current value. Atomic with `seq`: the explicit
  /// "initial state complete" every surveyed protocol needed.
  final Map<int, WireValue> snapshot;

  /// Per-key failures — one bad key never blanks a page.
  final Map<String, KeyReject> rejected;

  const SubscribeResult({
    required this.sub,
    required this.epoch,
    required this.seq,
    required this.handles,
    this.meta = const {},
    required this.snapshot,
    this.rejected = const {},
    this.generation = 0,
  });

  factory SubscribeResult.fromJson(Map<String, Object?> json) =>
      SubscribeResult(
        sub: json['sub'] as String,
        epoch: json['epoch'] as String,
        seq: (json['seq'] as num).toInt(),
        // Absent from a gateway that predates the generation: zero, which is
        // the same value every frame from such a gateway carries, so the
        // client's comparison passes rather than dropping everything.
        generation: (json['generation'] as num?)?.toInt() ?? 0,
        handles: (json['handles'] as Map? ?? const {}).cast<String, int>(),
        meta: _intKeyed(json['meta'], (v) => v),
        snapshot: _intKeyed(json['snapshot'],
            (v) => WireValue.fromJson((v as Map).cast())),
        rejected: (json['rejected'] as Map? ?? const {})
            .cast<String, Object?>()
            .map((k, v) =>
                MapEntry(k, KeyReject.fromJson((v as Map).cast()))),
      );

  Map<String, Object?> toJson() => {
        'sub': sub,
        'epoch': epoch,
        'seq': seq,
        'generation': generation,
        'handles': handles,
        if (meta.isNotEmpty) 'meta': _stringKeyed(meta, (v) => v),
        'snapshot': _stringKeyed(snapshot, (v) => v.toJson()),
        if (rejected.isNotEmpty)
          'rejected': rejected.map((k, v) => MapEntry(k, v.toJson())),
      };
}

/// The hot-path notification (`u`). Single-character field names here and
/// only here.
final class UpdateParams {
  final String sub;

  /// Per-subscription, increments by one per message. A gap ⇒ resync.
  final int seq;

  /// Which establishment of [sub] this frame belongs to — `g` on the wire,
  /// one character, because this is the hot path.
  ///
  /// A frame carrying any other generation than the one the client's last
  /// snapshot came with is from before that snapshot, and applying it puts a
  /// reading from a subscription that no longer exists onto a mimic under good
  /// quality. See [SubscribeResult.generation] for why the epoch cannot do
  /// this job.
  final int generation;

  /// Batch timestamp (UTC epoch ms) applying to values without their own.
  final int t;

  /// handle → changed value (slim).
  final Map<int, WireValue> changes;

  /// handle → quality-only transition.
  final Map<int, Quality> qualities;

  /// handles no longer available.
  final List<int> removed;

  const UpdateParams({
    required this.sub,
    required this.seq,
    required this.t,
    this.generation = 0,
    this.changes = const {},
    this.qualities = const {},
    this.removed = const [],
  });

  factory UpdateParams.fromJson(Map<String, Object?> json) => UpdateParams(
        sub: json['sub'] as String,
        seq: (json['seq'] as num).toInt(),
        t: (json['t'] as num).toInt(),
        generation: (json['g'] as num?)?.toInt() ?? 0,
        changes: _intKeyed(
            json['c'], (v) => WireValue.fromJson((v as Map).cast())),
        qualities: _intKeyed(json['q'], Quality.fromWire),
        removed: (json['r'] as List? ?? const []).cast<int>(),
      );

  Map<String, Object?> toJson() => {
        'sub': sub,
        'seq': seq,
        't': t,
        'g': generation,
        if (changes.isNotEmpty)
          'c': _stringKeyed(changes, (v) => v.toJson()),
        if (qualities.isNotEmpty)
          'q': _stringKeyed(qualities, (v) => v.code),
        if (removed.isNotEmpty) 'r': removed,
      };
}

/// Per-subscription heartbeat state inside a [TickParams]: proves the
/// subscription itself is alive, not just the socket (the
/// dead-subscription-on-live-connection failure).
final class SubTick {
  final int seq;
  final int evaluatedAt;
  const SubTick({required this.seq, required this.evaluatedAt});

  factory SubTick.fromJson(Map<String, Object?> json) => SubTick(
        seq: (json['seq'] as num).toInt(),
        evaluatedAt: (json['evaluatedAt'] as num).toInt(),
      );

  Map<String, Object?> toJson() => {'seq': seq, 'evaluatedAt': evaluatedAt};
}

/// Server → client on a fixed cadence even when nothing changed: silence is
/// never ambiguous (OPC UA keep-alive rule; client death deadline = 3×).
final class TickParams {
  final int serverTime;
  final Map<String, SubTick> subs;
  const TickParams({required this.serverTime, this.subs = const {}});

  factory TickParams.fromJson(Map<String, Object?> json) => TickParams(
        serverTime: (json['serverTime'] as num).toInt(),
        subs: (json['subs'] as Map? ?? const {})
            .cast<String, Object?>()
            .map((k, v) => MapEntry(k, SubTick.fromJson((v as Map).cast()))),
      );

  Map<String, Object?> toJson() => {
        'serverTime': serverTime,
        if (subs.isNotEmpty)
          'subs': subs.map((k, v) => MapEntry(k, v.toJson())),
      };
}

final class ResyncParams {
  final String sub;
  final String epoch;

  /// `epoch_changed` | `server_restart` | `overrun` |
  /// `permissions_changed` | `gateway_stalled` | `plc_reprogrammed`
  final String reason;

  /// For `gateway_stalled`: how long the event loop was frozen.
  final int? stalledMs;

  const ResyncParams(
      {required this.sub,
      required this.epoch,
      required this.reason,
      this.stalledMs});

  factory ResyncParams.fromJson(Map<String, Object?> json) => ResyncParams(
        sub: json['sub'] as String,
        epoch: json['epoch'] as String,
        reason: json['reason'] as String,
        stalledMs: (json['stalledMs'] as num?)?.toInt(),
      );

  Map<String, Object?> toJson() => {
        'sub': sub,
        'epoch': epoch,
        'reason': reason,
        if (stalledMs != null) 'stalledMs': stalledMs,
      };
}

/// Per-upstream link state — its own channel, never smuggled inside tag
/// values. Also feeds the `PIPE.upstream.<alias>.*` keys and alarm
/// master-inhibit.
final class StatusParams {
  final String alias;

  /// `connected` | `connecting` | `disconnected` | `unhealthy` |
  /// `reprogrammed`
  final String state;
  final String? error;

  const StatusParams({required this.alias, required this.state, this.error});

  factory StatusParams.fromJson(Map<String, Object?> json) => StatusParams(
        alias: json['alias'] as String,
        state: json['state'] as String,
        error: json['error'] as String?,
      );

  Map<String, Object?> toJson() => {
        'alias': alias,
        'state': state,
        if (error != null) 'error': error,
      };
}

final class WriteParams {
  /// Client-minted ULID, created when the operator acts — a re-send reuses
  /// it (idempotency key; server dedups within [ttlMs]).
  final String cmd;
  final String key;
  final Object? value;

  /// Optional compare-and-set guard: apply only if the current value
  /// matches.
  final Object? expect;
  final int? ttlMs;

  /// Refuses a non-finite [value] or [expect] rather than sanitizing it.
  ///
  /// Sanitizing is right for telemetry, where the alternative is a frame that
  /// fails for every client. On the write path the value is an operator's
  /// intent and the two losses are both silent: a non-finite [value] would
  /// become a write of `null`, actuating the device with something nobody
  /// chose, and a non-finite [expect] would become `null`, which is this
  /// class's encoding of "no compare-and-set guard" — turning a guarded write
  /// into an unconditional one. Nothing upstream of a write box can
  /// legitimately produce a NaN, so this is programmer error, and throwing is
  /// the one thing the write path is allowed to do about it.
  factory WriteParams(
      {required String cmd,
      required String key,
      required Object? value,
      Object? expect,
      int? ttlMs}) {
    final v = sanitize(value);
    final e = sanitize(expect);
    if (v.hadNonFinite || e.hadNonFinite) {
      throw ArgumentError.value(
          v.hadNonFinite ? value : expect,
          v.hadNonFinite ? 'value' : 'expect',
          'a write cannot carry a non-finite number: nulling it would actuate '
              'the device with a value the operator did not choose, and '
              'nulling an expect would turn a guarded write into an '
              'unconditional one');
    }
    return WriteParams._(cmd, key, v.value, e.value, ttlMs);
  }

  const WriteParams._(this.cmd, this.key, this.value, this.expect, this.ttlMs);

  factory WriteParams.fromJson(Map<String, Object?> json) {
    try {
      return WriteParams(
        cmd: json['cmd'] as String,
        key: json['key'] as String,
        value: json['value'],
        expect: json['expect'],
        ttlMs: (json['ttlMs'] as num?)?.toInt(),
      );
    } on ArgumentError catch (e) {
      // `1e999` decodes silently to Infinity, so a peer can reach the refusal
      // above. From here it is a malformed frame rather than local programmer
      // error — the write is refused either way, which is the point.
      throw FormatException('write params carry a non-finite number: '
          '${e.name} = ${e.invalidValue}');
    }
  }

  Map<String, Object?> toJson() => {
        'cmd': cmd,
        'key': key,
        'value': value,
        if (expect != null) 'expect': expect,
        if (ttlMs != null) 'ttlMs': ttlMs,
      };
}

final class WriteStatusParams {
  final List<String> cmds;
  const WriteStatusParams(this.cmds);

  factory WriteStatusParams.fromJson(Map<String, Object?> json) =>
      WriteStatusParams((json['cmds'] as List).cast<String>());

  Map<String, Object?> toJson() => {'cmds': cmds};
}

// JSON objects key by String; handles are ints. Convert at the boundary.
Map<int, V> _intKeyed<V>(Object? raw, V Function(Object?) decode) {
  if (raw == null) return const {};
  return (raw as Map).cast<String, Object?>().map(
        (k, v) => MapEntry(int.parse(k), decode(v)),
      );
}

Map<String, Object?> _stringKeyed<V>(
        Map<int, V> map, Object? Function(V) encode) =>
    map.map((k, v) => MapEntry('$k', encode(v)));
