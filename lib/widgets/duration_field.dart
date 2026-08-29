import 'package:flutter/material.dart';

import 'number_slider.dart' show parseTypedNumber;

/// The units a [DurationField] can be read and typed in.
///
/// The full ladder exists because the plant needs both ends — the collector
/// samples in microseconds and a certificate lives for days — but no single
/// field should offer all of it. Restrict each field's [DurationField.units]
/// to the units its setting is actually said in: offering days on a channel
/// lifetime invites a lifetime of three.
enum DurationUnit {
  microseconds('µs', 1),
  milliseconds('ms', Duration.microsecondsPerMillisecond),
  seconds('s', Duration.microsecondsPerSecond),
  minutes('min', Duration.microsecondsPerMinute),
  hours('h', Duration.microsecondsPerHour),
  days('d', Duration.microsecondsPerDay);

  const DurationUnit(this.label, this.micros);

  /// Shown in the dropdown and in [formatDuration].
  final String label;

  /// How many microseconds one of this unit is worth.
  final int micros;
}

/// Renders [d] as a number and a unit, picking the largest of [units] that
/// divides it evenly — 600000 ms reads as "10 min", 4500 ms as "4.5 s".
///
/// When nothing divides evenly the smallest allowed unit wins, so the figure
/// stays exact rather than rounding behind the reader's back.
String formatDuration(Duration d,
    {List<DurationUnit> units = DurationUnit.values}) {
  final unit = _unitFor(d.inMicroseconds, units);
  return '${_numberText(d.inMicroseconds, unit)} ${unit.label}';
}

DurationUnit _unitFor(int micros, List<DurationUnit> units) {
  final allowed = units.isEmpty ? DurationUnit.values : units;
  final largestFirst = allowed.toList()
    ..sort((a, b) => b.micros.compareTo(a.micros));
  for (final unit in largestFirst) {
    if (micros % unit.micros == 0) return unit;
  }
  return largestFirst.last;
}

/// The number half of the read-out, without a trailing `.0`.
String _numberText(int micros, DurationUnit unit) {
  final value = micros / unit.micros;
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}

