/// The OPC UA [UpstreamLink]: real quality, real source time, one supervised
/// iterate loop.
///
/// **Wrap, do not rebuild.** This class owns a `ClientWrapper`
/// (`packages/tfc_dart/lib/core/state_man.dart:834`) and not a session manager
/// of its own, because that class encodes three dated, measured things:
///
///  * the **two-phase resubscribe** that fixed a monitored-item storm
///    (`:1458-1510`, and the ordering at `:1480-1501`),
///  * a **heartbeat-derived effective status** with a 15 s stale / 30 s grace
///    window (`:958-964`) — the only thing that catches the frozen-session
///    failure, where TCP is Established, the channel is formally open, and no
///    state event is ever emitted again,
///  * `isSubscriptionDead` (`:872`), which tells a transient `Inactivity` from
///    a fatal `SubscriptionDeleted` / `SecureChannelClosed`.
///
/// Rebuilding those to the same fidelity is not a phase, and the failure mode
/// is silent. What is *not* inherited is the composer above them: `StateMan`'s
/// throwing `read`/`write` (`:1876-1878`, `:2042-2044`), its
/// `Future<Stream<…>>` subscribe (`:2054`), its quality-less values, and its
/// two unawaited `() async {…}()` loops driving `runIterate` with a bare
/// `Logger()` and no error seam (`:1364`, `:1398`). Those are the four gaps
/// this adapter exists to close.
///
/// **Two classes are called `DynamicValue` in this solve.** The binding's is
/// imported as `ua.` throughout; the relay's — the one with
/// [DynamicValue.quality] and [DynamicValue.sourceTime] as first-class fields —
/// is the unprefixed one. Every value crossing this seam goes through
/// [translateOpcUaSample], which is the adapter's entire reason for existing
/// and therefore gets its own function, its own tests and its own doc.
/// `M2400DeviceClientAdapter._mapStatus` (`state_man.dart:1277-1286`) is the
/// idiom being copied.
///
/// ## Assumption A5, recorded rather than decided
///
/// `StateMan.create(useIsolate: true)` is the app's default and keeps the
/// blocking FFI off the event loop the `LagMonitor` measures. The gateway's hot
/// path, though, is one isolate encoding once and fanning out (design §5), so
/// every isolate boundary is a copy. [useIsolate] is therefore a constructor
/// flag, defaulting to **true** — the safe half — and set false by the test
/// fixture so a leg can reach into the client. **Nothing in this phase measures
/// which is right.** That is A5, and it stays an assumption until somebody puts
/// a number on it.
library;

import 'dart:async';

import 'package:open62541/open62541.dart' as ua;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import 'upstream_link.dart';
import 'write_translation.dart';

// --------------------------------------------------------- the status codes
//
// Named constants rather than magic numbers, because the mapping below is the
// document a future reader checks against Part 4 and a hex literal in a switch
// is not checkable.

/// `Good`. Also what an *absent* status means (Part 4), which is why a null
/// code and a zero code answer the same quality — and why the adapter still
/// keeps them apart on the way in: `0` is a positive claim, `null` is the
/// absence of one.
const int opcUaStatusCodeGood = 0x00000000;

/// The `Uncertain` band's high bit.
const int opcUaUncertainMask = 0x40000000;

/// The `Bad` band's high bit.
const int opcUaBadMask = 0x80000000;

/// The tag is not in the address space at all.
const int opcUaBadNodeIdUnknown = 0x80340000;

/// The node id was syntactically refused.
const int opcUaBadNodeIdInvalid = 0x80330000;

/// The attribute does not exist on that node.
const int opcUaBadAttributeIdInvalid = 0x80350000;

/// The value does not fit the node's data type.
const int opcUaBadTypeMismatch = 0x80740000;

/// The link itself failed.
const int opcUaBadCommunicationError = 0x80050000;

/// The session or its channel is gone.
const int opcUaBadSessionIdInvalid = 0x80250000;

