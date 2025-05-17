import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart';
import 'package:rxdart/rxdart.dart';
import 'package:collection/collection.dart';

import 'ring_buffer.dart';

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
  OpcUAConfig opcua;

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
class NodeIdConfig {
  int namespace;
  String identifier;

  NodeIdConfig({required this.namespace, required this.identifier});

  NodeId toNodeId() {
    if (int.tryParse(identifier) != null) {
      return NodeId.fromNumeric(namespace, int.parse(identifier));
    }
    return NodeId.fromString(namespace, identifier);
  }

  factory NodeIdConfig.fromJson(Map<String, dynamic> json) =>
      _$NodeIdConfigFromJson(json);
  Map<String, dynamic> toJson() => _$NodeIdConfigToJson(this);
}

@JsonSerializable()
class KeyMappingEntry {
  NodeIdConfig? nodeId;
  int? collectSize;
  bool? io; // if true, the key is an IO unit

  KeyMappingEntry({this.nodeId, this.collectSize});

  factory KeyMappingEntry.fromJson(Map<String, dynamic> json) =>
      _$KeyMappingEntryFromJson(json);
  Map<String, dynamic> toJson() => _$KeyMappingEntryToJson(this);
}

@JsonSerializable()
class KeyMappings {
  Map<String, KeyMappingEntry> nodes;

  KeyMappings({required this.nodes});

  NodeId? lookup(String key) {
    return nodes[key]?.nodeId?.toNodeId();
  }

