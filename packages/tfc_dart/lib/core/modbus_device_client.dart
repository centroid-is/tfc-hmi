import 'dart:async';

import 'package:logger/logger.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:modbus_client/modbus_client.dart' show ModbusEndianness;
import 'package:modbus_client_tcp/modbus_client_tcp.dart' show ModbusClientTcp;
import 'package:rxdart/rxdart.dart' show BehaviorSubject;
import 'package:tfc_dart/core/modbus_client_wrapper.dart';
import 'package:tfc_dart/core/state_man.dart'
    show
        ConnectionStatus,
        DeviceClient,
        KeyMappings,
        ModbusConfig,
        ModbusNodeConfig,
        ModbusPollGroupConfig,
        StateMan;
import 'package:tfc_dart/core/umas_client.dart';
import 'package:tfc_dart/core/umas_types.dart'
    show TypedVariableValue, UmasException, UmasVariable, UmasDataTypeRef;

/// Adapter that wraps [ModbusClientWrapper] as a [DeviceClient] for use in
/// [StateMan].
///
/// Translates between [ModbusClientWrapper]'s `Object?` value streams and the
/// [DynamicValue]-based [DeviceClient] interface. Uses [ModbusRegisterSpec]
/// metadata (not runtime type inference) to assign correct [NodeId] typeIds.
///
/// B-1/B-2 (v1.1.x): when an entry has `variableName != null` and the
/// server has `umasEnabled == true`, reads + writes route through a
/// lazily-created per-adapter [UmasClient] keyed off the symbol name
/// rather than the Modbus address. See [_getUmasClient].
class ModbusDeviceClientAdapter implements DeviceClient {
  /// The underlying Modbus transport wrapper.
  final ModbusClientWrapper wrapper;

  /// Optional alias for display/logging purposes.
  final String? serverAlias;

  /// Register specs keyed by their subscription key.
  final Map<String, ModbusRegisterSpec> _specs;

  /// UMAS variable names per key (null for keys that use classic Modbus
  /// addressing). Populated from `KeyMappingEntry.variableName` at
  /// adapter construction.
  final Map<String, String?> _variableNames;

  /// True when this adapter's server has `umasEnabled == true` in its
  /// [ModbusConfig]. Determines whether variableName-bearing keys can
  /// route by name; when false they surface as errors per B-1.
  final bool umasEnabled;

  /// Last-known typed UMAS reads, mirroring [ModbusClientWrapper]'s
  /// last-cached-value semantics for keys whose data has not yet been
  /// polled. Updated by [read]/[subscribe] when they fire successfully.
  final Map<String, DynamicValue> _umasLastValues = {};

  /// Long-lived per-key broadcast subjects for UMAS-by-name keys (F-1).
  /// [subscribe] hands out the subject's stream and the subject stays
  /// open for the lifetime of the adapter. Every successful
  /// [readUmasVariable] adds the fresh [DynamicValue] so subscribers
  /// see updates without the stream completing. Disposed in [dispose].
  final Map<String, BehaviorSubject<DynamicValue>> _umasSubjects = {};

  /// Lazy UMAS client. Re-created when the underlying
  /// [ModbusClientWrapper.client] changes (reconnect).
  UmasClient? _umasClient;
  ModbusClientTcp? _umasClientFor;

