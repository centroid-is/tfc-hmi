import 'dart:async';
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart';
import 'package:rxdart/rxdart.dart';
part 'client.g.dart';

@JsonSerializable()
class OpcUAConfig {
  String endpoint = "opc.tcp://localhost:4840";
  String? username;
  String? password;

  OpcUAConfig();

  String toString() {
    return 'OpcUAConfig(endpoint: $endpoint, username: $username, password: $password)';
  }

  factory OpcUAConfig.fromJson(Map<String, dynamic> json) =>
      _$OpcUAConfigFromJson(json);
  Map<String, dynamic> toJson() => _$OpcUAConfigToJson(this);
}

@JsonSerializable()
class StateManConfig {
  OpcUAConfig opcua;

  StateManConfig({
    required this.opcua,
  });

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
    return NodeId.fromString(namespace, identifier);
  }

  factory NodeIdConfig.fromJson(Map<String, dynamic> json) =>
      _$NodeIdConfigFromJson(json);
  Map<String, dynamic> toJson() => _$NodeIdConfigToJson(this);
}

@JsonSerializable()
class KeyMappings {
  Map<String, NodeIdConfig> nodes;

  KeyMappings({required this.nodes});

  NodeId? lookup(String key) {
    return nodes[key]?.toNodeId();
  }

  factory KeyMappings.fromJson(Map<String, dynamic> json) {
    Map<String, NodeIdConfig> nodes = {};

    json.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        if (value['type'] == 'nodeId') {
          nodes[key] = NodeIdConfig.fromJson(value);
        } else {
          throw FormatException(
              'Unknown type or missing type field for key: $key');
        }
      } else {
        throw FormatException('Invalid value format for key: $key');
      }
    });

    return KeyMappings(nodes: nodes);
  }

  Map<String, dynamic> toJson() {
    return {
      for (var entry in nodes.entries)
        entry.key: {
          'type': 'nodeId',
          ...entry.value.toJson(),
        }
    };
  }
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
  final client = Client.fromStatic();
  int? subscriptionId;
  final Map<String, _SubscriptionEntry> _subscriptions = {};

  /// Constructor requires the server endpoint.
  StateMan({required this.config, required this.keyMappings}) {
    // spawn a background task to keep the client active
    () async {
      while (true) {
        client.connect(config.opcua.endpoint);
        while (client.runIterate(const Duration(milliseconds: 10))) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }();
  }

  /// Example: read("myKey")
  Future<DynamicValue> read(String key) async {
    await client.awaitConnect();
    try {
      final nodeId = keyMappings.lookup(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      return await client.readValue(nodeId, prefetchTypeId: true);
    } catch (e) {
      throw StateManException('Failed to read key: \"$key\": $e');
    }
  }

  /// Example: write("myKey", DynamicValue(value: 42, typeId: NodeId.int16))
  Future<void> write(String key, DynamicValue value) async {
    await client.awaitConnect();
    try {
      final nodeId = keyMappings.lookup(key);
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
    await client.awaitConnect();
    final nodeId = keyMappings.lookup(key);
    if (nodeId == null) {
      throw StateManException('Key: "$key" not found');
    }
    subscriptionId ??= await client.subscriptionCreate();
    if (!_subscriptions.containsKey(key)) {
      _subscriptions[key] = _SubscriptionEntry(
        key,
        client.monitoredItem(nodeId, subscriptionId!, prefetchTypeId: true),
        (key) {
          _subscriptions.remove(key);
          logger.d('Unsubscribed from $key');
        },
      );
    }
    return _subscriptions[key]!.stream;
  }

  void close() {
    logger.d('Closing connection');
    client.disconnect();
    client.delete();
  }
}

class _SubscriptionEntry {
  final String key;
  final ReplaySubject<DynamicValue> _subject;
  int _listenerCount = 0;
  Timer? _idleTimer;
  late final StreamSubscription<DynamicValue> _rawSub;
  final Function(String key) _onDispose;

  _SubscriptionEntry(
    this.key,
    Stream<DynamicValue> raw,
    this._onDispose,
  ) : _subject = ReplaySubject<DynamicValue>(maxSize: 1) {
    // 1) wire raw → subject
    _rawSub = raw.listen(
      _subject.add,
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
}
