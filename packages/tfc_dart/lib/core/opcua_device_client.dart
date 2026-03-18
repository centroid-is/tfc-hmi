/// OPC UA DeviceClient adapter — native-only.
///
/// Wraps open62541 [ClientApi] / [ClientIsolate] and presents the
/// protocol-agnostic [DeviceClient] interface used by [StateMan].
///
/// This file is NEVER imported on web.
import 'dart:async';
import 'dart:collection' show LinkedHashMap;
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:meta/meta.dart';
import 'package:open62541/open62541.dart' as opcua;
import 'package:rxdart/rxdart.dart';

import 'dynamic_value.dart' as tfc;
import 'state_man.dart';

// ---------------------------------------------------------------------------
// Conversion helpers: open62541.DynamicValue ↔ tfc_dart.DynamicValue
// ---------------------------------------------------------------------------

/// Convert an open62541 [DynamicValue] to a tfc_dart [DynamicValue].
tfc.DynamicValue fromOpcUaDynamicValue(opcua.DynamicValue ov) {
  if (ov.isNull) return tfc.DynamicValue();
  if (ov.isObject) {
    final map = <String, dynamic>{};
    for (final entry in ov.asObject.entries) {
      map[entry.key] = fromOpcUaDynamicValue(entry.value);
    }
    return tfc.DynamicValue.fromMap(Map<String, dynamic>.from(map));
  }
  if (ov.isArray) {
    return tfc.DynamicValue.fromList(
      ov.asArray.map(fromOpcUaDynamicValue).toList(),
      typeId: ov.typeId != null ? fromOpcUaNodeId(ov.typeId!) : null,
    );
  }
  final result = tfc.DynamicValue(
    value: ov.value,
    typeId: ov.typeId != null ? fromOpcUaNodeId(ov.typeId!) : null,
    name: ov.name,
  );
  if (ov.displayName != null) {
    result.displayName =
        tfc.LocalizedText(ov.displayName!.value, ov.displayName!.locale);
  }
  if (ov.description != null) {
    result.description =
        tfc.LocalizedText(ov.description!.value, ov.description!.locale);
  }
  if (ov.enumFields != null) {
    result.enumFields = ov.enumFields!.map(
      (k, v) => MapEntry(
        k,
        tfc.EnumField(
          v.value,
          v.name,
          tfc.LocalizedText(v.displayName.value, v.displayName.locale),
          tfc.LocalizedText(v.description.value, v.description.locale),
        ),
      ),
    );
  }
  return result;
}

/// Convert a tfc_dart [DynamicValue] to an open62541 [DynamicValue].
opcua.DynamicValue toOpcUaDynamicValue(tfc.DynamicValue tv) {
  if (tv.isNull) return opcua.DynamicValue();
  if (tv.isObject) {
    final map = <String, dynamic>{};
    for (final entry in tv.asObject.entries) {
      map[entry.key] = toOpcUaDynamicValue(entry.value);
    }
    return opcua.DynamicValue.fromMap(LinkedHashMap<String, dynamic>.from(map));
  }
  if (tv.isArray) {
    return opcua.DynamicValue.fromList(
      tv.asArray.map(toOpcUaDynamicValue).toList(),
      typeId: tv.typeId != null ? toOpcUaNodeId(tv.typeId!) : null,
    );
  }
  return opcua.DynamicValue(
    value: tv.value,
    typeId: tv.typeId != null ? toOpcUaNodeId(tv.typeId!) : null,
  );
}

/// Convert an open62541 [NodeId] to a tfc_dart [NodeId].
tfc.NodeId fromOpcUaNodeId(opcua.NodeId n) {
  if (n.isString()) return tfc.NodeId.fromString(n.namespace, n.string);
  return tfc.NodeId.fromNumeric(n.namespace, n.numeric);
}

/// Convert a tfc_dart [NodeId] to an open62541 [NodeId].
opcua.NodeId toOpcUaNodeId(tfc.NodeId n) {
  if (n.isString()) return opcua.NodeId.fromString(n.namespace, n.string);
  return opcua.NodeId.fromNumeric(n.namespace, n.numeric);
}

// ---------------------------------------------------------------------------
// ClientWrapper — manages a single OPC UA client connection
// ---------------------------------------------------------------------------