  /// B-4 (v1.1.x): per-poll-group state for batched MonitorPlc polling.
  /// All UMAS-by-name keys for this adapter share ONE MonitorPlc table
  /// on the PLC (the protocol only supports one table per session),
  /// but each poll group keeps its own [Timer.periodic] so the cadence
  /// matches the configured group interval. Each tick issues a single
  /// `monitorReadAll` and demuxes the response back into per-key
  /// [_umasSubjects] / [_umasLastValues].
  ///
  /// `_umasPollGroups`: poll-group name -> configured interval.
  /// `_umasKeysByGroup`: poll-group name -> list of UMAS-by-name keys
  ///   that opted into the group (via `KeyMappingEntry.modbusNode.pollGroup`).
  /// `_umasKeyOrder`: list of UMAS-by-name keys in MonitorPlc registration
  ///   order — populated when the table is built on a fresh UmasClient.
  ///   `monitorReadAll` returns values in sorted-index order, so the i-th
  ///   value belongs to `_umasKeyOrder[i]`.
  /// `_umasTimers`: per-group timers. Stopped on disconnect, restarted
  ///   on (re)connect after the table is rebuilt.
  /// `_umasTableBuiltFor`: the ModbusClientTcp identity the current
  ///   table was registered against — when it changes the table must
  ///   be rebuilt against the fresh UmasClient.
  final Map<String, Duration> _umasPollGroups = {};
  final Map<String, List<String>> _umasKeysByGroup = {};
  final List<String> _umasKeyOrder = [];
  final Map<String, Timer> _umasTimers = {};
  ModbusClientTcp? _umasTableBuiltFor;

  /// Guard so we don't kick off two concurrent table-build attempts when
  /// a poll tick races with the connection-state listener.
  bool _umasTableBuildInFlight = false;

  /// Subscription to [ModbusClientWrapper.connectionStream]. Drives
  /// table (re)build + timer lifecycle. Cancelled in [dispose].
  StreamSubscription<ConnectionStatus>? _umasConnectionSub;

  static final _log = Logger(printer: SimplePrinter(), level: Level.info);

  /// Default MonitorPlc-poll interval when the operator's key mapping
  /// references a poll group not present in [ModbusConfig.pollGroups].
  /// Conservative 1s default mirrors `ModbusClientWrapper._defaultPollInterval`.
  static const _defaultPollInterval = Duration(seconds: 1);

  ModbusDeviceClientAdapter(
    this.wrapper, {
    required Map<String, ModbusRegisterSpec> specs,
    this.serverAlias,
    Map<String, String?> variableNames = const {},
    this.umasEnabled = false,
    Map<String, String>? umasPollGroupByKey,
    List<ModbusPollGroupConfig>? pollGroups,
  })  : _specs = Map.unmodifiable(specs),
        _variableNames = Map.unmodifiable(variableNames) {
    _initUmasPollGroups(
      umasPollGroupByKey: umasPollGroupByKey ?? const {},
      pollGroups: pollGroups ?? const [],
    );
    _initUmasLifecycle();
  }

  /// Build the per-group key lists from the supplied per-key mapping
  /// `(key -> pollGroupName)` and the per-server pollGroup intervals.
  /// Called once at construction; the adapter is otherwise immutable.
  void _initUmasPollGroups({
    required Map<String, String> umasPollGroupByKey,
    required List<ModbusPollGroupConfig> pollGroups,
  }) {
    final groupIntervals = <String, Duration>{};
    for (final pg in pollGroups) {
      groupIntervals[pg.name] = pg.interval;
    }
    for (final entry in umasPollGroupByKey.entries) {
      final key = entry.key;
      if (_variableNames[key] == null) continue; // only UMAS-by-name
      final group = entry.value;
      _umasKeysByGroup.putIfAbsent(group, () => <String>[]).add(key);
      _umasPollGroups.putIfAbsent(
        group,
        () => groupIntervals[group] ?? _defaultPollInterval,
      );
    }
    // Keys without an explicit pollGroup mapping default to 'default'.
    for (final key in _variableNames.keys) {
      if (_variableNames[key] == null) continue;
      if (umasPollGroupByKey[key] != null) continue;
      _umasKeysByGroup.putIfAbsent('default', () => <String>[]).add(key);
      _umasPollGroups.putIfAbsent(
        'default',
        () => groupIntervals['default'] ?? _defaultPollInterval,
      );
    }
  }

  /// Wire the (re)connect → rebuild-table → start-timers chain. Cheap
  /// no-op when [umasEnabled] is false or there are no UMAS-by-name
  /// keys — keeps classic-Modbus adapters untouched.
  void _initUmasLifecycle() {
    if (!umasEnabled) return;
    if (_umasKeysByGroup.isEmpty) return;
    _umasConnectionSub = wrapper.connectionStream.listen((status) {
      if (status == ConnectionStatus.connected) {
        // Defer to a microtask so listeners don't fight `_getClientWrapper`
        // ordering on the very first connected emission.
        Future.microtask(_buildUmasTableAndStartTimers);
      } else {
        _stopUmasTimers();
        _umasTableBuiltFor = null;
      }
    });
  }

