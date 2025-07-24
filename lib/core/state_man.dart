import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart'; // Add this import at the top
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'collector.dart';

part 'state_man.g.dart';

class FileConverter implements JsonConverter<File?, String?> {
  const FileConverter();

  @override
  File? fromJson(String? json) {
    if (json == null) return null;
    return File(json);
  }

  @override
  String? toJson(File? file) {
    if (file == null) return null;
    return file.path;
  }
}

@JsonSerializable()
class OpcUAConfig {
  String endpoint = "opc.tcp://localhost:4840";
  String? username;
  String? password;
  @FileConverter()
  @JsonKey(name: 'ssl_cert')
  File? sslCert;
  @FileConverter()
  @JsonKey(name: 'ssl_key')
  File? sslKey;
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

@JsonSerializable()
class StateManConfig {
  List<OpcUAConfig> opcua;

  StateManConfig({required this.opcua});

  @override
  String toString() {
    return 'StateManConfig(opcua: ${opcua.toString()})';
  }

  factory StateManConfig.fromJson(Map<String, dynamic> json) =>
      _$StateManConfigFromJson(json);
  Map<String, dynamic> toJson() => _$StateManConfigToJson(this);
}

@JsonSerializable()
class OpcUANodeConfig {
  int namespace;
  String identifier;
  @JsonKey(name: 'server_alias')
  String? serverAlias;

  OpcUANodeConfig({required this.namespace, required this.identifier});

  NodeId toNodeId() {
    if (int.tryParse(identifier) != null) {
      return NodeId.fromNumeric(namespace, int.parse(identifier));
    }
    return NodeId.fromString(namespace, identifier);
  }

  factory OpcUANodeConfig.fromJson(Map<String, dynamic> json) =>
      _$OpcUANodeConfigFromJson(json);
  Map<String, dynamic> toJson() => _$OpcUANodeConfigToJson(this);

  @override
  String toString() {
    return 'OpcUANodeConfig(namespace: $namespace, identifier: $identifier)';
  }
}

@JsonSerializable()
class KeyMappingEntry {
  @JsonKey(name: 'opcua_node')
  OpcUANodeConfig? opcuaNode;
  bool? io; // if true, the key is an IO unit
  CollectEntry? collect;

  KeyMappingEntry({this.opcuaNode, this.collect});

  factory KeyMappingEntry.fromJson(Map<String, dynamic> json) =>
      _$KeyMappingEntryFromJson(json);
  Map<String, dynamic> toJson() => _$KeyMappingEntryToJson(this);

  @override
  String toString() {
    return 'KeyMappingEntry(opcuaNode: ${opcuaNode?.toString()}, collect: $collect, io: $io)';
  }
}

@JsonSerializable()
class KeyMappings {
  Map<String, KeyMappingEntry> nodes;

  KeyMappings({required this.nodes});

  NodeId? lookupNodeId(String key) {
    return nodes[key]?.opcuaNode?.toNodeId();
  }

  String? lookupServerAlias(String key) {
    return nodes[key]?.opcuaNode?.serverAlias;
  }

  String? lookupKey(NodeId nodeId) {
    return nodes.entries
        .firstWhereOrNull(
            (entry) => entry.value.opcuaNode?.toNodeId() == nodeId)
        ?.key;
  }

  Iterable<String> get keys => nodes.keys;

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

class ClientWrapper {
  final ClientApi client;
  final OpcUAConfig config;
  int? subscriptionId;
  final SingleWorker worker = SingleWorker();

  ClientWrapper(this.client, this.config);
}

class StateMan {
  final logger = Logger();
  final StateManConfig config;
  final KeyMappings keyMappings;
  final List<ClientWrapper> clients;
  final Map<String, AutoDisposingStream<DynamicValue>> _subscriptions = {};

  Timer? _healthCheckTimer;

