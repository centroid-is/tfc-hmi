import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'state_man.dart' show MqttConfig;

/// Create an MQTT client for native platforms (TCP or WebSocket).
MqttClient createMqttClient(MqttConfig config) {
  final clientId =
      config.clientId ?? 'tfc_${DateTime.now().millisecondsSinceEpoch}';

  final client = MqttServerClient.withPort(config.host, clientId, config.port);

  if (config.useWebSocket) {
    client.useWebSocket = true;
    client.websocketProtocols =
        MqttClientConstants.protocolsSingleDefault;
  }

  return client;
}
