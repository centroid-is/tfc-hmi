import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'pane_chrome.dart';
import 'standard_dialog.dart';

/// The one colour picker.
///
/// Seven editors had grown their own copy of "AlertDialog + ColorPicker +
/// a button labelled Done/OK/Close", each with slightly different chrome.
/// This is that dialog, once, in the standard frame.
///
/// Colour changes stream out through [onChanged] as the operator drags, so a
/// live preview keeps working; the returned future completes with the colour
/// that was settled on (or `null` if the picker was dismissed without a
/// change, which callers may ignore).
/// Pass [onCleared] where "no colour" is a meaningful value (inherit the
/// theme, drop a per-series override) — it adds a Clear action.
/// The one colour ROW: a labelled swatch that opens [showColorPickerDialog].
///
/// Editors had two ways of picking a colour — an inline `BlockPicker` swatch
/// grid (compact but only presets) and a hand-rolled tappable circle per
/// editor. This row replaces both: the swatch shows the current value, a tap
/// opens the full picker, and every editor gets the same chrome.
///
/// [color] may be null where "no colour" means "inherit" (a theme-default
/// text colour, a per-series override) — the swatch then shows the reset
/// glyph, and passing [onCleared] gives the dialog a Clear action to get
/// back to that state.
class ColorPickerRow extends StatelessWidget {
  final String label;
  final Color? color;
  final ValueChanged<Color> onChanged;
  final VoidCallback? onCleared;
  final String? subtitle;
  final bool enableAlpha;

  const ColorPickerRow({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
    this.onCleared,
    this.subtitle,
    this.enableAlpha = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showColorPickerDialog(
        context: context,
        title: label,
        subtitle: subtitle,
        initialColor: color ?? theme.colorScheme.primary,
        onChanged: onChanged,
        onCleared: onCleared,
        enableAlpha: enableAlpha,
      ),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: color == null
                  ? Icon(
                      Icons.format_color_reset,
                      size: 16,
                      color: theme.colorScheme.outline,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Icon(Icons.edit, size: 16, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

Future<Color?> showColorPickerDialog({
  required BuildContext context,
  required Color initialColor,
  ValueChanged<Color>? onChanged,
  VoidCallback? onCleared,
  String title = 'Select colour',
  String? subtitle,
  bool enableAlpha = true,
}) {
  var picked = initialColor;
  return showStandardDialog<Color>(
    context: context,
    title: title,
    subtitle: subtitle,
    icon: Icons.palette,
    width: 420,
    builder: (_) => ColorPicker(
      pickerColor: initialColor,
      enableAlpha: enableAlpha,
      // The HMI runs landscape, where the picker's side-by-side layout is
      // ~640px wide — it overflows the 420px dialog. The stacked portrait
      // layout fits at any orientation.
      portraitOnly: true,
      onColorChanged: (c) {
        picked = c;
        onChanged?.call(c);
      },
      pickerAreaHeightPercent: 0.8,
    ),
    actionsBuilder: (dialogContext) => [
      if (onCleared != null)
        PaneAction(
          label: 'Clear colour',
          icon: Icons.format_color_reset,
          onPressed: () {
            onCleared();
            Navigator.of(dialogContext).pop();
          },
        ),
      PaneAction.primary(
        label: 'Done',
        onPressed: () => Navigator.of(dialogContext).pop(picked),
      ),
    ],
  );
}
