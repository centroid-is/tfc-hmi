import 'package:flutter/material.dart';

import 'standard_dialog.dart';

/// Shared visual vocabulary for [SidePane] and [StandardDialog].
///
/// Every equipment popup in the HMI — conveyors, elevators/lifts, 3rd party
/// devices — is assembled from the widgets in this file so that they all read
/// the same way to an operator: a header with the equipment identity and a
/// live status chip, a body of sections/tiles, and a pinned action bar.
///
/// The house rule for the body is **"no more information than a normal
/// screen"**: whatever an operator needs at a glance fits without scrolling.
/// Detail that does not fit belongs behind a [PaneGraphTile] or a
/// [PaneExpandTile], which open a free-floating [StandardDialog] on tap.

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// The live state of a piece of equipment, rendered as a pill in the pane or
/// dialog header.
///
/// Use the named constructors for the common states so colours stay
/// consistent across every device; use the default constructor for a
/// device-specific state that does not map onto them.
@immutable
class PaneStatus {
  /// Short text shown in the chip, e.g. `Running`, `Fault`.
  final String label;

  /// Chip accent colour — drives both the dot and the pill tint.
  final Color color;

  /// Leading glyph. Defaults to a filled dot.
  final IconData icon;

  const PaneStatus({
    required this.label,
    required this.color,
    this.icon = Icons.circle,
  });

  /// Equipment is running / moving / energised.
  const PaneStatus.running([this.label = 'Running'])
      : color = Colors.green,
        icon = Icons.play_circle_fill;

  /// Equipment is healthy but idle.
  const PaneStatus.stopped([this.label = 'Stopped'])
      : color = Colors.blueGrey,
        icon = Icons.pause_circle_filled;

  /// Equipment is faulted and needs operator attention.
  const PaneStatus.fault([this.label = 'Fault'])
      : color = Colors.red,
        icon = Icons.error;

  /// Equipment is running but something needs watching.
  const PaneStatus.warning([this.label = 'Warning'])
      : color = Colors.orange,
        icon = Icons.warning_amber;

  /// The values shown are not fresh — the PLC link is down or the key has
  /// stopped updating.
  const PaneStatus.stale([this.label = 'Stale'])
      : color = Colors.amber,
        icon = Icons.cloud_off;

  /// No state key configured, or the value has not arrived yet.
  const PaneStatus.unknown([this.label = 'Unknown'])
      : color = Colors.grey,
        icon = Icons.help_outline;

  @override
  bool operator ==(Object other) =>
      other is PaneStatus &&
      other.label == label &&
      other.color == color &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(label, color, icon);
}

/// The pill that renders a [PaneStatus] in a pane/dialog header.
class PaneStatusChip extends StatelessWidget {
  final PaneStatus status;

  const PaneStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: status.color),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

/// How a [PaneAction] is rendered in the pinned action bar.
enum PaneActionStyle {
  /// Text button — secondary operations.
  plain,

  /// Filled button — the one action an operator most likely wants.
  primary,

  /// Error-coloured — writes that stop or reset equipment.
  destructive,
}

/// A single button in the pinned footer of a [SidePane] or [StandardDialog].
///
/// A null [onPressed] renders the button disabled, which is how a pane
/// signals "this command exists but is not available right now" (no write
/// key configured, interlock not satisfied, link down).
@immutable
class PaneAction {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PaneActionStyle style;

  /// Takes focus when the dialog opens, so Enter confirms without reaching
  /// for the mouse — worth setting on the confirm action of a prompt the
  /// operator answers repeatedly.
  final bool autofocus;

  /// Key applied to the rendered button, for tests and automation that
  /// address a specific action.
  final Key? buttonKey;

  const PaneAction({
    required this.label,
    this.onPressed,
    this.icon,
    this.buttonKey,
    this.style = PaneActionStyle.plain,
    this.autofocus = false,
  });

  const PaneAction.primary({
    required this.label,
    this.onPressed,
    this.icon,
    this.buttonKey,
    this.autofocus = false,
  }) : style = PaneActionStyle.primary;

  const PaneAction.destructive({
    required this.label,
    this.onPressed,
    this.icon,
    this.buttonKey,
    this.autofocus = false,
  }) : style = PaneActionStyle.destructive;

  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = icon == null ? null : Icon(icon, size: 18);
    final label = Text(this.label);
    switch (style) {
      case PaneActionStyle.primary:
        return child == null
            ? FilledButton(
                key: buttonKey,
                onPressed: onPressed,
                autofocus: autofocus,
                child: label)
            : FilledButton.icon(
                key: buttonKey,
                onPressed: onPressed,
                autofocus: autofocus,
                icon: child,
                label: label,
              );
      case PaneActionStyle.destructive:
        final style = TextButton.styleFrom(foregroundColor: scheme.error);
        return child == null
            ? TextButton(
                key: buttonKey,
                onPressed: onPressed,
                style: style,
                autofocus: autofocus,
                child: label,
              )
            : TextButton.icon(
                onPressed: onPressed,
                style: style,
                autofocus: autofocus,
                icon: child,
                label: label,
              );
      case PaneActionStyle.plain:
        return child == null
            ? TextButton(
                key: buttonKey,
                onPressed: onPressed,
                autofocus: autofocus,
                child: label)
            : TextButton.icon(
                key: buttonKey,
                onPressed: onPressed,
                autofocus: autofocus,
                icon: child,
                label: label,
              );
    }
  }
}

// ---------------------------------------------------------------------------
// Header / footer
// ---------------------------------------------------------------------------