class ClientWrapper {
  final opcua.ClientApi client;
  final OpcUAConfig config;
  int? subscriptionId;
  final SingleWorker worker = SingleWorker();
  StreamSubscription? _heartbeatSub;
  int _heartbeatGeneration = 0;
  DateTime? _lastHeartbeatTick;
  bool _inactive = false;
  bool sessionLost = false;
  bool resendOnRecovery;
  final Set<AutoDisposingStream> streams = {};
  final Logger _logger = Logger();

  static bool isSubscriptionDead(Object error) {
    if (error is opcua.SubscriptionDeleted || error is opcua.SecureChannelClosed) {
      return true;
    }
    if (error is String) {
      return error.contains('SubscriptionDeleted') ||
          error.contains('SecureChannelClosed');
    }
    return false;
  }

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final StreamController<ConnectionStatus> _connectionController =
      StreamController<ConnectionStatus>.broadcast();

  ClientWrapper(this.client, this.config, {this.resendOnRecovery = true});

  ConnectionStatus get connectionStatus => _connectionStatus;
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;

  void updateConnectionStatus(opcua.ClientState state) {
    final next = _mapState(state);
    if (next == _connectionStatus) return;
    _connectionStatus = next;
    _connectionController.add(next);
  }

  static ConnectionStatus _mapState(opcua.ClientState state) {
    if (state.sessionState == opcua.SessionState.UA_SESSIONSTATE_ACTIVATED) {
      return ConnectionStatus.connected;
    }
    if (state.channelState ==
        opcua.SecureChannelState.UA_SECURECHANNELSTATE_OPEN) {
      return ConnectionStatus.connecting;
    }
    return ConnectionStatus.disconnected;
  }

  void startHeartbeat(int subId) {
    _heartbeatSub?.cancel();
    final serverTimeNode = opcua.NodeId.fromNumeric(0, 2258);
    final gen = ++_heartbeatGeneration;
    _logger.i('[${config.endpoint}] Starting heartbeat on sub=$subId');
    _heartbeatSub = client.monitoredItems(
      {
        serverTimeNode: [opcua.AttributeId.UA_ATTRIBUTEID_VALUE]
      },
      subId,
    ).listen(
      (_) {
        if (gen != _heartbeatGeneration) return;
        _lastHeartbeatTick = DateTime.now();
        if (_inactive) {
          _logger.i('[${config.endpoint}] Heartbeat recovered (sub=$subId)');
          _handleRecovery();
        }
        if (_connectionStatus == ConnectionStatus.disconnected) {
          updateConnectionStatus(opcua.ClientState(
            channelState: opcua.SecureChannelState.UA_SECURECHANNELSTATE_OPEN,
            sessionState: opcua.SessionState.UA_SESSIONSTATE_ACTIVATED,
            recoveryStatus: 0,
          ));
        }
      },
      onError: (error) {
        if (gen != _heartbeatGeneration) return;
        final now = DateTime.now();
        final sinceTick = _lastHeartbeatTick != null
            ? now.difference(_lastHeartbeatTick!).inMilliseconds
            : -1;
        _logger.w('[${config.endpoint}] Heartbeat error (sub=$subId, '
            '${now.toUtc().toIso8601String()}, ${sinceTick}ms since last tick): $error');
        if (error is opcua.Inactivity ||
            error.toString().contains('Inactivity')) {
          _inactive = true;
          return;
        }
        if (isSubscriptionDead(error)) {
          _logger.e('[${config.endpoint}] Heartbeat lost (sub=$subId): $error');
          sessionLost = true;
          stopHeartbeat();
        }
      },
    );
  }

  void stopHeartbeat() {
    _heartbeatSub?.cancel();
    _heartbeatSub = null;
  }

  void _handleRecovery() {
    _inactive = false;
    if (resendOnRecovery) {
      for (final s in streams) {
        s.resendLastValue();
      }
    }
  }

  void markSessionLost() => sessionLost = true;

  @visibleForTesting
  void simulateInactivity() => _inactive = true;

  @visibleForTesting
  void simulateFatalHeartbeatError() {
    sessionLost = true;
    stopHeartbeat();
  }

  @visibleForTesting
  void simulateHeartbeatTick() {
    if (_inactive) {
      _handleRecovery();
    }
  }

  void dispose() {
    stopHeartbeat();
    _connectionController.close();
  }
}

// ---------------------------------------------------------------------------
// OpcUaDeviceClientAdapter — DeviceClient implementation for OPC UA
// ---------------------------------------------------------------------------