/// A read callback on the server threw. The fixture produces this one, and so
/// does a real PLC with an unhappy data source.
const int opcUaBadInternalError = 0x80020000;

/// The server is serving the last value it had, and says so.
const int opcUaUncertainLastUsableValue = 0x40900000;

/// Maps an OPC UA `StatusCode` onto the relay quality an operator reads.
///
/// The table is 08-RESEARCH §C.4's, and the reason it is a table rather than a
/// band check is that the two bad answers mean opposite things to the person
/// standing next to the machine:
///
/// | StatusCode | Quality | Why |
/// |---|---|---|
/// | absent, or `Good` (0) | [Quality.good] | An absent status means Good (Part 4) |
/// | `BadNodeIdUnknown` (0x80340000) | [Quality.errorConfig] | The tag left the address space. **Waiting will not fix it** |
/// | `BadNodeIdInvalid` (0x80330000) | [Quality.errorConfig] | Same: the configuration names a node this server does not have |
/// | `BadAttributeIdInvalid` (0x80350000) | [Quality.errorConfig] | Same, one level down |
/// | `BadTypeMismatch` (0x80740000) | [Quality.errorTypeMismatch] | The mapping and the PLC disagree about the type |
/// | any other `Bad` (0x8…) | [Quality.badCommFault] | Something went wrong on the link and waiting **might** fix it |
/// | any `Uncertain` (0x4…) | [Quality.uncertainLastKnown] | A number, openly labelled as not vouched for |
///
/// The default for an unrecognised `Bad` is deliberately the *transient* one.
/// Guessing `errorConfig` for a code this table does not name tells an operator
/// to stop waiting for something that may be seconds away from coming back,
/// and that is the more expensive of the two mistakes.
Quality qualityForOpcUaStatus(int? code) {
  if (code == null || code == opcUaStatusCodeGood) return Quality.good;
  switch (code) {
    case opcUaBadNodeIdUnknown:
    case opcUaBadNodeIdInvalid:
    case opcUaBadAttributeIdInvalid:
      return Quality.errorConfig;
    case opcUaBadTypeMismatch:
      return Quality.errorTypeMismatch;
  }
  if (code & opcUaBadMask != 0) return Quality.badCommFault;
  if (code & opcUaUncertainMask != 0) return Quality.uncertainLastKnown;
  // Everything below 0x40000000 is the Good band with sub-codes.
  return Quality.good;
}

/// The same table, read out of a formatted error string.
///
/// The binding's `read`/`connect` failures arrive as text — and under
/// `useIsolate: true` they arrive as text *by construction*, because
/// `isolate.dart` marshals every error across the port as `e.toString()`
/// (08-01's finding, the same one that made the write path's numeric code a
/// non-contained change). So the string branch is not a fallback for sloppy
/// servers; it is the only branch the isolate path can take, and 08-06's
/// `WriteErrorText` exists for the same reason on the write side.
Quality qualityForOpcUaErrorText(String text) {
  if (text.contains('BadNodeIdUnknown') || text.contains('BadNodeIdInvalid')) {
    return Quality.errorConfig;
  }
  if (text.contains('BadAttributeIdInvalid')) return Quality.errorConfig;
  if (text.contains('BadTypeMismatch')) return Quality.errorTypeMismatch;
  return Quality.badCommFault;
}