/// The standard header: identity on the left, live status and close on the
/// right. Shared by [SidePane] and [StandardDialog] so both read identically.
class PaneHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final PaneStatus? status;
  final VoidCallback? onClose;

  /// Extra control placed left of the close button (e.g. a pin or a
  /// "open config" icon button).
  final Widget? trailing;

  /// Wraps the whole header so a floating dialog can make it a drag handle.
  final Widget Function(BuildContext context, Widget header)? wrap;

  const PaneHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.status,
    this.onClose,
    this.trailing,
    this.wrap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(width: 8),
            PaneStatusChip(status: status!),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ],
          if (onClose != null)
            IconButton(
              // Deliberately larger than Material's default: this is the
              // control an operator reaches for most, often with gloves on
              // a panel, and it sits in the corner where aim is worst.
              icon: const Icon(Icons.close, size: 28),
              iconSize: 28,
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(
                minWidth: 52,
                minHeight: 52,
              ),
              tooltip: 'Close',
              onPressed: onClose,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
    return wrap?.call(context, header) ?? header;
  }
}

/// The pinned footer. Never scrolls away, so `Close` and the device's
/// commands stay reachable no matter how tall the body grows.
class PaneActionBar extends StatelessWidget {
  final List<PaneAction> actions;
  final VoidCallback? onClose;
  final String closeLabel;

  /// Extra space at the trailing end. A floating dialog reserves room here
  /// so its corner resize grip cannot swallow taps meant for Close.
  final double endInset;

  const PaneActionBar({
    super.key,
    this.actions = const [],
    this.onClose,
    this.closeLabel = 'Close',
    this.endInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12 + endInset, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Device actions sit left, Close is anchored right so its position
          // is identical in every popup.
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final a in actions) a.build(context)],
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onClose, child: Text(closeLabel)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body building blocks
// ---------------------------------------------------------------------------

/// A titled block inside a pane/dialog body.
class PaneSection extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const PaneSection({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 6),
          ],
          child,
        ],
      ),
    );
  }
}

/// A `label ......... value` row — the workhorse for read-only device data.
class PaneDetailRow extends StatelessWidget {
  final String label;

  /// Text value. Ignored when [child] is supplied.
  final String? value;

  /// Custom trailing widget (a chip, a small toggle, a formatted value).
  final Widget? child;

  /// Tints the value, e.g. red for a fault code.
  final Color? valueColor;

  const PaneDetailRow({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.valueColor,
  }) : assert(value != null || child != null,
            'PaneDetailRow needs either a value or a child');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child: child ??
                  Text(
                    value!,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact value tile — a big number with a label and optional unit.
///
/// Tiles keep a pane readable at a glance; prefer a row of tiles over a long
/// list of [PaneDetailRow]s when the values are the headline numbers.
class PaneMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? valueColor;
  final VoidCallback? onTap;

  /// Sized so three tiles fit across a default-width pane on one row.
  final double width;

  const PaneMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.valueColor,
    this.onTap,
    this.width = 108,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: valueColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unit != null) ...[
                      const SizedBox(width: 3),
                      Text(unit!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays tiles out in a wrap so a pane reflows when the operator resizes it.
class PaneTileRow extends StatelessWidget {
  final List<Widget> children;

  const PaneTileRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }
}

/// A small chart preview that opens the full-size chart in a free-floating
/// [StandardDialog] when tapped.
///
/// This is how a pane stays within "one screen of information" while still
/// giving the operator access to trends: the pane shows the sparkline, the
/// dialog shows the real graph, and because the dialog floats it can be
/// dragged aside and left open next to the live plant view.
class PaneGraphTile extends StatelessWidget {
  /// Caption above the preview. Omit it when the chart's own legend and axes
  /// already say what the lines are — a caption repeating them is noise in a
  /// tile this small.
  final String? label;

  /// The compact preview drawn inside the pane (sparkline, gauge, mini bar).
  final Widget preview;

  /// The full-size chart shown in the floating dialog. Not built until the
  /// tile is tapped.
  final WidgetBuilder expandedBuilder;

  /// Title of the floating dialog. Defaults to [label].
  final String? expandedTitle;

  /// Size of the floating dialog.
  final Size expandedSize;

  /// Preview height inside the pane. Kept small on purpose — the preview is
  /// a "something is happening" cue, the real chart is one tap away.
  final double height;

  const PaneGraphTile({
    super.key,
    this.label,
    required this.preview,
    required this.expandedBuilder,
    this.expandedTitle,
    this.expandedSize = const Size(720, 460),
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showFloatingDialog(
          context: context,
          id: 'graph:${expandedTitle ?? label}',
          title: expandedTitle ?? label ?? 'Trend',
          icon: Icons.show_chart,
          size: expandedSize,
          // A chart fills the window; it must not sit in a scroll view.
          scrollable: false,
          builder: expandedBuilder,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (label != null)
                    Expanded(
                      child: Text(
                        label!,
                        style: theme.textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  Icon(
                    Icons.open_in_full,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(height: height, child: preview),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line row that opens heavier content — an I/O channel grid, a fault
/// history, a parameter table — in a free-floating [StandardDialog].
///
/// Use it to keep bulk detail out of the pane body.
class PaneExpandTile extends StatelessWidget {
  final String label;
  final String? summary;
  final IconData icon;
  final WidgetBuilder expandedBuilder;
  final String? expandedTitle;
  final Size expandedSize;

  const PaneExpandTile({
    super.key,
    required this.label,
    required this.expandedBuilder,
    this.summary,
    this.icon = Icons.grid_view,
    this.expandedTitle,
    this.expandedSize = const Size(720, 520),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showFloatingDialog(
          context: context,
          id: 'expand:$label',
          title: expandedTitle ?? label,
          icon: icon,
          size: expandedSize,
          builder: expandedBuilder,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: theme.textTheme.bodyMedium),
                    if (summary != null)
                      Text(summary!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
