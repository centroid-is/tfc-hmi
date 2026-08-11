import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Rounds [value] onto the nearest of [divisions] steps between [min] and
/// [max], the way a `Slider` with the same divisions would land.
///
/// Exists so a typed number and a dragged one cannot disagree: without it,
/// typing 37 into a slider that only stops at multiples of 5 would leave the
/// handle between stops, and the next drag would jump.
///
/// A null or non-positive [divisions] means the slider is continuous, so the
/// value is only clamped.
double snapToDivisions({
  required double value,
  required double min,
  required double max,
  int? divisions,
}) {
  final clamped = value.clamp(min, max).toDouble();
  if (divisions == null || divisions <= 0 || max <= min) return clamped;
  final step = (max - min) / divisions;
  return (min + ((clamped - min) / step).round() * step).clamp(min, max);
}

/// Parses what an operator typed into a [NumberSlider]'s field.
///
/// Returns null when there is no number in [text] to use, in which case the
/// caller leaves the value alone rather than snapping it to zero.
///
/// Deliberately forgiving about what comes back with the number: the field
/// shows its own suffix, and re-typing "45°" or "80 %" over the top of it is
/// the obvious thing to do. A comma is read as a decimal point, which is what
/// an Icelandic or German keyboard produces.
double? parseTypedNumber(String text) {
  final cleaned =
      text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// A slider with the number beside it editable.
///
/// The read-out next to a slider used to be a `Text`, which made the slider
/// the only way in: fine for "a bit wider", useless for "exactly 45°" when the
/// track is 120px long and a pixel is three degrees. This keeps the slider for
/// the first job and takes typing for the second.
///
/// The field shows the value in whatever unit the label implies rather than
/// the raw one — [displayScale] 100 with a '%' [suffix] for the many settings
/// stored 0..1 — so what is typed matches what was read.
///
/// Edits commit on Enter or when the field loses focus, not per keystroke:
/// committing per keystroke would make "0.5" pass through 0 and then 5, and
/// each of those is a repaint of the canvas underneath.
class NumberSlider extends StatefulWidget {
  const NumberSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.displayScale = 1.0,
    this.decimals = 0,
    this.suffix = '',
    this.labelWidth,
    this.fieldWidth = 72,
    this.labelAbove = false,
  });

  /// Shown beside the track, e.g. 'Line Width:'.
  final String label;

  /// Puts the label on its own line above the track instead of beside it.
  ///
  /// Which one an editor wants is a matter of how much room its label needs:
  /// the pane opens at 520px, and "Actuation Length:" beside a track and a
  /// field leaves the track too short to aim with. Follows what each editor
  /// already did before it gained a field.
  final bool labelAbove;

  final double value;
  final double min;
  final double max;

  /// Slider stops. Null is a continuous slider; a typed value is then only
  /// clamped, never snapped.
  final int? divisions;

  final ValueChanged<double> onChanged;

  /// Multiplies [value] on the way to the field and divides on the way back,
  /// so a 0..1 setting can be read and typed as 0..100.
  final double displayScale;

  /// Decimal places in the field and in the slider's own drag label.
  final int decimals;

  /// Unit shown inside the field, e.g. '%', '°', 'px'.
  final String suffix;

  /// Fixes the label column so several sliders in a column line up. Null lets
  /// the label take its natural width.
  final double? labelWidth;

  final double fieldWidth;

  /// [value] as it is shown and typed.
  String get displayText => (value * displayScale).toStringAsFixed(decimals);

  @override
  State<NumberSlider> createState() => _NumberSliderState();
}

class _NumberSliderState extends State<NumberSlider> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.displayText);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) return;
      // Leaving the field commits it, so a value typed and then clicked away
      // from is not silently dropped.
      _commit();
    });
  }

  @override
  void didUpdateWidget(NumberSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the slider — but not while the field is being typed into, or the
    // caret would jump to the end on every keystroke.
    if (!_focus.hasFocus && widget.displayText != _controller.text) {
      _controller.text = widget.displayText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Reads the field, and either reports a new value or puts the old one back.
  void _commit() {
    final typed = parseTypedNumber(_controller.text);
    if (typed == null) {
      // Nothing usable in there — restore rather than reset to zero, so a
      // half-typed entry that is abandoned costs nothing.
      _controller.text = widget.displayText;
      return;
    }

    final snapped = snapToDivisions(
      value: typed / widget.displayScale,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
    );

    // Show what was actually taken, which is how an out-of-range or
    // off-a-stop entry explains itself: type 500 into a 0..100 and it comes
    // back 100.
    _controller.text =
        (snapped * widget.displayScale).toStringAsFixed(widget.decimals);

    if (snapped != widget.value) widget.onChanged(snapped);
  }

  @override
  Widget build(BuildContext context) {
    final track = Row(
      children: [
        if (!widget.labelAbove)
          widget.labelWidth == null
              ? Text(widget.label)
              : SizedBox(width: widget.labelWidth, child: Text(widget.label)),
        Expanded(
          child: Slider(
            value: widget.value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: '${widget.displayText}${widget.suffix}',
            onChanged: widget.onChanged,
          ),
        ),
        SizedBox(
          width: widget.fieldWidth,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
            keyboardType:
                TextInputType.numberWithOptions(decimal: widget.decimals > 0),
            // A minus is only worth allowing on a range that goes below zero.
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(widget.min < 0 ? r'[0-9.,\-]' : r'[0-9.,]'),
              ),
            ],
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              border: const OutlineInputBorder(),
              suffixText: widget.suffix.isEmpty ? null : widget.suffix,
            ),
            // Both routes out of the field go through unfocus, so the focus
            // listener is the only thing that commits. Committing here as
            // well would fire twice for one Enter — and the second pass runs
            // before the parent has rebuilt with the new value, so it reads
            // as a second distinct edit and lands twice on the undo history.
            onSubmitted: (_) => _focus.unfocus(),
            onTapOutside: (_) => _focus.unfocus(),
          ),
        ),
      ],
    );

    if (!widget.labelAbove) return track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
        track,
      ],
    );
  }
}
