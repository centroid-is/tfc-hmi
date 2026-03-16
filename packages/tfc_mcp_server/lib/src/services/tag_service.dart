import 'package:tfc_dart/tfc_dart_core.dart';

import '../interfaces/state_reader.dart';

/// Service for querying real-time tag values from the state system.
///
/// Implements progressive discovery (CORE-05): operators first browse tags
/// with [listTags] (Level 1), then drill into specific values with
/// [getTagValue] (Level 2).
///
/// All tag queries go through [StateReader], which abstracts the live state
/// source (IPC in production, in-memory for tests).
class TagService {
  /// Creates a [TagService] backed by the given [StateReader].
  TagService(this._stateReader);

  final StateReader _stateReader;

  /// Default maximum number of tags returned by [listTags].
  static const int defaultLimit = 50;

  /// Absolute maximum for the limit parameter.
  static const int maxLimit = 200;

  /// List tags with optional fuzzy filtering and result limiting.
  ///
  /// If [filter] is provided, only keys that fuzzy-match the filter are
  /// returned (e.g., "pump" matches "pump3.speed" but not "conveyor.speed").
  ///
  /// Returns at most [limit] results (default 50, max 200). Each result is
  /// a map with `key` and `value` entries.
  List<Map<String, dynamic>> listTags({String? filter, int limit = 50}) {
    // Enforce max limit
    final effectiveLimit = limit.clamp(1, maxLimit);

    final allKeys = _stateReader.keys;

    // Apply fuzzy filter if provided
    final filteredKeys = filter != null && filter.isNotEmpty
        ? fuzzyFilter<String>(allKeys, filter, [(key) => key])
        : allKeys;

    // Apply limit and build result maps
    return filteredKeys.take(effectiveLimit).map((key) {
      return <String, dynamic>{
        'key': key,
        'value': _stateReader.getValue(key),
      };
    }).toList();
  }

  /// Get the current value for a specific tag by key name.
  ///
  /// Returns a map with `key` and `value` if the key exists in the state
  /// system, or `null` if the key is unknown.
  Map<String, dynamic>? getTagValue(String key) {
    if (!_stateReader.keys.contains(key)) {
      return null;
    }
    return <String, dynamic>{
      'key': key,
      'value': _stateReader.getValue(key),
    };
  }
}
