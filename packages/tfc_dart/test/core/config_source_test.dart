import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/config_source.dart';
import 'package:tfc_dart/core/config_source_native.dart';

void main() {
  group('StateManConfig.fromString', () {
    test('parses valid JSON with mqtt config', () {
      final jsonStr = jsonEncode({
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
      });

      final config = StateManConfig.fromString(jsonStr);
      expect(config.opcua.length, 1);
      expect(config.mqtt.length, 1);
      expect(config.mqtt[0].host, 'broker.test');
      expect(config.mqtt[0].serverAlias, 'test-broker');
    });

    test('parses JSON with all protocol types', () {
      final jsonStr = jsonEncode({
        'opcua': [
          {'endpoint': 'opc.tcp://localhost:4840'}
        ],
        'jbtm': [],
        'modbus': [],
        'mqtt': [
          {'host': 'broker1.local', 'port': 1883, 'server_alias': 'b1'},
          {
            'host': 'broker2.local',
            'port': 8883,
            'server_alias': 'b2',
            'use_tls': true,
          },
        ],
      });

      final config = StateManConfig.fromString(jsonStr);
      expect(config.mqtt.length, 2);
      expect(config.mqtt[0].serverAlias, 'b1');
      expect(config.mqtt[1].useTls, true);
    });
  });

  group('KeyMappings.fromString', () {
    test('parses valid JSON with mqtt_node entries', () {
      final jsonStr = jsonEncode({
        'nodes': {
          'sensor.temperature': {
            'mqtt_node': {
              'topic': 'plant/sensor/temperature',
              'qos': 0,
              'server_alias': 'broker1',
              'payload_type': 'json',
            },
          },
          'actuator.valve': {
            'mqtt_node': {
              'topic': 'plant/actuator/valve',
              'qos': 1,
              'server_alias': 'broker1',
              'payload_type': 'json',
            },
          },
        },
      });

      final mappings = KeyMappings.fromString(jsonStr);
      expect(mappings.nodes.length, 2);
      expect(mappings.nodes['sensor.temperature']?.mqttNode?.topic,
          'plant/sensor/temperature');
      expect(mappings.nodes['actuator.valve']?.mqttNode?.qos, 1);
      expect(mappings.nodes['sensor.temperature']?.mqttNode?.serverAlias,
          'broker1');
    });

    test('parses JSON with mixed protocol entries', () {
      final jsonStr = jsonEncode({
        'nodes': {
          'opcKey': {
            'opcua_node': {'namespace': 2, 'identifier': 'test'},
          },
          'mqttKey': {
            'mqtt_node': {
              'topic': 'plant/temp',
              'qos': 0,
              'server_alias': 'broker1',
            },
          },
        },
      });

      final mappings = KeyMappings.fromString(jsonStr);
      expect(mappings.nodes.length, 2);
      expect(mappings.nodes['opcKey']?.opcuaNode, isNotNull);
      expect(mappings.nodes['mqttKey']?.mqttNode, isNotNull);
    });
  });

  group('StateManConfig.fromString — malformed JSON', () {
    test('throws FormatException on invalid JSON', () {
      expect(
        () => StateManConfig.fromString('not valid json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on truncated JSON', () {
      expect(
        () => StateManConfig.fromString('{"opcua": ['),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('KeyMappings.fromString — malformed JSON', () {
    test('throws FormatException on invalid JSON', () {
      expect(
        () => KeyMappings.fromString('not valid json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on truncated JSON', () {
      expect(
        () => KeyMappings.fromString('{"nodes": {'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('KeyMappings.fromFile', () {
    test('reads JSON from temp file and parses correctly', () async {
      final tempDir = Directory.systemTemp.createTempSync('km_fromfile_test_');
      try {
        final file = File('${tempDir.path}/keymappings.json');
        await file.writeAsString(jsonEncode({
          'nodes': {
            'sensor.temp': {
              'mqtt_node': {
                'topic': 'plant/temp',
                'qos': 0,
                'server_alias': 'broker1',
              },
            },
          },
        }));

        final mappings = await KeyMappings.fromFile(file.path);
        expect(mappings.nodes.length, 1);
        expect(mappings.nodes['sensor.temp']?.mqttNode?.topic, 'plant/temp');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('throws on missing file', () async {
      expect(
        () => KeyMappings.fromFile('/nonexistent/path/keymappings.json'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('not found'),
        )),
      );
    });

    test('throws with file path context on malformed JSON', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('km_malformed_test_');
      try {
        final file = File('${tempDir.path}/keymappings.json');
        await file.writeAsString('not valid json');

        await expectLater(
          KeyMappings.fromFile(file.path),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('Invalid JSON'), contains(file.path)),
          )),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('StaticConfig.fromStrings', () {
    test('creates valid StaticConfig from raw JSON', () {
      final configJson = jsonEncode({
        'opcua': [],
        'mqtt': [
          {
            'host': 'broker.local',
            'port': 1883,
            'server_alias': 'broker1',
          },
        ],
      });
      final keyMappingsJson = jsonEncode({
        'nodes': {
          'sensor.temp': {
            'mqtt_node': {
              'topic': 'plant/temp',
              'qos': 0,
              'server_alias': 'broker1',
            },
          },
        },
      });
      final pageEditorJson = '{"pages": []}';

      final staticConfig = StaticConfig.fromStrings(
        configJson: configJson,
        keyMappingsJson: keyMappingsJson,
        pageEditorJson: pageEditorJson,
      );

      expect(staticConfig.stateManConfig.mqtt.length, 1);
      expect(staticConfig.stateManConfig.mqtt[0].host, 'broker.local');
      expect(staticConfig.keyMappings.nodes.length, 1);
      expect(staticConfig.keyMappings.nodes['sensor.temp']?.mqttNode?.topic,
          'plant/temp');
      expect(staticConfig.pageEditorJson, pageEditorJson);
    });

    test('works without pageEditorJson', () {
      final configJson = jsonEncode({
        'opcua': [],
        'mqtt': [
          {'host': 'broker.local', 'port': 1883},
        ],
      });
      final keyMappingsJson = jsonEncode({
        'nodes': {
          'key1': {
            'mqtt_node': {'topic': 'plant/temp', 'qos': 0},
          },
        },
      });

      final staticConfig = StaticConfig.fromStrings(
        configJson: configJson,
        keyMappingsJson: keyMappingsJson,
      );

      expect(staticConfig.pageEditorJson, isNull);
      expect(staticConfig.stateManConfig.mqtt.length, 1);
      expect(staticConfig.keyMappings.nodes.length, 1);
    });
  });

  group('staticConfigFromDirectory', () {
    test('loads all 3 files from temp directory', () async {
      final tempDir = Directory.systemTemp.createTempSync('static_cfg_test_');
      try {
        await File('${tempDir.path}/config.json').writeAsString(jsonEncode({
          'opcua': [],
          'mqtt': [
            {
              'host': 'broker.local',
              'port': 1883,
              'server_alias': 'broker1',
            },
          ],
        }));
        await File('${tempDir.path}/keymappings.json')
            .writeAsString(jsonEncode({
          'nodes': {
            'sensor.temp': {
              'mqtt_node': {
                'topic': 'plant/temp',
                'qos': 0,
                'server_alias': 'broker1',
              },
            },
          },
        }));
        await File('${tempDir.path}/page-editor.json')
            .writeAsString('{"pages": [{"name": "home"}]}');

        final staticConfig =
            await staticConfigFromDirectory(tempDir.path);

        expect(staticConfig.stateManConfig.mqtt.length, 1);
        expect(staticConfig.stateManConfig.mqtt[0].host, 'broker.local');
        expect(staticConfig.stateManConfig.mqtt[0].serverAlias, 'broker1');
        expect(staticConfig.keyMappings.nodes.length, 1);
        expect(
          staticConfig.keyMappings.nodes['sensor.temp']?.mqttNode?.topic,
          'plant/temp',
        );
        expect(staticConfig.pageEditorJson, contains('home'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('works when page-editor.json is missing (optional)', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('static_cfg_nopage_test_');
      try {
        await File('${tempDir.path}/config.json').writeAsString(jsonEncode({
          'opcua': [],
          'mqtt': [
            {'host': 'broker.local', 'port': 1883},
          ],
        }));
        await File('${tempDir.path}/keymappings.json')
            .writeAsString(jsonEncode({
          'nodes': {
            'key1': {
              'mqtt_node': {'topic': 'test/topic', 'qos': 0},
            },
          },
        }));

        final staticConfig =
            await staticConfigFromDirectory(tempDir.path);

        expect(staticConfig.stateManConfig.mqtt.length, 1);
        expect(staticConfig.keyMappings.nodes.length, 1);
        expect(staticConfig.pageEditorJson, isNull);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('stateManConfig.mqtt is populated correctly', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('static_cfg_mqtt_test_');
      try {
        await File('${tempDir.path}/config.json').writeAsString(jsonEncode({
          'opcua': [],
          'mqtt': [
            {
              'host': 'broker1.local',
              'port': 1883,
              'server_alias': 'b1',
              'use_web_socket': false,
            },
            {
              'host': 'broker2.local',
              'port': 9001,
              'server_alias': 'b2',
              'use_web_socket': true,
              'ws_path': '/mqtt',
            },
          ],
        }));
        await File('${tempDir.path}/keymappings.json')
            .writeAsString(jsonEncode({'nodes': {}}));

        final staticConfig =
            await staticConfigFromDirectory(tempDir.path);

        expect(staticConfig.stateManConfig.mqtt.length, 2);
        expect(staticConfig.stateManConfig.mqtt[0].host, 'broker1.local');
        expect(staticConfig.stateManConfig.mqtt[0].useWebSocket, false);
        expect(staticConfig.stateManConfig.mqtt[1].host, 'broker2.local');
        expect(staticConfig.stateManConfig.mqtt[1].useWebSocket, true);
        expect(staticConfig.stateManConfig.mqtt[1].wsPath, '/mqtt');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('throws when config.json is missing', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('static_cfg_noconf_test_');
      try {
        // Only create keymappings.json, not config.json
        await File('${tempDir.path}/keymappings.json')
            .writeAsString(jsonEncode({'nodes': {}}));

        await expectLater(
          staticConfigFromDirectory(tempDir.path),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not found'),
          )),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('throws when keymappings.json is missing', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('static_cfg_nokm_test_');
      try {
        // Only create config.json, not keymappings.json
        await File('${tempDir.path}/config.json')
            .writeAsString(jsonEncode({'opcua': []}));

        await expectLater(
          staticConfigFromDirectory(tempDir.path),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('not found'),
          )),
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('keyMappings.nodes contains expected mqtt entries', () async {
      final tempDir =
          Directory.systemTemp.createTempSync('static_cfg_km_test_');
      try {
        await File('${tempDir.path}/config.json')
            .writeAsString(jsonEncode({'opcua': []}));
        await File('${tempDir.path}/keymappings.json')
            .writeAsString(jsonEncode({
          'nodes': {
            'sensor.temperature': {
              'mqtt_node': {
                'topic': 'plant/sensor/temperature',
                'qos': 0,
                'server_alias': 'broker1',
                'payload_type': 'json',
              },
            },
            'actuator.valve': {
              'mqtt_node': {
                'topic': 'plant/actuator/valve',
                'qos': 1,
                'server_alias': 'broker1',
                'payload_type': 'json',
              },
            },
          },
        }));

        final staticConfig =
            await staticConfigFromDirectory(tempDir.path);

        final nodes = staticConfig.keyMappings.nodes;
        expect(nodes.containsKey('sensor.temperature'), isTrue);
        expect(nodes.containsKey('actuator.valve'), isTrue);
        expect(nodes['sensor.temperature']!.mqttNode!.topic,
            'plant/sensor/temperature');
        expect(nodes['actuator.valve']!.mqttNode!.qos, 1);
        expect(nodes['sensor.temperature']!.mqttNode!.serverAlias, 'broker1');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
