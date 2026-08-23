import 'package:flutter/material.dart';

/// A numeric setpoint field for a side pane. Commits on Enter and on focus
/// loss -- never per keystroke, so a half-typed value never reaches the PLC.
///
/// The conveyor and sensor panes each had their own field that documented
/// "Enter / focus-out" and only did Enter: `onFieldSubmitted` is Enter only.
/// On a touch HMI there is often no Enter, and tapping the next field or the
/// page threw the edit away. Focus loss commits here, but only when the text
/// parses and differs from the value the PLC currently reports, so tabbing
/// through the fields does not re-write every setpoint.
///
/// When the PLC reports a different value the field follows it -- unless the
/// operator is typing in it right now, in which case their text stands until
/// they commit or leave.
class SetpointField<T extends num> extends StatefulWidget {
  const SetpointField({
    required this.fieldKey,
    required this.label,
    required this.text,
    required this.current,
    required this.parse,
    required this.onSubmitted,
    this.suffix,
    this.decimal = true,
    super.key,
  });

  /// Stable id for this field within its pane, e.g. `auto_freq_field`.
  final String fieldKey;
  final String label;

  /// What the field shows for the PLC's current value, e.g. `50.00`.
  final String text;

  /// The PLC's current value, to skip a focus-out commit that changes nothing.
  final T current;

  /// Parses the typed text; null means "not a value, do nothing".
  final T? Function(String text) parse;
  final void Function(T value) onSubmitted;
  final String? suffix;
  final bool decimal;

  @override
  State<SetpointField<T>> createState() => _SetpointFieldState<T>();
}

class _SetpointFieldState<T extends num> extends State<SetpointField<T>> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);
  final FocusNode _focus = FocusNode();

  /// What was last sent and not yet echoed by the PLC. Enter commits and
  /// drops focus in the same gesture; without this the focus-out would send
  /// the same value a second time while the PLC is still answering.
  T? _pending;

  @override
  void didUpdateWidget(covariant SetpointField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      _pending = null;
      if (!_focus.hasFocus) _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit({required bool onlyIfChanged}) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final parsed = widget.parse(text);
    if (parsed == null) return;
    if (onlyIfChanged && (parsed == widget.current || parsed == _pending)) {
      return;
    }
    _pending = parsed;
    widget.onSubmitted(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _commit(onlyIfChanged: true);
      },
      child: TextFormField(
        key: Key(widget.fieldKey),
        focusNode: _focus,
        controller: _controller,
        keyboardType:
            TextInputType.numberWithOptions(decimal: widget.decimal),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: widget.suffix,
          isDense: true,
        ),
        onFieldSubmitted: (_) => _commit(onlyIfChanged: false),
      ),
    );
  }
}
