/// The page editor's multi-select property editor: one row per setting the
/// whole selection has in common, showing the shared value or that the
/// selection disagrees about it.
///
/// The disagreeing case is the interesting one, and is why this exists rather
/// than "open the config form N times". A row whose assets hold different
/// values shows [_mixedLabel] instead of a value; typing one in writes it to
/// every selected asset, which is how a setting that was not common across
/// the selection becomes common — the move EPLAN's property dialog is built
/// around.
///
/// Rows come from [Asset.bulkProperties]; see `bulk_property.dart` for how a
/// selection is reduced to the settings its assets share.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../converter/color_converter.dart' show AssetColor;
import '../page_creator/assets/common.dart';
import 'panes/color_picker_dialog.dart';
import 'panes/pane_chrome.dart';

/// Shown in place of a value the selection does not agree on.
const String _mixedLabel = 'Multiple values';

/// Text that is present but not the point: the "Multiple values" hint, a
/// unit suffix, the pencil on a swatch.
///
/// Derived from `onSurface` rather than taken from `colorScheme.outline`:
/// neither Solarized scheme sets `outline`, so it falls back to a Material
/// default that is all but invisible against the dark surface — every hint
/// and border in this pane disappeared on a dark station. Alpha over the
/// theme's own body colour tracks both.
Color _mutedOn(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);

/// Field borders and swatch rings — quieter again than [_mutedOn].
Color _lineOn(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);

/// The row for the property with this id. Rows are addressed by property id
/// rather than by their visible label so a test does not break when a label
/// is reworded, and so a mixed row — which shows no value at all — is still
/// findable.
Key bulkRowKey(String propertyId) => Key('bulk-row:$propertyId');

/// The control inside [bulkRowKey]'s row: the text field, checkbox, dropdown
/// or swatch, depending on the property's type.
Key bulkControlKey(String propertyId) => Key('bulk-control:$propertyId');

/// The body of the properties pane.
///
/// Writes land straight on the assets, the same way the single-asset config
/// forms do. [onBeforeChange] runs once before the first write of an edit so
/// the editor can open an undo entry for it, and [onChanged] runs after so
/// the canvas repaints.
class BulkPropertyEditor extends StatefulWidget {
  /// The assets being edited, in selection order. May be a single asset —
  /// the rows then simply never read as mixed.
  final List<Asset> selection;

  /// Bumped by the editor whenever the canvas changes underneath the pane
  /// (an arrow-key nudge, a drag, an undo), so the rows re-read their values
  /// instead of showing what they held when the pane opened.
  final Listenable? revision;

  final VoidCallback onBeforeChange;
  final VoidCallback onChanged;

  const BulkPropertyEditor({
    super.key,
    required this.selection,
    required this.onBeforeChange,
    required this.onChanged,
    this.revision,
  });

  @override
  State<BulkPropertyEditor> createState() => _BulkPropertyEditorState();
}

