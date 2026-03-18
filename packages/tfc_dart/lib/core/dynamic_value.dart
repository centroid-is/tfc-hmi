/// Platform-agnostic DynamicValue, NodeId, and supporting types.
///
/// This file provides the pure-Dart definitions of types that originated in
/// the open62541 FFI package but are used throughout the codebase (UI, MQTT,
/// boolean expressions, collectors, converters, etc.).
///
/// The open62541 package retains its own DynamicValue with FFI extensions.
/// [OpcUaDeviceClientAdapter] converts between the two at the boundary.
import 'dart:collection' show LinkedHashMap;

// ---------------------------------------------------------------------------
// DynamicType enum
// ---------------------------------------------------------------------------

enum DynamicType { object, array, string, boolean, nullValue, unknown, integer, double }

// ---------------------------------------------------------------------------
// LocalizedText
// ---------------------------------------------------------------------------

class LocalizedText {
  final String value;
  final String locale;
  LocalizedText(this.value, this.locale);

  factory LocalizedText.from(LocalizedText other) {
    return LocalizedText(other.value, other.locale);
  }

  @override
  String toString() {
    if (value.isNotEmpty && locale.isNotEmpty) return "$locale : $value";
    return value;
  }

  @override
  bool operator ==(Object other) {
    if (other is LocalizedText) {
      return value == other.value && locale == other.locale;
    }
    return false;
  }

  @override
  int get hashCode => value.hashCode ^ locale.hashCode;
}

// ---------------------------------------------------------------------------
// EnumField
// ---------------------------------------------------------------------------

class EnumField {
  final int value;
  final LocalizedText displayName;
  final LocalizedText description;
  final String name;
  EnumField(this.value, this.name, this.displayName, this.description);

  factory EnumField.from(EnumField other) {
    return EnumField(other.value, other.name, other.displayName, other.description);
  }
}

// ---------------------------------------------------------------------------
// NodeId — pure Dart, no FFI
// ---------------------------------------------------------------------------

class NodeId {
  final int _namespaceIndex;
  final String? _stringId;
  final int? _numericId;

  NodeId._internal(this._namespaceIndex, {dynamic id})
      : _stringId = id is String ? id : null,
        _numericId = id is int ? id : null {
    if (_stringId == null && _numericId == null) {
      throw ArgumentError('NodeId requires a string or numeric identifier');
    }
  }

  factory NodeId.from(NodeId other) {
    if (other.isString()) {
      return NodeId.fromString(other.namespace, other.string);
    } else if (other.isNumeric()) {
      return NodeId.fromNumeric(other.namespace, other.numeric);
    } else {
      throw ArgumentError('NodeId is not initialized');
    }
  }

  factory NodeId.fromNumeric(int nsIndex, int identifier) {
    return NodeId._internal(nsIndex, id: identifier);
  }

  factory NodeId.fromString(int nsIndex, String chars) {
    return NodeId._internal(nsIndex, id: chars);
  }

  // OPC UA Namespace 0 standard type IDs
  static NodeId get nullId => NodeId.fromNumeric(0, 0);
  static NodeId get boolean => NodeId.fromNumeric(0, 1);
  static NodeId get sbyte => NodeId.fromNumeric(0, 2);
  static NodeId get byte => NodeId.fromNumeric(0, 3);
  static NodeId get int16 => NodeId.fromNumeric(0, 4);
  static NodeId get uint16 => NodeId.fromNumeric(0, 5);
  static NodeId get int32 => NodeId.fromNumeric(0, 6);
  static NodeId get uint32 => NodeId.fromNumeric(0, 7);
  static NodeId get int64 => NodeId.fromNumeric(0, 8);
  static NodeId get uint64 => NodeId.fromNumeric(0, 9);
  static NodeId get float => NodeId.fromNumeric(0, 10);
  static NodeId get double => NodeId.fromNumeric(0, 11);
  static NodeId get uastring => NodeId.fromNumeric(0, 12);
  static NodeId get datetime => NodeId.fromNumeric(0, 13);

