import 'package:tfc_mcp_server/src/interfaces/alarm_reader.dart';

/// In-memory implementation of [AlarmReader] for testing.
///
/// Use [addAlarmConfig] to populate test data and [clear] to reset.
class MockAlarmReader implements AlarmReader {
  final List<Map<String, dynamic>> _configs = [];

  /// Add an alarm configuration for testing.
  void addAlarmConfig(Map<String, dynamic> config) {
    _configs.add(config);
  }

  /// Remove all alarm configurations.
  void clear() {
    _configs.clear();
  }

  @override
  List<Map<String, dynamic>> get alarmConfigs =>
      List.unmodifiable(_configs);
}
