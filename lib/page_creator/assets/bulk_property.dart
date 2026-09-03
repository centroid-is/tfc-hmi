/// The settings an asset offers to the page editor's multi-select property
/// editor, and the logic that reduces a whole selection to one row per
/// setting.
///
/// Every asset hand-writes its own `configure()` form, so there is no shared
/// schema to drive a bulk editor from. Nor can one be recovered from the
/// serialized JSON: a `double? labelFontSize` and a `String? label` that both
/// happen to be null are the same `null` on the wire, and a wrong guess at
/// the type would write a value that `fromJson` then throws on — which
/// `AssetRegistry.parse` swallows by dropping the asset. So assets declare
/// what may be bulk-edited, in the terms an operator sees it:
///
/// ```dart
/// @JsonKey(includeFromJson: false, includeToJson: false)
/// @override
/// List<BulkProperty> get bulkProperties => [
///       ...super.bulkProperties,
///       NumberBulkProperty(
///         id: 'AnalogBoxConfig.minValue',
///         label: 'Min value',
///         group: 'Analog Box',
///         read: () => minValue,
///         apply: (value) => minValue = value ?? minValue,
///       ),
///     ];
/// ```
///
/// A descriptor is bound to the one asset that built it — [read] and [apply]
/// close over the instance — so applying an edit is a plain field write. No
/// JSON round-trip, and no new `Asset` instance, which matters: `AssetStack`
/// keys assets by identity, and replacing them would tear down the canvas the
/// way a page reload does.
///
/// [commonBulkProperties] takes the selection's lists and keeps only what all
/// of them share, which is what makes a mixed selection degrade gracefully —
/// four drives and an LED still have geometry in common.
library;

import 'package:flutter/widgets.dart' show Color;

import '../../converter/color_converter.dart' show AssetColor;

/// One editable setting on one asset.
///
/// Subclasses carry the type, because the editor has to render a row for it
/// and there is no useful way to render "some value". Two descriptors merge
/// into one row of a multi-asset selection when they are the same subclass
/// with the same [id] — see [BulkProperty.matches].
sealed class BulkProperty {
  /// Identity of the setting, and the whole of what makes two assets' rows
  /// "the same property".
  ///
  /// Geometry and label ids are bare (`width`, `label.text`) because they
  /// mean the same thing on every asset. Asset-specific ids are prefixed
  /// with the config class (`NumberConfig.decimalPlaces`) so that two
  /// unrelated assets which happen to both call a field `units` do not merge
  /// into a row that writes one asset's notion of the word onto the other's.
  final String id;

  /// What the row is called in the pane.
  final String label;

  /// Section heading the row sits under. 'Geometry' and 'Label' come first;
  /// everything else follows in the order the asset lists it.
  final String group;

  const BulkProperty({
    required this.id,
    required this.label,
    required this.group,
  });

  /// The setting's current value on the asset this descriptor came from.
  Object? get value;

  /// Writes [value] onto that asset.
  ///
  /// Implementations ignore a value that is not their own type rather than
  /// throwing: the editor is the only caller and passes the right one, and a
  /// half-applied bulk edit is worse than a skipped one.
  void write(Object? value);

  /// Whether [other] edits the same setting, so the two can share a row.
  bool matches(BulkProperty other) =>
      other.runtimeType == runtimeType && other.id == id;
}

/// A numeric setting — `double` or `int`, optionally nullable.
///
/// [decimals] is display only; [isInt] is what decides whether typed input is
/// rounded. [min] and [max] clamp rather than reject, so a bulk edit never
/// silently drops an asset out of the group.
final class NumberBulkProperty extends BulkProperty {
  final num? Function() read;
  final void Function(num?) apply;
  final num? min;
  final num? max;
  final int decimals;
  final bool isInt;

  /// Suffix shown after the field ('%', '°', 'pt'). Purely a label.
  final String? unit;

  /// Whether clearing the field writes null. False for a non-nullable field,
  /// where an empty box means "leave these alone".
  final bool nullable;

  const NumberBulkProperty({
    required super.id,
    required super.label,
    required super.group,
    required this.read,
    required this.apply,
    this.min,
    this.max,
    this.decimals = 2,
    this.isInt = false,
    this.unit,
    this.nullable = false,
  });