/// `EffectiveDeviceStatus` → the five wire states.
///
/// The one distinction worth keeping, and the reason this is a named function
/// with its own test: **connected-but-the-subscription-is-dead is
/// [UpstreamLinkState.unhealthy], not [UpstreamLinkState.connected]**. That is
/// the frozen-session shape (`state_man.dart:820-825`), it is F27's shape, and
/// Phase 9 will want it. Collapsing it into `connected` puts a green badge on
/// a screen full of values nobody has measured for fifteen seconds.
///
/// [UpstreamLinkState.reprogrammed] is not produced here: it is an epoch fact,
/// not a session fact, and 08-08 owns it.
UpstreamLinkState mapEffectiveStatus(EffectiveDeviceStatus status) {
  switch (status) {
    case EffectiveDeviceStatus.disconnected:
      return UpstreamLinkState.disconnected;
    case EffectiveDeviceStatus.connecting:
      return UpstreamLinkState.connecting;
    case EffectiveDeviceStatus.connected:
      return UpstreamLinkState.connected;
    case EffectiveDeviceStatus.opcuaUnhealthy:
    case EffectiveDeviceStatus.umasUnhealthy:
      return UpstreamLinkState.unhealthy;
  }
}

/// One monitored-item sample, translated.
///
/// Three facts from 08-01 shape this function and none of them are optional:
///
///  1. **Quality and source time come from the VALUE attribute only.** One
///     logical key is four monitored items — `monitor()` asks for DataType,
///     Value, Description and DisplayName — and only the VALUE attribute
///     arrives with a source timestamp. The binding already restricts the
///     recording to that attribute; this function is downstream of it and does
///     not have to re-check, but a caller that starts feeding it other
///     attributes' samples will clobber a Bad code with Good.
///  2. **A Bad sample carries no payload.** `hasValue` is clear on it, so
///     `statusCode != 0` arrives with a stale-or-null value. The value is
///     therefore dropped rather than published under a bad badge: a number
///     nobody measured, rendered greyed-out, is still a number nobody measured.
///  3. **Arrival is not freshness.** A sample arriving says something reached
///     the socket; [DynamicValue.quality] is what says whether it is worth
///     reading.
///
/// When the server sends no source timestamp, [arrivedAt] is used and
/// [onSourceTimeFallback] is called — a counter or a one-time log, **not
/// silence** — and the quality is deliberately **not** degraded for it. A
/// server that omits the timestamp is not a server sending a bad reading, and
/// degrading it would make every such server permanently suspect (threat
/// T-08-25's other half).
DynamicValue translateOpcUaSample(
  ua.DynamicValue sample, {
  required DateTime arrivedAt,
  required void Function() onSourceTimeFallback,
}) {
  final quality = qualityForOpcUaStatus(sample.statusCode);
  final stamped = sample.sourceTimestamp;
  if (stamped == null) onSourceTimeFallback();
  final sourceTime = stamped ?? arrivedAt;
  final bad = quality.isBad || quality.isError;
  return DynamicValue(
    value: bad ? null : _plainValueOf(sample),
    quality: quality,
    sourceTime: sourceTime,
  );
}

/// The payload of a binding value, as something the relay's sanitizing
/// constructor will accept.
///
/// Structs and arrays are handed over as-is and `DynamicValue`'s own
/// normalisation does the rest — including the depth bound, whose refusal is
/// the standing "one tag, never a poll cycle" constraint.
Object? _plainValueOf(ua.DynamicValue sample) {
  final raw = sample.value;
  if (raw is ua.DynamicValue) return _plainValueOf(raw);
  if (raw is List) {
    return <Object?>[
      for (final element in raw)
        element is ua.DynamicValue ? _plainValueOf(element) : element,
    ];
  }
  if (raw is Map) {
    return <String, Object?>{
      for (final entry in raw.entries)
        '${entry.key}': entry.value is ua.DynamicValue
            ? _plainValueOf(entry.value as ua.DynamicValue)
            : entry.value,
    };
  }
  return raw;
}