/// Wraps one or more OPC UA connections as a [DeviceClient].
///
/// The adapter owns [ClientWrapper] instances, drives their runIterate
/// background loops, manages subscriptions via [_monitor], and converts
/// between open62541's DynamicValue and tfc_dart's DynamicValue.
class OpcUaDeviceClientAdapter implements DeviceClient {
  final Logger _logger = Logger();
  final List<ClientWrapper> clients;
  final KeyMappings keyMappings;
  final String alias;
  final Map<String, AutoDisposingStream<tfc.DynamicValue>> _subscriptions = {};
  bool _shouldRun = true;

  OpcUaDeviceClientAdapter._({
    required this.clients,
    required this.keyMappings,
    required this.alias,
  });

  /// Create an OPC UA adapter from config.
  static Future<OpcUaDeviceClientAdapter> create({
    required List<OpcUAConfig> opcuaConfigs,
    required KeyMappings keyMappings,
    bool useIsolate = true,
    String alias = '',
    bool resendOnRecovery = true,
  }) async {
    List<ClientWrapper> clients = [];
    for (final opcuaConfig in opcuaConfigs) {
      Uint8List? cert;
      Uint8List? key;
      opcua.MessageSecurityMode securityMode =
          opcua.MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE;
      if (opcuaConfig.sslCert != null && opcuaConfig.sslKey != null) {
        cert = opcuaConfig.sslCert!;
        key = opcuaConfig.sslKey!;
        securityMode =
            opcua.MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT;
      }
      String? username;
      String? password;
      if (opcuaConfig.username != null && opcuaConfig.password != null) {
        username = opcuaConfig.username;
        password = opcuaConfig.password;
      }
      clients.add(ClientWrapper(
        useIsolate
            ? await opcua.ClientIsolate.create(
                username: username,
                password: password,
                certificate: cert,
                privateKey: key,
                securityMode: securityMode,
                logLevel: opcua.LogLevel.UA_LOGLEVEL_INFO,
                secureChannelLifeTime: Duration(minutes: 1),
              )
            : opcua.Client(
                username: username,
                password: password,
                certificate: cert,
                privateKey: key,
                securityMode: securityMode,
                logLevel: opcua.LogLevel.UA_LOGLEVEL_INFO,
                secureChannelLifeTime: Duration(minutes: 1),
              ),
        opcuaConfig,
        resendOnRecovery: resendOnRecovery,
      ));
    }
    final adapter = OpcUaDeviceClientAdapter._(
      clients: clients,
      keyMappings: keyMappings,
      alias: alias,
    );
    return adapter;
  }

  @override
  Set<String> get subscribableKeys {
    // All keys that have an opcuaNode config
    return keyMappings.nodes.entries
        .where((e) => e.value.opcuaNode != null)
        .map((e) => e.key)
        .toSet();
  }

  @override
  bool canSubscribe(String key) {
    return keyMappings.nodes[key]?.opcuaNode != null;
  }

  @override
  tfc.DynamicValue? read(String key) {
    // Synchronous read from last cached value
    final ads = _subscriptions[key];
    if (ads == null) return null;
    return ads.lastValue;
  }

  @override
  ConnectionStatus get connectionStatus {
    // Return connected if ANY client is connected
    for (final wrapper in clients) {
      if (wrapper.connectionStatus == ConnectionStatus.connected) {
        return ConnectionStatus.connected;
      }
    }
    for (final wrapper in clients) {
      if (wrapper.connectionStatus == ConnectionStatus.connecting) {
        return ConnectionStatus.connecting;
      }
    }
    return ConnectionStatus.disconnected;
  }

  @override
  Stream<ConnectionStatus> get connectionStream {
    if (clients.length == 1) return clients.first.connectionStream;
    return MergeStream(clients.map((c) => c.connectionStream)).distinct();
  }

  @override
  void connect() {
    for (final wrapper in clients) {
      _startBackground(wrapper);
      _listenToStateStream(wrapper);
    }
  }

  @override
  Stream<tfc.DynamicValue> subscribe(String key) {
    if (_subscriptions.containsKey(key)) {
      return _subscriptions[key]!.stream;
    }
    final ads = AutoDisposingStream<tfc.DynamicValue>(key, (key) {
      _subscriptions.remove(key);
      for (final w in clients) {
        w.streams.remove(_subscriptions[key]);
      }
      _logger.d('Unsubscribed from $key');
    });
    _subscriptions[key] = ads;
    try {
      _getClientWrapper(key).streams.add(ads);
    } catch (_) {}
    // Start async monitoring in background
    _monitor(key);
    return ads.stream;
  }

