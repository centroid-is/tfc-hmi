import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:meta/meta.dart'; // Add this import at the top
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'collector.dart';
import 'preferences.dart';

part 'state_man.g.dart';

/// Statistics tracker for runIterate timing
class RunIterateStats {
  final String clientName;
  final Logger _logger = Logger();

  DateTime? _lastCallTime;
  int _callCount = 0;

  // Time between calls (gaps)
  Duration _maxGap = Duration.zero;
  Duration _totalGap = Duration.zero;

  // Execution time
  Duration _maxExecTime = Duration.zero;
  Duration _totalExecTime = Duration.zero;

  // Report interval
  final int _reportInterval = 1000; // Report every N calls

  RunIterateStats(this.clientName);

  void recordCall(Duration execTime) {
    final now = DateTime.now();

    if (_lastCallTime != null) {
      final gap = now.difference(_lastCallTime!);
      _totalGap += gap;
      if (gap > _maxGap) {
        _maxGap = gap;
      }
    }

    _totalExecTime += execTime;
    if (execTime > _maxExecTime) {
      _maxExecTime = execTime;
    }

    _callCount++;
    _lastCallTime = now;

    // Log periodically
    if (_callCount % _reportInterval == 0) {
      _logStats();
    }
  }

  void _logStats() {
    if (_callCount == 0) return;

    final avgGapMs = _callCount > 1
        ? (_totalGap.inMicroseconds / (_callCount - 1) / 1000)
            .toStringAsFixed(2)
        : 'N/A';
    final avgExecMs =
        (_totalExecTime.inMicroseconds / _callCount / 1000).toStringAsFixed(2);

    _logger.i('[$clientName] runIterate stats after $_callCount calls: '
        'gap(avg: ${avgGapMs}ms, max: ${_maxGap.inMilliseconds}ms) '
        'exec(avg: ${avgExecMs}ms, max: ${_maxExecTime.inMilliseconds}ms)');
  }

  void logFinal() {
    _logStats();
  }
}

class Base64Converter implements JsonConverter<Uint8List?, String?> {
  const Base64Converter();

  @override
  Uint8List? fromJson(String? json) {
    if (json == null) return null;
    return base64Decode(json);
  }

  @override
  String? toJson(Uint8List? certificateContents) {
    if (certificateContents == null) return null;
    return base64Encode(certificateContents);
  }
}

@JsonSerializable(explicitToJson: true)
class OpcUAConfig {
  String endpoint = "opc.tcp://localhost:4840";
  String? username;
  String? password;
  @Base64Converter()
  @JsonKey(name: 'ssl_cert')
  Uint8List? sslCert;
  @Base64Converter()
  @JsonKey(name: 'ssl_key')
  Uint8List? sslKey;
  @JsonKey(name: 'server_alias')
  String? serverAlias;

  OpcUAConfig();

  @override
  String toString() {
    return 'OpcUAConfig(endpoint: $endpoint, username: $username, password: $password, sslCert: $sslCert, sslKey: $sslKey)';
  }

  factory OpcUAConfig.fromJson(Map<String, dynamic> json) =>
      _$OpcUAConfigFromJson(json);
  Map<String, dynamic> toJson() => _$OpcUAConfigToJson(this);
}

@JsonSerializable(explicitToJson: true)
class StateManConfig {
  List<OpcUAConfig> opcua;

  StateManConfig({required this.opcua});

  StateManConfig copy() => StateManConfig.fromJson(toJson());

  @override
  String toString() {
    return 'StateManConfig(opcua: ${opcua.toString()})';
  }

  static Future<StateManConfig> fromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Config file not found: $path');
    }
    final contents = await file.readAsString();
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(contents) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw Exception('Invalid JSON in config file: $path - ${e.message}');
    }
    return StateManConfig.fromJson(json);
  }

  static Future<StateManConfig> fromPrefs(Preferences prefs) async {
    var configJson = await prefs.getString(configKey, secret: true);
    if (configJson == null) {
      configJson = jsonEncode(StateManConfig(opcua: [OpcUAConfig()]).toJson());
      await prefs.setString(configKey, configJson,
          secret: true, saveToDb: false);
    }
    return StateManConfig.fromJson(jsonDecode(configJson));
  }

  Future<void> toPrefs(Preferences prefs) async {
    final configJson = jsonEncode(toJson());
    await prefs.setString(configKey, configJson, secret: true, saveToDb: false);
  }

  factory StateManConfig.fromJson(Map<String, dynamic> json) =>
      _$StateManConfigFromJson(json);
  Map<String, dynamic> toJson() => _$StateManConfigToJson(this);

  static const String configKey = 'state_man_config';
}

