import 'dart:convert';

import 'package:tfc_dart/core/dynamic_value.dart' show DynamicValue;
import 'package:test/test.dart';

import 'package:tfc_dart/core/config_source.dart';
import 'package:tfc_dart/core/state_man.dart';

/// Tests for the static config provider integration path.
///
/// These verify that when a StaticConfig is available, StateMan can be
/// created directly from it (bypassing preferences), with only MQTT
/// device clients — the same logic the stateManProvider will use when
/// staticConfigProvider returns non-null.
void main() {
  group('StateMan creation from StaticConfig', () {
    test('StateMan.create works with StaticConfig-sourced config', () async {
      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({
          'opcua': [],
          'mqtt': [
            {
              'host': 'broker.local',
              'port': 1883,
              'server_alias': 'broker1',
            },
          ],
        }),
        keyMappingsJson: jsonEncode({
          'nodes': {
            'sensor.temp': {
              'mqtt_node': {
                'topic': 'plant/temp',
                'qos': 0,
                'server_alias': 'broker1',
              },
            },
          },
        }),
      );

      // Create StateMan using static config (no preferences)
      final stateMan = await StateMan.create(
        config: staticConfig.stateManConfig,
        keyMappings: staticConfig.keyMappings,
        deviceClients: <DeviceClient>[], // No real clients in test
      );

      expect(stateMan, isNotNull);
      expect(stateMan.config.mqtt.length, 1);
      expect(stateMan.config.mqtt[0].host, 'broker.local');
      expect(stateMan.keyMappings.nodes.containsKey('sensor.temp'), isTrue);

      await stateMan.close();
    });

    test('StaticConfig-sourced keyMappings are used for routing', () async {
      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({
          'opcua': [],
          'mqtt': [
            {'host': 'broker.local', 'port': 1883, 'server_alias': 'b1'},
          ],
        }),
        keyMappingsJson: jsonEncode({
          'nodes': {
            'mqtt_sensor': {
              'mqtt_node': {
                'topic': 'plant/sensor',
                'qos': 0,
                'server_alias': 'b1',
              },
            },
          },
        }),
      );

      final mock = _MockDeviceClient(keys: {'mqtt_sensor'});
      final stateMan = await StateMan.create(
        config: staticConfig.stateManConfig,
        keyMappings: staticConfig.keyMappings,
        deviceClients: [mock],
      );

      mock.setCachedValue('mqtt_sensor', DynamicValue(value: 42.5));
      final value = await stateMan.read('mqtt_sensor');
      expect(value.value, 42.5);

      await stateMan.close();
    });

    test('StaticConfig without pageEditorJson has null', () {
      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({'opcua': []}),
        keyMappingsJson: jsonEncode({'nodes': {}}),
      );
      expect(staticConfig.pageEditorJson, isNull);
    });

    test('StaticConfig with pageEditorJson preserves it', () {
      final pageJson = jsonEncode({
        '/': {
          'menu_item': {
            'label': 'Home',
            'path': '/',
            'icon': 'home',
            'children': []
          },
          'assets': [],
          'mirroring_disabled': false,
        }
      });

      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({'opcua': []}),
        keyMappingsJson: jsonEncode({'nodes': {}}),
        pageEditorJson: pageJson,
      );
      expect(staticConfig.pageEditorJson, pageJson);
    });

    test('static config creates StateMan with only MQTT clients (no OPC UA)', () async {
      // On the static config / web path, the provider creates only MQTT
      // device clients and passes them in — OPC UA list may still be in
      // the config JSON but no OPC UA DeviceClients are created.
      final staticConfig = StaticConfig.fromStrings(
        configJson: jsonEncode({
          'opcua': [], // empty — provider won't create OPC UA clients
          'mqtt': [
            {'host': 'broker.local', 'port': 1883, 'server_alias': 'b1'},
          ],
        }),
        keyMappingsJson: jsonEncode({
          'nodes': {
            'mqtt_key': {
              'mqtt_node': {
                'topic': 'plant/key',
                'qos': 0,
                'server_alias': 'b1',
              },
            },
          },
        }),
      );

      // Only MQTT device clients — no OPC UA, no M2400, no Modbus
      final mqttMock = _MockDeviceClient(keys: {'mqtt_key'});
      final stateMan = await StateMan.create(
        config: staticConfig.stateManConfig,
        keyMappings: staticConfig.keyMappings,
        deviceClients: [mqttMock], // Only MQTT
      );

      // The StateMan has only the MQTT mock as device client
      expect(stateMan.deviceClients.length, 1);
      expect(stateMan.deviceClients[0], same(mqttMock));

      await stateMan.close();
    });
  });
}

/// Minimal mock DeviceClient for testing.
class _MockDeviceClient implements DeviceClient {
  @override
  final Set<String> subscribableKeys;
  final Map<String, DynamicValue> _values = {};

  _MockDeviceClient({required Set<String> keys}) : subscribableKeys = keys;

  @override
  bool canSubscribe(String key) =>
      subscribableKeys.contains(key) ||
      subscribableKeys.any((k) => key.startsWith('$k.'));

  @override
  Stream<DynamicValue> subscribe(String key) => const Stream.empty();

  @override
  DynamicValue? read(String key) => _values[key];

  @override
  Future<void> write(String key, DynamicValue value) async {}

  @override
  ConnectionStatus get connectionStatus => ConnectionStatus.disconnected;

  @override
  Stream<ConnectionStatus> get connectionStream => const Stream.empty();

  @override
  void connect() {}

  @override
  void dispose() {}

  void setCachedValue(String key, DynamicValue value) {
    _values[key] = value;
  }
}
