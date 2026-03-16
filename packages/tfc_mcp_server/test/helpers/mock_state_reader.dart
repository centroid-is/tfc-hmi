import 'package:tfc_mcp_server/src/interfaces/state_reader.dart';

/// In-memory implementation of [StateReader] for testing.
///
/// Use [setValue] to populate test data and [clear] to reset between tests.
class MockStateReader implements StateReader {
  final Map<String, dynamic> _values = {};

  /// Set a value for testing.
  void setValue(String key, dynamic value) {
    _values[key] = value;
  }

  /// Remove all values.
  void clear() {
    _values.clear();
  }

  @override
  Map<String, dynamic> get currentValues => Map.unmodifiable(_values);

  @override
  dynamic getValue(String key) => _values[key];

  @override
  List<String> get keys => _values.keys.toList();
}
