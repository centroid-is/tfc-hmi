import 'package:jbtm/src/m2400.dart';
import 'package:jbtm/src/m2400_fields.dart';
import 'package:jbtm/src/m2400_log_throttle.dart';
import 'package:logger/logger.dart';

final _logger = Logger();

/// A parsed M2400 record with typed field values.
///
/// Wraps the raw [M2400Record] and provides type-safe access to known fields.
/// Unknown field IDs are retained in [unknownFields] as raw strings.
/// The original raw data is preserved in [rawFields] for debugging.
class M2400ParsedRecord {
  /// The record type (recBatch, recStat, recLua, etc.)
  final M2400RecordType type;

  /// Typed field values keyed by [M2400Field] enum.
  /// Values are the correct Dart type (double, int, String) per the field's
  /// [FieldType].
  final Map<M2400Field, Object> typedFields;

  /// Field IDs not found in the [M2400Field] enum, stored as raw strings.
  final Map<int, String> unknownFields;

  /// The original raw field data from the M2400 wire format.
  final Map<String, String> rawFields;

  /// When this record was received/parsed.
  final DateTime receivedAt;

  /// Device-reported timestamp extracted from date/time/timeMs fields.
  /// Null if those fields are absent or unparseable.
  final DateTime? deviceTimestamp;

  const M2400ParsedRecord({
    required this.type,
    required this.typedFields,
    required this.unknownFields,
    required this.rawFields,
    required this.receivedAt,
    this.deviceTimestamp,
  });

  /// Get a typed field value, returns null if field not present or wrong type.
  T? getField<T>(M2400Field field) {
    final value = typedFields[field];
    return value is T ? value : null;
  }

  /// Convenience: weight value as double.
  double? get weight => getField<double>(M2400Field.weight);

  /// Convenience: unit string (e.g., 'kg', 'lb').
  String? get unitString => getField<String>(M2400Field.unit);

  /// Convenience: SI weight string (e.g., '11.00kg').
  String? get siWeight => getField<String>(M2400Field.siWeight);

  /// Convenience: weigher status from status field code.
  WeigherStatus? get weigherStatus {
    final code = getField<int>(M2400Field.status);
    return code != null ? WeigherStatus.fromCode(code) : null;
  }

  @override
  String toString() =>
      'M2400ParsedRecord(type: $type, fields: ${typedFields.length} typed, '
      '${unknownFields.length} unknown)';
}

/// Reports a parse failure, throttled per (kind, field id).
///
/// See [shouldReportM2400]: a scale that emits one malformed field emits it on
/// every weighment, and these are warnings, so no log level a station would be
/// set to suppresses them.
void _reportParseFailure(String kind, int? fieldId, String rawValue) {
  final reason = '$kind:$fieldId';
  if (!shouldReportM2400(reason)) return;
  // Always carry the count, even when it is 1: the six throttled sites in
  // this package read the same way, and "(occurrence 1)" says the number is
  // known rather than leaving the reader to infer it from an absence.
  _logger.w('Failed to parse $kind field $fieldId: "$rawValue" '
      '(occurrence ${m2400LogCount(reason)})');
}

/// Parse a raw field value string to its target Dart type.
///
/// Returns null if parsing fails (logs a warning with [fieldId] for
/// diagnostics -- first occurrence, then every thousandth).
Object? parseFieldValue(String rawValue, FieldType type, {int? fieldId}) {
  switch (type) {
    case FieldType.decimal:
      var parsed = double.tryParse(rawValue);
      if (parsed == null) {
        // Strip trailing unit suffix (e.g. "11.00kg" -> "11.00")
        final stripped = rawValue.replaceFirst(RegExp(r'[a-zA-Z%°]+$'), '');
        parsed = double.tryParse(stripped);
        if (parsed == null) {
          _reportParseFailure('decimal', fieldId, rawValue);
        }
      }
      return parsed;
    case FieldType.integer:
      final parsed = int.tryParse(rawValue);
      if (parsed == null) {
        _reportParseFailure('integer', fieldId, rawValue);
      }
      return parsed;
    case FieldType.string:
      return rawValue;
    case FieldType.percentage:
      final parsed = double.tryParse(rawValue);
      if (parsed == null) {
        _reportParseFailure('percentage', fieldId, rawValue);
      }
      return parsed;
    case FieldType.date:
    case FieldType.time:
    case FieldType.timeMs:
      return rawValue; // Stored as string; combined into DateTime post-parse
  }
}

/// Combine date, time, and milliseconds fields into a [DateTime].
///
/// Returns null if date or time fields are absent or unparseable.
/// Adds milliseconds from timeMs if present.
DateTime? extractTimestamp(Map<M2400Field, Object> typedFields) {
  final dateStr = typedFields[M2400Field.date] as String?;
  final timeStr = typedFields[M2400Field.time] as String?;
  final timeMsStr = typedFields[M2400Field.timeMs] as String?;

  if (dateStr == null || timeStr == null) return null;

  // Attempt ISO 8601 parse: "YYYY-MM-DDThh:mm:ss"
  final dt = DateTime.tryParse('${dateStr}T$timeStr');
  if (dt == null) return null;

  // Add milliseconds if present
  final ms = timeMsStr != null ? int.tryParse(timeMsStr) : null;
  if (ms != null) {
    return dt.add(Duration(milliseconds: ms));
  }
  return dt;
}

/// Parse a raw [M2400Record] into a typed [M2400ParsedRecord].
///
/// Iterates raw field entries, looks up each field ID in the [M2400Field]
/// enum, and parses the value to the correct Dart type. Unknown field IDs
/// are stored in [M2400ParsedRecord.unknownFields]. Parse failures are
/// logged but do not affect other fields.
M2400ParsedRecord parseTypedRecord(M2400Record raw) {
  final typed = <M2400Field, Object>{};
  final unknown = <int, String>{};

  for (final entry in raw.fields.entries) {
    final fieldId = int.tryParse(entry.key);
    if (fieldId == null) {
      // Fixed reason key, not the raw key: the reason is device data here and
      // would grow the counter map without bound.
      if (shouldReportM2400('nonNumericFieldKey')) {
        _logger.d('Non-numeric field key: "${entry.key}" '
            '(occurrence ${m2400LogCount('nonNumericFieldKey')})');
      }
      continue;
    }

    final field = M2400Field.fromId(fieldId);
    if (field == null) {
      // Unknown ids are routine -- firmware emits fields this parser has not
      // been taught -- and every record carries the same ones. Two of these
      // cost 138us per record before throttling.
      final reason = 'unknownFieldId:$fieldId';
      if (shouldReportM2400(reason)) {
        _logger.d('Unknown field ID: $fieldId with value: "${entry.value}" '
            '(occurrence ${m2400LogCount(reason)})');
      }
      unknown[fieldId] = entry.value;
      continue;
    }

    final parsed =
        parseFieldValue(entry.value, field.fieldType, fieldId: fieldId);
    if (parsed != null) {
      typed[field] = parsed;
    }
  }

  // Post-parse: extract composite timestamp if date/time fields present
  final timestamp = extractTimestamp(typed);

  return M2400ParsedRecord(
    type: raw.type,
    typedFields: typed,
    unknownFields: unknown,
    rawFields: raw.fields,
    receivedAt: DateTime.timestamp(),
    deviceTimestamp: timestamp,
  );
}