  @override
  Future<void> write(String key, tfc.DynamicValue value) async {
    final client = _getClientWrapper(key).client;
    final nodeId = _lookupNodeId(key);
    if (nodeId == null) {
      throw StateManException("Key: \"$key\" not found");
    }
    final (id, idx) = nodeId;
    await client.awaitConnect();
    if (idx != null) {
      final readValue = await client.read(toOpcUaNodeId(id));
      readValue[idx] = toOpcUaDynamicValue(value);
      await client.write(toOpcUaNodeId(id), readValue);
      return;
    }
    await client.write(toOpcUaNodeId(id), toOpcUaDynamicValue(value));
  }

  /// Read a single OPC UA key (used by StateMan.read fallback).
  Future<tfc.DynamicValue> readSingle(String key) async {
    final client = _getClientWrapper(key).client;
    final nodeId = _lookupNodeId(key);
    if (nodeId == null) {
      throw StateManException("Key: \"$key\" not found");
    }
    final (id, idx) = nodeId;
    await client.awaitConnect();
    var value = await client.read(toOpcUaNodeId(id));
    if (idx != null) {
      value = value[idx];
    }
    final result = fromOpcUaDynamicValue(value);
    final entry = keyMappings.nodes[key];
    return StateMan.applyBitMask(result, entry?.bitMask, entry?.bitShift);
  }

