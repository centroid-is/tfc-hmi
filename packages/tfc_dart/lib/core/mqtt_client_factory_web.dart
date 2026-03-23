import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

import 'state_man.dart' show MqttConfig;

/// Create an MQTT client for web platforms (WebSocket only).
MqttClient createMqttClient(MqttConfig config) {
  final clientId =
      config.clientId ?? 'tfc_${DateTime.now().millisecondsSinceEpoch}';
  final scheme = config.useTls ? 'wss' : 'ws';
  final url = '$scheme://${config.host}:${config.port}${config.wsPath}';

  debugPrint('[createMqttClient] url=$url clientId=$clientId alias=${config.serverAlias}');
  // Must use withPort: MqttBrowserClient default constructor sets port=1883,
  // and the browser WS connection replaces the URL's port with this field.
  return MqttBrowserClient.withPort(url, clientId, config.port);
}