/// One configured OPC UA server, behind the gateway's uniform surface.
final class OpcUaUpstreamLink implements UpstreamLink {
  OpcUaUpstreamLink({
    required this.alias,
    required String endpoint,
    this.useIsolate = true,
    this.supportsWrites = true,
    this.supportsBrowse = true,
    this.staleAfter = const Duration(seconds: 10),
    Duration publishingInterval = const Duration(milliseconds: 100),
    Duration iteratePeriod = const Duration(milliseconds: 10),
    ua.ClientApi? client,
    void Function(Object error, StackTrace stack)? onIterateError,
  })  : _endpoint = endpoint,
        _iteratePeriod = iteratePeriod,
        _injectedClient = client,
        _onIterateError = onIterateError {
    _config = OpcUAConfig()
      ..endpoint = endpoint
      ..serverAlias = alias
      ..publishingIntervalMs = publishingInterval.inMilliseconds;
  }

  @override
  final String alias;

  @override
  final bool supportsWrites;

  @override
  final bool supportsBrowse;

  /// The freshness deadline this link declares, for 08-05's sweep.
  final Duration staleAfter;

  /// See the library doc: assumption A5, recorded and not decided.
  final bool useIsolate;

  final String _endpoint;
  final Duration _iteratePeriod;
  final ua.ClientApi? _injectedClient;
  final void Function(Object error, StackTrace stack)? _onIterateError;

  late final OpcUAConfig _config;

  ua.ClientApi? _client;
  ClientWrapper? _wrapper;
  int? _subscriptionId;

  /// The iterate driver. **One periodic timer, owned by this class**, started
  /// on connect and cancelled on dispose — allow-listed in `freeze_test.dart`
  /// by name in the commit that created it.
  Timer? _iterateTimer;

  /// Re-entrancy guard for the driver.
  ///
  /// `Client.runIterate` is a blocking FFI call and `ClientIsolate.runIterate`
  /// is a long-lived await; either way a second tick arriving while the first
  /// has not returned must not start a second loop.
  bool _iterating = false;

  /// How many times the driver has turned the crank. Diagnostics, and the
  /// thing a test reads to know the loop is running at all.
  int _iterateTicks = 0;

  /// Errors the driver saw, in order. **The seam that replaces the bare
  /// `Logger()`** at `state_man.dart:1364`/`:1398`: a supervised loop whose
  /// errors go nowhere a test can read is a loop that swallows the failure it
  /// was added to surface (threat T-08-27).
  final List<Object> _iterateErrors = <Object>[];

  final StreamController<UpstreamLinkState> _states =
      StreamController<UpstreamLinkState>.broadcast();
  final StreamController<String> _epochs = StreamController<String>.broadcast();
  StreamSubscription<EffectiveDeviceStatus>? _statusSub;

  UpstreamLinkState _state = UpstreamLinkState.disconnected;
  String _epoch = 'unconnected';
  int _birthCount = 0;
  DateTime? _lastDeathAt;
  String? _lastError;
  int _subscriptionsCreated = 0;
  int _sourceTimeFallbacks = 0;
  bool _disposed = false;

  /// Node ids by key, learned from the mapping entries `resolve` was handed.
  final Map<String, ua.NodeId> _nodes = <String, ua.NodeId>{};

  /// Array-element keys, and which element. 08-06's handoff: the guard belongs
  /// here, because this is the only layer that can see the `array_index`.
  final Map<String, int> _arrayIndices = <String, int>{};

  /// The last value each key delivered, for [peek].
  final Map<String, DynamicValue> _cache = <String, DynamicValue>{};

  final Map<String, _MonitoredKey> _monitors = <String, _MonitoredKey>{};

  // ------------------------------------------------------------ diagnostics

  /// Driver ticks so far.
  int get iterateTicks => _iterateTicks;

  /// Everything the driver's supervisor caught.
  List<Object> get iterateErrors => List<Object>.unmodifiable(_iterateErrors);

  /// How many samples arrived with no source timestamp of their own.
  ///
  /// The recorded fact behind [translateOpcUaSample]'s fallback: a gateway
  /// silently substituting arrival time for source time is exactly threat
  /// T-08-25, and the difference between a mitigation and a hope is that this
  /// number exists.
  int get sourceTimeFallbacks => _sourceTimeFallbacks;

  // ------------------------------------------------------------- the surface