  /// Build the MonitorPlc table from `_umasKeysByGroup` and start each
  /// group's [Timer.periodic]. Safe to call repeatedly — bails when the
  /// table is already built against the current UmasClient.
  Future<void> _buildUmasTableAndStartTimers() async {
    if (_umasTableBuildInFlight) return;
    _umasTableBuildInFlight = true;
    try {
      final umas = _getUmasClient();
      if (umas == null) return;
      if (identical(_umasTableBuiltFor, _umasClientFor)) {
        // Same client identity, table is already wired. Restart timers
        // if they're not running (e.g. after a transient stream blip
        // that didn't actually drop the socket).
        _startUmasTimers();
        return;
      }
      // Fresh client — drop any stale ordering and reset the server-side
      // table so we own the index space cleanly.
      _umasKeyOrder.clear();
      try {
        await umas.monitorReset();
      } catch (e) {
        _log.w('UMAS monitorReset before rebuild failed: $e');
        // Continue anyway — registering still allocates fresh indices on
        // the client side, and the PLC will overwrite stale entries.
      }
      // Prime project block / blockCrcs so monitorRegister succeeds.
      try {
        await umas.readPlcStatus();
      } catch (e) {
        _log.w('UMAS readPlcStatus during table build failed: $e');
        return;
      }

      // Resolve every UMAS-by-name key and build the registration list
      // in a deterministic order (groups in insertion order; keys within
      // a group in insertion order). The same ordering is mirrored in
      // [_umasKeyOrder] so `monitorReadAll` results demux correctly.
      final refs = <(UmasVariable, UmasDataTypeRef)>[];
      for (final group in _umasKeysByGroup.keys) {
        for (final key in _umasKeysByGroup[group]!) {
          final symbolPath = _variableNames[key];
          if (symbolPath == null) continue;
          try {
            final sym = await umas.lookupSymbol(symbolPath);
            if (!sym.readable) {
              _log.w('UMAS key "$key" symbol "$symbolPath" is not readable — '
                  'skipping MonitorPlc registration');
              continue;
            }
            refs.add((sym.variable, sym.dataType));
            _umasKeyOrder.add(key);
          } catch (e) {
            _log.w('UMAS lookupSymbol for "$symbolPath" (key "$key") '
                'failed: $e — skipping');
          }
        }
      }

      if (refs.isEmpty) {
        _log.i('UMAS MonitorPlc table build: no resolvable symbols');
        _umasTableBuiltFor = _umasClientFor;
        return;
      }

      // Chunk to fit the 1-byte index limit (255). Each chunk is one
      // monitorRegister TCP roundtrip; the table accumulates server-side.
      const chunkSize = 100;
      for (var i = 0; i < refs.length; i += chunkSize) {
        final chunk = refs.sublist(i, (i + chunkSize).clamp(0, refs.length));
        try {
          await umas.monitorRegister(chunk);
        } catch (e) {
          _log.w('UMAS monitorRegister chunk (size=${chunk.length}) failed: $e');
          // Drop the corresponding key-order entries so demux stays aligned.
          // We registered nothing past this chunk.
          _umasKeyOrder.removeRange(i, _umasKeyOrder.length);
          break;
        }
      }
      _umasTableBuiltFor = _umasClientFor;
      _log.i('UMAS MonitorPlc table built: ${_umasKeyOrder.length} '
          'variable(s) across ${_umasKeysByGroup.length} group(s)');
      _startUmasTimers();
    } finally {
      _umasTableBuildInFlight = false;
    }
  }

