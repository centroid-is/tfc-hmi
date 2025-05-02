import 'dart:async';
import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart';

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
    try {
      final nodeId = keyMappings.lookup(key);
      if (nodeId == null) {
        await Future.delayed(const Duration(seconds: 1000));
        throw StateManException("Key: \"$key\" not found");
      }
      subscriptionId ??= await client.subscriptionCreate();
      return client.monitoredItem(nodeId, subscriptionId!,
          prefetchTypeId: true);
    } catch (e) {
      logger.e('Failed to subscribe: $e, retrying in 1 second');
      await Future.delayed(const Duration(seconds: 1));
      return subscribe(key);
    }
  }

  void close() {
    logger.d('Closing connection');
    client.disconnect();
    client.delete();
  }
}
