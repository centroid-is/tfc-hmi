/// The value type every component of the pipe passes around.
///
/// Pure Dart: no FFI, no `package:open62541`, no codegen, no I/O — mandated by
/// CONTEXT D-08 ("It just can't have native bindings like the other impl", the
/// #107 lesson). A native-backed value type made the whole client tier depend
/// on a git-pinned FFI package shared with the native OPC UA client; this one
/// is 100% Dart and can be built for Flutter web.
///
/// Two invariants the constructor enforces, both operational:
///
///  * **Immutable and value-equal.** The value store's promise — unchanged
///    keys cost zero rebuilds with 1500 keys on one page (CLI-06) — is the
///    `if (next == current) return;` guard. A shared mutable object makes that
///    comparison meaningless, so every field is `final` and equality is
///    structural over nested children.
///  * **No non-finite double can exist inside one.** Dart's `jsonEncode`
///    throws on NaN/±Infinity, so one open-circuit 4-20 mA input would fail the
///    batch for every connected client. Construction runs [sanitize]; a poison
///    leaf becomes `null` with [Quality.badNonFinite].
///
/// [quality] and [sourceTime] are first-class fields (CONTEXT), mirroring OPC
/// UA's DataValue: one type at every call site, so a widget can never read a
/// number without being able to see whether it is trustworthy.
library;

import 'quality.dart';
import 'sanitize.dart';

/// Protocol-native value type tag.
///
/// Deliberately not OPC UA's `NodeId`: the pipe also carries Modbus, M2400 /
/// JBTM and UMAS values, for which a namespaced OPC UA node id is meaningless.
/// The original source type id (e.g. `"ns=2;s=X"`) round-trips opaquely in
/// [DynamicValue.sourceTypeId].
enum ValueType {
  unknown,
  boolean,
  integer,
  double,
  string,
  bytes,
  dateTime,
  object,
  array,
  null_,
}

/// A human-readable string with an optional locale (the Icelandic plant runs
/// `is` and `en` side by side).
final class LocalizedText {
  final String value;
  final String? locale;

  const LocalizedText(this.value, {this.locale});

  factory LocalizedText.fromJson(Map<String, Object?> json) => LocalizedText(
        json['text'] as String? ?? '',
        locale: json['locale'] as String?,
      );

  Map<String, Object?> toJson() => {
        'text': value,
        if (locale != null) 'locale': locale,
      };

  @override
  bool operator ==(Object other) =>
      other is LocalizedText && other.value == value && other.locale == locale;

  @override
  int get hashCode => Object.hash(value, locale);

  @override
  String toString() => value;
}

/// One member of an enumeration declared upstream: the numeric code plus the
/// name operators actually read on screen.
final class EnumField {
  final int value;
  final String name;
  final LocalizedText? displayName;
  final LocalizedText? description;

  const EnumField({
    required this.value,
    required this.name,
    this.displayName,
    this.description,
  });