  @override
  UpstreamLinkState get state {
    final wrapper = _wrapper;
    if (wrapper == null) return _state;
    return mapEffectiveStatus(wrapper.effectiveStatus);
  }

  @override
  Stream<UpstreamLinkState> get stateStream => _states.stream;

  @override
  String? get lastError => redactUpstreamError(_lastError);

  @override
  String get epoch => _epoch;

  @override
  Stream<String> get epochStream => _epochs.stream;

  @override
  int get birthCount => _birthCount;

  @override
  DateTime? get lastDeathAt => _lastDeathAt;

  @override
  int get upstreamSubscriptionsCreated => _subscriptionsCreated;

  @override
  UpstreamRef? resolve(String key, Object mappingEntry) {
    if (mappingEntry is! KeyMappingEntry) return null;
    final node = mappingEntry.opcuaNode;
    if (node == null) return null;
    // **The adapter checks its own alias.** 08-04's handoff, in one line: the
    // router does not filter candidates by `server_alias`, it offers the key to
    // every link in order and takes the first claim. A resolve that claims
    // anything OPC-UA-shaped takes ST201's key on a two-PLC plant, and the
    // router's ambiguity check does not catch it because the two links have
    // different aliases. `_resolveM2400Key` (`state_man.dart:1774-1783`) and
    // `_resolveModbusDeviceClient` (`:1787-1799`) both do this and this is why.
    if (StateManConfig.normalizeAlias(node.serverAlias) !=
        StateManConfig.normalizeAlias(alias)) {
      return null;
    }
    final (nodeId, arrayIndex) = node.toNodeId();
    _nodes[key] = nodeId;
    if (arrayIndex != null) {
      _arrayIndices[key] = arrayIndex;
    } else {
      _arrayIndices.remove(key);
    }
    return UpstreamRef(
        alias: alias, epoch: _epoch, payload: nodeId, key: key);
  }

  /// Whether [ref] still addresses something this link vouches for.
  bool _isLive(UpstreamRef ref) =>
      ref.alias == alias && ref.epoch == _epoch && _nodes.containsKey(ref.key);

  @override
  DynamicValue? peek(UpstreamRef ref) => _isLive(ref) ? _cache[ref.key] : null;

  @override
  Stream<DynamicValue> subscribe(UpstreamRef ref) {
    if (!_isLive(ref)) {
      // A bad-quality value, and the stream stays OPEN. An ended stream is
      // indistinguishable to a widget from a key that stopped changing —
      // `AutoDisposingStream`'s close-on-source-end (`state_man.dart:2691`) is
      // on the do-not-inherit list.
      final controller = StreamController<DynamicValue>();
      controller.add(DynamicValue(
          value: null,
          quality: Quality.badCommFault,
          sourceTime: DateTime.now().toUtc()));
      return controller.stream;
    }
    final existing = _monitors[ref.key];
    if (existing != null) return existing.controller.stream;
    final monitored = _MonitoredKey(ref.key);
    _monitors[ref.key] = monitored;
    _subscriptionsCreated++;
    unawaited(_establish(monitored).then<void>((_) {}, onError: (Object e, StackTrace s) {
      // `state_man.dart:2369`'s discipline, not just its shape: a
      // fire-and-forget future that can error gets a handler, or the zone
      // does.
      _recordError(e);
      monitored.controller.add(DynamicValue(
          value: null,
          quality: qualityForOpcUaErrorText(e.toString()),
          sourceTime: DateTime.now().toUtc()));
    }));
    return monitored.controller.stream;
  }

