/// Read-only interface for accessing alarm configuration and state.
///
/// Uses [Map<String, dynamic>] instead of the tfc_dart AlarmConfig class
/// because AlarmConfig lives in alarm.dart which has FFI transitive
/// dependencies (state_man.dart, boolean_expression.dart -> open62541).
///
/// The MCP server reads alarm data from the database using Drift queries
/// and works with maps or its own model classes.
abstract class AlarmReader {
  /// All alarm configurations as maps.
  ///
  /// Each map typically contains keys: uid, key, title, description, rules.
  List<Map<String, dynamic>> get alarmConfigs;
}
