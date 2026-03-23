import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'dynamic_value.dart';
import 'package:rxdart/rxdart.dart';
import 'package:typed_data/typed_data.dart' as typed;

import 'mqtt_client_factory.dart' as factory_;
import 'state_man.dart';

/// Parse raw MQTT payload bytes into a [DynamicValue].
@visibleForTesting
DynamicValue parseMqttPayload(List<int> bytes, MqttPayloadType payloadType) {
  switch (payloadType) {
    case MqttPayloadType.json:
      final str = utf8.decode(bytes);
      final json = jsonDecode(str);
      return _dynamicValueFromJson(json);
    case MqttPayloadType.string:
      return DynamicValue(value: utf8.decode(bytes));
    case MqttPayloadType.raw:
      return DynamicValue(value: bytes);
  }
}

/// Recursively convert a decoded JSON value into a [DynamicValue].
DynamicValue _dynamicValueFromJson(dynamic json) {
  if (json == null) return DynamicValue();
  if (json is int) return DynamicValue(value: json);
  if (json is double) return DynamicValue(value: json);
  if (json is bool) return DynamicValue(value: json);
  if (json is String) return DynamicValue(value: json);
  if (json is Map<String, dynamic>) {
    final converted = LinkedHashMap<String, dynamic>.from(
      json.map((k, v) => MapEntry(k, _dynamicValueFromJson(v))),
    );
    return DynamicValue.fromMap(converted);
  }
  if (json is List) {
    return DynamicValue.fromList(json.map(_dynamicValueFromJson).toList());
  }
  return DynamicValue(value: json);
}

/// Serialize a [DynamicValue] to a JSON-compatible Dart object.
dynamic _dynamicValueToJson(DynamicValue dv) {
  if (dv.isNull) return null;
  if (dv.isInteger) return dv.asInt;
  if (dv.isDouble) return dv.asDouble;
  if (dv.isBoolean) return dv.asBool;
  if (dv.isString) return dv.asString;
  if (dv.isObject) {
    return dv.asObject.map(
      (k, v) => MapEntry(k, _dynamicValueToJson(v)),
    );
  }
  if (dv.isArray) {
    return dv.asArray.map((v) => _dynamicValueToJson(v)).toList();
  }
  return dv.value;
}

/// MQTT device client adapter implementing the [DeviceClient] interface.
///
/// Wraps an MQTT client and routes topic messages to keyed streams
/// using [KeyMappings] for topic-to-key resolution.
class MqttDeviceClientAdapter implements DeviceClient {
  final MqttConfig config;
  final KeyMappings keyMappings;

  /// Override for testing — replaces [createMqttClient] from the factory.
  @visibleForTesting
  final MqttClient Function(MqttConfig)? clientFactory;

  MqttClient? _client;
  final _connectionController =
      BehaviorSubject<ConnectionStatus>.seeded(ConnectionStatus.disconnected);
  final Map<String, BehaviorSubject<DynamicValue>> _topicStreams = {};
  final Map<String, DynamicValue> _lastValues = {};
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
      _updatesSubscription;

  /// Topics already subscribed on the MQTT client.
  final Set<String> _subscribedTopics = {};

  /// QoS level per topic, used for re-subscribing on (re)connect.
  final Map<String, MqttQos> _topicQos = {};

  /// Reverse lookup: MQTT topic → set of keymapping keys.
  final Map<String, Set<String>> _topicToKeys = {};

  MqttDeviceClientAdapter(
    this.config,
    this.keyMappings, {
    this.clientFactory,
  });

  @override
  Set<String> get subscribableKeys {
    return keyMappings.nodes.entries
        .where((e) =>
            e.value.mqttNode != null &&
            e.value.mqttNode!.serverAlias == config.serverAlias)
        .map((e) => e.key)
        .toSet();
  }

  @override
  bool canSubscribe(String key) {
    final keys = subscribableKeys;
    return keys.contains(key) || keys.any((k) => key.startsWith('$k.'));
  }

  @override
  Stream<DynamicValue> subscribe(String key) {
    // Resolve root key for dot-notation access
    final rootKey = _resolveRootKey(key);
    final mqttNode = keyMappings.nodes[rootKey]!.mqttNode!;

    _topicStreams.putIfAbsent(rootKey, () => BehaviorSubject<DynamicValue>());

    // Subscribe to MQTT topic if not already done
    if (!_subscribedTopics.contains(mqttNode.topic)) {
      final qos = MqttQos.values[mqttNode.qos];
      _topicQos[mqttNode.topic] = qos;
      // Register the topic BEFORE calling _client.subscribe() —
      // the library throws ConnectionException when not yet connected,
      // and we need the topic in _subscribedTopics so that onConnected
      // can re-subscribe it once the connection is established.
      _subscribedTopics.add(mqttNode.topic);
      try {
        _client?.subscribe(mqttNode.topic, qos);
      } catch (_) {
        // Will be (re-)subscribed in onConnected callback.
      }
    }

    // Register reverse lookup
    _topicToKeys.putIfAbsent(mqttNode.topic, () => {}).add(rootKey);

    if (key == rootKey) {
      return _topicStreams[rootKey]!.stream;
    }

    // Dot-notation: navigate the DynamicValue tree
    final subPath = key.substring(rootKey.length + 1).split('.');
    return _topicStreams[rootKey]!.stream.map((dv) => _navigatePath(dv, subPath));
  }