  @override
  num? get value => read();

  @override
  void write(Object? value) {
    if (value == null) {
      if (nullable) apply(null);
      return;
    }
    if (value is! num) return;
    var next = value;
    if (min != null && next < min!) next = min!;
    if (max != null && next > max!) next = max!;
    apply(isInt ? next.round() : next.toDouble());
  }
}

/// An on/off setting. Never null: a checkbox with no third state is what an
/// operator expects, and every bool field in the asset configs is non-null.
final class BoolBulkProperty extends BulkProperty {
  final bool Function() read;
  final void Function(bool) apply;

  const BoolBulkProperty({
    required super.id,
    required super.label,
    required super.group,
    required this.read,
    required this.apply,
  });

  @override
  bool get value => read();

  @override
  void write(Object? value) {
    if (value is bool) apply(value);
  }
}

/// A free-text setting.
///
/// Deliberately not used for OPC UA key fields. Bulk-setting a tag name
/// points every selected asset at one signal, which is occasionally what you
/// want after a paste and much more often a mistake you cannot see on the
/// mimic — those stay in the per-asset form, where the key picker can vet
/// them one at a time.
final class TextBulkProperty extends BulkProperty {
  final String? Function() read;
  final void Function(String?) apply;

  /// Whether clearing the field writes null (or empty, for a non-nullable
  /// field) rather than leaving the assets alone.
  final bool nullable;

  const TextBulkProperty({
    required super.id,
    required super.label,
    required super.group,
    required this.read,
    required this.apply,
    this.nullable = true,
  });

  @override
  String? get value => read();

  @override
  void write(Object? value) {
    if (value == null) {
      apply(nullable ? null : '');
      return;
    }
    if (value is String) apply(value);
  }
}

/// A pick-one-of-a-fixed-set setting: an enum, rendered as a dropdown.
///
/// [options] is the full list even when the selection only uses two of them,
/// so the row can move the whole selection onto a value none of them holds.
final class ChoiceBulkProperty<T extends Object> extends BulkProperty {
  final T Function() read;
  final void Function(T) apply;
  final List<T> options;
  final String Function(T) optionLabel;

  const ChoiceBulkProperty({
    required super.id,
    required super.label,
    required super.group,
    required this.read,
    required this.apply,
    required this.options,
    required this.optionLabel,
  });

  @override
  T get value => read();

  @override
  void write(Object? value) {
    if (value is T) apply(value);
  }

  /// [options] without the type parameter.
  ///
  /// The editor renders every property kind through one switch, which erases
  /// [T] to `Object` — and `List<TextPos>` read back as `List<Object>` is
  /// fine, but `String Function(TextPos)` called as `String Function(Object)`
  /// is a runtime type error. These two accessors are the type-erased face
  /// the editor uses instead.
  List<Object> get optionValues => List<Object>.of(options);

  /// [optionLabel] for a value that has lost its type on the way here.
  /// Returns the raw `toString` for anything that is not a [T]; the editor
  /// only ever passes back what [optionValues] handed it.
  String labelForOption(Object option) =>
      option is T ? optionLabel(option) : option.toString();

  /// Same-subclass matching is not enough here: `ChoiceBulkProperty<TextPos>`
  /// and `ChoiceBulkProperty<LEDType>` are distinct runtime types, so the
  /// inherited check already separates them — but two properties over the
  /// same enum with different option lists would merge into a dropdown that
  /// cannot write half its own entries.
  @override
  bool matches(BulkProperty other) =>
      super.matches(other) &&
      other is ChoiceBulkProperty<T> &&
      _sameOptions(other.options);

  bool _sameOptions(List<T> other) {
    if (other.length != options.length) return false;
    for (var i = 0; i < options.length; i++) {
      if (other[i] != options[i]) return false;
    }
    return true;
  }
}

/// A literal colour, where null means "inherit the theme's".
final class ColorBulkProperty extends BulkProperty {
  final Color? Function() read;
  final void Function(Color?) apply;

  /// Whether "no colour" is a value this field can hold. Gives the picker its
  /// Clear action.
  final bool nullable;

  const ColorBulkProperty({
    required super.id,
    required super.label,
    required super.group,
    required this.read,
    required this.apply,
    this.nullable = false,
  });

