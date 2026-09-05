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
///
/// ## Locked
///
/// [locked] renders the same row with the value still legible, a lock beside
/// it, and the tap going to [onLockedTap] instead of to a cursor. It is
/// **never** disabled, greyed or silently read-only: the acceptance criterion
/// is that no control is ever greyed and inert, and a field an operator can
/// see but not understand is worse than one that explains itself.
///
/// **This widget knows nothing about keys, members or permissions.** The pane
/// that builds it does, and it passes the answer in. That keeps the field
/// usable in a pane with no key at all, and keeps the one place the decision
/// is made (`tag_access_guard.dart`) from acquiring a second copy in here.
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
    this.locked = false,
    this.onLockedTap,
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

  /// Whether the session in force may write this setpoint.
  final bool locked;

  /// What a tap on the locked field does -- normally opening the elevation
  /// prompt via `guardTagWrite`. Null means the tap does nothing, which is the
  /// only shape of this widget that *is* inert, so callers passing
  /// [locked] should pass this too.
  final VoidCallback? onLockedTap;

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
    if (widget.locked != oldWidget.locked) _lockChanged();
  }

  /// The unlock is the acceptance criterion, and it is half a sentence long:
  /// *"a value field goes live and focused but uncommitted"*.
  ///
  /// So: take the focus, and do **nothing else**. [_commit] is not called,
  /// [_pending] is not touched, and [onSubmitted] does not fire. The operator
  /// gets the affordance back; making the change is still theirs to do, and
  /// `kAccessDeniedNoReplayNote` is what told them so. Re-submitting here
  /// would be "helpful" and would be the exact replay the requirement forbids
  /// (T-04-34).
  ///
  /// Post-frame because the editable field does not exist yet: this runs
  /// during the rebuild that creates it, and a [FocusNode] that is not
  /// attached cannot take focus.
  void _lockChanged() {
    if (widget.locked) {
      // Going the other way: a field that was focused when the session
      // dropped must not keep a cursor in a box that is no longer editable.
      _focus.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.locked) _focus.requestFocus();
    });
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

  /// The locked row: the same decoration, the same box, the value still
  /// readable, and a lock where the cursor would go.
  ///
  /// Built from [InputDecorator] rather than from the [TextFormField] with
  /// something switched off. Both of the obvious switches are forbidden:
  /// disabling the field greys it, which the acceptance criteria rule out
  /// outright, and making it silently uneditable teaches the operator that
  /// the panel is broken. What is left is a field that is not there: an
  /// identical decoration around a [Text], with the whole row wrapped in a
  /// [GestureDetector] so the tap reaches [SetpointField.onLockedTap] instead
  /// of a focus request.
  ///
  /// A grep in `04-06-PLAN.md` pins both of those spellings at zero in this
  /// file, so the shape cannot quietly regress into the greyed one.
  ///
  /// `HitTestBehavior.opaque` so the padding around the number is part of the
  /// target too. On a touch HMI the number itself is a small thing to hit.
  Widget _lockedField(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onLockedTap,
      child: Semantics(
        label: 'Locked. ${widget.label}',
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.label,
            suffixText: widget.suffix,
            isDense: true,
            suffixIcon: Icon(
              Icons.lock_outline,
              size: _lockGlyphSize,
              // Not orange, which means forced/override and elevation, and not
              // red, which is a fault. The same colour the denial prompt and
              // `AccessLockBadge` paint their locks.
              color: theme.colorScheme.onSurfaceVariant,
            ),
            // Without this the suffix icon claims Material's 48x48 minimum and
            // the locked row grows taller than the same row unlocked -- which
            // is the "the lock pushed the value out of the box" defect the
            // height test exists to catch.
            suffixIconConstraints: const BoxConstraints(
              minWidth: _lockGlyphSize,
              minHeight: _lockGlyphSize,
            ),
          ),
          isEmpty: false,
          // The value, at the field's own text style, so the number does not
          // change size when a lock appears on it.
          child: Text(
            widget.text,
            key: Key('${widget.fieldKey}_locked_value'),
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }

  /// Matches `AccessLockBadge.glyphSize`: the lock annotates the field, it is
  /// not a second subject in it.
  static const double _lockGlyphSize = 16.0;

  @override
  Widget build(BuildContext context) {
    if (widget.locked) return _lockedField(context);
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