  /// Start per-group poll timers. Called after [_buildUmasTableAndStartTimers]
  /// and on transient stream events. Idempotent — replaces any prior timer
  /// for a group so interval edits picked up via adapter re-creation take
  /// effect immediately.
  void _startUmasTimers() {
    for (final group in _umasPollGroups.keys) {
      _umasTimers[group]?.cancel();
      final interval = _umasPollGroups[group]!;
      _umasTimers[group] = Timer.periodic(interval, (_) {
        // Fire-and-forget; errors caught inside _pollUmasGroup.
        unawaited(_pollUmasGroup(group));
      });
    }
  }

  /// Cancel and clear all per-group poll timers.
  void _stopUmasTimers() {
    for (final t in _umasTimers.values) {
      t.cancel();
    }
    _umasTimers.clear();
  }

  /// Single poll tick for a UMAS poll group. Issues one
  /// `monitorReadAll` and demuxes the per-key values into
  /// [_umasLastValues] and [_umasSubjects].
  ///
  /// `monitorReadAll` returns values for ALL registered variables in
  /// sorted-index order — not just the calling group's keys. We could
  /// filter here, but pushing every fresh value into every subscriber's
  /// subject is exactly the semantics callers want: a fresh read on a
  /// faster group's tick benefits slower-group subscribers too. The
  /// poll-group interval only controls how often THIS group fires; it
  /// does not gate which keys receive updates.
  Future<void> _pollUmasGroup(String group) async {
    if (wrapper.connectionStatus != ConnectionStatus.connected) return;
    final umas = _getUmasClient();
    if (umas == null) return;
    if (!identical(_umasTableBuiltFor, _umasClientFor)) {
      // Client changed under us — kick off a rebuild and skip this tick.
      unawaited(_buildUmasTableAndStartTimers());
      return;
    }
    if (_umasKeyOrder.isEmpty) return;
    try {
      final values = await umas.monitorReadAll();
      _demuxUmasReadAll(values);
    } catch (e) {
      _log.w('UMAS monitorReadAll for group "$group" failed: $e');
      // Subjects retain their last value (SCADA semantics).
    }
  }

  /// Demux a [monitorReadAll] response into the per-key subjects + cache.
  /// Assumes `values` is in the same order as [_umasKeyOrder].
  void _demuxUmasReadAll(List<TypedVariableValue> values) {
    final n = values.length < _umasKeyOrder.length
        ? values.length
        : _umasKeyOrder.length;
    for (var i = 0; i < n; i++) {
      final key = _umasKeyOrder[i];
      final dv = _typedVariableToDynamicValue(values[i]);
      _umasLastValues[key] = dv;
      final subject = _umasSubjects[key];
      if (subject != null && !subject.isClosed) {
        subject.add(dv);
      }
    }
  }

  /// All keys claimed by this adapter — the union of classic-Modbus
  /// specs and UMAS-by-name keys.
  @override
  Set<String> get subscribableKeys =>
      {..._specs.keys, ..._variableNames.keys.where((k) => _variableNames[k] != null)};

  @override
  bool canSubscribe(String key) =>
      _specs.containsKey(key) ||
      (_variableNames[key] != null);

  /// Returns the UMAS variable name for [key], or null if [key] is not
  /// routed by name.
  String? variableNameFor(String key) => _variableNames[key];

  /// Get or lazily construct a UmasClient bound to the wrapper's current
  /// TCP client. Returns null if the wrapper is disconnected (no
  /// underlying ModbusClientTcp yet).
  UmasClient? _getUmasClient() {
    final tcp = wrapper.client;
    if (tcp == null) {
      // Connection torn down — drop the stale client so the next
      // successful reconnect rebuilds it against the fresh socket.
      _umasClient?.dispose();
      _umasClient = null;
      _umasClientFor = null;
      return null;
    }
    if (_umasClient != null && identical(_umasClientFor, tcp)) {
      return _umasClient;
    }
    _umasClient?.dispose();
    _umasClient = UmasClient(sendFn: tcp.send, unitId: wrapper.unitId);
    _umasClientFor = tcp;
    return _umasClient;
  }

