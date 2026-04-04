// Test C: Verify that every keymapping mqtt_node server_alias matches an
// MQTT config entry's server_alias in the web config files.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/state_man.dart';

void main() {
  group('Web config consistency', () {
    test('every keymapping server_alias matches an MQTT config entry', () {
      final configFile = File('centroid-hmi/web/config/config.json');
      final keyMappingsFile = File('centroid-hmi/web/config/keymappings.json');

      expect(configFile.existsSync(), isTrue,
          reason: 'web/config/config.json must exist');
      expect(keyMappingsFile.existsSync(), isTrue,
          reason: 'web/config/keymappings.json must exist');

      final configJson =
          jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      final keyMappings = KeyMappings.fromString(keyMappingsFile.readAsStringSync());

      // Collect all server_alias values from MQTT config entries
      final mqttConfigs = (configJson['mqtt'] as List<dynamic>?) ?? [];
      final mqttAliases = mqttConfigs
          .map((e) => (e as Map<String, dynamic>)['server_alias'] as String?)
          .whereType<String>()
          .toSet();

      expect(mqttAliases, isNotEmpty,
          reason: 'MQTT config must have at least one server_alias');

      // Check every keymapping mqtt_node has a matching server_alias
      for (final entry in keyMappings.nodes.entries) {
        final mqttNode = entry.value.mqttNode;
        if (mqttNode != null) {
          expect(mqttNode.serverAlias, isNotNull,
              reason: 'Key "${entry.key}" mqtt_node must have a server_alias');
          expect(mqttAliases, contains(mqttNode.serverAlias),
              reason:
                  'Key "${entry.key}" server_alias "${mqttNode.serverAlias}" '
                  'must match an MQTT config entry. Available: $mqttAliases');
        }
      }
    });
  });
}