  /// Batch read multiple OPC UA keys.
  Future<Map<String, tfc.DynamicValue>> readMany(List<String> keys) async {
    final results = <String, tfc.DynamicValue>{};
    final parameters = <opcua.ClientApi, Map<opcua.NodeId, List<opcua.AttributeId>>>{};

    for (final key in keys) {
      final opcua.ClientApi client;
      try {
        client = _getClientWrapper(key).client;
      } catch (e) {
        throw StateManException('No client for key: "$key": $e');
      }
      final nodeId = _lookupNodeId(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      final (id, _) = nodeId;
      parameters[client] = {
        toOpcUaNodeId(id): [
          opcua.AttributeId.UA_ATTRIBUTEID_DESCRIPTION,
          opcua.AttributeId.UA_ATTRIBUTEID_DISPLAYNAME,
          opcua.AttributeId.UA_ATTRIBUTEID_DATATYPE,
          opcua.AttributeId.UA_ATTRIBUTEID_VALUE,
        ]
      };
    }

    for (final pair in parameters.entries) {
      final client = pair.key;
      final params = pair.value;
      await client.awaitConnect();
      final res = await client.readAttribute(params);
      results.addAll(res.map((nodeId, value) {
        final tfcNodeId = fromOpcUaNodeId(nodeId);
        final key = keyMappings.lookupKey(tfcNodeId);
        if (key == null) {
          throw StateManException("Key not found for nodeId: $nodeId");
        }
        final foo = _lookupNodeId(key);
        if (foo == null) {
          throw StateManException("Weird error: Key: \"$key\" not found");
        }
        final (_, idx) = foo;
        if (idx != null) {
          return MapEntry(key, fromOpcUaDynamicValue(value[idx]));
        }
        return MapEntry(key, fromOpcUaDynamicValue(value));
      }));
    }
    return results;
  }

  @override
  void dispose() {
    _shouldRun = false;
    for (final wrapper in clients) {
      try {
        if (wrapper.client is opcua.ClientIsolate) {
          (wrapper.client as opcua.ClientIsolate).disconnect();
        } else {
          (wrapper.client as opcua.Client).disconnect();
        }
      } catch (_) {}
      wrapper.client.delete();
      wrapper.dispose();
    }
    for (final entry in _subscriptions.values) {
      entry.cancelRawSub();
      entry.closeSubject();
    }
    _subscriptions.clear();
  }

  // -----------------------------------------------------------------------
  // Internal
  // -----------------------------------------------------------------------

  void _startBackground(ClientWrapper wrapper) {
    if (wrapper.client is opcua.Client) {
      () async {
        final clientref = wrapper.client as opcua.Client;
        final stats = RunIterateStats("${wrapper.config.endpoint} \"$alias\"");
        while (_shouldRun) {
          try {
            clientref.connect(wrapper.config.endpoint).onError(
                (e, stacktrace) => _logger.e(
                    'Failed to connect to ${wrapper.config.endpoint}: $e'));
            while (_shouldRun) {
              final startTime = DateTime.now();
              final continueRunning =
                  clientref.runIterate(const Duration(milliseconds: 10));
              final execTime = DateTime.now().difference(startTime);
              stats.recordCall(execTime);
              if (!continueRunning) break;
              await Future.delayed(const Duration(milliseconds: 10));
            }
            stats.logFinal();
            _logger.e('Disconnecting client');
            clientref.disconnect();
          } catch (error) {
            _logger.e("Client run iterate error: $error");
            try {
              clientref.disconnect();
            } catch (_) {}
          }
          await Future.delayed(const Duration(milliseconds: 1000));
        }
        _logger.e('OpcUaDeviceClientAdapter background run iterate task exited');
      }();
    }
    if (wrapper.client is opcua.ClientIsolate) {
      final clientref = wrapper.client as opcua.ClientIsolate;
      () async {
        while (_shouldRun) {
          try {
            clientref.connect(wrapper.config.endpoint).onError(
                (e, stacktrace) => _logger.e(
                    'Failed to connect to ${wrapper.config.endpoint}: $e'));
            await clientref.runIterate();
          } catch (error) {
            _logger.e("run iterate error: $error");
            try {
              await clientref.disconnect();
            } catch (_) {}
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }();
    }
  }

  void _listenToStateStream(ClientWrapper wrapper) {
    opcua.SecureChannelState? lastChannelState;
    DateTime? channelOpenedAt;
    final channelLifetimeSec = 60;

    wrapper.client.stateStream.listen((value) {
      wrapper.updateConnectionStatus(value);
      final now = DateTime.now();

      if (value.channelState != lastChannelState) {
        final timeSinceOpen = channelOpenedAt != null
            ? now.difference(channelOpenedAt!).inSeconds
            : 0;
        _logger.i(
            '[$alias ${wrapper.config.endpoint}] SecureChannel state: ${lastChannelState?.name} -> ${value.channelState.name} '
            '(session: ${value.sessionState.name}, recovery: ${value.recoveryStatus}) '
            '[uptime: ${timeSinceOpen}s]');

        if (value.channelState ==
            opcua.SecureChannelState.UA_SECURECHANNELSTATE_OPEN) {
          channelOpenedAt = now;
          _logger.i(
              '[$alias ${wrapper.config.endpoint}] Channel opened at $now, renewal expected at ~${channelLifetimeSec * 0.75}s');
        }

        lastChannelState = value.channelState;
      }

      if (value.channelState ==
          opcua.SecureChannelState.UA_SECURECHANNELSTATE_CLOSED) {
        final timeSinceOpen = channelOpenedAt != null
            ? now.difference(channelOpenedAt!).inSeconds
            : 0;
        _logger.e(
            '[$alias ${wrapper.config.endpoint}] Channel closed after ${timeSinceOpen}s (expected lifetime: ${channelLifetimeSec}s, '
            'renewal window: ${channelLifetimeSec * 0.75}s-${channelLifetimeSec}s)');
        channelOpenedAt = null;
      }
      if (value.sessionState ==
              opcua.SessionState.UA_SESSIONSTATE_CREATE_REQUESTED &&
          wrapper.subscriptionId != null) {
        _logger.e('[$alias ${wrapper.config.endpoint}] Session lost!');
        wrapper.markSessionLost();
      }
      if (value.sessionState == opcua.SessionState.UA_SESSIONSTATE_ACTIVATED) {
        if (wrapper.sessionLost) {
          _logger.e(
              '[$alias ${wrapper.config.endpoint}] Session lost, resubscribing (old sub=${wrapper.subscriptionId})');
          wrapper.sessionLost = false;
          wrapper.subscriptionId = null;
          wrapper.stopHeartbeat();
          final lostAlias = wrapper.config.serverAlias;
          final keysToResub = _subscriptions.values
              .where((e) => keyMappings.lookupServerAlias(e.key) == lostAlias)
              .map((e) => e.key)
              .toList();
          _logger.i(
              '[$alias ${wrapper.config.endpoint}] Resubscribing ${keysToResub.length} keys');

          // Phase 1: Cancel ALL old raw subscriptions
          for (final key in keysToResub) {
            final ads = _subscriptions[key];
            _logger.d('[$alias] resub $key: exists=${ads != null}, '
                'hasRawSub=${ads?.rawSub != null}');
            if (ads != null && ads.rawSub != null) {
              ads.cancelRawSub();
            }
          }

          // Phase 2: Create new monitored items
          for (final key in keysToResub) {
            _monitor(key, resub: true).catchError((e, s) {
              _logger.e('[$alias] Failed to resubscribe key "$key": $e\n$s');
            });
          }
        }
      }
    }, onError: (e, s) {
      _logger.e('[$alias] Failed to listen to state stream: $e, $s');
    });
  }

  ClientWrapper _getClientWrapper(String key) {
    final alias = keyMappings.lookupServerAlias(key);
    final wrapper = clients.firstWhere(
      (wrapper) => wrapper.config.serverAlias == alias,
      orElse: () => throw StateManException(
          'No OPC-UA client found for key "$key" (server alias: $alias)'),
    );
    return wrapper;
  }

  (tfc.NodeId, int?)? _lookupNodeId(String key) {
    return keyMappings.lookupNodeId(key);
  }

  Future<void> _monitor(String key, {bool resub = false}) async {
    if (_subscriptions.containsKey(key) && !resub) {
      return;
    }

    _logger.d(
        '[$alias] _monitor($key, resub=$resub) hasExisting=${_subscriptions.containsKey(key)}');

    // Ensure ADS exists (subscribe() creates it for initial calls)
    if (!_subscriptions.containsKey(key)) {
      final ads = AutoDisposingStream<tfc.DynamicValue>(key, (key) {
        _subscriptions.remove(key);
        for (final w in clients) {
          w.streams.remove(_subscriptions[key]);
        }
        _logger.d('Unsubscribed from $key');
      });
      _subscriptions[key] = ads;
      try {
        _getClientWrapper(key).streams.add(ads);
      } catch (_) {}
    }

    late opcua.ClientApi client;
    late (tfc.NodeId, int?) nodeId;
    try {
      client = _getClientWrapper(key).client;
      await client.awaitConnect();
      final lookup = _lookupNodeId(key);
      if (lookup == null) {
        throw StateManException('Key: "$key" not found');
      }
      nodeId = lookup;
    } catch (e) {
      _logger.e('Failed to connect to client for key: "$key": $e');
      _subscriptions[key]?.closeSubject();
      return;
    }
    final (id, idx) = nodeId;

    int retries = 0;
    while (_shouldRun) {
      try {
        final wrapper = _getClientWrapper(key);
        _subscriptions[key]?.cancelRawSub();

        await client.awaitConnect();

        if (wrapper.subscriptionId == null &&
            await wrapper.worker.doTheWork()) {
          try {
            wrapper.subscriptionId = await client.subscriptionCreate(
              requestedMaxKeepAliveCount: 30,
            );
            _logger.i(
                '[$alias ${wrapper.config.endpoint}] Created subscription ${wrapper.subscriptionId}');
            wrapper.startHeartbeat(wrapper.subscriptionId!);
          } catch (e) {
            _logger.e('Failed to create subscription: $e');
          } finally {
            wrapper.worker.complete();
          }
        }
        if (wrapper.subscriptionId == null) {
          continue;
        }

        final ads = _subscriptions[key]!;
        final hadPrevious = ads.rawSub != null;

        _logger.d(
            '[$alias] Creating monitored items for $key on sub=${wrapper.subscriptionId}');

        var stream = client.monitor(toOpcUaNodeId(id), wrapper.subscriptionId!);
        Stream<tfc.DynamicValue> tfcStream = stream.map((value) {
          var v = value;
          if (idx != null) v = v[idx];
          var result = fromOpcUaDynamicValue(v);
          final entry = keyMappings.nodes[key];
          if (entry?.bitMask != null) {
            result = StateMan.applyBitMask(result, entry!.bitMask, entry.bitShift);
          }
          return result;
        });

        final firstEmission = Completer<void>();
        final wrappedStream = tfcStream.map((value) {
          if (!firstEmission.isCompleted) firstEmission.complete();
          return value;
        });
        ads.subscribe(wrappedStream, null);
        await firstEmission.future.timeout(const Duration(seconds: 5));
        _logger.i('[$alias] Subscribed $key (replaced previous: $hadPrevious)');
        return; // Successfully monitoring
      } catch (e) {
        retries++;
        if (retries > 10) {
          _logger.w('Failed to get initial value for $key: $e');
          retries = 0;
        }
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
    }
    _logger.e('OPC UA adapter closed while monitoring "$key"');
  }
}