  @override
  Stream<DynamicValue> subscribe(String key) {
    // UMAS-by-name routing (F-1): return a long-lived BehaviorSubject
    // per key so subscribers don't see `onDone` after a single emit.
    // The subject is seeded with the most-recent cached value (if any)
    // and stays open for the adapter's lifetime. Every successful
    // [readUmasVariable] pushes the fresh DynamicValue. MonitorPlc-
    // driven streaming polling is a v1.2 follow-up; see B-4 TODO at
    // the bottom of this file.
    final variableName = _variableNames[key];
    if (variableName != null) {
      return _umasSubjectFor(key).stream;
    }
    final spec = _specs[key];
    if (spec == null) throw ArgumentError('Unknown Modbus key: $key');
    return wrapper.subscribe(spec).map((v) => _toDynamicValue(v, spec));
  }

  /// Get-or-create the long-lived [BehaviorSubject] for a UMAS-by-name
  /// [key]. Seeded with the cached last value when present (so a fresh
  /// subscriber sees the most-recent typed read), otherwise unseeded.
  /// Reused across subscribe/unsubscribe cycles for the same key.
  BehaviorSubject<DynamicValue> _umasSubjectFor(String key) {
    final existing = _umasSubjects[key];
    if (existing != null && !existing.isClosed) return existing;
    final cached = _umasLastValues[key];
    final subject = cached != null
        ? BehaviorSubject<DynamicValue>.seeded(cached)
        : BehaviorSubject<DynamicValue>();
    _umasSubjects[key] = subject;
    return subject;
  }

  @override
  DynamicValue? read(String key) {
    final variableName = _variableNames[key];
    if (variableName != null) {
      // Synchronous reads return the last cached typed value; live
      // reads happen via [readUmasVariable] (await). The async fetch
      // is wired from StateMan.read() which already awaits and so can
      // call the typed path; this synchronous fallback exists for
      // [readMany] which only consults the cache.
      return _umasLastValues[key];
    }
    final spec = _specs[key];
    if (spec == null) return null;
    final raw = wrapper.read(key);
    if (raw == null) return null;
    return _toDynamicValue(raw, spec);
  }

  /// Read a single UMAS-by-name key. Throws [StateError] if [key] is
  /// not routed by name. Throws [UmasException] when the server has
  /// `umasEnabled == false` (B-1 contract) or when the underlying
  /// PLC read fails. Caches the typed result for the next [read].
  Future<DynamicValue> readUmasVariable(String key) async {
    final variableName = _variableNames[key];
    if (variableName == null) {
      throw StateError('readUmasVariable: key "$key" is not UMAS-by-name');
    }
    if (!umasEnabled) {
      throw UmasException(
        errorCode: 0,
        message: "Server '${serverAlias ?? '<unknown>'}' does not have UMAS "
            "enabled — variable name '$variableName' cannot be read",
      );
    }
    final umas = _getUmasClient();
    if (umas == null) {
      throw StateError(
          'readUmasVariable: server "${serverAlias ?? '<unknown>'}" not connected');
    }
    // Prime the session so blockCrcs is populated before readVariable.
    await umas.readPlcStatus();
    final typed = await umas.readVariableByName(variableName);
    final dv = _typedVariableToDynamicValue(typed);
    _umasLastValues[key] = dv;
    // F-1: push the fresh value to any active subscribers so
    // StreamBuilder / StreamProvider keep updating across reads. Only
    // forward when a subject already exists — don't materialize one on
    // every read.
    final subject = _umasSubjects[key];
    if (subject != null && !subject.isClosed) {
      subject.add(dv);
    }
    return dv;
  }

  /// Write a single UMAS-by-name key. Same UX contract as
  /// [readUmasVariable]: throws [UmasException] when the server has
  /// `umasEnabled == false`, [StateError] when the key is not routed by
  /// name or when the server is disconnected.
  Future<void> writeUmasVariable(String key, DynamicValue value) async {
    final variableName = _variableNames[key];
    if (variableName == null) {
      throw StateError('writeUmasVariable: key "$key" is not UMAS-by-name');
    }
    if (!umasEnabled) {
      throw UmasException(
        errorCode: 0,
        message: "Server '${serverAlias ?? '<unknown>'}' does not have UMAS "
            "enabled — variable name '$variableName' cannot be written",
      );
    }
    final umas = _getUmasClient();
    if (umas == null) {
      throw StateError(
          'writeUmasVariable: server "${serverAlias ?? '<unknown>'}" not connected');
    }
    await umas.readPlcStatus();
    // Encode via the resolved symbol so the byte layout matches the
    // PLC's declared type. `writeVariableByName` runs the encode via
    // `VariableWriteRef.fromVariable` -> `encodeVariableValue`.
    await umas.writeVariableByName(variableName, value.value);
  }

