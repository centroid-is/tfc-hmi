import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_dart/core/state_man.dart';

void main() {
  group('MqttPayloadType', () {
    test('enum serializes as string', () {
      // MqttPayloadType values should serialize as their name strings
      expect(MqttPayloadType.json.name, 'json');
      expect(MqttPayloadType.raw.name, 'raw');
      expect(MqttPayloadType.string.name, 'string');
    });

    test('round-trips through MqttNodeConfig JSON', () {
      for (final pt in MqttPayloadType.values) {
        final node = MqttNodeConfig(
          topic: 'test/topic',
          payloadType: pt,
        );
        final json = node.toJson();
        final restored = MqttNodeConfig.fromJson(json);
        expect(restored.payloadType, pt,
            reason: 'Failed round-trip for ${pt.name}');
      }
    });
  });

  group('MqttConfig', () {
    test('JSON round-trip with all fields populated', () {
      final config = MqttConfig(
        host: '10.0.0.1',
        port: 8883,
        serverAlias: 'broker1',
        useTls: true,
        useWebSocket: true,
        wsPath: '/ws',
        username: 'admin',
        password: 'secret',
        clientId: 'hmi-001',
        keepAlivePeriod: 30,
      );
      final json = config.toJson();
      expect(json, containsPair('host', '10.0.0.1'));
      expect(json, containsPair('port', 8883));
      expect(json, containsPair('server_alias', 'broker1'));
      expect(json, containsPair('use_tls', true));
      expect(json, containsPair('use_web_socket', true));
      expect(json, containsPair('ws_path', '/ws'));
      expect(json, containsPair('username', 'admin'));
      expect(json, containsPair('password', 'secret'));
      expect(json, containsPair('client_id', 'hmi-001'));
      expect(json, containsPair('keep_alive_period', 30));

      final restored = MqttConfig.fromJson(json);
      expect(restored.host, '10.0.0.1');
      expect(restored.port, 8883);
      expect(restored.serverAlias, 'broker1');
      expect(restored.useTls, true);
      expect(restored.useWebSocket, true);
      expect(restored.wsPath, '/ws');
      expect(restored.username, 'admin');
      expect(restored.password, 'secret');
      expect(restored.clientId, 'hmi-001');
      expect(restored.keepAlivePeriod, 30);
    });

    test('JSON round-trip with only defaults (just host)', () {
      final json = {'host': 'broker.local'};
      final config = MqttConfig.fromJson(json);
      expect(config.host, 'broker.local');
      expect(config.port, 1883);
      expect(config.serverAlias, isNull);
      expect(config.useTls, false);
      expect(config.useWebSocket, false);
      expect(config.wsPath, '/mqtt');
      expect(config.username, isNull);
      expect(config.password, isNull);
      expect(config.clientId, isNull);
      expect(config.keepAlivePeriod, 60);

      // Round-trip back
      final restored = MqttConfig.fromJson(config.toJson());
      expect(restored.host, 'broker.local');
      expect(restored.port, 1883);
    });

    test('defaults: host empty, port 1883, useTls false', () {
      final config = MqttConfig();
      expect(config.host, '');
      expect(config.port, 1883);
      expect(config.useTls, false);
      expect(config.useWebSocket, false);
      expect(config.wsPath, '/mqtt');
      expect(config.keepAlivePeriod, 60);
    });

    test('toString includes key fields', () {
      final config = MqttConfig(host: 'broker.local', port: 1883, serverAlias: 'b1');
      final s = config.toString();
      expect(s, contains('broker.local'));
      expect(s, contains('1883'));
      expect(s, contains('b1'));
    });
  });

  group('MqttNodeConfig', () {
    test('JSON round-trip with all fields', () {
      final node = MqttNodeConfig(
        topic: 'plant/line1/motor1/speed',
        qos: 1,
        serverAlias: 'broker1',
        payloadType: MqttPayloadType.raw,
      );
      final json = node.toJson();
      expect(json, containsPair('topic', 'plant/line1/motor1/speed'));
      expect(json, containsPair('qos', 1));
      expect(json, containsPair('server_alias', 'broker1'));
      expect(json, containsPair('payload_type', 'raw'));

      final restored = MqttNodeConfig.fromJson(json);
      expect(restored.topic, 'plant/line1/motor1/speed');
      expect(restored.qos, 1);
      expect(restored.serverAlias, 'broker1');
      expect(restored.payloadType, MqttPayloadType.raw);
    });

    test('defaults: qos 0, payloadType json', () {
      final node = MqttNodeConfig(topic: 'test/topic');
      expect(node.qos, 0);
      expect(node.payloadType, MqttPayloadType.json);
      expect(node.serverAlias, isNull);
    });

    test('fromJson with minimal JSON applies defaults', () {
      final node = MqttNodeConfig.fromJson({'topic': 'x'});
      expect(node.topic, 'x');
      expect(node.qos, 0);
      expect(node.payloadType, MqttPayloadType.json);
      expect(node.serverAlias, isNull);
    });

    test('toString includes topic', () {
      final node = MqttNodeConfig(topic: 'a/b/c', serverAlias: 'broker1');
      final s = node.toString();
      expect(s, contains('a/b/c'));
      expect(s, contains('broker1'));
    });
  });

  group('KeyMappingEntry with mqttNode', () {
    test('serializes correctly alongside opcuaNode', () {
      final entry = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'test')
          ..serverAlias = 'opcServer',
        mqttNode: MqttNodeConfig(
          topic: 'plant/temp',
          qos: 1,
          serverAlias: 'broker1',
        ),
      );
      final json = entry.toJson();
      expect(json, contains('opcua_node'));
      expect(json, contains('mqtt_node'));
      expect(json['mqtt_node'], isNotNull);
      expect(json['mqtt_node']['topic'], 'plant/temp');

      final restored = KeyMappingEntry.fromJson(json);
      expect(restored.opcuaNode, isNotNull);
      expect(restored.mqttNode, isNotNull);
      expect(restored.mqttNode!.topic, 'plant/temp');
      expect(restored.mqttNode!.qos, 1);
      expect(restored.mqttNode!.serverAlias, 'broker1');
    });

    test('server returns mqttNode.serverAlias when others are null', () {
      final entry = KeyMappingEntry(
        mqttNode: MqttNodeConfig(
          topic: 'plant/temp',
          serverAlias: 'broker1',
        ),
      );
      expect(entry.server, 'broker1');
    });

    test('server returns opcuaNode.serverAlias when both exist (opcua precedence)', () {
      final entry = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'test')
          ..serverAlias = 'opcServer',
        mqttNode: MqttNodeConfig(
          topic: 'plant/temp',
          serverAlias: 'broker1',
        ),
      );
      expect(entry.server, 'opcServer');
    });

    test('copyWith preserves mqttNode', () {
      final original = KeyMappingEntry(
        mqttNode: MqttNodeConfig(
          topic: 'plant/temp',
          serverAlias: 'broker1',
        ),
      );
      final copied = original.copyWith(
        opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'new'),
      );
      expect(copied.mqttNode, isNotNull);
      expect(copied.mqttNode!.topic, 'plant/temp');
      expect(copied.mqttNode!.serverAlias, 'broker1');
      expect(copied.opcuaNode, isNotNull);
    });

    test('copyWith replaces mqttNode when provided', () {
      final original = KeyMappingEntry(
        mqttNode: MqttNodeConfig(
          topic: 'plant/temp',
          serverAlias: 'broker1',
        ),
      );
      final newNode = MqttNodeConfig(
        topic: 'plant/pressure',
        serverAlias: 'broker2',
      );
      final copied = original.copyWith(mqttNode: newNode);
      expect(copied.mqttNode!.topic, 'plant/pressure');
      expect(copied.mqttNode!.serverAlias, 'broker2');
    });

    test('toString includes mqttNode', () {
      final entry = KeyMappingEntry(
        mqttNode: MqttNodeConfig(
          topic: 'plant/temp',
          serverAlias: 'broker1',
        ),
      );
      final s = entry.toString();
      expect(s, contains('mqttNode'));
    });
  });

  group('StateManConfig with mqtt', () {
    test('serializes with mqtt list', () {
      final config = StateManConfig(
        opcua: [OpcUAConfig()],
        mqtt: [
          MqttConfig(
            host: 'broker.local',
            port: 1883,
            serverAlias: 'broker1',
          ),
        ],
      );
      final json = config.toJson();
      expect(json, contains('mqtt'));
      expect((json['mqtt'] as List).length, 1);
      expect((json['mqtt'] as List)[0]['host'], 'broker.local');
    });

    test('empty mqtt list defaults correctly', () {
      final json = {
        'opcua': [
          {'endpoint': 'opc.tcp://localhost:4840'}
        ]
      };
      final config = StateManConfig.fromJson(json);
      expect(config.mqtt, isEmpty);
      expect(config.opcua, isNotEmpty);
    });

    test('round-trips with opcua + mqtt', () {
      final original = StateManConfig(
        opcua: [OpcUAConfig()],
        mqtt: [
          MqttConfig(
            host: 'broker1.local',
            port: 1883,
            serverAlias: 'b1',
          ),
          MqttConfig(
            host: 'broker2.local',
            port: 8883,
            serverAlias: 'b2',
            useTls: true,
          ),
        ],
      );
      final restored = StateManConfig.fromJson(original.toJson());
      expect(restored.mqtt.length, 2);
      expect(restored.mqtt[0].host, 'broker1.local');
      expect(restored.mqtt[0].serverAlias, 'b1');
      expect(restored.mqtt[1].host, 'broker2.local');
      expect(restored.mqtt[1].useTls, true);
    });

    test('toString includes mqtt', () {
      final config = StateManConfig(
        opcua: [OpcUAConfig()],
        mqtt: [MqttConfig(host: 'broker.local')],
      );
      final s = config.toString();
      expect(s, contains('mqtt'));
    });

    test('fromFile works with mqtt config', () async {
      final tempDir = Directory.systemTemp.createTempSync('mqtt_config_test_');
      try {
        final configFile = File('${tempDir.path}/config.json');
        final configJson = {
          'opcua': [
            {'endpoint': 'opc.tcp://localhost:4840'}
          ],
          'mqtt': [
            {
              'host': 'broker.test',
              'port': 1883,
              'server_alias': 'test-broker',
            }
          ],
        };
        await configFile.writeAsString(jsonEncode(configJson));

        final config = await StateManConfig.fromFile(configFile.path);
        expect(config.opcua.length, 1);
        expect(config.mqtt.length, 1);
        expect(config.mqtt[0].host, 'broker.test');
        expect(config.mqtt[0].serverAlias, 'test-broker');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('KeyMappings with MQTT entries', () {
    test('lookupServerAlias returns correct alias for MQTT keys', () {
      final mappings = KeyMappings(nodes: {
        'mqttTemp': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'plant/temp',
            serverAlias: 'broker1',
          ),
        ),
      });
      expect(mappings.lookupServerAlias('mqttTemp'), 'broker1');
    });

    test('filterByServer filters MQTT entries correctly', () {
      final mappings = KeyMappings(nodes: {
        'mqttTemp': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'plant/temp',
            serverAlias: 'broker1',
          ),
        ),
        'mqttPressure': KeyMappingEntry(
          mqttNode: MqttNodeConfig(
            topic: 'plant/pressure',
            serverAlias: 'broker2',
          ),
        ),
        'opcKey': KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'test')
            ..serverAlias = 'opcServer',
        ),
      });
      final broker1Only = mappings.filterByServer('broker1');
      expect(broker1Only.nodes.length, 1);
      expect(broker1Only.nodes.containsKey('mqttTemp'), isTrue);
    });
  });

  group('Regression: existing protocols unaffected by mqtt additions', () {
    test('OPC UA config JSON round-trips unchanged', () {
      final opcConfig = OpcUAConfig()
        ..endpoint = 'opc.tcp://10.0.0.1:4840'
        ..username = 'admin'
        ..password = 'secret'
        ..serverAlias = 'myOpc';

      final json = opcConfig.toJson();
      final restored = OpcUAConfig.fromJson(json);
      expect(restored.endpoint, 'opc.tcp://10.0.0.1:4840');
      expect(restored.username, 'admin');
      expect(restored.password, 'secret');
      expect(restored.serverAlias, 'myOpc');
    });

    test('KeyMappingEntry with only opcuaNode still works (mqttNode is null)', () {
      final entry = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(namespace: 2, identifier: 'test')
          ..serverAlias = 'myOpc',
      );
      final json = entry.toJson();
      final restored = KeyMappingEntry.fromJson(json);
      expect(restored.opcuaNode, isNotNull);
      expect(restored.m2400Node, isNull);
      expect(restored.modbusNode, isNull);
      expect(restored.mqttNode, isNull);
      expect(restored.server, 'myOpc');
    });

    test('StateManConfig without mqtt key backward-compatible', () {
      final json = {
        'opcua': [
          {'endpoint': 'opc.tcp://localhost:4840'}
        ],
        'jbtm': [],
        'modbus': [],
      };
      final config = StateManConfig.fromJson(json);
      expect(config.opcua.length, 1);
      expect(config.jbtm, isEmpty);
      expect(config.modbus, isEmpty);
      expect(config.mqtt, isEmpty);
    });
  });
}