  Future<void> _establish(_MonitoredKey monitored) async {
    final client = _client;
    final subscriptionId = _subscriptionId;
    if (client == null || subscriptionId == null) {
      throw StateError('$alias: subscribe before connect');
    }
    final nodeId = _nodes[monitored.key]!;
    // **The opt-in delivery flag, and the reason this adapter and not
    // ClientWrapper owns the monitor call.** At the binding's default a sample
    // the server marked Bad is DROPPED and its code survives only as English on
    // the error channel — which means a key whose PLC has gone unhappy simply
    // stops updating, and the panel holds the last plausible number. 08-01
    // added `deliverBadStatus` for exactly this, and `false` is what the app
    // wants while `true` is what a gateway minting qualities wants.
    monitored.subscription = client
        .monitor(nodeId, subscriptionId,
            samplingInterval: _config.publishingInterval,
            deliverBadStatus: true)
        .listen(
      (sample) {
        final translated = translateOpcUaSample(
          sample,
          arrivedAt: DateTime.now().toUtc(),
          onSourceTimeFallback: () => _sourceTimeFallbacks++,
        );
        _cache[monitored.key] = translated;
        if (!monitored.controller.isClosed) {
          monitored.controller.add(translated);
        }
      },
      onError: (Object error) {
        _recordError(error);
        final degraded = DynamicValue(
            value: null,
            quality: qualityForOpcUaErrorText(error.toString()),
            sourceTime: DateTime.now().toUtc());
        _cache[monitored.key] = degraded;
        if (!monitored.controller.isClosed) monitored.controller.add(degraded);
      },
    );
  }

  @override
  Future<DynamicValue> read(UpstreamRef ref,
      {required Duration deadline}) async {
    if (!_isLive(ref)) {
      // SRV-07: no stale-handle read ever returns a value. The handle
      // addresses a node that may now mean a different tag, and answering from
      // it is not a stale read but a confidently wrong one.
      return DynamicValue(
          value: null,
          quality: Quality.badCommFault,
          sourceTime: DateTime.now().toUtc());
    }
    final client = _client;
    if (client == null) {
      return DynamicValue(
          value: null,
          quality: Quality.badCommFault,
          sourceTime: DateTime.now().toUtc());
    }
    try {
      // The deadline is the whole reason this is an adapter and not a direct
      // call: `state_man.dart:1868` awaits `client.awaitConnect()` inside its
      // read with no bound, and a disconnected PLC pends that caller forever
      // (T-08-10). `ClientWrapper` does not bound it either, so the bound is
      // applied here rather than by editing tfc_dart.
      final sample = await client.read(_nodes[ref.key]!).timeout(deadline);
      final translated = translateOpcUaSample(
        sample,
        arrivedAt: DateTime.now().toUtc(),
        onSourceTimeFallback: () => _sourceTimeFallbacks++,
      );
      _cache[ref.key] = translated;
      return translated;
    } on TimeoutException {
      return DynamicValue(
          value: null,
          quality: Quality.badCommFault,
          sourceTime: DateTime.now().toUtc());
    } catch (error) {
      _recordError(error);
      return DynamicValue(
          value: null,
          quality: qualityForOpcUaErrorText(error.toString()),
          sourceTime: DateTime.now().toUtc());
    }
  }