  @override
  DynamicValue? read(String key) => _lastValues[key];

  @override
  Future<void> write(String key, DynamicValue value) async {
    final rootKey = _resolveRootKey(key);
    final mqttNode = keyMappings.nodes[rootKey]!.mqttNode!;
    final typed.Uint8Buffer payload;
    switch (mqttNode.payloadType) {
      case MqttPayloadType.json:
        final jsonStr = jsonEncode(_dynamicValueToJson(value));
        payload = typed.Uint8Buffer()..addAll(utf8.encode(jsonStr));
      case MqttPayloadType.string:
        payload = typed.Uint8Buffer()
          ..addAll(utf8.encode(value.isString ? value.asString : value.value.toString()));
      case MqttPayloadType.raw:
        payload = typed.Uint8Buffer()..addAll(value.value as List<int>);
    }
    _client?.publishMessage(
      mqttNode.topic,
      MqttQos.values[mqttNode.qos],
      payload,
    );
  }

  @override
  ConnectionStatus get connectionStatus =>
      _connectionController.valueOrNull ?? ConnectionStatus.disconnected;

  @override
  Stream<ConnectionStatus> get connectionStream =>
      _connectionController.stream;

  @override
  void connect() {
    _connectAsync();
  }

  Future<void> _connectAsync() async {
    // Guard against double invocation — dispose old client first.
    if (_client != null) {
      _updatesSubscription?.cancel();
      _updatesSubscription = null;
      _client!.disconnect();
      _client = null;
    }

    _connectionController.add(ConnectionStatus.connecting);

    _client =
        clientFactory?.call(config) ?? factory_.createMqttClient(config);

    _client!.keepAlivePeriod = config.keepAlivePeriod;
    _client!.autoReconnect = true;
    _client!.onConnected = () {
      _connectionController.add(ConnectionStatus.connected);
      // Ensure the updates listener is active — onConnected may fire before
      // connect() returns, so we set it up here as well.
      if (_updatesSubscription == null) {
        _updatesSubscription = _client!.updates?.listen(_handleUpdates);
      }
      // Re-subscribe all topics that were registered before the connection
      // was established (subscribe() can be called before connect() completes
      // since connect() is fire-and-forget from StateMan.create).
      for (final topic in _subscribedTopics) {
        final qos = _topicQos[topic] ?? MqttQos.atMostOnce;
        _client?.subscribe(topic, qos);
      }
    };
    _client!.onDisconnected = () {
      _connectionController.add(ConnectionStatus.disconnected);
    };
    _client!.onAutoReconnect = () {
      _connectionController.add(ConnectionStatus.connecting);
    };
    _client!.onAutoReconnected = () {
      _connectionController.add(ConnectionStatus.connected);
    };

    if (config.username != null) {
      _client!.connectionMessage = MqttConnectMessage()
          .authenticateAs(config.username, config.password)
          .startClean();
    }

    try {
      final status =
          await _client!.connect(config.username, config.password);
      if (status?.state == MqttConnectionState.connected) {
        // Listen for incoming messages only on successful connect
        _updatesSubscription = _client!.updates?.listen(_handleUpdates);
      } else {
        _connectionController.add(ConnectionStatus.disconnected);
      }
    } catch (e) {
      _connectionController.add(ConnectionStatus.disconnected);
    }
  }

  void _handleUpdates(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final topic = msg.topic;
      final pubMsg = msg.payload as MqttPublishMessage;
      final payloadBytes = pubMsg.payload.message.toList();

      final keys = _topicToKeys[topic];
      if (keys == null) continue;

      for (final key in keys) {
        final mqttNode = keyMappings.nodes[key]?.mqttNode;
        if (mqttNode == null) continue;

        final dv = parseMqttPayload(payloadBytes, mqttNode.payloadType);
        _lastValues[key] = dv;
        _topicStreams[key]?.add(dv);
      }
    }
  }

  @override
  void dispose() {
    _updatesSubscription?.cancel();
    _client?.disconnect();
    for (final subject in _topicStreams.values) {
      subject.close();
    }
    _topicStreams.clear();
    _connectionController.close();
  }

  /// Resolve a possibly dot-notated key to its root key in subscribableKeys.
  String _resolveRootKey(String key) {
    if (keyMappings.nodes.containsKey(key) &&
        keyMappings.nodes[key]!.mqttNode != null) {
      return key;
    }
    for (final k in subscribableKeys) {
      if (key.startsWith('$k.')) return k;
    }
    throw ArgumentError('Cannot resolve MQTT key: $key');
  }

  /// Navigate a DynamicValue tree by dot-separated path segments.
  static DynamicValue _navigatePath(DynamicValue dv, List<String> path) {
    DynamicValue current = dv;
    for (final segment in path) {
      if (current.isObject) {
        final obj = current.asObject;
        final child = obj[segment];
        if (child == null) return DynamicValue();
        current = child;
      } else {
        return DynamicValue();
      }
    }
    return current;
  }
}