class _BulkPropertyEditorState extends State<BulkPropertyEditor> {
  /// One per text-backed row, kept across rebuilds so typing is not
  /// interrupted, and keyed by the slot id rather than by position — a
  /// selection change reshuffles the rows.
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    widget.revision?.addListener(_onRevision);
  }

  @override
  void didUpdateWidget(BulkPropertyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      oldWidget.revision?.removeListener(_onRevision);
      widget.revision?.addListener(_onRevision);
    }
  }

  @override
  void dispose() {
    widget.revision?.removeListener(_onRevision);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  /// Opens one undo entry, applies [write], and repaints the canvas.
  ///
  /// Every row goes through here so that a bulk edit is one Ctrl+Z, not one
  /// per asset it touched.
  void _edit(VoidCallback write) {
    widget.onBeforeChange();
    setState(write);
    widget.onChanged();
  }

  /// Whether writing [next] to [slot] would change nothing.
  ///
  /// A field commits on Enter *and* on losing focus, so pressing Enter and
  /// then clicking away sends the same value twice; without this that is two
  /// undo entries for one edit, and the operator's first Ctrl+Z appears to do
  /// nothing. A disagreeing selection is never "already" anything — writing
  /// one asset's value to all of them is exactly the edit being made.
  bool _isAlready(BulkPropertySlot slot, Object? next) =>
      !slot.isMixed && slot.value == next;

  TextEditingController _controllerFor(String id, String text) {
    final existing = _controllers[id];
    if (existing == null) {
      return _controllers[id] = TextEditingController(text: text);
    }
    // Only overwrite what the operator is not currently typing into: a
    // revision tick mid-edit would otherwise snatch the caret back to the
    // asset's stored value on every keystroke-triggered repaint.
    if (!(_focusNodes[id]?.hasFocus ?? false) && existing.text != text) {
      existing.text = text;
    }
    return existing;
  }

  FocusNode _focusFor(String id) =>
      _focusNodes[id] ??= FocusNode(debugLabel: 'bulk:$id');

  @override
  Widget build(BuildContext context) {
    final groups = groupBulkProperties(
      commonBulkProperties(
        [for (final asset in widget.selection) asset.bulkProperties],
      ),
    );

    if (groups.isEmpty) {
      return _EmptyState(count: widget.selection.length);
    }

    return ListView(
      primary: false,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (final group in groups)
          PaneSection(
            title: group.name,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final slot in group.slots) _row(context, slot),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, BulkPropertySlot slot) {
    final property = slot.first;
    return switch (property) {
      NumberBulkProperty() => _numberRow(slot, property),
      TextBulkProperty() => _textRow(slot, property),
      BoolBulkProperty() => _boolRow(slot),
      ChoiceBulkProperty() => _choiceRow(context, slot, property),
      ColorBulkProperty() => _colorRow(context, slot, property),
      AssetColorBulkProperty() => _assetColorRow(context, slot),
    };
  }

  // ---------------------------------------------------------------- numbers

  Widget _numberRow(BulkPropertySlot slot, NumberBulkProperty property) {
    final mixed = slot.isMixed;
    final value = mixed ? null : slot.value as num?;
    final controller = _controllerFor(
      slot.id,
      value == null ? '' : _formatNumber(value, property.decimals),
    );

    void commit(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        // An empty box is "leave these as they are" for a field that cannot
        // hold nothing; for one that can it is how the selection is put back
        // on the default.
        if (property.nullable && !_isAlready(slot, null)) {
          _edit(() => slot.write(null));
        } else {
          setState(() {});
        }
        return;
      }
      final parsed = double.tryParse(trimmed.replaceAll(',', '.'));
      if (parsed == null) {
        // Re-render from the assets, which discards the unparseable text
        // rather than leaving it sitting there looking applied.
        setState(() {});
        return;
      }
      if (_isAlready(slot, parsed)) return;
      _edit(() => slot.write(parsed));
    }

    return _RowFrame(
      key: bulkRowKey(slot.id),
      label: slot.label,
      child: _Field(
        key: bulkControlKey(slot.id),
        controller: controller,
        focusNode: _focusFor(slot.id),
        hintText: mixed ? _mixedLabel : null,
        suffixText: property.unit,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9eE\+\-\.,]')),
        ],
        onCommitted: commit,
      ),
    );
  }

  /// A number as a field value: [decimals] places, but without the trailing
  /// zeros that make an angle of 90 read as `90.00` in a box you are about to
  /// type into.
  static String _formatNumber(num value, int decimals) {
    if (value is int || value == value.roundToDouble()) {
      return value.round().toString();
    }
    final fixed = value.toStringAsFixed(decimals);
    return fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : fixed;
  }

  // ------------------------------------------------------------------- text

  Widget _textRow(BulkPropertySlot slot, TextBulkProperty property) {
    final mixed = slot.isMixed;
    final value = mixed ? null : slot.value as String?;
    final controller = _controllerFor(slot.id, value ?? '');

    return _RowFrame(
      key: bulkRowKey(slot.id),
      label: slot.label,
      child: _Field(
        key: bulkControlKey(slot.id),
        controller: controller,
        focusNode: _focusFor(slot.id),
        hintText: mixed ? _mixedLabel : null,
        onCommitted: (raw) {
          // Unlike a number field, an empty string is a legitimate thing to
          // want here — clearing labels off a row of assets — so it is
          // written rather than treated as "no change".
          final next = raw.isEmpty ? null : raw;
          if (_isAlready(slot, next)) return;
          _edit(() => slot.write(next));
        },
      ),
    );
  }

  // ------------------------------------------------------------------ bools

  Widget _boolRow(BulkPropertySlot slot) {
    final mixed = slot.isMixed;
    final value = mixed ? null : slot.value as bool;

    return _RowFrame(
      key: bulkRowKey(slot.id),
      label: slot.label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              key: bulkControlKey(slot.id),
              // Tristate only while the selection disagrees: the null state
              // is a report, not something an operator can choose, so the
              // tap below always resolves it to a real value.
              tristate: mixed,
              value: value,
              onChanged: (_) => _edit(() => slot.write(!(value ?? false))),
            ),
            if (mixed) const _MixedTag(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- choices

  Widget _choiceRow(
    BuildContext context,
    BulkPropertySlot slot,
    ChoiceBulkProperty<Object> property,
  ) {
    final mixed = slot.isMixed;
    return _RowFrame(
      key: bulkRowKey(slot.id),
      label: slot.label,
      child: DropdownButtonFormField<Object>(
        key: bulkControlKey(slot.id),
        initialValue: mixed ? null : slot.value,
        isDense: true,
        isExpanded: true,
        decoration: _fieldDecoration(context, hintText: null),
        hint: mixed ? const Text(_mixedLabel) : null,
        items: [
          for (final option in property.optionValues)
            DropdownMenuItem<Object>(
              value: option,
              child: Text(property.labelForOption(option)),
            ),
        ],
        onChanged: (picked) {
          if (picked == null) return;
          _edit(() => slot.write(picked));
        },
      ),
    );
  }

  // ----------------------------------------------------------------- colour

  Widget _colorRow(
    BuildContext context,
    BulkPropertySlot slot,
    ColorBulkProperty property,
  ) {
    final mixed = slot.isMixed;
    final value = mixed ? null : slot.value as Color?;

    return _RowFrame(
      key: bulkRowKey(slot.id),
      label: slot.label,
      child: _SwatchButton(
        key: bulkControlKey(slot.id),
        color: value,
        mixed: mixed,
        onTap: () {
          // Once, before the picker streams its live updates — the drag is
          // one edit, so it gets one undo entry.
          widget.onBeforeChange();
          showColorPickerDialog(
            context: context,
            title: slot.label,
            subtitle: _subtitleFor(slot),
            initialColor: value ?? Theme.of(context).colorScheme.primary,
            onChanged: (picked) {
              setState(() => slot.write(picked));
              widget.onChanged();
            },
            onCleared: property.nullable
                ? () {
                    setState(() => slot.write(null));
                    widget.onChanged();
                  }
                : null,
          );
        },
      ),
    );
  }

  Widget _assetColorRow(BuildContext context, BulkPropertySlot slot) {
    final mixed = slot.isMixed;
    final value = mixed ? null : slot.value as AssetColor?;

    return _RowFrame(
      key: bulkRowKey(slot.id),
      label: slot.label,
      child: _SwatchButton(
        key: bulkControlKey(slot.id),
        color: value?.resolve(context),
        mixed: mixed,
        roleName: value?.role?.displayName,
        onTap: () {
          widget.onBeforeChange();
          showAssetColorPickerDialog(
            context: context,
            title: slot.label,
            subtitle: _subtitleFor(slot),
            initialColor: value ?? AssetColor.primary,
            onChanged: (picked) {
              setState(() => slot.write(picked));
              widget.onChanged();
            },
          );
        },
      ),
    );
  }

  /// What a picker opened from this row is about to change, spelled out —
  /// the dialog covers the canvas, so "4 assets" has to travel with it.
  static String? _subtitleFor(BulkPropertySlot slot) =>
      slot.count > 1 ? '${slot.count} assets' : null;
}

/// `label ......... control`, the shape every row shares so that the controls
/// line up down the pane instead of stepping in and out with label length.
class _RowFrame extends StatelessWidget {
  final String label;
  final Widget child;

  const _RowFrame({
    required Key super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(
  BuildContext context, {
  String? hintText,
  String? suffixText,
}) {
  final theme = Theme.of(context);
  final border = OutlineInputBorder(
    borderSide: BorderSide(color: _lineOn(context)),
  );
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    border: border,
    enabledBorder: border,
    hintText: hintText,
    hintStyle: theme.textTheme.bodySmall?.copyWith(
      color: _mutedOn(context),
      fontStyle: FontStyle.italic,
    ),
    suffixText: suffixText,
    suffixStyle: theme.textTheme.bodySmall?.copyWith(
      color: _mutedOn(context),
    ),
  );
}

/// A text box that reports its value on Enter and on losing focus, never
/// per keystroke: a bulk edit writes to every selected asset and pushes an
/// undo entry, which is not something to do halfway through a typed number.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String> onCommitted;

  const _Field({
    required Key super.key,
    required this.controller,
    required this.focusNode,
    required this.onCommitted,
    this.hintText,
    this.suffixText,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) onCommitted(controller.text);
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: _fieldDecoration(
          context,
          hintText: hintText,
          suffixText: suffixText,
        ),
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onSubmitted: onCommitted,
      ),
    );
  }
}

