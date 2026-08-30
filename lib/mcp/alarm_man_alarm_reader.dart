import 'package:tfc_dart/core/alarm.dart';
import 'package:tfc_mcp_server/tfc_mcp_server.dart' show AlarmReader;

/// [AlarmReader] implementation backed by the Flutter app's [AlarmMan].
///
/// Converts [AlarmConfig] objects from [AlarmMan.config.alarms] to
/// `Map<String, dynamic>` format expected by the MCP server's alarm tools.
///
/// Each map contains: uid, key, title, description, rules (serialized
/// via [AlarmRule.toJson]).
class AlarmManAlarmReader implements AlarmReader {
  final List<AlarmConfig> _configs;

  /// Creates an [AlarmManAlarmReader] backed by the given [AlarmMan].
  AlarmManAlarmReader(AlarmMan alarmMan)
      : _configs = alarmMan.config.alarms;

  /// Creates an [AlarmManAlarmReader] directly from a list of [AlarmConfig].
  ///
  /// Used for testing without needing a full AlarmMan instance.
  AlarmManAlarmReader.fromConfigs(this._configs);

  @override
  List<Map<String, dynamic>> get alarmConfigs {
    return _configs.map((alarm) {
      return <String, dynamic>{
        'uid': alarm.uid,
        'key': alarm.key,
        'title': alarm.title,
        'description': alarm.description,
        'rules': alarm.rules.map((r) => r.toJson()).toList(),
        // Where the alarm sits in the alarm tree. The copilot needs this to
        // answer "what is under Line 3" and to place a new alarm sensibly.
        'group': List<String>.from(alarm.group),
        'bindToGroup': alarm.bindToGroup,
      };
    }).toList();
  }
}
