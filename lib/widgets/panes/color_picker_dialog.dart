import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../converter/color_converter.dart';
// `RecentColors` is a static-only class with no `ref` to read
// `localPreferencesProvider` from, so it calls the factory instead. A widgets
// file importing a provider file is unusual here; the import is what keeps
// this site inside spec §6's one-construction-site rule.
import '../../providers/preferences.dart' show createDeviceLocalPreferences;
import '../../theme.dart';
import 'pane_chrome.dart';
import 'standard_dialog.dart';

/// The quick-pick strip: the active color scheme's own colours — equipment
/// states (running, manual, cleaning, stopped, fault, unknown) and the main
/// theme roles — plus white and black. Most picks are one tap here instead
/// of a hunt through the HSV square, and everything on offer already fits
/// the scheme. The full picker below stays for tweaking.
List<(HmiColorRole?, Color)> colorPickerSwatches(BuildContext context) => [
      for (final role in HmiColorRole.values) (role, role.resolve(context)),
      (null, Colors.white),
      (null, Colors.black),
    ];

/// Colours the operator actually settled on, newest first, persisted across
/// restarts.
///
/// The point is "make this LED the same blue as the last one" without
/// remembering an RGB value: confirm a colour with Done once and it is a
/// one-tap swatch in every later dialog. Presets are not recorded — they are
/// already in the strip.
abstract final class RecentColors {
  static const String prefsKey = 'color_picker_recent_colors';
  static const int max = 8;

  /// In-memory copy, so the strip renders without an async gap once any
  /// dialog has loaded it. Null until first [load].
  static List<Color>? _cache;

  static Future<List<Color>> load() async {
    if (_cache != null) return _cache!;
    // A broken preferences store must never take the colour picker with it —
    // the strip just starts empty.
    List<String> stored;
    try {
      stored =
          await createDeviceLocalPreferences().getStringList(prefsKey) ?? [];
    } catch (_) {
      stored = [];
    }
    _cache = [
      for (final s in stored)
        if (int.tryParse(s, radix: 16) case final v?) Color(v),
    ];
    return _cache!;
  }

  /// Records a confirmed pick: move-to-front, capped at [max]. Colours in
  /// [skipArgb] (the theme strip on display) are skipped — recording them
  /// would only duplicate the strip.
  static Future<void> add(Color color, {Set<int> skipArgb = const {}}) async {
    if (skipArgb.contains(color.toARGB32())) {
      return;
    }
    final list = List<Color>.of(await load())
      ..removeWhere((c) => c.toARGB32() == color.toARGB32())
      ..insert(0, color);
    if (list.length > max) list.removeRange(max, list.length);
    _cache = list;
    try {
      await createDeviceLocalPreferences().setStringList(
        prefsKey,
        [for (final c in list) c.toARGB32().toRadixString(16)],
      );
    } catch (_) {
      // The in-memory copy still works for this session; Done is called
      // fire-and-forget, so a throw here would surface as an unhandled
      // async error over nothing.
    }
  }

  /// Test seam: forget the in-memory copy so the next [load] re-reads
  /// whatever the (mocked) store holds.
  @visibleForTesting
  static void resetCache() => _cache = null;
}

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

/// [ColorPickerRow] for [AssetColor] fields: the swatch shows the resolved
/// colour, the trailing label names the role ("Running", "Primary") when the
/// value follows the theme, and the dialog is role-aware.
class AssetColorPickerRow extends StatelessWidget {
  final String label;
  final AssetColor color;
  final ValueChanged<AssetColor> onChanged;
  final String? subtitle;
  final bool enableAlpha;

