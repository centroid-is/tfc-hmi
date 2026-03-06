import 'package:jbtm/src/m2400_field_parser.dart';
import 'package:jbtm/src/m2400_fields.dart';
import 'package:open62541/open62541.dart'
    show DynamicValue, EnumField, LocalizedText;

/// Pre-built enum field map for WeigherStatus values.
///
/// Maps each [WeigherStatus] code to an [EnumField] with display name.
/// Attached to status-type child DynamicValues so consumers can resolve
/// the integer code to a human-readable label.
final Map<int, EnumField> _statusEnumFields = {
  for (final ws in WeigherStatus.values)
    ws.code: EnumField(
      ws.code,
      ws.name,
      LocalizedText(ws.displayName, ''),
      LocalizedText('', ''),
    ),
};

/// Whether a field represents weigher status and should carry enum metadata.
bool _isStatusField(M2400Field field) =>
    field == M2400Field.status || field == M2400Field.weighingStatus;

/// Convert an [M2400ParsedRecord] into a [DynamicValue] object tree.
///
/// The returned DynamicValue is a structured object (LinkedHashMap) with:
/// - One child per known typed field, keyed by the [M2400Field] enum name
///   (e.g., 'weight', 'unit', 'siWeight', 'field6')
/// - One child per unknown field, keyed by numeric ID string (e.g., '99')
/// - 'receivedAt' child with ISO 8601 string timestamp
/// - 'deviceTimestamp' child with ISO 8601 string (only if non-null)
///
/// Status fields ([M2400Field.status], [M2400Field.weighingStatus]) have
/// their [DynamicValue.enumFields] populated with [WeigherStatus] entries.
DynamicValue convertRecordToDynamicValue(M2400ParsedRecord record) {
  final parent = DynamicValue(name: record.type.name);

  // Add typed fields
  for (final entry in record.typedFields.entries) {
    final field = entry.key;
    final value = entry.value;
    final child = DynamicValue(value: value, name: field.displayName);

    if (_isStatusField(field)) {
      child.enumFields = _statusEnumFields;
    }

    parent[field.name] = child;
  }

  // Add unknown fields as string children
  for (final entry in record.unknownFields.entries) {
    parent[entry.key.toString()] = DynamicValue(value: entry.value);
  }

  // Add metadata timestamps as microseconds (avoids string allocation)
  parent['receivedAt'] =
      DynamicValue(value: record.receivedAt.microsecondsSinceEpoch);

  if (record.deviceTimestamp != null) {
    parent['deviceTimestamp'] =
        DynamicValue(value: record.deviceTimestamp!.microsecondsSinceEpoch);
  }

  return parent;
}