  factory EnumField.fromJson(Map<String, Object?> json) => EnumField(
        value: (json['value'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        displayName: json['displayName'] == null
            ? null
            : LocalizedText.fromJson(
                (json['displayName'] as Map).cast<String, Object?>()),
        description: json['description'] == null
            ? null
            : LocalizedText.fromJson(
                (json['description'] as Map).cast<String, Object?>()),
      );

  Map<String, Object?> toJson() => {
        'value': value,
        'name': name,
        if (displayName != null) 'displayName': displayName!.toJson(),
        if (description != null) 'description': description!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is EnumField &&
      other.value == value &&
      other.name == name &&
      other.displayName == displayName &&
      other.description == description;

  @override
  int get hashCode => Object.hash(value, name, displayName, description);

  @override
  String toString() => '$name($value)';
}

/// An immutable value plus everything needed to judge it.
///
/// [value] is a primitive, a `Map<Object, DynamicValue>` (object members) or a
/// `List<DynamicValue>` (array elements) — never a raw nested map or list, so
/// indexing, equality and encoding are uniform at every depth.
final class DynamicValue {
  /// Sentinel distinguishing "argument omitted" from "explicitly set to null"
  /// in [copyWith] — the ported call sites need to clear `displayName` and
  /// `description`, not just replace them.
  static const Object _unset = Object();

  final Object? value;
  final Quality quality;
  final DateTime? sourceTime;
  final ValueType? typeId;

  /// Opaque round-trip of the source's own type id, e.g. `"ns=2;s=X"`. Never
  /// parsed here — the wire shape the existing converter uses does not change.
  final String? sourceTypeId;

  final LocalizedText? displayName;
  final LocalizedText? description;
  final Map<int, EnumField>? enumFields;

  const DynamicValue._({
    required this.value,
    required this.quality,
    required this.sourceTime,
    required this.typeId,
    required this.sourceTypeId,
    required this.displayName,
    required this.description,
    required this.enumFields,
  });

  /// Sanitizing constructor.
  ///
  /// Nested maps and lists are normalized into `Map<Object, DynamicValue>` /
  /// `List<DynamicValue>`; non-finite doubles anywhere become `null` and force
  /// [Quality.badNonFinite]; a parent's quality is worst-wins over its own and
  /// all of its children's, so a healthy-looking header can never hide a dead
  /// member.
  factory DynamicValue({
    Object? value,
    Quality quality = Quality.good,
    DateTime? sourceTime,
    ValueType? typeId,
    String? sourceTypeId,
    LocalizedText? displayName,
    LocalizedText? description,
    Map<int, EnumField>? enumFields,
  }) {
    final normalized = _normalize(value, quality);
    return DynamicValue._(
      value: normalized.value,
      quality: normalized.quality,
      sourceTime: _normalizeTime(sourceTime),
      typeId: typeId,
      sourceTypeId: sourceTypeId,
      displayName: displayName,
      description: description,
      enumFields: enumFields == null
          ? null
          : Map<int, EnumField>.unmodifiable(enumFields),
    );
  }

  /// Positional convenience mirroring `WireValue.of`.
  factory DynamicValue.of(
    Object? value, {
    Quality quality = Quality.good,
    DateTime? sourceTime,
  }) =>
      DynamicValue(value: value, quality: quality, sourceTime: sourceTime);

  /// Deep copy. Kept as a named constructor because the ported call sites read
  /// `DynamicValue.from(x)` today; with an immutable type the follow-up
  /// mutation becomes [copyWith].
  factory DynamicValue.from(DynamicValue other) => DynamicValue(
        value: _deepCopy(other.value),
        quality: other.quality,
        sourceTime: other.sourceTime,
        typeId: other.typeId,
        sourceTypeId: other.sourceTypeId,
        displayName: other.displayName,
        description: other.description,
        enumFields: other.enumFields == null
            ? null
            : Map<int, EnumField>.from(other.enumFields!),
      );

  // ---------------------------------------------------------------- coercion

  /// Never null, never a throw — 44 call sites index the result directly.
  double get asDouble => _parseDouble(value) ?? 0.0;

  /// Never null, never a throw — 43 call sites index the result directly.
  int get asInt => _parseInt(value) ?? 0;

  String get asString => value?.toString() ?? '';

  bool get asBool => _parseBool(value) ?? false;

  static double? _parseDouble(Object? val) {
    if (val is num) return val.toDouble();
    if (val is bool) return val ? 1.0 : 0.0;
    if (val is String) return double.tryParse(val.trim());
    return null;
  }

  static int? _parseInt(Object? val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is bool) return val ? 1 : 0;
    if (val is String) {
      final trimmed = val.trim();
      return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
    }
    return null;
  }

  static bool? _parseBool(Object? val) {
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final lc = val.trim().toLowerCase();
      return lc == 'true' || lc == '1';
    }
    return null;
  }

  // -------------------------------------------------------------- type tests

  bool get isNull => value == null;
  bool get isBoolean => value is bool;
  bool get isInteger => value is int;
  bool get isDouble => value is double;
  bool get isString => value is String;
  bool get isArray => value is List<DynamicValue>;
  bool get isObject => value is Map<Object, DynamicValue>;

  /// Object members. Throws [StateError] when this is not an object — an
  /// unexpected shape is a configuration fault worth surfacing, not one to
  /// paper over with an empty map.
  Map<Object, DynamicValue> get asObject {
    final v = value;
    if (v is Map<Object, DynamicValue>) return v;
    throw StateError('not an object: ${_shape()}');
  }

  /// Array elements. Throws [StateError] when this is not an array.
  List<DynamicValue> get asArray {
    final v = value;
    if (v is List<DynamicValue>) return v;
    throw StateError('not an array: ${_shape()}');
  }

  // ------------------------------------------------------ indexing / members

  /// Non-throwing membership test. Paired with the throwing [operator []] this
  /// is the guard idiom at `lib/page_creator/assets/sensor.dart:125-132`: an
  /// older PLC library revision missing a member must degrade, not crash the
  /// mimic.
  bool contains(Object key) {
    final v = value;
    if (v is Map<Object, DynamicValue>) return v.containsKey(key);
    if (v is List<DynamicValue>) {
      return key is int && key >= 0 && key < v.length;
    }
    return false;
  }

  /// Object members index by `String`, array elements by `int`.
  ///
  /// Throws [StateError] on a missing member. That throw is depended upon:
  /// returning a null-valued placeholder would let a renamed tag render as a
  /// plausible-looking zero forever.
  DynamicValue operator [](Object key) {
    final v = value;
    if (v is Map<Object, DynamicValue>) {
      final child = v[key];
      if (child == null) {
        throw StateError("no member '$key' (have: ${v.keys.join(', ')})");
      }
      return child;
    }
    if (v is List<DynamicValue>) {
      if (key is int && key >= 0 && key < v.length) return v[key];
      throw StateError('index $key out of range (length ${v.length})');
    }
    throw StateError('cannot index ${_shape()} with $key');
  }

  /// Object children in insertion order; array elements keyed by index.
  Iterable<MapEntry<Object, DynamicValue>> get entries {
    final v = value;
    if (v is Map<Object, DynamicValue>) return v.entries;
    if (v is List<DynamicValue>) {
      return v.asMap().entries.map(
            (e) => MapEntry<Object, DynamicValue>(e.key, e.value),
          );
    }
    throw StateError('${_shape()} has no entries');
  }

  /// Number of members or elements.
  int get length {
    final v = value;
    if (v is Map<Object, DynamicValue>) return v.length;
    if (v is List<DynamicValue>) return v.length;
    throw StateError('${_shape()} has no length');
  }

  // ----------------------------------------------------------------- copying

  /// Returns a new instance; the receiver is untouched. Pass an explicit
  /// `null` to clear an optional field.
  DynamicValue copyWith({
    Object? value = _unset,
    Quality? quality,
    Object? sourceTime = _unset,
    Object? typeId = _unset,
    Object? sourceTypeId = _unset,
    Object? displayName = _unset,
    Object? description = _unset,
    Object? enumFields = _unset,
  }) =>
      DynamicValue(
        value: identical(value, _unset) ? this.value : value,
        quality: quality ?? this.quality,
        sourceTime: identical(sourceTime, _unset)
            ? this.sourceTime
            : sourceTime as DateTime?,
        typeId: identical(typeId, _unset) ? this.typeId : typeId as ValueType?,
        sourceTypeId: identical(sourceTypeId, _unset)
            ? this.sourceTypeId
            : sourceTypeId as String?,
        displayName: identical(displayName, _unset)
            ? this.displayName
            : displayName as LocalizedText?,
        description: identical(description, _unset)
            ? this.description
            : description as LocalizedText?,
        enumFields: identical(enumFields, _unset)
            ? this.enumFields
            : enumFields as Map<int, EnumField>?,
      );

  // ---------------------------------------------------------------- equality

  @override
  bool operator ==(Object other) =>
      other is DynamicValue &&
      other.quality == quality &&
      other.sourceTime == sourceTime &&
      other.typeId == typeId &&
      other.sourceTypeId == sourceTypeId &&
      other.displayName == displayName &&
      other.description == description &&
      _enumFieldsEqual(other.enumFields, enumFields) &&
      _valuesEqual(other.value, value);

  @override
  int get hashCode => Object.hash(
        _deepHash(value),
        quality,
        sourceTime,
        typeId,
        sourceTypeId,
        displayName,
        description,
        _enumFieldsHash(enumFields),
      );

  @override
  String toString() {
    if (value == null) return 'null';
    final fields = enumFields;
    if (fields != null) return '${fields[value]?.name}($value)';
    final label = displayName == null ? '' : '${displayName!.value}: ';
    final q = quality == Quality.good ? '' : ' [q=${quality.code}]';
    return '$label$value$q';
  }

  // ----------------------------------------------------------------- helpers

  String _shape() {
    if (isNull) return 'null';
    if (isObject) return 'object';
    if (isArray) return 'array';
    return '${value.runtimeType}';
  }

  /// Rebuilds [raw] into the normalized shape and composes the quality.
  static ({Object? value, Quality quality}) _normalize(
      Object? raw, Quality own) {
    if (raw is DynamicValue) {
      return (value: raw.value, quality: _compose(own, [raw.quality]));
    }
    if (raw is Map) {
      final members = <Object, DynamicValue>{};
      for (final entry in raw.entries) {
        members[entry.key as Object] = _wrap(entry.value);
      }
      return (
        value: Map<Object, DynamicValue>.unmodifiable(members),
        quality: _compose(own, members.values.map((c) => c.quality)),
      );
    }
    if (raw is List) {
      final elements = List<DynamicValue>.unmodifiable(raw.map(_wrap));
      return (
        value: elements,
        quality: _compose(own, elements.map((c) => c.quality)),
      );
    }
    // Leaf: `1e999` from outside and a divide-by-zero rate from a weigher both
    // land here, and both must not reach jsonEncode.
    final s = sanitize(raw);
    return (
      value: s.value,
      quality:
          s.hadNonFinite ? Quality.worst([own, Quality.badNonFinite]) : own,
    );
  }

  static DynamicValue _wrap(Object? raw) =>
      raw is DynamicValue ? raw : DynamicValue(value: raw);

  /// Worst-wins over children, but never launders the value's own quality down
  /// to plain good: `Quality.worst` resets to `good` within a band, which would
  /// erase the write-pending badge an operator is watching.
  static Quality _compose(Quality own, Iterable<Quality> children) {
    final worst = Quality.worst([own, ...children]);
    return worst.band > own.band ? worst : own;
  }

  /// Timestamps are normalized to UTC milliseconds — the precision the wire
  /// carries — so `fromJson(toJson())` is `==` to the original.
  static DateTime? _normalizeTime(DateTime? t) => t == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch,
          isUtc: true);

