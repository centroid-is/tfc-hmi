import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/config_source.dart';
import 'package:tfc_dart/core/config_source_native.dart';

/// Tests for the native config loader logic.
///
/// We can't set Platform.environment in tests, so we test the underlying
/// staticConfigFromDirectory function and verify the config_loader_native
/// module's structure. The provider integration (env var detection) is
/// validated via the web build + deployment tests.
void main() {
  group('config_loader native path (staticConfigFromDirectory)', () {
    test('loads StaticConfig from a directory with all files', () async {
      final tempDir = Directory.systemTemp.createTempSync('cfg_loader_test_');
      try {
        await File('${tempDir.path}/config.json').writeAsString(jsonEncode({
          'opcua': [],
          'mqtt': [
            {'host': 'broker.test', 'port': 1883, 'server_alias': 'test-b'},
          ],
        }));
        await File('${tempDir.path}/keymappings.json')
            .writeAsString(jsonEncode({
          'nodes': {
            'temp': {
              'mqtt_node': {
                'topic': 'plant/temp',
                'qos': 0,
                'server_alias': 'test-b',
              },
            },
          },
        }));
        await File('${tempDir.path}/page-editor.json')
            .writeAsString('{"pages": []}');

        final config = await staticConfigFromDirectory(tempDir.path);

        expect(config.stateManConfig.mqtt.length, 1);
        expect(config.stateManConfig.mqtt[0].host, 'broker.test');
        expect(config.keyMappings.nodes.containsKey('temp'), isTrue);
        expect(config.pageEditorJson, isNotNull);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('StaticConfig.fromStrings works correctly (web path)', () {
      final config = StaticConfig.fromStrings(
        configJson: jsonEncode({
          'opcua': [],
          'mqtt': [
            {
              'host': 'ws-broker.test',
              'port': 9001,
              'server_alias': 'ws-b',
              'use_web_socket': true,
              'ws_path': '/mqtt',
            },
          ],
        }),
        keyMappingsJson: jsonEncode({
          'nodes': {
            'sensor': {
              'mqtt_node': {
                'topic': 'plant/sensor',
                'qos': 1,
                'server_alias': 'ws-b',
              },
            },
          },
        }),
      );

      expect(config.stateManConfig.mqtt.length, 1);
      expect(config.stateManConfig.mqtt[0].useWebSocket, true);
      expect(config.stateManConfig.mqtt[0].wsPath, '/mqtt');
      expect(config.keyMappings.nodes['sensor']?.mqttNode?.topic,
          'plant/sensor');
      expect(config.pageEditorJson, isNull);
    });
  });
}