  /// Convert a TypedVariableValue from UMAS to a DynamicValue with the
  /// correct [NodeId] type id. Best-effort mapping — STRING / BYTE
  /// strings preserve their parsed Dart value. Unknown UMAS type names
  /// fall back to `NodeId.byte` because [DynamicValue] requires a
  /// non-null typeId; the raw value stays untouched so the consumer
  /// can still inspect it.
  static DynamicValue _typedVariableToDynamicValue(TypedVariableValue t) {
    final upper = t.typeName.toUpperCase();
    final typeId = switch (upper) {
      'BOOL' || 'EBOOL' => NodeId.boolean,
      'INT' => NodeId.int16,
      'UINT' || 'WORD' => NodeId.uint16,
      'DINT' || 'TIME' => NodeId.int32,
      'UDINT' || 'DWORD' => NodeId.uint32,
      'REAL' => NodeId.float,
      'LREAL' => NodeId.double,
      'LINT' => NodeId.int64,
      'ULINT' => NodeId.uint64,
      'BYTE' => NodeId.byte,
      'STRING' || 'WSTRING' || 'BYTE_STRING' => NodeId.uastring,
      _ => NodeId.byte,
    };
    return DynamicValue(value: t.value, typeId: typeId);
  }

  @override
  Future<void> write(String key, DynamicValue value) async {
    // UMAS-by-name routing takes precedence.
    if (_variableNames[key] != null) {
      await writeUmasVariable(key, value);
      return;
    }
    final spec = _specs[key];
    if (spec == null) throw ArgumentError('Unknown Modbus key: $key');

    if (spec.bitMask != null) {
      // Read-modify-write: preserve unmasked bits.
      // Note: reads the last-polled cached value, not a fresh device read.
      // A concurrent write between the last poll and this write could be
      // overwritten. Modbus has no atomic bit-set instruction, so this is
      // inherent to the protocol. The race window is bounded by poll interval.
      final current = wrapper.read(key);
      final currentInt = (current is num) ? current.toInt() : 0;
      final shift = spec.bitShift ?? 0;
      final isSingle =
          spec.bitMask! != 0 && (spec.bitMask! & (spec.bitMask! - 1)) == 0;
      int newValue;
      if (isSingle) {
        final boolVal = value.value == true || value.value == 1;
        if (boolVal) {
          newValue = currentInt | spec.bitMask!;
        } else {
          newValue = currentInt & ~spec.bitMask!;
        }
      } else {
        final writeInt =
            (value.value is num) ? (value.value as num).toInt() : 0;
        newValue =
            (currentInt & ~spec.bitMask!) | ((writeInt << shift) & spec.bitMask!);
      }
      await wrapper.write(spec, newValue);
    } else {
      await wrapper.write(spec, value.value);
    }
  }

  @override
  ConnectionStatus get connectionStatus => wrapper.connectionStatus;

  @override
  Stream<ConnectionStatus> get connectionStream => wrapper.connectionStream;

  @override
  void connect() => wrapper.connect();

