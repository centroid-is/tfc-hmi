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
