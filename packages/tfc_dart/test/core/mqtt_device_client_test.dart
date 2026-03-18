import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:tfc_dart/core/dynamic_value.dart' show DynamicValue;
import 'package:tfc_dart/core/mqtt_device_client.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:test/test.dart';
import 'package:typed_data/typed_data.dart' as typed;

// ---------------------------------------------------------------------------
// FakeMqttClient — simulates MQTT message delivery without a real broker
// ---------------------------------------------------------------------------

class FakeMqttClient extends MqttClient {
  FakeMqttClient() : super('fake', 'fake_client') {
    // MqttClient subclass can access @protected field
    instantiationCorrect = true;
  }

  final _updatesController =
      StreamController<List<MqttReceivedMessage<MqttMessage>>>.broadcast();
  final subscribedTopics = <String>[];
  final publishedMessages =
      <({String topic, MqttQos qos, typed.Uint8Buffer payload})>[];
  bool shouldFailConnect = false;

  @override
  Stream<List<MqttReceivedMessage<MqttMessage>>>? get updates =>
      _updatesController.stream;

  @override
  Future<MqttClientConnectionStatus?> connect([
    String? username,
    String? password,
  ]) async {
    if (shouldFailConnect) {
      onDisconnected?.call();
      return MqttClientConnectionStatus()
        ..state = MqttConnectionState.disconnected;
    }
    onConnected?.call();
    return MqttClientConnectionStatus()
      ..state = MqttConnectionState.connected;
  }

  @override
  Subscription? subscribe(String topic, MqttQos qosLevel) {
    subscribedTopics.add(topic);
    return null;
  }

  @override
  int publishMessage(
    String topic,
    MqttQos qualityOfService,
    typed.Uint8Buffer data, {
    bool retain = false,
  }) {
    publishedMessages.add((topic: topic, qos: qualityOfService, payload: data));
    return publishedMessages.length;
  }

  @override
  void disconnect() {
    onDisconnected?.call();
  }

  /// Simulate receiving an MQTT message on a topic.
  void simulateMessage(String topic, List<int> payload) {
    final pubMsg = MqttPublishMessage();
    pubMsg.payload.message.addAll(payload);
    _updatesController
        .add([MqttReceivedMessage<MqttMessage>(topic, pubMsg)]);
  }

  Future<void> close() => _updatesController.close();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MqttDeviceClientAdapter', () {
    late MqttConfig config;
    late KeyMappings keyMappings;

