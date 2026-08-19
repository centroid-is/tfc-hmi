import 'dart:async';
import 'dart:io' as io;

import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    show ServerAliasProvider, StateReader;

/// [StateReader] implementation backed by the Flutter app's [StateMan].
///
/// Subscribes to each key in [StateMan.keyMappings] and caches values
/// for synchronous access by the MCP server's tag tools. This bridges
/// live OPC UA / M2400 data into the in-process MCP server.
///
/// Usage:
/// ```dart
/// final reader = StateManStateReader(stateMan);
/// await reader.init(); // subscribes to all keys
/// reader.getValue('pump1.speed'); // synchronous cached access
/// reader.dispose(); // cancel all subscriptions
/// ```
class StateManStateReader implements StateReader, ServerAliasProvider {
  final StateMan? _stateMan;
  final Map<String, dynamic> _cache = {};
  final List<StreamSubscription<DynamicValue>> _subscriptions = [];

  /// Keys available from this reader.
  ///
  /// In production, sourced from [StateMan.keyMappings.nodes.keys].
  /// In test mode, provided directly via [forTest].
  final List<String> _keys;

  /// Test-only streams for subscription simulation.
  final Map<String, Stream<DynamicValue>> _testStreams;

  /// Test-only stand-in for [StateMan.subscribe].
  ///
  /// When supplied, [init] awaits this instead of reading [_testStreams],
  /// which lets a test exercise the *awaiting* half of a subscription --
  /// including one that never resolves.
  final Future<Stream<DynamicValue>> Function(String key)? _testSubscribe;

  /// How long a single [StateMan.subscribe] may take before the key is
  /// abandoned.
  ///
  /// A key whose mapping names no server -- or names one that is not
  /// configured -- can leave `subscribe` pending forever rather than
  /// throwing. Without a deadline that one key would stall the whole
  /// warm-up and leave every later key permanently null.
  final Duration subscribeTimeout;

  /// Default deadline for a single subscription.
  static const defaultSubscribeTimeout = Duration(seconds: 15);

  /// How many keys are subscribed concurrently.
  ///
  /// Bounded so a large mapping (>1500 keys in a full plant config) does not
  /// open every subscription against the OPC UA clients at once.
  static const subscribeConcurrency = 32;

  /// Creates a [StateManStateReader] backed by the given [StateMan].
  StateManStateReader(StateMan stateMan,
      {this.subscribeTimeout = defaultSubscribeTimeout})
      : _stateMan = stateMan,
        _keys = stateMan.keyMappings.nodes.keys.toList(),
        _testStreams = const {},
        _testSubscribe = null;

  /// Creates a [StateManStateReader] for unit testing without a real [StateMan].
  ///
  /// Accepts a list of keys and a map of streams to simulate subscriptions.
  /// This avoids the need for a real OPC UA / FFI-backed StateMan instance.
  ///
  /// Pass [subscribe] instead of [streams] to simulate the await on
  /// `StateMan.subscribe` itself -- e.g. a key that never resolves.
  StateManStateReader.forTest({
    required List<String> keys,
    Map<String, Stream<DynamicValue>> streams = const {},
    Future<Stream<DynamicValue>> Function(String key)? subscribe,
    this.subscribeTimeout = defaultSubscribeTimeout,
  })  : _stateMan = null,
        _keys = keys,
        _testStreams = streams,
        _testSubscribe = subscribe;

  /// Subscribes to each key and populates the value cache.
  ///
  /// Each subscription converts [DynamicValue] to a plain Dart value
  /// (int, double, bool, String, or null) via the `.value` property
  /// and stores it in the cache for synchronous access.
  ///
  /// Keys that fail to subscribe (e.g., OPC UA disconnected) or that do not
  /// resolve within [subscribeTimeout] are skipped -- they will return null
  /// from [getValue], but they no longer hold up the remaining keys.
  Future<void> init() async {
    for (var i = 0; i < _keys.length; i += subscribeConcurrency) {
      final batch = _keys.skip(i).take(subscribeConcurrency);
      await Future.wait(batch.map(_subscribeKey));
    }
  }

  /// Subscribes a single key and wires its stream into [_cache].
  ///
  /// Never throws: subscription failures are logged and the key is left
  /// uncached.
  Future<void> _subscribeKey(String key) async {
    try {
      Stream<DynamicValue> stream;
      if (_stateMan == null) {
        // Test mode: await the injected subscriber, else use provided streams
        if (_testSubscribe != null) {
          stream = await _testSubscribe(key).timeout(subscribeTimeout);
        } else if (_testStreams.containsKey(key)) {
          stream = _testStreams[key]!;
        } else {
          return;
        }
      } else {
        stream = await _stateMan.subscribe(key).timeout(subscribeTimeout);
      }

      final sub = stream.listen(
        (dynamicValue) {
          try {
            _cache[key] = _extractValue(dynamicValue);
          } catch (e) {
            _cache[key] = dynamicValue.toString();
          }
        },
        onError: (error) {
          io.stderr.writeln(
              'StateManStateReader: subscription error for key "$key": $error');
        },
      );
      _subscriptions.add(sub);
    } catch (e) {
      io.stderr.writeln(
          'StateManStateReader: failed to subscribe to key "$key": $e');
    }
  }

  /// Extract a plain Dart value from a [DynamicValue].
  ///
  /// Returns int, double, bool, String, or null for scalar types.
  /// Falls back to `.toString()` for unexpected types.
  static dynamic _extractValue(DynamicValue dv) {
    final v = dv.value;
    if (v == null) return null;
    if (v is int || v is double || v is bool || v is String) return v;
    return v.toString();
  }

  @override
  List<String> get keys => _keys;

  @override
  dynamic getValue(String key) => _cache[key];

  @override
  Map<String, dynamic> get currentValues => Map.unmodifiable(_cache);

  @override
  List<String> get serverAliases {
    if (_stateMan == null) return const [];
    return _stateMan.config.opcua
        .map((c) => c.serverAlias)
        .whereType<String>()
        .toList();
  }

  /// Cancel all stream subscriptions and clear the cache.
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _cache.clear();
  }
}