  @override
  Color? get value => read();

  @override
  void write(Object? value) {
    if (value == null) {
      if (nullable) apply(null);
      return;
    }
    if (value is Color) apply(value);
  }
}

/// An [AssetColor] — a literal, or a reference into the active scheme that
/// re-resolves when the theme changes. Kept apart from [ColorBulkProperty]
/// because the picker is a different one and a role must survive the edit.
final class AssetColorBulkProperty extends BulkProperty {
  final AssetColor Function() read;
  final void Function(AssetColor) apply;

  const AssetColorBulkProperty({
    required super.id,
    required super.label,
    required super.group,
    required this.read,
    required this.apply,
  });

  @override
  AssetColor get value => read();

  @override
  void write(Object? value) {
    if (value is AssetColor) apply(value);
  }
}

/// One row of the bulk editor: the same setting, bound to each selected asset.
class BulkPropertySlot {
  /// One descriptor per selected asset, in selection order. Never empty.
  final List<BulkProperty> bindings;

  BulkPropertySlot(this.bindings) : assert(bindings.isNotEmpty);

  BulkProperty get first => bindings.first;
  String get id => first.id;
  String get label => first.label;
  String get group => first.group;

  /// How many assets this row writes to.
  int get count => bindings.length;

  /// Whether the selection disagrees about this setting.
  ///
  /// This is what EPLAN shows as `<<...>>`: the row has no one value to
  /// display, and typing into it is what turns a non-common parameter into a
  /// common one.
  bool get isMixed {
    final head = first.value;
    for (var i = 1; i < bindings.length; i++) {
      if (bindings[i].value != head) return true;
    }
    return false;
  }

  /// The value every selected asset holds, or null when they disagree.
  /// Callers must consult [isMixed] first — a uniform null is a real value
  /// for a nullable setting.
  Object? get value => isMixed ? null : first.value;

  /// Writes [value] onto every asset in the selection, making the setting
  /// common across it.
  void write(Object? value) {
    for (final binding in bindings) {
      binding.write(value);
    }
  }
}

/// The settings shared by every asset whose [BulkProperty] list appears in
/// [perAsset], as one slot each.
///
/// Order follows the first asset's own list, so a selection of one kind of
/// asset reads exactly like that asset's property list rather than an
/// alphabetical jumble. A property only survives if *every* other asset has
/// one that [BulkProperty.matches] it, which is what keeps a mixed selection
/// honest: four drives and an LED share geometry and their label, and the
/// drives' own fields disappear until the LED is deselected.
List<BulkPropertySlot> commonBulkProperties(List<List<BulkProperty>> perAsset) {
  if (perAsset.isEmpty) return const [];
  final rest = perAsset.skip(1).toList();

  final slots = <BulkPropertySlot>[];
  final claimed = <String>{};
  for (final candidate in perAsset.first) {
    // An asset listing the same id twice would otherwise produce two rows
    // that both write the first field.
    if (!claimed.add(candidate.id)) continue;

    final bindings = <BulkProperty>[candidate];
    for (final other in rest) {
      final match =
          other.where((property) => candidate.matches(property)).firstOrNull;
      if (match == null) {
        bindings.clear();
        break;
      }
      bindings.add(match);
    }
    if (bindings.isNotEmpty) slots.add(BulkPropertySlot(bindings));
  }
  return slots;
}

/// [slots] split into sections, in the order the groups first appear.
///
/// The pane renders sections rather than one flat list because a homogeneous
/// selection can run to a dozen rows, and 'Geometry' / 'Label' / the asset's
/// own name is the same grouping the single-asset forms already use.
List<BulkPropertyGroup> groupBulkProperties(List<BulkPropertySlot> slots) {
  final order = <String>[];
  final byGroup = <String, List<BulkPropertySlot>>{};
  for (final slot in slots) {
    final bucket = byGroup.putIfAbsent(slot.group, () {
      order.add(slot.group);
      return [];
    });
    bucket.add(slot);
  }
  return [
    for (final name in order) BulkPropertyGroup(name, byGroup[name]!),
  ];
}

/// A named section of the bulk editor.
class BulkPropertyGroup {
  final String name;
  final List<BulkPropertySlot> slots;

  const BulkPropertyGroup(this.name, this.slots);
}