@JsonSerializable(explicitToJson: true)
class OpcUANodeConfig {
  int namespace;
  String identifier;
  // I only want to support one dimension arrays, I dont think it is relevant to support multi-dimensional arrays
  @JsonKey(name: 'array_index')
  int? arrayIndex;
  @JsonKey(name: 'server_alias')
  String? serverAlias;

  OpcUANodeConfig({required this.namespace, required this.identifier});

  (NodeId, int?) toNodeId() {
    if (int.tryParse(identifier) != null) {
      return (NodeId.fromNumeric(namespace, int.parse(identifier)), arrayIndex);
    }
    return (NodeId.fromString(namespace, identifier), arrayIndex);
  }

  factory OpcUANodeConfig.fromJson(Map<String, dynamic> json) =>
      _$OpcUANodeConfigFromJson(json);
  Map<String, dynamic> toJson() => _$OpcUANodeConfigToJson(this);

  @override
  String toString() {
    return 'OpcUANodeConfig(namespace: $namespace, identifier: $identifier)';
  }
}

@JsonSerializable(explicitToJson: true)
class KeyMappingEntry {
  @JsonKey(name: 'opcua_node')
  OpcUANodeConfig? opcuaNode;
  bool? io; // if true, the key is an IO unit
  CollectEntry? collect;

  String? get server => opcuaNode?.serverAlias;

  KeyMappingEntry({this.opcuaNode, this.collect});

  factory KeyMappingEntry.fromJson(Map<String, dynamic> json) =>
      _$KeyMappingEntryFromJson(json);
  Map<String, dynamic> toJson() => _$KeyMappingEntryToJson(this);

  @override
  String toString() {
    return 'KeyMappingEntry(opcuaNode: ${opcuaNode?.toString()}, collect: $collect, io: $io)';
  }
}

@JsonSerializable(explicitToJson: true)
class KeyMappings {
  Map<String, KeyMappingEntry> nodes;

  KeyMappings({required this.nodes});

  (NodeId, int?)? lookupNodeId(String key) {
    return nodes[key]?.opcuaNode?.toNodeId();
  }

  String? lookupServerAlias(String key) {
    return nodes[key]?.opcuaNode?.serverAlias;
  }

  String? lookupKey(NodeId nodeId) {
    return nodes.entries.firstWhereOrNull((entry) {
      final result = entry.value.opcuaNode?.toNodeId();
      if (result == null) return false;
      final (entryNodeId, _) = result;
      return entryNodeId == nodeId;
    })?.key;
  }

  Iterable<String> get keys => nodes.keys;

  /// Filter key mappings to only include entries for a specific server alias.
  KeyMappings filterByServer(String? serverAlias) {
    final filtered = Map.fromEntries(
      nodes.entries.where((e) => e.value.server == serverAlias),
    );
    return KeyMappings(nodes: filtered);
  }

  static Future<KeyMappings> fromPrefs(PreferencesApi prefs,
      {bool createDefault = true}) async {
    var keyMappingsJson = await prefs.getString('key_mappings');
    if (keyMappingsJson == null) {
      if (!createDefault) {
        throw Exception(
            'key_mappings not found in preferences and createDefault is false');
      }
      final defaultKeyMappings = KeyMappings(nodes: {
        "exampleKey": KeyMappingEntry(
            opcuaNode: OpcUANodeConfig(namespace: 42, identifier: "identifier"))
      });
      keyMappingsJson = jsonEncode(defaultKeyMappings.toJson());
      await prefs.setString('key_mappings', keyMappingsJson);
    }
    return KeyMappings.fromJson(jsonDecode(keyMappingsJson));
  }

