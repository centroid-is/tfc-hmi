import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

import 'state_man.dart' show MqttConfig;

/// Create an MQTT client for web platforms (WebSocket only).
MqttClient createMqttClient(MqttConfig config) {
  final clientId =
      config.clientId ?? 'tfc_${DateTime.now().millisecondsSinceEpoch}';
  final scheme = config.useTls ? 'wss' : 'ws';
  final url = '$scheme://${config.host}:${config.port}${config.wsPath}';

  return MqttBrowserClient(url, clientId);
}