  @override
  Future<WriteResult> write(
    UpstreamRef ref,
    DynamicValue value, {
    required String cmd,
    required Duration deadline,
  }) async {
    if (!supportsWrites) {
      return WriteRejected(cmd, notWritableReason,
          at: DateTime.now().millisecondsSinceEpoch);
    }
    if (!_isLive(ref)) {
      // A stale-handle write is REJECTED, not unknown: nothing was sent, so it
      // is definitively no effect (08-03's ruling, and what the fake does).
      return WriteRejected(
        cmd,
        const WriteReason('stale_handle',
            message: 'this handle was resolved before the link changed '
                'identity; re-resolve the key and try again'),
        at: DateTime.now().millisecondsSinceEpoch,
      );
    }
    // 08-06's handoff: `guardArrayElementWrite` had no caller because the
    // router does not surface the mapping entry. This adapter resolved the ref
    // from that entry, so it is the layer that can see the `array_index`, and
    // the refusal happens before anything is sent.
    if (_arrayIndices.containsKey(ref.key)) {
      final refusal = guardArrayElementWrite(cmd: cmd, hasExpect: false);
      if (refusal != null) return refusal;
    }
    final client = _client;
    if (client == null) {
      return translateWriteAnswer(
          protocol: UpstreamProtocol.opcUa,
          cmd: cmd,
          answer: const WriteDeadlineExpired(requestSent: false));
    }
    // ONE crossing into the plant, and no retry shape anywhere near it. The
    // three-state outcome is what makes a re-send the operator's decision, and
    // readback is the only confirmation.
    WriteAnswer answer;
    try {
      await client.write(_nodes[ref.key]!, _toBindingValue(value)).timeout(deadline);
      answer = WriteAcknowledged(at: DateTime.now().millisecondsSinceEpoch);
    } on TimeoutException {
      answer = const WriteDeadlineExpired();
    } catch (error) {
      _recordError(error);
      // 08-01's finding: the binding completes a failed write with a formatted
      // String, and under `useIsolate: true` a typed exception would be
      // flattened to one anyway. So the string branch is what this path feeds,
      // exactly as 08-06 planned for.
      answer = WriteErrorText(error.toString());
    }
    return translateWriteAnswer(
        protocol: UpstreamProtocol.opcUa, cmd: cmd, answer: answer);
  }

  /// The relay's value, as something the binding will serialise.
  ///
  /// **An `int` carries no deducible OPC UA type** — the binding throws
  /// `'Unable to auto deduce type'` rather than guessing between Int16, Int32,
  /// Int64 and the unsigned family (`opcua_serializer.dart:334`), and it is
  /// right to. Int32 is the assumption this adapter makes, and it is written
  /// down here rather than buried: a plant tag that is genuinely Int16 or a
  /// UInt32 needs the type in its keymapping entry, which is a mapping-model
  /// change and therefore not this plan's. Until then a write of the wrong
  /// width comes back as `BadTypeMismatch` from the server — a named refusal,
  /// which is the safe way for this assumption to be wrong.
  ua.DynamicValue _toBindingValue(DynamicValue value) => ua.DynamicValue(
        value: value.value,
        typeId: value.value is int ? ua.NodeId.int32 : null,
      );

  @override
  Future<void> connect({required Duration deadline}) async {
    if (_disposed) throw StateError('$alias: connect after dispose');
    final client = _injectedClient ??
        (useIsolate
            ? await ua.ClientIsolate.create(
                logLevel: ua.LogLevel.UA_LOGLEVEL_ERROR)
            : ua.Client(logLevel: ua.LogLevel.UA_LOGLEVEL_ERROR));
    _client = client;
    final wrapper = ClientWrapper(client, _config);
    _wrapper = wrapper;
    _statusSub = wrapper.effectiveStatusStream.listen(_onEffectiveStatus);
    client.stateStream.listen(wrapper.updateConnectionStatus);
    _setState(UpstreamLinkState.connecting);
    // The driver first: `connect` does not complete until the session is
    // activated, and the session cannot activate unless somebody is turning
    // the crank.
    _startIterate();
    await client.connect(_endpoint).timeout(deadline);
    _subscriptionId = await client
        .subscriptionCreate(
            requestedPublishingInterval: _config.publishingInterval,
            requestedMaxKeepAliveCount: 30)
        .timeout(deadline);
    // The heartbeat is `ClientWrapper`'s, and it is the reason this class
    // wraps rather than rebuilds: a session that dies quietly still ages out
    // of `connected` because a clock says so, not because an event arrived.
    wrapper.startHeartbeat(_subscriptionId!);
    _epoch = 'session:${DateTime.now().microsecondsSinceEpoch}';
    // **`connect` returning is deliberately NOT the same as being connected.**
    // The state comes from `ClientWrapper.effectiveStatus` and nowhere else,
    // and until the first heartbeat tick that is `connecting` — a live session
    // whose data plane has not been observed to work yet. Forcing `connected`
    // here would put a green badge on a link before anything had arrived from
    // it, which is the frozen-session failure with a head start. It is
    // measured: this line used to be `_setState(connected)` and the first
    // assertion written against it read `connecting`.
  }