  factory KeyMappings.fromJson(Map<String, dynamic> json) =>
      _$KeyMappingsFromJson(json);
  Map<String, dynamic> toJson() => _$KeyMappingsToJson(this);
}

class StateManException implements Exception {
  final String message;
  StateManException(this.message);
  @override
  String toString() => 'StateManException: $message';
}

class SingleWorker {
  List<Completer<bool>> waiters = [];

  Future<bool> doTheWork() async {
    waiters.add(Completer<bool>());
    if (waiters.length == 1) {
      waiters.last.complete(true);
    }

    return waiters.last.future;
  }

  void complete() {
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete(false);
      }
    }
    waiters.clear();
  }
}

enum ConnectionStatus { connected, connecting, disconnected }

class ClientWrapper {
  final ClientApi client;
  final OpcUAConfig config;
  int? subscriptionId;
  final SingleWorker worker = SingleWorker();

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final StreamController<ConnectionStatus> _connectionController =
      StreamController<ConnectionStatus>.broadcast();

  ClientWrapper(this.client, this.config);

  /// Current connection status (synchronous, always up-to-date).
  ConnectionStatus get connectionStatus => _connectionStatus;

  /// Stream of connection status changes. Subscribe anytime — read
  /// [connectionStatus] for the current value.
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;

  void updateConnectionStatus(ClientState state) {
    final next = _mapState(state);
    if (next == _connectionStatus) return;
    _connectionStatus = next;
    _connectionController.add(next);
  }

  static ConnectionStatus _mapState(ClientState state) {
    if (state.sessionState == SessionState.UA_SESSIONSTATE_ACTIVATED) {
      return ConnectionStatus.connected;
    }
    if (state.channelState == SecureChannelState.UA_SECURECHANNELSTATE_OPEN) {
      return ConnectionStatus.connecting;
    }
    return ConnectionStatus.disconnected;
  }

  void dispose() {
    _connectionController.close();
  }
}

class StateMan {
  final logger = Logger();
  final StateManConfig config;
  KeyMappings keyMappings;
  final List<ClientWrapper> clients;
  final Map<String, AutoDisposingStream<DynamicValue>> _subscriptions = {};
  bool _shouldRun = true;
  final Map<String, String> _substitutions = {};
  final _subsMap$ = BehaviorSubject<Map<String, String>>.seeded(const {});
  String alias;

  Timer? _healthCheckTimer;