  @override
  void dispose() {
    _stopUmasTimers();
    _umasConnectionSub?.cancel();
    _umasConnectionSub = null;
    _umasClient?.dispose();
    _umasClient = null;
    _umasClientFor = null;
    _umasTableBuiltFor = null;
    _umasKeyOrder.clear();
    // F-1: close every long-lived UMAS-by-name subject so subscribers
    // see `onDone` exactly once at adapter teardown rather than after
    // a single read.
    for (final subject in _umasSubjects.values) {
      if (!subject.isClosed) subject.close();
    }
    _umasSubjects.clear();
    wrapper.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Wraps a raw Modbus value in a [DynamicValue] with the correct [typeId]
  /// derived from the register spec's declared data type, then applies
  /// optional bit masking.
  static DynamicValue _toDynamicValue(Object? value, ModbusRegisterSpec spec) {
    final dv = DynamicValue(value: value, typeId: _typeIdFromDataType(spec.dataType));
    return StateMan.applyBitMask(dv, spec.bitMask, spec.bitShift);
  }

  /// Maps [ModbusDataType] to the corresponding OPC UA [NodeId] type identifier.
  static NodeId _typeIdFromDataType(ModbusDataType dataType) {
    switch (dataType) {
      case ModbusDataType.bit:
        return NodeId.boolean;
      case ModbusDataType.int16:
        return NodeId.int16;
      case ModbusDataType.uint16:
        return NodeId.uint16;
      case ModbusDataType.int32:
        return NodeId.int32;
      case ModbusDataType.uint32:
        return NodeId.uint32;
      case ModbusDataType.float32:
        return NodeId.float;
      case ModbusDataType.int64:
        return NodeId.int64;
      case ModbusDataType.uint64:
        return NodeId.uint64;
      case ModbusDataType.float64:
        return NodeId.double;
    }
  }
}

// ---------------------------------------------------------------------------
// Config-to-spec helpers (Phase 9)
// ---------------------------------------------------------------------------

/// Converts [KeyMappings] entries with a [ModbusNodeConfig] into a map of
/// [ModbusRegisterSpec] instances, filtered by [serverAlias].
///
/// Entries without a `modbusNode`, or whose `modbusNode.serverAlias` does not
/// match [serverAlias], are skipped.
///
/// The [endianness] parameter is the per-device byte order from
/// [ModbusConfig.endianness]. All specs for a given device share the same
/// endianness since byte order is a device-level property.
Map<String, ModbusRegisterSpec> buildSpecsFromKeyMappings(
  KeyMappings keyMappings,
  String? serverAlias, {
  ModbusEndianness endianness = ModbusEndianness.ABCD,
  int addressBase = 0,
}) {
  final specs = <String, ModbusRegisterSpec>{};
  for (final entry in keyMappings.nodes.entries) {
    final modbusNode = entry.value.modbusNode;
    if (modbusNode == null) continue;
    if (modbusNode.serverAlias != serverAlias) continue;
    // UMAS-by-name keys still carry a modbusNode for serverAlias/registerType
    // metadata but route through the symbol cache at runtime — the
    // ModbusRegisterSpec is built defensively so a misconfigured key
    // (umasEnabled flipped off post-pick) still has an address-space
    // fallback, but adapter routing prefers the variableName path.
    specs[entry.key] = ModbusRegisterSpec(
      key: entry.key,
      registerType: modbusNode.registerType.toModbusElementType(),
      address: modbusNode.address,
      dataType: modbusNode.dataType,
      pollGroup: modbusNode.pollGroup,
      endianness: endianness,
      addressBase: addressBase,
      bitMask: entry.value.bitMask,
      bitShift: entry.value.bitShift,
    );
  }
  return specs;
}

/// Extract `KeyMappingEntry.variableName` for every entry whose
/// `modbusNode.serverAlias` matches [serverAlias]. Returns a map of
/// `key → variableName` (only entries with a non-null variableName are
/// present). Used by [ModbusDeviceClientAdapter] to route reads/writes
/// by name when the server has UMAS enabled.
Map<String, String> buildVariableNamesFromKeyMappings(
  KeyMappings keyMappings,
  String? serverAlias,
) {
  final out = <String, String>{};
  for (final entry in keyMappings.nodes.entries) {
    final modbusNode = entry.value.modbusNode;
    if (modbusNode == null) continue;
    if (modbusNode.serverAlias != serverAlias) continue;
    final vn = entry.value.variableName;
    if (vn != null && vn.isNotEmpty) out[entry.key] = vn;
  }
  return out;
}

/// Extract `KeyMappingEntry.modbusNode.pollGroup` for every UMAS-by-name
/// key whose server alias matches [serverAlias]. Used by
/// [ModbusDeviceClientAdapter]'s B-4 batched MonitorPlc poll loop to
/// place each key into its configured group cadence.
Map<String, String> buildUmasPollGroupsFromKeyMappings(
  KeyMappings keyMappings,
  String? serverAlias,
) {
  final out = <String, String>{};
  for (final entry in keyMappings.nodes.entries) {
    final modbusNode = entry.value.modbusNode;
    if (modbusNode == null) continue;
    if (modbusNode.serverAlias != serverAlias) continue;
    final vn = entry.value.variableName;
    if (vn == null || vn.isEmpty) continue;
    out[entry.key] = modbusNode.pollGroup;
  }
  return out;
}

/// Builds Modbus [DeviceClient] instances from config and key mappings.
///
/// For each [ModbusConfig], translates key mappings into [ModbusRegisterSpec]s
/// via [buildSpecsFromKeyMappings], pre-configures poll groups from
/// [ModbusConfig.pollGroups], and creates the adapter.
///
/// This is the primary entry point for both data_acquisition_isolate and
/// the Flutter UI provider.
List<DeviceClient> buildModbusDeviceClients(
  List<ModbusConfig> modbusConfigs,
  KeyMappings keyMappings,
) {
  return modbusConfigs.map((config) {
    final specs = buildSpecsFromKeyMappings(
      keyMappings, config.serverAlias,
      endianness: config.endianness,
      addressBase: config.addressBase,
    );
    final variableNames =
        buildVariableNamesFromKeyMappings(keyMappings, config.serverAlias);
    final umasPollGroups =
        buildUmasPollGroupsFromKeyMappings(keyMappings, config.serverAlias);
    final wrapper = ModbusClientWrapper(
      config.host,
      config.port,
      config.unitId,
    );
    // Pre-configure poll groups from config BEFORE adapter creation
    for (final pg in config.pollGroups) {
      wrapper.addPollGroup(pg.name, pg.interval);
    }
    return ModbusDeviceClientAdapter(
      wrapper,
      specs: specs,
      serverAlias: config.serverAlias,
      variableNames: variableNames,
      umasEnabled: config.umasEnabled,
      umasPollGroupByKey: umasPollGroups,
      pollGroups: config.pollGroups,
    );
  }).toList();
}

// B-4 (v1.1.x): batched MonitorPlc polling for UMAS-by-name keys SHIPPED.
//
// `ModbusDeviceClientAdapter` now wires a `connectionStream` listener that,
// on every successful (re)connect, calls `monitorReset()` to clear any
// stale server-side state and then `monitorRegister(refs)` for the union
// of all UMAS-by-name keys configured for the adapter's server. A per-
// poll-group `Timer.periodic` then issues ONE `monitorReadAll()` per
// tick and demuxes the response back into the matching per-key
// `BehaviorSubject` / `_umasLastValues` entry. The MonitorPlc table is
// SHARED across all poll groups for the adapter's server (the UMAS
// protocol exposes a single registration table per session), so a faster
// group's tick incidentally refreshes all keys; the group cadence still
// controls how often each timer fires.
//
// Lifecycle:
//   - Built on the first ConnectionStatus.connected emission after the
//     UmasClient identity changes (covers cold start + every reconnect).
//   - Reset + rebuilt on UmasClient re-creation (TCP reconnect → fresh
//     ModbusClientTcp → `_getUmasClient` allocates a new UmasClient
//     against the new socket, so the server-side table is gone too).
//   - Disposed in `dispose()`.
//
// Still v1.2:
//   - F-10 (cache survival across reconnect): the symbol cache is dropped
//     on every UmasClient teardown. Would save one browse round-trip per
//     reconnect.
//   - In-place table mutation on Key Repository save: today the adapter
//     is re-created when `key_mappings` changes (the stateManProvider
//     listener invalidates and rebuilds), which transparently rebuilds
//     the table. Mutating the live table without a full adapter rebuild
//     is a possible optimisation but not required for correctness.
