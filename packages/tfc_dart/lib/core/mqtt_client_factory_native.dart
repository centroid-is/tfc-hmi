import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'state_man.dart' show MqttConfig;

/// Create an MQTT client for native platforms (TCP or WebSocket).
MqttClient createMqttClient(MqttConfig config) {
  final clientId =
      config.clientId ?? 'tfc_${DateTime.now().millisecondsSinceEpoch}';

  // For WebSocket mode, MqttServerClient expects a full ws:// URI as the host
  // so the connection handler can parse the scheme and path correctly.
  final host = config.useWebSocket
      ? '${config.useTls ? 'wss' : 'ws'}://${config.host}${config.wsPath}'
      : config.host;

  final client = MqttServerClient.withPort(host, clientId, config.port);

  if (config.useWebSocket) {
    client.useWebSocket = true;
    client.websocketProtocols =
        MqttClientConstants.protocolsSingleDefault;
  }

  return client;
}