  /// Constructor requires the server endpoint.
  StateMan._({
    required this.config,
    required this.keyMappings,
    required this.clients,
    required this.alias,
  }) {
    for (final wrapper in clients) {
      if (wrapper.client is Client) {
        // spawn a background task to keep the client active
        () async {
          final clientref = wrapper.client as Client;
          final stats =
              RunIterateStats("${wrapper.config.endpoint} \"$alias\"");
          while (_shouldRun) {
            clientref.connect(wrapper.config.endpoint).onError(
                (e, stacktrace) => logger
                    .e('Failed to connect to ${wrapper.config.endpoint}: $e'));
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
            logger.e('Disconnecting client');
            clientref.disconnect();
            await Future.delayed(const Duration(milliseconds: 1000));
          }
          logger.e('StateMan background run iterate task exited');
        }();
      }
      if (wrapper.client is ClientIsolate) {
        final clientref = wrapper.client as ClientIsolate;
        () async {
          while (_shouldRun) {
            try {
              clientref.connect(wrapper.config.endpoint).onError(
                  (e, stacktrace) => logger.e(
                      'Failed to connect to ${wrapper.config.endpoint}: $e'));
              await clientref.runIterate();
            } catch (error) {
              logger.e("run iterate error: $error");
              try {
                // try to disconnect
                await clientref.disconnect();
              } catch (_) {}
              // Throttle if often occuring error
              await Future.delayed(const Duration(seconds: 1));
            }
          }
        }();
      }

      bool sessionLost = false;
      SecureChannelState? lastChannelState;
      DateTime? channelOpenedAt;
      final channelLifetimeSec = 60; // 1 minute as configured

      wrapper.client.stateStream.listen((value) {
        wrapper.updateConnectionStatus(value);
        final now = DateTime.now();

        // Log ALL SecureChannel state transitions with timestamps
        if (value.channelState != lastChannelState) {
          final timeSinceOpen = channelOpenedAt != null
              ? now.difference(channelOpenedAt!).inSeconds
              : 0;
          logger.i(
              '[$alias ${wrapper.config.endpoint}] SecureChannel state: ${lastChannelState?.name} -> ${value.channelState.name} '
              '(session: ${value.sessionState.name}, recovery: ${value.recoveryStatus}) '
              '[uptime: ${timeSinceOpen}s]');

          // Track when channel opens
          if (value.channelState ==
              SecureChannelState.UA_SECURECHANNELSTATE_OPEN) {
            channelOpenedAt = now;
            logger.i(
                '[$alias ${wrapper.config.endpoint}] Channel opened at $now, renewal expected at ~${channelLifetimeSec * 0.75}s');
          }

          lastChannelState = value.channelState;
        }

        if (value.channelState ==
            SecureChannelState.UA_SECURECHANNELSTATE_CLOSED) {
          final timeSinceOpen = channelOpenedAt != null
              ? now.difference(channelOpenedAt!).inSeconds
              : 0;
          logger.e(
              '[$alias ${wrapper.config.endpoint}] Channel closed after ${timeSinceOpen}s (expected lifetime: ${channelLifetimeSec}s, '
              'renewal window: ${channelLifetimeSec * 0.75}s-${channelLifetimeSec}s)');
          channelOpenedAt = null;
        }
        // Only treat as session loss if this wrapper actually had a subscription
        if (value.sessionState ==
                SessionState.UA_SESSIONSTATE_CREATE_REQUESTED &&
            wrapper.subscriptionId != null) {
          logger.e('[$alias ${wrapper.config.endpoint}] Session lost!');
          sessionLost = true;
        }
        if (value.sessionState == SessionState.UA_SESSIONSTATE_ACTIVATED) {
          if (sessionLost) {
            logger.e(
                '[$alias ${wrapper.config.endpoint}] Session lost, resubscribing (old sub=${wrapper.subscriptionId})');
            sessionLost = false;
            wrapper.subscriptionId = null;
            // Only resubscribe keys belonging to this wrapper
            final lostAlias = wrapper.config.serverAlias;
            final keysToResub = _subscriptions.values
                .where((e) => keyMappings.lookupServerAlias(e.key) == lostAlias)
                .map((e) => e.key)
                .toList();
            logger.i(
                '[$alias ${wrapper.config.endpoint}] Resubscribing ${keysToResub.length} keys');
            for (final key in keysToResub) {
              _monitor(key, resub: true);
            }
          } else {
            _resendLastValues();
          }
        }
      }).onError((e, s) {
        logger.e('[$alias] Failed to listen to state stream: $e, $s');
      });
    }

    // Periodic health check - actively probe each connected server.
    // This detects half-open TCP connections where the remote has disappeared
    // but the local TCP stack hasn't noticed (due to long keepalive defaults).
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      for (final wrapper in clients) {
        if (wrapper.client is Client) {
          final clientRef = wrapper.client as Client;
          final state = clientRef.state;
          logger.d('[$alias] Health check: channel=${state.channelState.name}, '
              'session=${state.sessionState.name}, recovery=${state.recoveryStatus}');
        }
        // Active probe: if we think we're connected, try reading the server's
        // current time (ns=0;i=2258). If it times out, the connection is dead.
        // I would really like to add SO_KEEPALIVE to open62541 .......
        if (wrapper.connectionStatus == ConnectionStatus.connected) {
          final serverTimeNode = NodeId.fromNumeric(0, 2258);
          wrapper.client
              .readAttribute({
                serverTimeNode: [AttributeId.UA_ATTRIBUTEID_VALUE]
              })
              .timeout(const Duration(seconds: 5))
              .then((_) {
                // Read succeeded — connection is alive, nothing to do.
              })
              .catchError((e) {
                logger.e(
                    '[$alias] Health check read failed for ${wrapper.config.endpoint}: $e — marking disconnected');
                wrapper.updateConnectionStatus(ClientState(
                  channelState: SecureChannelState.UA_SECURECHANNELSTATE_CLOSED,
                  sessionState: SessionState.UA_SESSIONSTATE_CLOSED,
                  recoveryStatus: 0,
                ));
              });
        }
      }
    });
  }

  void _resendLastValues() {
    for (final entry in _subscriptions.values) {
      entry.resendLastValue();
    }
  }

  static Future<StateMan> create({
    required StateManConfig config,
    required KeyMappings keyMappings,
    bool useIsolate = true,
    String alias = '',
  }) async {
    // Example directory: /Users/jonb/Library/Containers/is.centroid.sildarvinnsla.skammtalina/Data/Documents/certs
    List<ClientWrapper> clients = [];
    for (final opcuaConfig in config.opcua) {
      Uint8List? cert;
      Uint8List? key;
      MessageSecurityMode securityMode =
          MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE;
      if (opcuaConfig.sslCert != null && opcuaConfig.sslKey != null) {
        cert = opcuaConfig.sslCert!;
        key = opcuaConfig.sslKey!;
        securityMode =
            MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT;
      }
      String? username;
      String? password;
      if (opcuaConfig.username != null && opcuaConfig.password != null) {
        username = opcuaConfig.username;
        password = opcuaConfig.password;
      }
      clients.add(ClientWrapper(
          useIsolate
              ? await ClientIsolate.create(
                  libraryPath: '', // empty is static linking
                  username: username,
                  password: password,
                  certificate: cert,
                  privateKey: key,
                  securityMode: securityMode,
                  logLevel: LogLevel.UA_LOGLEVEL_INFO,
                  secureChannelLifeTime: Duration(
                      minutes:
                          1), // TODO can I reproduce the problem more often
                )
              : Client(
                  loadOpen62541Library(staticLinking: true),
                  username: username,
                  password: password,
                  certificate: cert,
                  privateKey: key,
                  securityMode: securityMode,
                  logLevel: LogLevel.UA_LOGLEVEL_INFO,
                  secureChannelLifeTime: Duration(
                      minutes:
                          1), // TODO can I reproduce the problem more often
                ),
          opcuaConfig));
    }
    final stateMan = StateMan._(
        config: config,
        keyMappings: keyMappings,
        clients: clients,
        alias: alias);
    return stateMan;
  }

  ClientWrapper _getClientWrapper(String key) {
    // This throws if the key is not found
    // Be mindful that null == null is true
    return clients.firstWhere((wrapper) =>
        wrapper.config.serverAlias == keyMappings.lookupServerAlias(key));
  }

  void setSubstitution(String key, String value) {
    _substitutions[key] = value;
    logger.d('Substitution set: $key = $value');
    _subsMap$.add(Map.unmodifiable(_substitutions));
  }

  Stream<Map<String, String>> get substitutionsChanged => _subsMap$.stream;

  String? getSubstitution(String key) {
    return _substitutions[key];
  }

  String resolveKey(String key) {
    if (!key.contains('\$')) return key;

    String resolvedKey = key;
    for (final entry in _substitutions.entries) {
      final variablePattern = '\$${entry.key}';
      if (resolvedKey.contains(variablePattern)) {
        resolvedKey = resolvedKey.replaceAll(variablePattern, entry.value);
      }
    }

    if (resolvedKey != key) {
      logger.d('Resolved key: $key -> $resolvedKey');
    }

    if (resolvedKey.contains('\$')) {
      logger.e('Resolved key still contains \$: $resolvedKey');
    }

    return resolvedKey;
  }

  /// Example: read("myKey")
  Future<DynamicValue> read(String key) async {
    key = resolveKey(key);
    try {
      final client = _getClientWrapper(key).client;
      final nodeId = _lookupNodeId(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      final (id, idx) = nodeId;
      await client.awaitConnect();
      final value = await client.read(id);
      if (idx != null) {
        return value[idx];
      }
      return value;
    } catch (e) {
      throw StateManException('Failed to read key: \"$key\": $e');
    }
  }

  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    final parameters = <ClientApi, Map<NodeId, List<AttributeId>>>{};

    for (final keyToResolve in keys) {
      final key = resolveKey(keyToResolve);
      final client = _getClientWrapper(key).client;
      final nodeId = _lookupNodeId(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      final (id, idx) = nodeId;
      parameters[client] = {
        id: [
          AttributeId.UA_ATTRIBUTEID_DESCRIPTION,
          AttributeId.UA_ATTRIBUTEID_DISPLAYNAME,
          AttributeId.UA_ATTRIBUTEID_DATATYPE,
          AttributeId.UA_ATTRIBUTEID_VALUE,
        ]
      };
    }

    final results = <String, DynamicValue>{};
    for (final pair in parameters.entries) {
      final client = pair.key;
      final parameters = pair.value;
      await client.awaitConnect();
      final res = await client.readAttribute(parameters);
      results.addAll(res.map((nodeId, value) {
        final key = keyMappings.lookupKey(nodeId);
        if (key == null) {
          throw StateManException("Key: \"$key\" not found");
        }
        // todo refactor this to not be so ugly
        final foo = _lookupNodeId(key);
        if (foo == null) {
          throw StateManException("Weird error:Key: \"$key\" not found");
        }
        final (_, idx) = foo;
        if (idx != null) {
          return MapEntry(key, value[idx]);
        }
        return MapEntry(key, value);
      }));
    }
    return results;
  }

  /// Example: write("myKey", DynamicValue(value: 42, typeId: NodeId.int16))
  Future<void> write(String key, DynamicValue value) async {
    key = resolveKey(key);
    try {
      final client = _getClientWrapper(key).client;
      final nodeId = _lookupNodeId(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      final (id, idx) = nodeId;
      await client.awaitConnect();
      if (idx != null) {
        // a bit special, we need to read to be able to write
        // not sure I like this
        final readValue = await client.read(id);
        readValue[idx] = value;
        await client.write(id, readValue);
        return;
      }
      await client.write(id, value);
    } catch (e) {
      throw StateManException('Failed to write node: \"$key\": $e');
    }
  }

  /// Subscribe to data changes on a specific node with type safety.
  /// Returns a Stream that can be cancelled to stop the subscription.
  /// Example: subscribe("myIntKey") or subscribe("myStringKey")
  Future<Stream<DynamicValue>> subscribe(String key) async {
    key = resolveKey(key);
    return _monitor(key);
  }

  void updateKeyMappings(KeyMappings newKeyMappings) {
    keyMappings = newKeyMappings;
  }

  List<String> get keys => keyMappings.keys.toList();

  /// Close the connection to the server.
  Future<void> close() async {
    _shouldRun = false;
    logger.d('Closing connection');
    for (final wrapper in clients) {
      try {
        if (wrapper.client is ClientIsolate) {
          await (wrapper.client as ClientIsolate).disconnect();
        } else {
          (wrapper.client as Client).disconnect();
        }
      } catch (_) {}
      wrapper.client.delete();
      wrapper.dispose();
    }
    // Clean up subscriptions
    for (final entry in _subscriptions.values) {
      entry._rawSub?.cancel();
      entry._subject.close();
    }
    _subscriptions.clear();
    _healthCheckTimer?.cancel();

    _subsMap$.close();
  }

  (NodeId, int?)? _lookupNodeId(String key) {
    return keyMappings.lookupNodeId(key);
  }

  @visibleForTesting
  void addSubscription({
    required String key,
    required Stream<DynamicValue> subscription,
    required DynamicValue? firstValue,
  }) {
    _subscriptions[key] = AutoDisposingStream(key, (key) {
      _subscriptions.remove(key);
      logger.d('Unsubscribed from $key');
    });
    _subscriptions[key]!.subscribe(subscription, firstValue);
  }

  Future<Stream<DynamicValue>> _monitor(String key,
      {bool resub = false}) async {
    if (_subscriptions.containsKey(key) && !resub) {
      return _subscriptions[key]!.stream;
    }

    logger.d(
        '[$alias] _monitor($key, resub=$resub) hasExisting=${_subscriptions.containsKey(key)}');

    // Register entry synchronously before any await so concurrent
    // callers for the same key hit the early return above.
    if (!_subscriptions.containsKey(key)) {
      _subscriptions[key] = AutoDisposingStream(key, (key) {
        _subscriptions.remove(key);
        logger.d('Unsubscribed from $key');
      });
    }

    late ClientApi client;
    try {
      client = _getClientWrapper(key).client;
      await client.awaitConnect();
    } catch (e) {
      logger.e('Failed to connect to client for key: "$key": $e');
      return Stream.error(
          StateManException('Failed to connect to client for key: "$key": $e'));
    }

    final nodeId = _lookupNodeId(key);
    if (nodeId == null) {
      throw StateManException('Key: "$key" not found');
    }
    final (id, idx) = nodeId;

    int retries = 0;
    while (true) {
      try {
        await client.awaitConnect();
        final wrapper = _getClientWrapper(key);

        if (wrapper.subscriptionId == null &&
            await wrapper.worker.doTheWork()) {
          try {
            wrapper.subscriptionId = await client.subscriptionCreate();
            logger.i(
                '[$alias ${wrapper.config.endpoint}] Created subscription ${wrapper.subscriptionId}');
          } catch (e) {
            logger.e('Failed to create subscription: $e');
          } finally {
            wrapper.worker.complete();
          }
        }
        if (wrapper.subscriptionId == null) {
          continue;
        }

        // Verify node is accessible before creating monitored items.
        final readValue =
            await client.read(id).timeout(const Duration(seconds: 1));
        final firstValue = idx != null ? readValue[idx] : readValue;

        // Only create monitored items after confirming the node is readable.
        // The raw stream goes directly to AutoDisposingStream — its _rawSub
        // cancel properly triggers UA_Client_MonitoredItems_delete_async.
        logger.d(
            '[$alias] Creating monitored items for $key on sub=${wrapper.subscriptionId}');
        var stream = client.monitor(id, wrapper.subscriptionId!);
        if (idx != null) {
          stream = stream.map((value) => value[idx]);
        }

        final hadPrevious = _subscriptions[key]!._rawSub != null;
        _subscriptions[key]!.subscribe(stream, firstValue);
        logger.d('[$alias] Subscribed $key (replaced previous: $hadPrevious)');

        return _subscriptions[key]!.stream;
      } catch (e) {
        retries++;
        if (retries > 10) {
          logger.w('Failed to get initial value for $key: $e');
          retries = 0;
        }
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
    }
  }
}

class AutoDisposingStream<T> {
  final String key;
  final ReplaySubject<T> _subject;
  int _listenerCount = 0;
  Timer? _idleTimer;
  StreamSubscription<T>? _rawSub;
  final Function(String key) _onDispose;
  T? _lastValue;
  final Duration idleTimeout;
  AutoDisposingStream(this.key, this._onDispose,
      {this.idleTimeout = const Duration(minutes: 10)})
      : _subject = ReplaySubject<T>(maxSize: 1) {
    // Count UI listeners for idle shutdown:
    _subject
      ..onListen = _handleListen
      ..onCancel = _handleCancel;
  }

  Stream<T> get stream => _subject.stream;

  void subscribe(Stream<T> raw, T? firstValue) {
    _rawSub?.cancel();
    // wire raw → subject
    _rawSub = raw.listen(
      (value) {
        _lastValue = value;
        _subject.add(value);
      },
      onError: _subject.addError,
      onDone: _subject.close,
    );
    _lastValue = firstValue;
    if (firstValue != null) {
      _subject.add(firstValue);
    }
  }

  void _handleListen() {
    _listenerCount++;
    _idleTimer?.cancel();
  }

  void _handleCancel() {
    _listenerCount--;
    if (_listenerCount == 0) {
      _idleTimer = Timer(idleTimeout, () {
        _rawSub?.cancel(); // tear down the OPC-UA monitoredItem
        _onDispose(key); // remove from StateMan._subscriptions
        _subject.close(); // close the replay buffer
      });
    }
  }

  void resendLastValue() {
    if (_lastValue != null) {
      _subject.add(_lastValue!);
    }
  }
}