  static Object? _deepCopy(Object? v) {
    if (v is Map<Object, DynamicValue>) {
      return {
        for (final e in v.entries) e.key: DynamicValue.from(e.value),
      };
    }
    if (v is List<DynamicValue>) {
      return [for (final child in v) DynamicValue.from(child)];
    }
    return v;
  }

  static bool _valuesEqual(Object? a, Object? b) {
    if (a is Map<Object, DynamicValue>) {
      if (b is! Map<Object, DynamicValue> || a.length != b.length) return false;
      for (final entry in a.entries) {
        final other = b[entry.key];
        if (other == null || other != entry.value) return false;
      }
      return true;
    }
    if (a is List<DynamicValue>) {
      if (b is! List<DynamicValue> || a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }

  static int _deepHash(Object? v) {
    if (v is Map<Object, DynamicValue>) {
      var acc = 0;
      for (final entry in v.entries) {
        acc ^= Object.hash(entry.key, entry.value);
      }
      return Object.hash('object', acc, v.length);
    }
    if (v is List<DynamicValue>) return Object.hash('array', Object.hashAll(v));
    return v.hashCode;
  }

  static bool _enumFieldsEqual(
      Map<int, EnumField>? a, Map<int, EnumField>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static int _enumFieldsHash(Map<int, EnumField>? fields) {
    if (fields == null) return 0;
    var acc = 0;
    for (final entry in fields.entries) {
      acc ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(acc, fields.length);
  }
}
