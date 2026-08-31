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
///
/// The second house rule is the **order** of that body, top to bottom:
///
/// > **Status → Trend → Manual → Setpoints**, then anything device-specific.
///
/// Reading down a pane goes from what the equipment is doing now, to what it
/// has been doing, to taking hold of it, to the numbers that are set once and
/// left — and it goes that way in every pane, so an operator who has learned
/// one has learned them all. Build the body with [PaneBody] and tag each
/// block with its [PaneSectionSlot]; the order is then the widget's job, not
/// the pane author's, and cannot drift as a pane grows a section.

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
                // Was dropped here alone: every other branch passes the key
                // through, so a destructive action WITH an icon was the one
                // shape that could not be addressed by tests or automation.
                key: buttonKey,
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

/// The standard header: the equipment identity on the first line, what kind
/// of thing it is and its live status on the second, the close button in the
/// corner. Shared by [SidePane] and [StandardDialog] so both read identically.
///
/// ```
/// [icon] CVS02.CN01.FD01                          X
///        Conveyor                    (● Running)
/// ```
///
/// The status chip sits under the title rather than beside it so that the
/// identity is never the thing that gives way. A pane is 380 px wide; with
/// the chip and the close button on the title row, a full PLC key such as
/// `CVS02.CN01.FD01` next to a `Connecting` chip came out as `CVS02.CN0…` —
/// and the name is what the operator opened the pane to check. The subtitle
/// is short, fixed wording (`Conveyor`, `Third-party equipment`) and can
/// share its row with the chip; the chip keeps its place at the right, so
/// the eye still finds the state where it always has been.
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

  /// Icon glyph size and the gap to the title; the second line indents by
  /// their sum so the subtitle lines up under the title, not the icon.
  static const double _iconSize = 22;
  static const double _iconGap = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final hasSecondLine = hasSubtitle || status != null;
    final indent = icon != null ? _iconSize + _iconGap : 0.0;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Line one: the identity, with the whole width to itself.
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon,
                          size: _iconSize, color: theme.colorScheme.primary),
                      const SizedBox(width: _iconGap),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Line two: what it is on the left, how it is on the right.
                if (hasSecondLine) ...[
                  const SizedBox(height: 2),
                  Padding(
                    padding: EdgeInsets.only(left: indent),
                    child: Row(
                      children: [
                        Expanded(
                          child: hasSubtitle
                              ? Text(
                                  subtitle!,
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (status != null) ...[
                          const SizedBox(width: 8),
                          PaneStatusChip(status: status!),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
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

/// The pinned footer. Never scrolls away, so the device's commands stay
/// reachable no matter how tall the body grows. Closing is the header's job
/// ([PaneHeader]'s corner button) — the bar holds only the device actions,
/// so panes and dialogs without any have no footer at all.
class PaneActionBar extends StatelessWidget {
  final List<PaneAction> actions;

  /// Extra space at the trailing end. A floating dialog reserves room here
  /// so its corner resize grip cannot swallow taps meant for an action.
  final double endInset;

  const PaneActionBar({
    super.key,
    this.actions = const [],
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
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [for (final a in actions) a.build(context)],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body building blocks
// ---------------------------------------------------------------------------

/// Where a standard section sits in a pane body, top to bottom.
///
/// The order of the enumerators **is** the on-screen order, and it is the
/// house layout for every equipment pane:
///
/// 1. [status] — what the equipment is doing right now. The reason the
///    operator opened the pane, so it is never below the fold.
/// 2. [trend] — the same numbers over time. It reads as history of the
///    block above it, so it belongs directly under it.
/// 3. [manual] — hand control: jog, force, push. Below the readings that
///    tell an operator whether to touch anything, and far enough down the
///    pane that it is not the first thing a sleeve brushes.
/// 4. [setpoints] — configuration that is changed rarely and then left
///    alone. Last of the standard four.
/// 5. [details] — anything device-specific that is none of the above
///    (ranges, notes, channel lists). Appended in the order given.
///
/// Panes name their sections with a device's own vocabulary — a sensor's
/// live block is `Signal`, a gate's hand control is `Force` — but they all
/// occupy the same slot and therefore the same place on screen, so an
/// operator who has learned one pane has learned them all. Use [PaneBody]
/// rather than ordering sections by hand.
enum PaneSectionSlot {
  status('Status'),
  trend('Trend'),
  manual('Manual'),
  setpoints('Setpoints'),
  details(null);

  const PaneSectionSlot(this.defaultTitle);

  /// Section heading used when a pane does not override it.
  final String? defaultTitle;
}

/// One section of a [PaneBody], tagged with the slot it belongs to.
///
/// Build these with the named constructors — [PaneBodySection.status] and
/// friends — so the slot and the default heading come as a pair.
class PaneBodySection {
  /// Decides where this section renders, regardless of where it was written.
  final PaneSectionSlot slot;

  /// Heading, defaulting to [PaneSectionSlot.defaultTitle]. Override it when
  /// the device has its own word for the slot (`Signal`, `Force`).
  final String? title;

  /// Small control on the heading row — a reset button, a unit toggle.
  final Widget? trailing;

  final Widget child;

  const PaneBodySection({
    required this.slot,
    required this.child,
    this.title,
    this.trailing,
  });

  /// Live values: what the equipment is doing now.
  const PaneBodySection.status({
    required Widget child,
    String? title,
    Widget? trailing,
  }) : this(
          slot: PaneSectionSlot.status,
          child: child,
          title: title,
          trailing: trailing,
        );

  /// Those values over time — normally a [PaneGraphTile].
  const PaneBodySection.trend({
    required Widget child,
    String? title,
    Widget? trailing,
  }) : this(
          slot: PaneSectionSlot.trend,
          child: child,
          title: title,
          trailing: trailing,
        );

  /// Hand control: jog, force, push.
  const PaneBodySection.manual({
    required Widget child,
    String? title,
    Widget? trailing,
  }) : this(
          slot: PaneSectionSlot.manual,
          child: child,
          title: title,
          trailing: trailing,
        );

  /// Values the operator sets and leaves.
  const PaneBodySection.setpoints({
    required Widget child,
    String? title,
    Widget? trailing,
  }) : this(
          slot: PaneSectionSlot.setpoints,
          child: child,
          title: title,
          trailing: trailing,
        );

  /// Device-specific material that is none of the four standard slots.
  /// Requires an explicit [title] — there is no house word for it.
  const PaneBodySection.details({
    required Widget child,
    required String title,
    Widget? trailing,
  }) : this(
          slot: PaneSectionSlot.details,
          child: child,
          title: title,
          trailing: trailing,
        );

  /// This section rendered as the block a pane body actually shows.
  PaneSection build() => PaneSection(
        title: title ?? slot.defaultTitle,
        trailing: trailing,
        child: child,
      );
}

/// The body of an equipment pane: sections rendered in [PaneSectionSlot]
/// order with hairline dividers between them.
///
/// Sections may be listed in any order — the body sorts them, so the layout
/// an operator sees is the same in every pane and cannot drift as a pane
/// grows a section. Sections sharing a slot keep the order they were given.
/// Null entries are allowed and dropped, so a pane can write
/// `hasTrend ? PaneBodySection.trend(...) : null` inline.
class PaneBody extends StatelessWidget {
  final List<PaneBodySection?> sections;

  const PaneBody({super.key, required this.sections});

  @override
  Widget build(BuildContext context) {
    final present = sections.whereType<PaneBodySection>().toList();
    // List.sort is not stable, so carry the position each section was
    // written at and break slot ties on it.
    final withOrder = List.generate(
      present.length,
      (i) => (section: present[i], order: i),
    )..sort((a, b) {
        final bySlot = a.section.slot.index.compareTo(b.section.slot.index);
        return bySlot != 0 ? bySlot : a.order.compareTo(b.order);
      });

    final children = <Widget>[];
    for (final entry in withOrder) {
      if (children.isNotEmpty) children.add(const Divider(height: 1));
      children.add(entry.section.build());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

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

  /// How the label and the value line up.
  ///
  /// Top-aligned by default, which is right for two blocks of text: a label
  /// that wraps should start level with its value. A fixed-height child --
  /// a diode, a chip -- wants centring instead, or it hangs at the top of a
  /// row whose height its wrapping label decided.
  final CrossAxisAlignment crossAxisAlignment;

  const PaneDetailRow({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.valueColor,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  }) : assert(value != null || child != null,
            'PaneDetailRow needs either a value or a child');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: crossAxisAlignment,
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

/// Preview height for a LINE trend in a pane — the conveyor's drive stats, the
/// analog box's value, the box erector's throughput.
///
/// Tall enough for a line chart to be readable rather than decorative, and no
/// taller: whatever sits below the tile has to fit on the same screen. Named
/// here rather than repeated at each call site because three tiles that nearly
/// match is what a `84` written next to a `100` produces, and an operator with
/// two panes open reads the difference as two different products.
///
/// The one deliberate exception is [kPaneBooleanTrendTileHeight].
const double kPaneTrendTileHeight = 100;

/// Preview height for a two-state BOOLEAN timeline — the sensor's blocked/clear
/// history.
///
/// Shorter than [kPaneTrendTileHeight] on purpose, and named so it reads as a
/// decision rather than as an `84` that someone forgot to make `100`. A
/// boolean trace only ever occupies two rows, so the height a line chart needs
/// to show shape is height this chart would spend on empty band; what it does
/// need is enough room that the "True"/"False" tick labels and the time row do
/// not print over each other.
///
/// A NUMERIC trend must not borrow this. The box erector's cartons/min tile did
/// — it was built from the sensor's tile as a template — and that is half of why
/// it and the conveyor's did not read as the same product.
const double kPaneBooleanTrendTileHeight = 84;

/// Floating-dialog size for a pane trend opened out of a [PaneGraphTile].
///
/// Same reasoning as [kPaneTrendTileHeight]: the tap-through from one machine's
/// pane must not open a visibly smaller window than the tap-through from the
/// machine beside it.
const Size kPaneTrendDialogSize = Size(820, 520);

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

  /// Series names and their trace colours, drawn as dots in the tile header.
  ///
  /// A chart legend belongs beside the plot, but cristalyse puts it in a
  /// column down the right-hand side, which at tile size takes more width
  /// than the plot it explains. Naming the series up here instead lets the
  /// preview run the full width of the card. Leave empty for a single-series
  /// trend the pane has already named.
  final Map<String, Color> legend;

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
    this.legend = const {},
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
        // The header keeps its inset; the preview below only gets a hairline
        // of it, so the plot uses the card rather than floating in it. The
        // size-up glyph is pinned to the tile's corner rather than ending
        // the header row: with a long label or a wrapping legend it used to
        // drift down to wherever the row happened to end.
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 28, 0),
                  child: Row(
                    children: [
                      if (label != null)
                        Flexible(
                          child: Text(
                            label!,
                            style: theme.textTheme.labelSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      // The legend takes the slack rather than sharing it with a
                      // Spacer — competing for the row is what wrapped two short
                      // series names onto two lines.
                      if (legend.isNotEmpty) ...[
                        if (label != null) const SizedBox(width: 10),
                        Expanded(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            children: [
                              for (final entry in legend.entries)
                                _LegendDot(
                                    label: entry.key, color: entry.value),
                            ],
                          ),
                        ),
                      ] else
                        const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: SizedBox(height: height, child: preview),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 10,
              child: Icon(
                Icons.open_in_full,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One series in a [PaneGraphTile] header: the trace colour, then its name.
class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
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

/// A [PaneDetailRow] whose value is a word an operator may not know, with the
/// explanation folded in underneath it.
///
/// Use it where the honest answer is a term of art — a drive state, a fault
/// name, an interlock — and the operator standing at the machine needs both
/// "what does that word mean" and "what do I do about it". The row stays one
/// line until it is asked; the detail is not a dialog, because reading it and
/// acting on it happen at the same time and a dialog would cover the mimic.
///
/// Label and value share one line while they fit. When they do not — a
/// `Last fault (LFT)` label against `CNF · Fieldbus communication lost` in a
/// 380 px pane — the value drops under the label on a line of its own, still
/// right-aligned with the info glyph at its end, rather than being ellipsised
/// or folded into a narrow right-hand column. Nothing in either row is ever
/// cut short: both are things the operator came to read.
///
/// Contrast with [PaneExpandTile], which is for *bulk* detail (a channel
/// grid, a parameter table) and does open a dialog.
class PaneExplainRow extends StatefulWidget {
  final String label;

  /// The short words, e.g. `Overcurrent`.
  final String value;

  /// Tints the value — pass the severity colour from the theme.
  final Color? valueColor;

  /// A muted qualifier trailing the value, e.g. `cleared`. For saying what
  /// kind of reading this is when the words alone would be read as a live
  /// condition; deliberately quieter than the value it follows.
  final String? valueNote;

  /// The explanation, revealed on tap. Built lazily.
  final WidgetBuilder explanationBuilder;

  /// Starts open. Useful for a fault that wants to be read.
  final bool initiallyExpanded;

  const PaneExplainRow({
    super.key,
    required this.label,
    required this.value,
    required this.explanationBuilder,
    this.valueColor,
    this.valueNote,
    this.initiallyExpanded = false,
  });

  @override
  State<PaneExplainRow> createState() => _PaneExplainRowState();
}

class _PaneExplainRowState extends State<PaneExplainRow> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(PaneExplainRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A row that opened itself for one fault should not stay open over the
    // next value — but never fold away something the operator opened.
    if (widget.initiallyExpanded && !oldWidget.initiallyExpanded) {
      _expanded = true;
    }
  }

  /// The info / fold glyph at the end of the value, and the gaps around the
  /// pieces. Named so the one-line fit check below measures the same row the
  /// build lays out.
  static const double _iconSize = 16;
  static const double _labelGap = 8;
  static const double _iconGap = 4;

  /// Whether label, value and glyph all fit on one line of [width].
  ///
  /// Measured with the same styles and text scale the row renders with, so
  /// the answer is the layout's own, not a character-count guess.
  bool _fitsOneLine(
    BuildContext context,
    double width,
    TextStyle labelStyle,
    InlineSpan valueSpan,
  ) {
    if (!width.isFinite) return true;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(InlineSpan span) {
      final painter = TextPainter(
        text: span,
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    final needed = measure(TextSpan(text: widget.label, style: labelStyle)) +
        _labelGap +
        measure(valueSpan) +
        _iconGap +
        _iconSize;
    return needed <= width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // What `Text(style: bodyMedium)` resolves to, spelled out so the fit
    // check measures the glyphs that will actually be drawn.
    final bodyStyle =
        DefaultTextStyle.of(context).style.merge(theme.textTheme.bodyMedium);
    // One paragraph rather than two widgets, so a value and its note wrap
    // around each other instead of the note squeezing the value onto two
    // lines.
    final valueSpan = TextSpan(style: bodyStyle, children: [
      TextSpan(
        text: widget.value,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: widget.valueColor,
        ),
      ),
      if (widget.valueNote != null)
        TextSpan(
          text: '  ${widget.valueNote}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
        ),
    ]);
    final label = Text(widget.label, style: theme.textTheme.bodyMedium);
    final value = Text.rich(valueSpan, textAlign: TextAlign.right);
    final glyph = Icon(
      _expanded ? Icons.expand_less : Icons.info_outline,
      size: _iconSize,
      color: theme.colorScheme.primary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final oneLine = _fitsOneLine(
                    context, constraints.maxWidth, bodyStyle, valueSpan);
                // The value keeps its right rail and its glyph either way;
                // only the label moves — off the line, to the one above.
                final valueRow = Row(
                  children: [
                    Expanded(child: value),
                    const SizedBox(width: _iconGap),
                    glyph,
                  ],
                );
                if (oneLine) {
                  return Row(
                    children: [
                      label,
                      const SizedBox(width: _labelGap),
                      Expanded(child: valueRow),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    label,
                    const SizedBox(height: 2),
                    valueRow,
                  ],
                );
              },
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: widget.explanationBuilder(context),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}
