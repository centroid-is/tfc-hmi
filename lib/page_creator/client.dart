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
  bool get isConnected => _connected;
  bool _connected = true; // todo implement

  /// Constructor requires the server endpoint.
  StateMan({required this.config, required this.keyMappings}) {
    // spawn a background thread to keep the client active
    () async {
      while (true) {
        logger.t("Connecting to server: ${config.opcua.endpoint}");
        var statusCode = client.connect(
          "opc.tcp://172.30.118.178:4840",
        );
        // Todo: listen to stream of something
        _connected = statusCode == UA_STATUSCODE_GOOD;
        if (statusCode != UA_STATUSCODE_GOOD) {
          logger.e("Not connected. retrying in 1 second");
        } else {
          break;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      () async {
        int subid = client.subscriptionCreate();
        var stream = client.monitoredItemStream(
            NodeId.fromString(4, "GVL_IO.domeLightGreen.i_xSignal"), subid);
        stream.listen((event) {
          print("the answer is ${event}");
        }).onDone(() {
          print("Done");
        });
      }();
      while (true) {
        print(
            "#############################running iterate#############################");
        client.runIterate(const Duration(milliseconds: 10));
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }();
  }

  /// Example: read("myKey")
  Future<DynamicValue> read(String key) async {
    if (!_connected) {
      throw StateManException('Not connected to server');
    }
    try {
      final nodeId = keyMappings.lookup(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      return await client.readValue(nodeId);
    } catch (e) {
      throw StateManException('Failed to read key: \"$key\": $e');
    }
  }

  /// Example: write("myKey", DynamicValue(value: 42, typeId: NodeId.int16))
  Future<void> write(String key, DynamicValue value) async {
    if (!_connected) {
      throw StateManException('Not connected to server');
    }
    try {
      final nodeId = keyMappings.lookup(key);
      if (nodeId == null) {
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
    if (!_connected) {
      throw StateManException(
          'Cannot subscribe to node. Not connected to server.');
    }
    try {
      final nodeId = keyMappings.lookup(key);
      if (nodeId == null) {
        throw StateManException("Key: \"$key\" not found");
      }
      // Todo the internals will be futures, but not at the moment
      // Enforce that this is a future
      await Future.delayed(const Duration(microseconds: 1));
      subscriptionId ??= client.subscriptionCreate();
      return client.monitoredItemStream(nodeId, subscriptionId!);
    } catch (e) {
      throw StateManException('Failed to subscribe: $e');
    }
  }

  void close() {
    logger.d('Closing connection');
    _connected = false;
    client.disconnect();
    client.delete();
  }
}