/// A single-row duration input: a number, and the unit it is in.
///
/// Exists because the alternative is counting zeros. A channel lifetime typed
/// as `600000` is a field where 60000 and 6000000 look the same at a glance,
/// and the operator setting it is thinking "ten minutes" anyway. This shows
/// ten and a unit, and stores the exact [Duration] underneath.
///
/// Design decisions, so every caller behaves the same way:
///
/// * **Reading**: the value is shown in the largest allowed unit that divides
///   it evenly (`600000 ms` → `10 min`), falling back to the smallest so the
///   figure is never rounded behind the reader's back.
/// * **Changing the unit keeps the number** — picking `s` while `10 min` is
///   showing gives `10 s`, not `600 s`. That is the move someone makes on
///   realising they chose the wrong unit; converting instead would leave
///   them clearing the box before they can type.
/// * **A half-typed box commits nothing.** Empty or unparseable text emits no
///   value, so `12` on the way to `120` never becomes a setting. Callers
///   that mean something by empty — "same as open time", "no schedule" —
///   pass [onCleared] and get told exactly once when the box is emptied.
/// * **Out-of-range input is clamped, and the box is rewritten to what was
///   actually stored** when the clamp came from a unit switch — a field
///   claiming `100` when `5 s` was saved is worse than the correction.
/// * **The helper line always opens with the accepted range**, in the
///   field's own units, so the bounds are on screen before they bite.
class DurationField extends StatefulWidget {
  const DurationField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.labelText,
    required this.min,
    required this.max,
    this.units = DurationUnit.values,
    this.resolution,
    this.onCleared,
    this.hintText,
    this.helperText,
    this.prefixIcon,
    this.isDense = false,
  });

  /// Null renders an empty box (with [hintText] if given) — the state of a
  /// setting that is unset rather than zero.
  final Duration? value;

  final ValueChanged<Duration> onChanged;
  final String labelText;

  /// Typed values are clamped into [min]..[max] before they are emitted.
  final Duration min;
  final Duration max;

  /// Units offered in the dropdown, smallest first by convention. A null
  /// [value] seeds the dropdown with the first entry.
  final List<DurationUnit> units;

  /// Emitted values are rounded to the nearest multiple of this.
  ///
  /// For settings whose storage is coarser than a [Duration] — a config that
  /// serialises whole minutes cannot hold the 90 s a typed `1.5 min` means,
  /// and silently truncating on save would betray what the box showed. Null
  /// keeps microsecond precision.
  final Duration? resolution;

  /// Called when the operator empties the box, for settings where empty
  /// means something ("same as open time", "no schedule"). When null,
  /// emptying the box is treated as half-typed input and commits nothing.
  final VoidCallback? onCleared;

  /// Shown in the empty box; pair with [onCleared] to say what empty means.
  final String? hintText;

  /// Appended after the accepted range, which is always shown.
  final String? helperText;

  final Widget? prefixIcon;

  /// Tightens the field for inline rows (poll-group tables and the like).
  /// Dense fields drop the range helper — a table row has no room for it,
  /// and the clamp still enforces it.
  final bool isDense;

  @override
  State<DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<DurationField> {
  late TextEditingController _controller;
  late DurationUnit _unit;

  @override
  void initState() {
    super.initState();
    _seedFromValue();
  }

  void _seedFromValue() {
    final value = widget.value;
    if (value == null) {
      _unit = widget.units.isEmpty ? DurationUnit.milliseconds : widget.units.first;
      _controller = TextEditingController();
    } else {
      _unit = _unitFor(value.inMicroseconds, widget.units);
      _controller =
          TextEditingController(text: _numberText(value.inMicroseconds, _unit));
    }
  }

  @override
  void didUpdateWidget(covariant DurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-seed when the value changed underneath us — an import, or a
    // card rebuilt around a different server. Re-seeding on every rebuild
    // would fight the operator's cursor mid-word.
    if (widget.value == oldWidget.value || widget.value == _typedValue()) {
      return;
    }
    final value = widget.value;
    if (value == null) {
      _controller.text = '';
    } else {
      _unit = _unitFor(value.inMicroseconds, widget.units);
      _controller.text = _numberText(value.inMicroseconds, _unit);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// What is in the box right now, or null if it is not a number yet.
  Duration? _typedValue() {
    final number = parseTypedNumber(_controller.text);
    if (number == null) return null;
    return Duration(microseconds: (number * _unit.micros).round());
  }

  Duration _clamp(Duration d) {
    final res = widget.resolution;
    final snapped = res == null || res <= Duration.zero
        ? d
        : Duration(
            microseconds: (d.inMicroseconds / res.inMicroseconds).round() *
                res.inMicroseconds);
    return snapped < widget.min
        ? widget.min
        : snapped > widget.max
            ? widget.max
            : snapped;
  }

  void _onTextChanged(String text) {
    final typed = _typedValue();
    if (typed == null) {
      if (text.trim().isEmpty) widget.onCleared?.call();
      return;
    }
    widget.onChanged(_clamp(typed));
  }

  void _onUnitChanged(DurationUnit? unit) {
    if (unit == null || unit == _unit) return;
    setState(() => _unit = unit);
    final typed = _typedValue();
    if (typed == null) return;
    final clamped = _clamp(typed);
    // A number that was in range under the old unit may not be under the new
    // one — 10 becomes 10 h on a field that stops at 24 h fine, but 100 does
    // not. Show what was actually stored rather than leaving the box
    // claiming a value the config does not hold.
    if (clamped != typed) {
      _controller.text = _numberText(clamped.inMicroseconds, _unit);
    }
    widget.onChanged(clamped);
  }

  String get _rangeText =>
      '${formatDuration(widget.min, units: widget.units)}–'
      '${formatDuration(widget.max, units: widget.units)}';

  @override
  Widget build(BuildContext context) {
    final helper = widget.isDense
        ? null
        : widget.helperText == null
            ? _rangeText
            : '$_rangeText · ${widget.helperText}';

    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        helperText: helper,
        helperMaxLines: 2,
        prefixIcon: widget.prefixIcon,
        isDense: widget.isDense,
        suffixIcon: Padding(
          padding: EdgeInsets.only(left: 8, right: widget.isDense ? 4 : 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<DurationUnit>(
              value: _unit,
              isDense: true,
              // The unit is a modifier on the number beside it, not a
              // heading — it should not out-weigh the value it qualifies.
              style: Theme.of(context).textTheme.bodyMedium,
              onChanged: _onUnitChanged,
              items: [
                for (final unit in widget.units)
                  DropdownMenuItem(value: unit, child: Text(unit.label)),
              ],
            ),
          ),
        ),
        // Lets the dropdown size to its content instead of being squeezed
        // into the icon box a suffix normally gets.
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: _onTextChanged,
    );
  }
}