    setUp(() {
      config = MqttConfig(
        host: 'localhost',
        port: 1883,
        serverAlias: 'broker1',
      );

      keyMappings = KeyMappings(nodes: {
        'temperature': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'sensors/temp',
            qos: 0,
            serverAlias: 'broker1',
            payloadType: MqttPayloadType.json,
          ),
        ),
        'pressure': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'sensors/pressure',
            qos: 1,
            serverAlias: 'broker1',
            payloadType: MqttPayloadType.json,
          ),
        ),
        'motor_speed': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'actuators/motor',
            qos: 0,
            serverAlias: 'other_broker',
            payloadType: MqttPayloadType.json,
          ),
        ),
        'status_text': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'status/text',
            qos: 0,
            serverAlias: 'broker1',
            payloadType: MqttPayloadType.string,
          ),
        ),
        'opcua_node': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 1, identifier: 'Temp'),
        ),
      });
    });

    // ----- subscribableKeys -----

    group('subscribableKeys', () {
      test('correctly filters by serverAlias', () {
        final adapter = MqttDeviceClientAdapter(config, keyMappings);
        expect(
          adapter.subscribableKeys,
          equals({'temperature', 'pressure', 'status_text'}),
        );
      });

      test('returns empty set when no mqtt_nodes match', () {
        final noMatchConfig = MqttConfig(
          host: 'localhost',
          serverAlias: 'nonexistent',
        );
        final adapter = MqttDeviceClientAdapter(noMatchConfig, keyMappings);
        expect(adapter.subscribableKeys, isEmpty);
      });

      test('matches when both config.serverAlias and mqttNode.serverAlias are null', () {
        final nullAliasConfig = MqttConfig(host: 'localhost');
        final nullAliasKeyMappings = KeyMappings(nodes: {
          'sensor': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'data/sensor',
              qos: 0,
              payloadType: MqttPayloadType.json,
            ),
          ),
          'other': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'data/other',
              qos: 0,
              serverAlias: 'broker1',
              payloadType: MqttPayloadType.json,
            ),
          ),
        });
        final adapter = MqttDeviceClientAdapter(nullAliasConfig, nullAliasKeyMappings);
        expect(adapter.subscribableKeys, equals({'sensor'}));
      });
    });

    // ----- canSubscribe -----

    group('canSubscribe', () {
      test('returns true for exact key match', () {
        final adapter = MqttDeviceClientAdapter(config, keyMappings);
        expect(adapter.canSubscribe('temperature'), isTrue);
        expect(adapter.canSubscribe('pressure'), isTrue);
      });

      test('returns true for dot-notation child key', () {
        final adapter = MqttDeviceClientAdapter(config, keyMappings);
        expect(adapter.canSubscribe('temperature.value'), isTrue);
        expect(adapter.canSubscribe('temperature.unit.celsius'), isTrue);
      });

      test('returns false for unknown key', () {
        final adapter = MqttDeviceClientAdapter(config, keyMappings);
        expect(adapter.canSubscribe('unknown_key'), isFalse);
        // motor_speed belongs to other_broker, not broker1
        expect(adapter.canSubscribe('motor_speed'), isFalse);
        // opcua_node has no mqttNode
        expect(adapter.canSubscribe('opcua_node'), isFalse);
      });
    });

    // ----- Payload parsing -----

    group('payload parsing', () {
      test('JSON payload produces correct DynamicValue int', () {
        final bytes = utf8.encode('42');
        final dv = parseMqttPayload(bytes, MqttPayloadType.json);
        expect(dv.isInteger, isTrue);
        expect(dv.value, equals(42));
      });

      test('JSON payload produces correct DynamicValue string', () {
        final bytes = utf8.encode('"hello"');
        final dv = parseMqttPayload(bytes, MqttPayloadType.json);
        expect(dv.isString, isTrue);
        expect(dv.value, equals('hello'));
      });

      test('JSON payload produces correct DynamicValue bool', () {
        final bytes = utf8.encode('true');
        final dv = parseMqttPayload(bytes, MqttPayloadType.json);
        expect(dv.isBoolean, isTrue);
        expect(dv.value, equals(true));
      });

      test('JSON payload produces correct DynamicValue nested object', () {
        final bytes = utf8.encode('{"temp": 42, "unit": "C"}');
        final dv = parseMqttPayload(bytes, MqttPayloadType.json);
        expect(dv.isObject, isTrue);
        final obj = dv.asObject;
        expect((obj['temp'] as DynamicValue).value, equals(42));
        expect((obj['unit'] as DynamicValue).value, equals('C'));
      });

      test('String payload produces DynamicValue string', () {
        final bytes = utf8.encode('hello world');
        final dv = parseMqttPayload(bytes, MqttPayloadType.string);
        expect(dv.isString, isTrue);
        expect(dv.value, equals('hello world'));
      });

      test('raw payload produces DynamicValue bytes', () {
        final bytes = [0x01, 0x02, 0x03];
        final dv = parseMqttPayload(bytes, MqttPayloadType.raw);
        expect(dv.value, equals([0x01, 0x02, 0x03]));
      });
    });

    // ----- read -----

    group('read', () {
      test('returns null before any subscribe', () {
        final adapter = MqttDeviceClientAdapter(config, keyMappings);
        expect(adapter.read('temperature'), isNull);
      });

      test('returns last value after subscribe receives data', () async {
        final fake = FakeMqttClient();
        final adapter = MqttDeviceClientAdapter(
          config,
          keyMappings,
          clientFactory: (_) => fake,
        );

        adapter.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final stream = adapter.subscribe('temperature');
        final completer = Completer<DynamicValue>();
        final sub = stream.listen((dv) {
          if (!completer.isCompleted) completer.complete(dv);
        });

        // Simulate MQTT message with JSON int payload
        fake.simulateMessage('sensors/temp', utf8.encode('42'));

        final dv =
            await completer.future.timeout(const Duration(seconds: 2));
        expect(dv.isInteger, isTrue);
        expect(dv.value, equals(42));

        // read() should return the cached value
        final cached = adapter.read('temperature');
        expect(cached, isNotNull);
        expect(cached!.value, equals(42));

        await sub.cancel();
        adapter.dispose();
        await fake.close();
      });
    });

    // ----- dot-notation subscribe -----

    group('dot-notation subscribe', () {
      test('subscribe with dot-path navigates JSON object', () async {
        final fake = FakeMqttClient();
        final adapter = MqttDeviceClientAdapter(
          config,
          keyMappings,
          clientFactory: (_) => fake,
        );

        adapter.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final stream = adapter.subscribe('temperature.value');
        final completer = Completer<DynamicValue>();
        final sub = stream.listen((dv) {
          if (!completer.isCompleted) completer.complete(dv);
        });

        // Simulate a JSON object message
        fake.simulateMessage(
          'sensors/temp',
          utf8.encode('{"value": 42, "unit": "C"}'),
        );

        final dv =
            await completer.future.timeout(const Duration(seconds: 2));
        expect(dv.isInteger, isTrue);
        expect(dv.value, equals(42));

        await sub.cancel();
        adapter.dispose();
        await fake.close();
      });
    });

    // ----- write -----

    group('write', () {
      test('serializes DynamicValue to JSON bytes', () async {
        final fake = FakeMqttClient();
        final adapter = MqttDeviceClientAdapter(
          config,
          keyMappings,
          clientFactory: (_) => fake,
        );

        adapter.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final dv = DynamicValue(value: 42);
        await adapter.write('temperature', dv);

        expect(fake.publishedMessages, hasLength(1));
        expect(fake.publishedMessages.first.topic, equals('sensors/temp'));
        // Payload should be JSON-encoded
        final payloadStr =
            utf8.decode(fake.publishedMessages.first.payload.toList());
        expect(payloadStr, equals('42'));

        adapter.dispose();
        await fake.close();
      });

      test('serializes DynamicValue as plain string for string payloadType', () async {
        final fake = FakeMqttClient();
        final adapter = MqttDeviceClientAdapter(
          config,
          keyMappings,
          clientFactory: (_) => fake,
        );

        adapter.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final dv = DynamicValue(value: 'hello world');
        await adapter.write('status_text', dv);

        expect(fake.publishedMessages, hasLength(1));
        final payloadStr =
            utf8.decode(fake.publishedMessages.first.payload.toList());
        expect(payloadStr, equals('hello world'));

        adapter.dispose();
        await fake.close();
      });

      test('serializes DynamicValue as raw bytes for raw payloadType', () async {
        final rawKeyMappings = KeyMappings(nodes: {
          'raw_sensor': KeyMappingEntry(
            mqttNode: MqttNodeConfig(
              topic: 'sensors/raw',
              qos: 0,
              serverAlias: 'broker1',
              payloadType: MqttPayloadType.raw,
            ),
          ),
        });
        final fake = FakeMqttClient();
        final adapter = MqttDeviceClientAdapter(
          config,
          rawKeyMappings,
          clientFactory: (_) => fake,
        );

        adapter.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        final dv = DynamicValue(value: [0x01, 0x02, 0x03]);
        await adapter.write('raw_sensor', dv);

        expect(fake.publishedMessages, hasLength(1));
        expect(
          fake.publishedMessages.first.payload.toList(),
          equals([0x01, 0x02, 0x03]),
        );

        adapter.dispose();
        await fake.close();
      });
    });

    // ----- connection status -----

    group('connection', () {
      test('connection status starts as disconnected', () {
        final adapter = MqttDeviceClientAdapter(config, keyMappings);
        expect(
          adapter.connectionStatus,
          equals(ConnectionStatus.disconnected),
        );
      });

      test('connection status changes on connect', () async {
        final fake = FakeMqttClient();
        final adapter = MqttDeviceClientAdapter(
          config,
          keyMappings,
          clientFactory: (_) => fake,
        );

        final statuses = <ConnectionStatus>[];
        final sub = adapter.connectionStream.listen(statuses.add);

        adapter.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(statuses, contains(ConnectionStatus.connected));
        expect(
          adapter.connectionStatus,
          equals(ConnectionStatus.connected),
        );

        await sub.cancel();
        adapter.dispose();
        await fake.close();
      });

      test('emits disconnected on connection failure', () async {
        final fake = FakeMqttClient()..shouldFailConnect = true;
        final adapter = MqttDeviceClientAdapter(
          config,
          keyMappings,
          clientFactory: (_) => fake,
        );

        final statuses = <ConnectionStatus>[];
        final sub = adapter.connectionStream.listen(statuses.add);

        adapter.connect();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(statuses, contains(ConnectionStatus.disconnected));
        expect(
          adapter.connectionStatus,
          equals(ConnectionStatus.disconnected),
        );

        await sub.cancel();
        adapter.dispose();
        await fake.close();
      });
    });
  });
}