  void _onEffectiveStatus(EffectiveDeviceStatus status) =>
      _setState(mapEffectiveStatus(status));

  void _setState(UpstreamLinkState next) {
    if (_state == next) return;
    if (next == UpstreamLinkState.connected) _birthCount++;
    if (next == UpstreamLinkState.disconnected ||
        next == UpstreamLinkState.unhealthy) {
      _lastDeathAt = DateTime.now().toUtc();
    }
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _recordError(Object error) {
    _lastError = error.toString();
    _wrapper?.recordError(_lastError!);
  }

  /// **The supervised iterate loop.**
  ///
  /// One `Timer.periodic` owned by this class, started on connect and cancelled
  /// on dispose, with its errors going to [_iterateErrors] and to the injected
  /// callback. The shape it replaces is `state_man.dart:1364`/`:1398`: two
  /// unawaited `() async {…}()` loops per client, logging to a bare `Logger()`,
  /// with nothing that can be read from a test and nothing that stops.
  void _startIterate() {
    _iterateTimer ??= Timer.periodic(_iteratePeriod, (_) => _pump());
  }

  void _pump() {
    if (_iterating || _disposed) return;
    final client = _client;
    if (client == null) return;
    _iterating = true;
    _iterateTicks++;
    if (client is ua.Client) {
      try {
        client.runIterate(_iteratePeriod);
      } catch (error, stack) {
        _superviseIterate(error, stack);
      } finally {
        _iterating = false;
      }
      return;
    }
    if (client is ua.ClientIsolate) {
      unawaited(client.runIterate(duration: _iteratePeriod).then<void>(
        (_) => _iterating = false,
        onError: (Object error, StackTrace stack) {
          _iterating = false;
          _superviseIterate(error, stack);
        },
      ));
      return;
    }
    // An injected fake: nothing to iterate.
    _iterating = false;
  }

  void _superviseIterate(Object error, StackTrace stack) {
    _iterateErrors.add(error);
    _recordError(error);
    _onIterateError?.call(error, stack);
  }

  /// Forces a new epoch, for the cases that need a stale handle without a PLC
  /// download.
  ///
  /// 08-08 replaces this with the real multi-input epoch (`StartTime` + a
  /// `NamespaceArray` hash + an optional build stamp); until then the epoch is
  /// per-session and this is how a test reaches it. Named `debug` so it reads
  /// as what it is.
  void debugBumpEpoch() {
    _epoch = 'session:${DateTime.now().microsecondsSinceEpoch}:bumped';
    if (!_epochs.isClosed) _epochs.add(_epoch);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // The driver first, for the fixture's reason in reverse: a `runIterate`
    // racing a client `delete()` is native work against freed memory. No
    // `.timeout` anywhere on this path (project memory: a dispose that gives
    // up half way leaves the thing it was disposing in a state nobody owns).
    _iterateTimer?.cancel();
    _iterateTimer = null;
    for (final monitored in _monitors.values) {
      await monitored.subscription?.cancel();
      await monitored.controller.close();
    }
    _monitors.clear();
    await _statusSub?.cancel();
    _wrapper?.dispose();
    final client = _client;
    _client = null;
    if (client != null && _injectedClient == null) {
      await client.delete();
    }
    if (!_states.isClosed) await _states.close();
    if (!_epochs.isClosed) await _epochs.close();
  }
}

/// One key's monitored item and the controller its values reach.
final class _MonitoredKey {
  _MonitoredKey(this.key);

  final String key;
  final StreamController<DynamicValue> controller =
      StreamController<DynamicValue>.broadcast();
  StreamSubscription<ua.DynamicValue>? subscription;
}