  // OPC UA well-known folder NodeIds
  static NodeId get objectsFolder => NodeId.fromNumeric(0, 85);

  int get namespace => _namespaceIndex;
  int get numeric => _numericId!;
  String get string => _stringId!;

  bool isNumeric() => _numericId != null;
  bool isString() => _stringId != null;

  @override
  String toString() {
    if (_stringId != null) {
      return "ns=$namespace;s=$_stringId";
    } else if (_numericId != null) {
      return "ns=$namespace;i=$_numericId";
    } else {
      return 'NodeId(?)';
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is NodeId) {
      return _namespaceIndex == other._namespaceIndex &&
          _stringId == other._stringId &&
          _numericId == other._numericId;
    }
    return false;
  }

  @override
  int get hashCode =>
      _namespaceIndex.hashCode ^ _stringId.hashCode ^ _numericId.hashCode;
}

// ---------------------------------------------------------------------------
// DynamicValue — pure Dart, no FFI
// ---------------------------------------------------------------------------

class DynamicValue {
  dynamic value;
  NodeId? typeId;
  String? name;
  LocalizedText? description;
  LocalizedText? displayName;
  Map<int, EnumField>? enumFields;
  bool isOptional = false;

  DynamicValue({this.value, this.description, this.typeId, this.displayName, this.name});

  factory DynamicValue.fromMap(Map<String, dynamic> entries, {String? name}) {
    DynamicValue v = DynamicValue(name: name);
    entries.forEach((key, value) => v[key] = value);
    return v;
  }

  factory DynamicValue.fromList(List<dynamic> entries, {NodeId? typeId, String? name}) {
    DynamicValue v = DynamicValue(typeId: typeId, name: name);
    var counter = 0;
    for (var value in entries) {
      v[counter] = value;
      if (typeId != null) {
        v[counter].typeId = typeId;
      }
      counter = counter + 1;
    }
    return v;
  }

  factory DynamicValue.from(DynamicValue other) {
    var v = DynamicValue();
    if (other.value is DynamicValue) {
      v.value = DynamicValue.from(other.value);
    } else if (other.value is LinkedHashMap) {
      v.value = LinkedHashMap<String, DynamicValue>();
      other.value.forEach((key, value) => v.value[key] = DynamicValue.from(value));
    } else if (other.value is List) {
      v.value = other.value.map<DynamicValue>((e) => DynamicValue.from(e)).toList();
    } else {
      v.value = other.value;
    }

    if (other.typeId != null) {
      v.typeId = NodeId.from(other.typeId!);
    }
    if (other.displayName != null) {
      v.displayName = LocalizedText.from(other.displayName!);
    }
    if (other.description != null) {
      v.description = LocalizedText.from(other.description!);
    }
    if (other.enumFields != null) {
      v.enumFields = LinkedHashMap<int, EnumField>();
      other.enumFields!.forEach((key, value) => v.enumFields![key] = EnumField.from(value));
    }
    v.name = other.name;
    v.isOptional = other.isOptional;
    return v;
  }

  DynamicType get type {
    if (value == null) return DynamicType.nullValue;
    if (value is LinkedHashMap) return DynamicType.object;
    if (value is List<DynamicValue>) return DynamicType.array;
    if (value is String) return DynamicType.string;
    if (value is int) return DynamicType.integer;
    if (value is double) return DynamicType.double;
    if (value is bool) return DynamicType.boolean;
    return DynamicType.unknown;
  }

  // Type check accessors
  bool get isNull => type == DynamicType.nullValue;
  bool get isObject => type == DynamicType.object;
  bool get isArray => type == DynamicType.array;
  bool get isString => type == DynamicType.string;
  bool get isInteger => type == DynamicType.integer;
  bool get isDouble => type == DynamicType.double;
  bool get isBoolean => type == DynamicType.boolean;