  String? lookupKey(NodeId nodeId) {
    return nodes.entries
        .firstWhereOrNull((entry) => entry.value.nodeId?.toNodeId() == nodeId)
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

class StateMan {
  final logger = Logger();
  final StateManConfig config;
  final KeyMappings keyMappings;
  final Client client;
  int? subscriptionId;
  final Map<String, _SubscriptionEntry> _subscriptions = {};

  // Use the new manager
  late final KeyCollectorManager _collectorManager;

  /// Constructor requires the server endpoint.
  StateMan._(
      {required this.config, required this.keyMappings, required this.client}) {
    _collectorManager = KeyCollectorManager(monitorFn: _monitor);

    client.config.stateStream.listen((state) {
      logger.e('State: $state');
    });
    client.config.subscriptionInactivityStream.listen((inactivity) {
      logger.e('Subscription inactivity: $inactivity');
      // Send error to all active subscriptions
      for (final entry in _subscriptions.values) {
        entry.addInactivityError();
      }

      // I would like to periodically read
    });

    // spawn a background task to keep the client active
    () async {
      while (true) {
        try {
          client.connect(config.opcua.endpoint);
        } catch (e) {
          logger.e('Failed to connect to $config.opcua.endpoint: $e');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        while (client.runIterate(const Duration(milliseconds: 10))) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        client.disconnect();
        await Future.delayed(const Duration(seconds: 1));
      }
    }();
  }

  static Future<StateMan> create(
      {required StateManConfig config,
      required KeyMappings keyMappings}) async {
    Uint8List? cert;
    Uint8List? key;
    MessageSecurityMode securityMode =
        MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE;
    // Example directory: /Users/jonb/Library/Containers/is.centroid.sildarvinnsla.skammtalina/Data/Documents/certs
    if (config.opcua.sslCert != null && config.opcua.sslKey != null) {
      print('path: ${config.opcua.sslCert!.path}');
      cert = await config.opcua.sslCert!.readAsBytes();
      key = await config.opcua.sslKey!.readAsBytes();
      securityMode = MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT;
    }
    String? username;
    String? password;
    if (config.opcua.username != null && config.opcua.password != null) {
      username = config.opcua.username;
      password = config.opcua.password;
    }
    final client = Client.fromStatic(
      username: username,
      password: password,
      certificate: cert,
      privateKey: key,
      securityMode: securityMode,
    );
    final stateMan =
        StateMan._(config: config, keyMappings: keyMappings, client: client);
    return stateMan;
  }

  /// Example: read("myKey")
  Future<DynamicValue> read(String key) async {
    await client.awaitConnect();
    try {
      final nodeId = lookupNodeId(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      return await client.read(nodeId);
    } catch (e) {
      throw StateManException('Failed to read key: \"$key\": $e');
    }
  }

  Future<Map<String, DynamicValue>> readMany(List<String> keys) async {
    await client.awaitConnect();

    final parameters = <NodeId, List<AttributeId>>{};
    for (final key in keys) {
      final nodeId = lookupNodeId(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      parameters[nodeId] = [
        AttributeId.UA_ATTRIBUTEID_DESCRIPTION,
        AttributeId.UA_ATTRIBUTEID_DISPLAYNAME,
        AttributeId.UA_ATTRIBUTEID_DATATYPE,
        AttributeId.UA_ATTRIBUTEID_VALUE,
      ];
    }
    final results = await client.readAttribute(parameters);

    return results
        .map((key, value) => MapEntry(keyMappings.lookupKey(key)!, value));
  }

  /// Example: write("myKey", DynamicValue(value: 42, typeId: NodeId.int16))
  Future<void> write(String key, DynamicValue value) async {
    await client.awaitConnect();
    try {
      final nodeId = lookupNodeId(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      await client.writeValue(nodeId, value);
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

  /// Initiate a collection of data from a node.
  /// The data is collected in a ring buffer and stored in RAM.
  /// Returns when the collection is started.
  Future<void> collect(String key, int collectSize) =>
      _collectorManager.collect(key, collectSize);

  /// Returns a Stream of the collected data.
  Stream<List<CollectedSample>> collectStream(String key) =>
      _collectorManager.collectStream(key);

  /// Stop a collection.
  void stopCollect(String key) => _collectorManager.stopCollect(key);

  List<String> get keys => keyMappings.keys.toList();

  /// Close the connection to the server.
  void close() {
    logger.d('Closing connection');
    client.disconnect();
    client.delete();
    _collectorManager.close();
    // Clean up subscriptions
    for (final entry in _subscriptions.values) {
      entry._rawSub.cancel();
      entry._subject.close();
    }
    _subscriptions.clear();
  }

  NodeId? lookupNodeId(String key) {
    final regex = RegExp(r'ns=(\d+);s=(.+)');
    final match = regex.firstMatch(key);
    NodeId? nodeId;
    if (match == null) {
      nodeId = keyMappings.lookup(key);
    } else {
      final namespace = int.parse(match.group(1)!);
      final identifier = match.group(2)!;
      nodeId = NodeId.fromString(namespace, identifier);
    }
    return nodeId;
  }

  Future<Stream<DynamicValue>> _monitor(String key) async {
    await client.awaitConnect();

    final nodeId = lookupNodeId(key);
    if (nodeId == null) {
      throw StateManException('Key: "$key" not found');
    }

    if (_subscriptions.containsKey(key) && _subscriptions[key]!.hasFirstValue) {
      return _subscriptions[key]!.stream;
    }

    while (true) {
      try {
        subscriptionId ??= await client.subscriptionCreate();
        final stream =
            client.monitor(nodeId, subscriptionId!).asBroadcastStream();

        // Create subscription first
        if (!_subscriptions.containsKey(key)) {
          _subscriptions[key] = _SubscriptionEntry(
            key,
            stream,
            (key) {
              _subscriptions.remove(key);
              logger.d('Unsubscribed from $key');
            },
          );
        }

        // Then test for first value
        await stream.first.timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            throw TimeoutException('No value received within 1 seconds');
          },
        );

        return _subscriptions[key]!.stream;
      } catch (e) {
        logger.w('Failed to get initial value for $key: $e');
        // Clean up the failed subscription
        _subscriptions[key]?._rawSub.cancel();
        _subscriptions[key]?._subject.close();
        _subscriptions.remove(key);
        continue;
      }
    }
  }
}

class _SubscriptionEntry {
  final String key;
  final ReplaySubject<DynamicValue> _subject;
  int _listenerCount = 0;
  Timer? _idleTimer;
  late final StreamSubscription<DynamicValue> _rawSub;
  final Function(String key) _onDispose;
  var _hasFirstValue = false;

  bool get hasFirstValue => _hasFirstValue;

  _SubscriptionEntry(this.key, Stream<DynamicValue> raw, this._onDispose)
      : _subject = ReplaySubject<DynamicValue>(maxSize: 1) {
    // 1) wire raw → subject
    _rawSub = raw.listen(
      (value) {
        _hasFirstValue = true;
        _subject.add(value);
      },
      onError: _subject.addError,
      onDone: _subject.close,
    );
    // 2) Count UI listeners for idle shutdown:
    _subject
      ..onListen = _handleListen
      ..onCancel = _handleCancel;
  }

  Stream<DynamicValue> get stream => _subject.stream;

  void _handleListen() {
    _listenerCount++;
    _idleTimer?.cancel();
  }

  void _handleCancel() {
    _listenerCount--;
    if (_listenerCount == 0) {
      _idleTimer = Timer(const Duration(minutes: 10), () {
        _rawSub.cancel(); // tear down the OPC-UA monitoredItem
        _onDispose(key); // remove from StateMan._subscriptions
        _subject.close(); // close the replay buffer
      });
    }
  }

  void addInactivityError() {
    _subject.addError(StateManException('Subscription inactive'));
  }
}

class CollectedSample {
  final DynamicValue value;
  final DateTime time;

  @override
  String toString() {
    return 'CollectedSample(value: $value, time: $time)';
  }

  CollectedSample(this.value, this.time);
}

class KeyCollectorManager {
  final Future<Stream<DynamicValue>> Function(String key) monitorFn;
  final Map<String, BehaviorSubject<List<CollectedSample>>> _collectors = {};
  final Map<String, RingBuffer<CollectedSample>> _buffers = {};
  final Map<String, StreamSubscription<DynamicValue>> _collectorSubs = {};

  KeyCollectorManager({required this.monitorFn});

  Future<void> collect(String key, int size) async {
    if (_collectors.containsKey(key)) {
      return;
    }

    final buffer = RingBuffer<CollectedSample>(size);
    final subject = BehaviorSubject<List<CollectedSample>>();

    final sub = await monitorFn(key);
    final subscription = sub.listen((value) {
      buffer.add(CollectedSample(DynamicValue.from(value), DateTime.now()));
      subject.add(buffer.toList());
    }, onError: (e, s) {
      // TODO: handle error, I think I dont care about this error
    });

    _collectors[key] = subject;
    _buffers[key] = buffer;
    _collectorSubs[key] = subscription;
  }

  Stream<List<CollectedSample>> collectStream(String key) {
    final subject = _collectors[key];
    if (subject == null) {
      throw StateManException('No collection started for key: $key');
    }
    return subject.stream;
  }

  void stopCollect(String key) {
    _collectorSubs[key]?.cancel();
    _collectors[key]?.close();
    _collectors.remove(key);
    _buffers.remove(key);
    _collectorSubs.remove(key);
  }

  void close() {
    for (final sub in _collectorSubs.values) {
      sub.cancel();
    }
    for (final subject in _collectors.values) {
      subject.close();
    }
    _collectorSubs.clear();
    _collectors.clear();
    _buffers.clear();
  }
}
