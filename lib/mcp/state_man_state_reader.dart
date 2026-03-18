import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:tfc_dart/core/dynamic_value.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart'
    if (dart.library.js_interop) 'package:tfc_mcp_server/tfc_mcp_server_web.dart'
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

  /// Creates a [StateManStateReader] backed by the given [StateMan].
  StateManStateReader(StateMan stateMan)
      : _stateMan = stateMan,
        _keys = stateMan.keyMappings.nodes.keys.toList(),
        _testStreams = const {};

  /// Creates a [StateManStateReader] for unit testing without a real [StateMan].
  ///
  /// Accepts a list of keys and a map of streams to simulate subscriptions.
  /// This avoids the need for a real OPC UA / FFI-backed StateMan instance.
  StateManStateReader.forTest({
    required List<String> keys,
    required Map<String, Stream<DynamicValue>> streams,
  })  : _stateMan = null,
        _keys = keys,
        _testStreams = streams;

  /// Subscribes to each key and populates the value cache.
  ///
  /// Each subscription converts [DynamicValue] to a plain Dart value
  /// (int, double, bool, String, or null) via the `.value` property
  /// and stores it in the cache for synchronous access.
  ///
  /// Keys that fail to subscribe (e.g., OPC UA disconnected) are silently
  /// skipped -- they will return null from [getValue] until subscribed.
  Future<void> init() async {
    for (final key in _keys) {
      try {
        Stream<DynamicValue> stream;
        if (_stateMan == null) {
          // Test mode: use provided streams
          if (_testStreams.containsKey(key)) {
            stream = _testStreams[key]!;
          } else {
            continue;
          }
        } else {
          stream = await _stateMan.subscribe(key);
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
            debugPrint(
                'StateManStateReader: subscription error for key "$key": $error');
          },
        );
        _subscriptions.add(sub);
      } catch (e) {
        debugPrint(
            'StateManStateReader: failed to subscribe to key "$key": $e');
      }
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