  // Value accessors
  double get asDouble => _parseDouble(value) ?? 0.0;
  int get asInt => _parseInt(value) ?? 0;
  String get asString => value?.toString() ?? '';
  bool get asBool => _parseBool(value) ?? false;
  DateTime? get asDateTime => _parseDateTime(value);

  List<DynamicValue> get asArray =>
      isArray ? value : throw StateError('DynamicValue is not an array, ${value.runtimeType}');

  Map<String, DynamicValue> get asObject =>
      isObject ? value : throw StateError('DynamicValue is not an object, ${value.runtimeType}');

  bool contains(dynamic key) {
    if (key is int && isArray) {
      final list = value as List<DynamicValue>;
      return (key >= 0 && key < list.length);
    } else if (key is String && isObject) {
      return (value as Map<String, DynamicValue>).containsKey(key);
    }
    return false;
  }

  DynamicValue operator [](dynamic key) {
    if (key is int && isArray) {
      final list = value as List<DynamicValue>;
      return (key >= 0 && key < list.length) ? list[key] : throw StateError('Index "$key" out of bounds');
    } else if (key is String && isObject) {
      return (value as Map<String, DynamicValue>).putIfAbsent(key, () => throw StateError('Key "$key" not found'));
    }
    throw StateError('Invalid key type: ${key.runtimeType}');
  }

  operator []=(dynamic key, dynamic passed) {
    DynamicValue innerValue;
    if (passed is DynamicValue) {
      innerValue = passed;
    } else {
      if (passed is LinkedHashMap<String, dynamic>) {
        innerValue = DynamicValue.fromMap(passed);
      } else if (passed is Map) {
        throw ArgumentError('Unstable ordering, will not result in correct structures.');
      } else if (passed is List) {
        innerValue = DynamicValue.fromList(passed);
      } else {
        NodeId? foundType = contains(key) ? this[key].typeId : null;
        innerValue = DynamicValue(value: passed, typeId: foundType);
      }
    }
    if (key is int) {
      if (isNull) value = <DynamicValue>[];
      if (isArray) {
        var list = value as List<DynamicValue>;
        if (key > list.length) {
          throw StateError('Index "$key" out of bounds');
        } else if (key == list.length) {
          list.add(innerValue);
        } else {
          list[key] = innerValue;
        }
      } else {
        throw StateError('DynamicValue is not an array');
      }
    } else if (key is String) {
      if (isNull) {
        value = LinkedHashMap<String, DynamicValue>();
      }
      if (isObject) {
        (value as LinkedHashMap<String, DynamicValue>)[key] = innerValue;
      } else {
        throw StateError('DynamicValue is not an object');
      }
    }
  }

  List<T> toList<T>(T Function(DynamicValue)? converter) {
    if (!isArray) return [];
    final list = asArray;
    return converter != null ? list.map(converter).toList() : [];
  }

  Map<String, T> toMap<T>(T Function(DynamicValue)? converter) {
    if (!isObject) return {};
    final map = asObject;
    return converter != null ? map.map((k, v) => MapEntry(k, converter(v))) : {};
  }

  Iterable<MapEntry<String, DynamicValue>> get entries {
    if (!isObject) {
      throw StateError('DynamicValue is not an object');
    }
    return (value as LinkedHashMap<String, DynamicValue>).entries;
  }

  @override
  String toString() {
    if (enumFields != null) {
      if (value == null) {
        return "null";
      }
      return "${enumFields![value]?.name}(${value.toString()})";
    }
    return "${displayName == null ? '' : displayName!.value} ${description == null ? '' : description!.value} ${value?.toString() ?? 'null'}";
  }

  static double? _parseDouble(dynamic val) {
    if (val is double) return val;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  static int? _parseInt(dynamic val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  static bool? _parseBool(dynamic val) {
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final lc = val.trim().toLowerCase();
      return (lc == 'true' || lc == '1');
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic val) {
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    return null;
  }
}
