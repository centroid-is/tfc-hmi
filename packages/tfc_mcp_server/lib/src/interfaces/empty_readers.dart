import 'alarm_reader.dart';
import 'state_reader.dart';

/// A [StateReader] that returns empty state data.
///
/// Used in standalone mode (Claude Desktop) where no live StateMan
/// is available via IPC. In production, the Flutter app provides
/// a real IPC-backed implementation (Phase 5).
class EmptyStateReader implements StateReader {
  @override
  Map<String, dynamic> get currentValues => const {};

  @override
  dynamic getValue(String key) => null;

  @override
  List<String> get keys => const [];
}

/// An [AlarmReader] that returns empty alarm configuration.
///
/// Used in standalone mode (Claude Desktop) where no live AlarmMan
/// is available via IPC. In production, the Flutter app provides
/// a real IPC-backed implementation (Phase 5).
class EmptyAlarmReader implements AlarmReader {
  @override
  List<Map<String, dynamic>> get alarmConfigs => const [];
}