/// The colour control: a swatch that opens the picker, hatched when the
/// selection disagrees.
class _SwatchButton extends StatelessWidget {
  final Color? color;
  final bool mixed;
  final String? roleName;
  final VoidCallback onTap;

  const _SwatchButton({
    required Key super.key,
    required this.color,
    required this.mixed,
    required this.onTap,
    this.roleName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: mixed ? null : color,
                shape: BoxShape.circle,
                border: Border.all(color: _lineOn(context)),
              ),
              child: mixed
                  ? Icon(Icons.more_horiz, size: 14, color: _mutedOn(context))
                  : color == null
                      ? Icon(Icons.format_color_reset,
                          size: 14, color: _mutedOn(context))
                      : null,
            ),
            const SizedBox(width: 8),
            if (mixed)
              const Expanded(child: _MixedTag())
            else if (roleName != null)
              Expanded(
                child: Text(
                  roleName!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: _mutedOn(context)),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
            Icon(Icons.edit, size: 14, color: _mutedOn(context)),
          ],
        ),
      ),
    );
  }
}

/// The words for a value the selection does not agree on, in the same
/// italic-outline voice as the text fields' hint.
class _MixedTag extends StatelessWidget {
  const _MixedTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _mixedLabel,
      style: theme.textTheme.bodySmall?.copyWith(
        color: _mutedOn(context),
        fontStyle: FontStyle.italic,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// What a selection with nothing in common looks like. Only reachable if an
/// asset overrides [Asset.bulkProperties] down to nothing, since `BaseAsset`
/// gives every asset the geometry rows — but a pane that renders blank with
/// no explanation reads as a bug.
class _EmptyState extends StatelessWidget {
  final int count;

  const _EmptyState({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          count == 0
              ? 'Nothing selected.'
              : 'These $count assets have no settings in common.',
          textAlign: TextAlign.center,
          style:
              theme.textTheme.bodySmall?.copyWith(color: _mutedOn(context)),
        ),
      ),
    );
  }
}
