@Tags(['integration'])
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:tfc_dart/core/dynamic_value.dart' show DynamicValue;
import 'package:tfc_dart/core/mqtt_device_client.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:test/test.dart';
import 'package:typed_data/typed_data.dart' as typed;

import 'mosquitto_helpers.dart';

void main() {
  setUpAll(() async {
    await startMosquitto();
    await waitForMosquittoReady();
  });

  tearDownAll(() async {
    await stopMosquitto();
  });

  group('MQTT integration', () {
    // ---- Test: TCP connect to localhost:1883, verify connected status ----

    test('TCP connect to localhost:1883 and verify connected status', () async {
      final config = MqttConfig(
        host: 'localhost',
        port: 1883,
        serverAlias: 'test-broker',
        clientId: 'integration_connect_test',
        keepAlivePeriod: 10,
      );
      final keyMappings = KeyMappings(nodes: {});
      final adapter = MqttDeviceClientAdapter(config, keyMappings);

      final connected = Completer<void>();
      final sub = adapter.connectionStream.listen((status) {
        if (status == ConnectionStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      });

      adapter.connect();
      await connected.future.timeout(const Duration(seconds: 10));

      expect(adapter.connectionStatus, equals(ConnectionStatus.connected));

      await sub.cancel();
      adapter.dispose();
    });

    // ---- Test: Subscribe and receive JSON payload ----

    test(
        'subscribe to topic, publish JSON, verify DynamicValue received',
        () async {
      final config = MqttConfig(
        host: 'localhost',
        port: 1883,
        serverAlias: 'test-broker',
        clientId: 'integration_sub_test',
        keepAlivePeriod: 10,
      );
      final keyMappings = KeyMappings(nodes: {
        'temperature': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'test/sensor/temperature',
            qos: 0,
            serverAlias: 'test-broker',
            payloadType: MqttPayloadType.json,
          ),
        ),
      });

      final adapter = MqttDeviceClientAdapter(config, keyMappings);

      // Wait for connection
      final connected = Completer<void>();
      adapter.connectionStream.listen((status) {
        if (status == ConnectionStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      });
      adapter.connect();
      await connected.future.timeout(const Duration(seconds: 10));

      // Subscribe
      final stream = adapter.subscribe('temperature');
      final received = Completer<DynamicValue>();
      final sub = stream.listen((dv) {
        if (!received.isCompleted) received.complete(dv);
      });

      // Small delay to ensure subscription is active on broker
      await Future.delayed(const Duration(milliseconds: 500));

      // Publish via a second raw MQTT client
      final publisher = MqttServerClient.withPort('localhost', 'integration_pub_temp', 1883);
      publisher.keepAlivePeriod = 10;
      await publisher.connect();
      final payload = typed.Uint8Buffer()
        ..addAll(utf8.encode('{"value": 42.5}'));
      publisher.publishMessage(
          'test/sensor/temperature', MqttQos.atMostOnce, payload);

      final dv = await received.future.timeout(const Duration(seconds: 10));
      expect(dv.isObject, isTrue);
      final obj = dv.asObject;
      expect((obj['value'] as DynamicValue).asDouble, equals(42.5));

      await sub.cancel();
      adapter.dispose();
      publisher.disconnect();
    });

    // ---- Test: Write DynamicValue, verify message arrives ----

    test('write DynamicValue to topic, verify message arrives via second client',
        () async {
      final config = MqttConfig(
        host: 'localhost',
        port: 1883,
        serverAlias: 'test-broker',
        clientId: 'integration_write_test',
        keepAlivePeriod: 10,
      );
      final keyMappings = KeyMappings(nodes: {
        'valve': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'test/actuator/valve',
            qos: 0,
            serverAlias: 'test-broker',
            payloadType: MqttPayloadType.json,
          ),
        ),
      });

      final adapter = MqttDeviceClientAdapter(config, keyMappings);

      // Wait for connection
      final connected = Completer<void>();
      adapter.connectionStream.listen((status) {
        if (status == ConnectionStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      });
      adapter.connect();
      await connected.future.timeout(const Duration(seconds: 10));

      // Set up a second client to verify the message arrives
      final verifier =
          MqttServerClient.withPort('localhost', 'integration_verify_write', 1883);
      verifier.keepAlivePeriod = 10;
      await verifier.connect();
      verifier.subscribe('test/actuator/valve', MqttQos.atMostOnce);

      final received = Completer<String>();
      verifier.updates?.listen((messages) {
        for (final msg in messages) {
          final pubMsg = msg.payload as MqttPublishMessage;
          final payloadStr =
              utf8.decode(pubMsg.payload.message.toList());
          if (!received.isCompleted) received.complete(payloadStr);
        }
      });

      // Small delay to ensure verifier subscription is active
      await Future.delayed(const Duration(milliseconds: 500));

      // Write via adapter
      await adapter.write('valve', DynamicValue(value: 100));

      final payloadStr =
          await received.future.timeout(const Duration(seconds: 10));
      expect(payloadStr, equals('100'));

      adapter.dispose();
      verifier.disconnect();
    });

    // ---- Test: Disconnect and reconnect ----

    test('disconnect client, verify status, reconnect, verify reconnected',
        () async {
      final config = MqttConfig(
        host: 'localhost',
        port: 1883,
        serverAlias: 'test-broker',
        clientId: 'integration_reconnect_test',
        keepAlivePeriod: 10,
      );
      final keyMappings = KeyMappings(nodes: {});
      final adapter = MqttDeviceClientAdapter(config, keyMappings);

      // Connect
      final connected1 = Completer<void>();
      final sub = adapter.connectionStream.listen((status) {
        if (status == ConnectionStatus.connected && !connected1.isCompleted) {
          connected1.complete();
        }
      });
      adapter.connect();
      await connected1.future.timeout(const Duration(seconds: 10));
      expect(adapter.connectionStatus, equals(ConnectionStatus.connected));
      await sub.cancel();

      // Reconnect the same adapter — connect() internally disconnects first
      final disconnected = Completer<void>();
      final reconnected = Completer<void>();
      final sub2 = adapter.connectionStream
          .skip(1) // skip current BehaviorSubject value
          .listen((status) {
        if (status == ConnectionStatus.disconnected &&
            !disconnected.isCompleted) {
          disconnected.complete();
        }
        if (status == ConnectionStatus.connected &&
            !reconnected.isCompleted) {
          reconnected.complete();
        }
      });

      adapter.connect();

      // Verify disconnected status occurs during reconnection
      await disconnected.future.timeout(const Duration(seconds: 10));

      // Then verify reconnected
      await reconnected.future.timeout(const Duration(seconds: 10));
      expect(adapter.connectionStatus, equals(ConnectionStatus.connected));

      await sub2.cancel();
      adapter.dispose();
    });

    // ---- Test: WebSocket connect ----

    test('WebSocket connect to ws://localhost:9001/mqtt, subscribe and receive',
        () async {
      final config = MqttConfig(
        host: 'localhost',
        port: 9001,
        serverAlias: 'ws-broker',
        clientId: 'integration_ws_test',
        keepAlivePeriod: 10,
        useWebSocket: true,
        wsPath: '/mqtt',
      );
      final keyMappings = KeyMappings(nodes: {
        'ws_sensor': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'test/ws/sensor',
            qos: 0,
            serverAlias: 'ws-broker',
            payloadType: MqttPayloadType.json,
          ),
        ),
      });

      final adapter = MqttDeviceClientAdapter(config, keyMappings);

      // Wait for connection
      final connected = Completer<void>();
      adapter.connectionStream.listen((status) {
        if (status == ConnectionStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      });
      adapter.connect();
      await connected.future.timeout(const Duration(seconds: 10));
      expect(adapter.connectionStatus, equals(ConnectionStatus.connected));

      // Subscribe
      final stream = adapter.subscribe('ws_sensor');
      final received = Completer<DynamicValue>();
      final sub = stream.listen((dv) {
        if (!received.isCompleted) received.complete(dv);
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // Publish via TCP (cross-protocol: publish TCP, receive WS)
      final publisher =
          MqttServerClient.withPort('localhost', 'integration_ws_pub', 1883);
      publisher.keepAlivePeriod = 10;
      await publisher.connect();
      final payload = typed.Uint8Buffer()..addAll(utf8.encode('{"ws": true}'));
      publisher.publishMessage(
          'test/ws/sensor', MqttQos.atMostOnce, payload);

      final dv = await received.future.timeout(const Duration(seconds: 10));
      expect(dv.isObject, isTrue);
      expect((dv.asObject['ws'] as DynamicValue).asBool, isTrue);

      await sub.cancel();
      adapter.dispose();
      publisher.disconnect();
    });

    // ---- Test: Multiple keys on different topics ----

    test('multiple keys on different topics receive independent streams',
        () async {
      final config = MqttConfig(
        host: 'localhost',
        port: 1883,
        serverAlias: 'test-broker',
        clientId: 'integration_multi_test',
        keepAlivePeriod: 10,
      );
      final keyMappings = KeyMappings(nodes: {
        'sensor_a': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'test/multi/a',
            qos: 0,
            serverAlias: 'test-broker',
            payloadType: MqttPayloadType.json,
          ),
        ),
        'sensor_b': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'test/multi/b',
            qos: 0,
            serverAlias: 'test-broker',
            payloadType: MqttPayloadType.json,
          ),
        ),
      });

      final adapter = MqttDeviceClientAdapter(config, keyMappings);

      // Wait for connection
      final connected = Completer<void>();
      adapter.connectionStream.listen((status) {
        if (status == ConnectionStatus.connected && !connected.isCompleted) {
          connected.complete();
        }
      });
      adapter.connect();
      await connected.future.timeout(const Duration(seconds: 10));

      // Subscribe to both keys
      final streamA = adapter.subscribe('sensor_a');
      final streamB = adapter.subscribe('sensor_b');

      final receivedA = Completer<DynamicValue>();
      final receivedB = Completer<DynamicValue>();

      final subA = streamA.listen((dv) {
        if (!receivedA.isCompleted) receivedA.complete(dv);
      });
      final subB = streamB.listen((dv) {
        if (!receivedB.isCompleted) receivedB.complete(dv);
      });

      await Future.delayed(const Duration(milliseconds: 500));

      // Publish to both topics via a second client
      final publisher =
          MqttServerClient.withPort('localhost', 'integration_multi_pub', 1883);
      publisher.keepAlivePeriod = 10;
      await publisher.connect();

      final payloadA = typed.Uint8Buffer()..addAll(utf8.encode('111'));
      publisher.publishMessage(
          'test/multi/a', MqttQos.atMostOnce, payloadA);

      final payloadB = typed.Uint8Buffer()..addAll(utf8.encode('222'));
      publisher.publishMessage(
          'test/multi/b', MqttQos.atMostOnce, payloadB);

      final dvA = await receivedA.future.timeout(const Duration(seconds: 10));
      final dvB = await receivedB.future.timeout(const Duration(seconds: 10));

      expect(dvA.isInteger, isTrue);
      expect(dvA.value, equals(111));
      expect(dvB.isInteger, isTrue);
      expect(dvB.value, equals(222));

      await subA.cancel();
      await subB.cancel();
      adapter.dispose();
      publisher.disconnect();
    });
  });
}