  const AssetColorPickerRow({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
    this.subtitle,
    this.enableAlpha = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showAssetColorPickerDialog(
        context: context,
        title: label,
        subtitle: subtitle,
        initialColor: color,
        onChanged: onChanged,
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
                color: color.resolve(context),
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            if (color.role case final role?) ...[
              Text(
                role.displayName,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(width: 4),
            ],
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
}) async {
  final picked = await _showPickerDialog(
    context: context,
    initial: AssetColor.literal(initialColor),
    onChanged: onChanged == null ? null : (c) => onChanged(c.resolve(context)),
    onCleared: onCleared,
    title: title,
    subtitle: subtitle,
    enableAlpha: enableAlpha,
    // Plain-Color callers can't store a role — a theme swatch tap becomes
    // the swatch's current literal value.
    roleAware: false,
  );
  if (picked == null) return null;
  if (!context.mounted) return picked.literal;
  return picked.resolve(context);
}

/// [showColorPickerDialog] for [AssetColor] fields: theme-strip picks return
/// the *role* (so the asset follows scheme switches), HSV picks a literal.
Future<AssetColor?> showAssetColorPickerDialog({
  required BuildContext context,
  required AssetColor initialColor,
  ValueChanged<AssetColor>? onChanged,
  String title = 'Select colour',
  String? subtitle,
  bool enableAlpha = true,
}) {
  return _showPickerDialog(
    context: context,
    initial: initialColor,
    onChanged: onChanged,
    onCleared: null,
    title: title,
    subtitle: subtitle,
    enableAlpha: enableAlpha,
    roleAware: true,
  );
}

Future<AssetColor?> _showPickerDialog({
  required BuildContext context,
  required AssetColor initial,
  required ValueChanged<AssetColor>? onChanged,
  required VoidCallback? onCleared,
  required String title,
  required String? subtitle,
  required bool enableAlpha,
  required bool roleAware,
}) {
  final swatches = colorPickerSwatches(context);
  final swatchArgb = {for (final (_, c) in swatches) c.toARGB32()};
  var picked = initial;
  return showStandardDialog<AssetColor>(
    context: context,
    title: title,
    subtitle: subtitle,
    icon: Icons.palette,
    width: 420,
    builder: (dialogContext) => _ColorPickerContent(
      initialColor: initial.role != null
          ? initial.resolve(dialogContext)
          : initial.literal!,
      initialRole: initial.role,
      swatches: swatches,
      roleAware: roleAware,
      enableAlpha: enableAlpha,
      onPicked: (c) {
        picked = c;
        onChanged?.call(c);
      },
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
        onPressed: () {
          // Fire-and-forget: the recents strip is a convenience, and a
          // failed preferences write must not hold the dialog open. Role
          // picks are not recorded — they are already in the strip.
          if (picked.literal case final c?) {
            RecentColors.add(c, skipArgb: swatchArgb);
          }
          Navigator.of(dialogContext).pop(picked);
        },
      ),
    ],
  );
}

/// Quick-pick strip (recents + theme swatches) over the full HSV picker.
///
/// Tapping a swatch is a full selection — it streams through [onPicked]
/// like a drag would, and the HSV picker below jumps to it (its
/// `didUpdateWidget` re-syncs from `pickerColor`), so a preset can still be
/// tweaked before Done. In role-aware mode a theme swatch selects the *role*;
/// any HSV/recents interaction demotes the pick back to a literal.
class _ColorPickerContent extends StatefulWidget {
  final Color initialColor;
  final HmiColorRole? initialRole;
  final List<(HmiColorRole?, Color)> swatches;
  final bool roleAware;
  final bool enableAlpha;
  final ValueChanged<AssetColor> onPicked;

  const _ColorPickerContent({
    required this.initialColor,
    required this.initialRole,
    required this.swatches,
    required this.roleAware,
    required this.enableAlpha,
    required this.onPicked,
  });

  @override
  State<_ColorPickerContent> createState() => _ColorPickerContentState();
}

class _ColorPickerContentState extends State<_ColorPickerContent> {
  late Color _current = widget.initialColor;
  late HmiColorRole? _currentRole = widget.initialRole;
  List<Color> _recents = RecentColors._cache ?? const [];

  @override
  void initState() {
    super.initState();
    // Usually a no-op thanks to the cache; first dialog after launch loads
    // from disk and the strip appears a frame later.
    RecentColors.load().then((r) {
      if (mounted && r.isNotEmpty) setState(() => _recents = r);
    });
  }

  void _select(Color c, {HmiColorRole? role}) {
    setState(() {
      _current = c;
      _currentRole = role;
    });
    widget.onPicked(widget.roleAware && role != null
        ? AssetColor.role(role)
        : AssetColor.literal(c));
  }

  Widget _swatch(Color c, {HmiColorRole? role}) {
    final selected = role != null && widget.roleAware
        ? role == _currentRole
        : _currentRole == null && c.toARGB32() == _current.toARGB32();
    final scheme = Theme.of(context).colorScheme;
    final swatch = InkWell(
      onTap: () => _select(c, role: role),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 2.5 : 1,
          ),
        ),
      ),
    );
    if (role == null) return swatch;
    return Tooltip(message: role.displayName, child: swatch);
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_recents.isNotEmpty) ...[
          Text('Recent', style: labelStyle),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final c in _recents) _swatch(c)],
          ),
          const SizedBox(height: 8),
        ],
        Text(widget.roleAware ? 'Theme (follows color scheme)' : 'Theme',
            style: labelStyle),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (role, c) in widget.swatches) _swatch(c, role: role)
          ],
        ),
        const SizedBox(height: 8),
        ColorPicker(
          pickerColor: _current,
          enableAlpha: widget.enableAlpha,
          // The HMI runs landscape, where the picker's side-by-side layout
          // is ~640px wide — it overflows the 420px dialog. The stacked
          // portrait layout fits at any orientation.
          portraitOnly: true,
          onColorChanged: (c) {
            // No setState: the picker paints its own drag feedback, and a
            // rebuild here would fight it. _current still tracks the value
            // so the strip's selection ring is right on the next rebuild.
            _current = c;
            _currentRole = null;
            widget.onPicked(AssetColor.literal(c));
          },
          pickerAreaHeightPercent: 0.8,
        ),
      ],
    );
  }
}