  /// Constructor requires the server endpoint.
  StateMan._({
    required this.config,
    required this.keyMappings,
    required this.clients,
  }) {
    for (final wrapper in clients) {
      wrapper.client.connect(wrapper.config.endpoint).onError((e, stacktrace) =>
          logger.e('Failed to connect to ${wrapper.config.endpoint}: $e'));

      bool sessionLost = false;
      wrapper.client.stateStream.listen((value) {
        if (value.sessionState ==
                SessionState.UA_SESSIONSTATE_CREATE_REQUESTED &&
            _subscriptions.isNotEmpty) {
          logger.e('Session lost!');
          sessionLost = true;
        }
        if (value.sessionState == SessionState.UA_SESSIONSTATE_ACTIVATED &&
            sessionLost) {
          logger.e('Session lost, resubscribing');
          // Session was lost, resubscribe
          sessionLost = false;
          wrapper.subscriptionId = null;
          for (final entry in _subscriptions.values) {
            _monitor(entry.key, resub: true);
          }
        } else if (value.sessionState ==
            SessionState.UA_SESSIONSTATE_ACTIVATED) {
          // Session was not lost, retransmit last data values.
          logger.w(
              'Session regained, resending last values ${_subscriptions.length}');
          _resendLastValues();
        }
      }).onError((e, s) {
        logger.e('Failed to listen to state stream: $e, $s');
      });
    }
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
  }) async {
    // Example directory: /Users/jonb/Library/Containers/is.centroid.sildarvinnsla.skammtalina/Data/Documents/certs
    List<ClientWrapper> clients = [];
    for (final opcuaConfig in config.opcua) {
      Uint8List? cert;
      Uint8List? key;
      MessageSecurityMode securityMode =
          MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE;
      if (opcuaConfig.sslCert != null && opcuaConfig.sslKey != null) {
        cert = await opcuaConfig.sslCert!.readAsBytes();
        key = await opcuaConfig.sslKey!.readAsBytes();
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
                  logLevel: LogLevel.UA_LOGLEVEL_ERROR,
                )
              : Client(
                  loadOpen62541Library(staticLinking: true),
                  username: username,
                  password: password,
                  certificate: cert,
                  privateKey: key,
                  securityMode: securityMode,
                  logLevel: LogLevel.UA_LOGLEVEL_ERROR,
                ),
          opcuaConfig));
    }
    final stateMan = StateMan._(
      config: config,
      keyMappings: keyMappings,
      clients: clients,
    );
    return stateMan;
  }

  ClientWrapper _getClientWrapper(String key) {
    // This throws if the key is not found
    // Be mindful that null == null is true
    return clients.firstWhere((wrapper) =>
        wrapper.config.serverAlias == keyMappings.lookupServerAlias(key));
  }

  /// Example: read("myKey")
  Future<DynamicValue> read(String key) async {
    try {
      final client = _getClientWrapper(key).client;
      final nodeId = lookupNodeId(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      await client.awaitConnect();
      return await client.read(nodeId);
    } catch (e) {
      throw StateManException('Failed to read key: \"$key\": $e');
    }
  }

  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    final parameters = <ClientApi, Map<NodeId, List<AttributeId>>>{};

    for (final key in keys) {
      final client = _getClientWrapper(key).client;
      final nodeId = lookupNodeId(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      parameters[client] = {
        nodeId: [
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
      results.addAll(res
          .map((key, value) => MapEntry(keyMappings.lookupKey(key)!, value)));
    }
    return results;
  }

  /// Example: write("myKey", DynamicValue(value: 42, typeId: NodeId.int16))
  Future<void> write(String key, DynamicValue value) async {
    try {
      final client = _getClientWrapper(key).client;
      final nodeId = lookupNodeId(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      await client.awaitConnect();
      await client.write(nodeId, value);
    } catch (e) {
      throw StateManException('Failed to write node: \"$key\": $e');
    }
  }

  /// Subscribe to data changes on a specific node with type safety.
  /// Returns a Stream that can be cancelled to stop the subscription.
  /// Example: subscribe("myIntKey") or subscribe("myStringKey")
  Future<Stream<DynamicValue>> subscribe(String key) async {
    return _monitor(key);
  }

  List<String> get keys => keyMappings.keys.toList();

  /// Close the connection to the server.
  void close() {
    logger.d('Closing connection');
    for (final wrapper in clients) {
      wrapper.client.delete();
    }
    // Clean up subscriptions
    for (final entry in _subscriptions.values) {
      entry._rawSub?.cancel();
      entry._subject.close();
    }
    _subscriptions.clear();
    _healthCheckTimer?.cancel();
  }

  NodeId? lookupNodeId(String key) {
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
    bool keyExists = _subscriptions.containsKey(key);

    if (keyExists && !resub) {
      return _subscriptions[key]!.stream;
    }

    late ClientApi client;
    try {
      client = _getClientWrapper(key).client;
      await client.awaitConnect();
    } catch (e) {
      throw StateManException(
          'Failed to connect to client for key: "$key": $e');
    }

    final nodeId = lookupNodeId(key);
    if (nodeId == null) {
      throw StateManException('Key: "$key" not found');
    }

    // async boundary between the last check, let's make sure the key still exists or not
    keyExists = _subscriptions.containsKey(key);

    if (!keyExists && !resub) {
      _subscriptions[key] = AutoDisposingStream(key, (key) {
        _subscriptions.remove(key);
        logger.d('Unsubscribed from $key');
      });
    }

    while (true) {
      try {
        await client.awaitConnect();
        final wrapper = _getClientWrapper(key);

        if (wrapper.subscriptionId == null &&
            await wrapper.worker.doTheWork()) {
          try {
            wrapper.subscriptionId = await client.subscriptionCreate();
          } catch (e) {
            logger.e('Failed to create subscription: $e');
          } finally {
            wrapper.worker.complete();
          }
        }
        if (wrapper.subscriptionId == null) {
          continue;
        }
        final stream =
            client.monitor(nodeId, wrapper.subscriptionId!).asBroadcastStream();

        // Test for first value
        final firstValue = await stream.first.timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            throw TimeoutException('No value received within 1 seconds');
          },
        );

        // Got first value, create subscription
        _subscriptions[key]!.subscribe(stream, firstValue);

        return _subscriptions[key]!.stream;
      } catch (e) {
        logger.w('Failed to get initial value for $key: $e');
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
