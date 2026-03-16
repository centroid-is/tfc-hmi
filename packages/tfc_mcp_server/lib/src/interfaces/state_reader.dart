/// Read-only interface for accessing live system state values.
///
/// In production, this is backed by IPC to the Flutter app's StateMan.
/// In tests, [MockStateReader] provides an in-memory implementation.
/// In standalone/Claude Desktop mode, database-only data is used.
abstract class StateReader {
  /// All current key-value pairs in the state system.
  Map<String, dynamic> get currentValues;

  /// Get the current value for a specific key.
  ///
  /// Returns `null` if the key does not exist.
  dynamic getValue(String key);

  /// All keys currently known to the state system.
  List<String> get keys;
}
