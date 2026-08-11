import 'package:flutter/material.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import '../../painter/beckhoff/io8.dart' show IOState;
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';

/// The shared operator surface for digital I/O modules — Beckhoff EL1008 /
/// EL2008, Advantys STB DDI3725 / DDO3705.
///
/// All of them face the same problem: a `RowIOView` grid is ~900px wide
/// (state, force buttons, filter fields, description — twice over), which fits
/// neither a pane nor comfortably in a dialog. So the surface splits the way
/// the pane standard prescribes:
///
///   * the PANE answers "is this module healthy and is anything forced?" —
///     identity, link status, a channel strip and the counts, at a glance;
///   * the GRID lives behind a "Channel detail" tile in a free-floating
///     dialog the operator can drag onto the plant view and resize.
///
/// Keeping it in one place means the five modules cannot drift apart.

/// A channel state read-out: one square per channel, colour is the state and
/// an orange outline marks a forced channel.
class IoChannelStrip extends StatelessWidget {
  final List<IOState> states;

  /// Channels per row. 8 gives the familiar two-row block for a 16-channel
  /// module and a single row for an 8-channel one.
  final int perRow;

  const IoChannelStrip({
    super.key,
    required this.states,
    this.perRow = 8,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget cell(int index) {
      final state = index < states.length ? states[index] : IOState.low;
      final high = state == IOState.high || state == IOState.forcedHigh;
      final forced = state == IOState.forcedHigh || state == IOState.forcedLow;
      final error = state == IOState.error;
      final color = error
          ? theme.colorScheme.error
          : high
              ? Colors.green
              : theme.disabledColor;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: high ? 0.85 : 0.25),
                  borderRadius: BorderRadius.circular(4),
                  border: forced
                      ? Border.all(color: Colors.orange, width: 2)
                      : null,
                ),
              ),
              const SizedBox(height: 2),
              Text('${index + 1}', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var start = 0; start < states.length; start += perRow) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(Row(
        children: [
          for (var i = start; i < start + perRow; i++)
            if (i < states.length) cell(i) else const Spacer(),
        ],
      ));
    }
    return Column(children: rows);
  }
}

/// Counts of channels that are high and channels that are forced.
({int high, int forced}) countChannels(List<IOState> states) {
  var high = 0;
  var forced = 0;
  for (final s in states) {
    if (s == IOState.high || s == IOState.forcedHigh) high++;
    if (s == IOState.forcedHigh || s == IOState.forcedLow) forced++;
  }
  return (high: high, forced: forced);
}

/// Opens the standard digital-I/O module pane.
///
/// [summaryStream] feeds the strip (raw + force is enough); [statesOf] turns
/// an emission into per-channel states — each module keeps its own bit order.
/// [gridBuilder] builds the wide per-channel grid shown in the floating
/// dialog, and owns its own subscription so it is released when that dialog
/// closes.
void showIoModulePane({
  required BuildContext context,
  required String id,
  required String title,
  required String subtitle,
  required Stream<Map<String, DynamicValue>> summaryStream,
  required List<IOState> Function(Map<String, DynamicValue>? data) statesOf,
  required WidgetBuilder gridBuilder,
  IconData icon = Icons.developer_board,
  int channelsPerRow = 8,
  String gridLabel = 'Channel detail',
  String gridSummary = 'Force and descriptions for every channel',
  Size gridSize = const Size(940, 560),
  String highLabel = 'High',
}) {
  showSidePane(
    context: context,
    id: id,
    builder: (paneContext) => StreamBuilder<Map<String, DynamicValue>>(
      stream: summaryStream,
      builder: (context, snap) {
        final data = (snap.hasData && !snap.hasError) ? snap.data : null;
        final states = statesOf(data);
        final counts = countChannels(states);
        final total = states.length;

        return SidePane(
          title: title,
          subtitle: subtitle,
          icon: icon,
          status: data == null
              ? const PaneStatus.stale('No data')
              : counts.forced > 0
                  ? PaneStatus.warning('${counts.forced} forced')
                  : const PaneStatus.running('Live'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PaneSection(
                title: 'Channels',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IoChannelStrip(states: states, perRow: channelsPerRow),
                    const SizedBox(height: 10),
                    PaneTileRow(
                      children: [
                        PaneMetricTile(
                          label: highLabel,
                          value: '${counts.high}',
                          unit: '/ $total',
                          icon: Icons.input,
                        ),
                        PaneMetricTile(
                          label: 'Forced',
                          value: '${counts.forced}',
                          unit: '/ $total',
                          icon: Icons.pan_tool,
                          valueColor: counts.forced > 0 ? Colors.orange : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              PaneSection(
                title: 'Detail',
                child: PaneExpandTile(
                  label: gridLabel,
                  summary: gridSummary,
                  icon: Icons.grid_on,
                  expandedTitle: '$title — channels',
                  expandedSize: gridSize,
                  expandedBuilder: gridBuilder,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Wraps a `RowIOView` grid so it scrolls sideways instead of overflowing
/// when the operator narrows the floating dialog.
///
/// A row needs ~900px for state + force + filters + description twice over;
/// below that the grid scrolls rather than clipping controls out of reach.
class IoGridViewport extends StatelessWidget {
  final Widget child;
  final double minWidth;

  const IoGridViewport({
    super.key,
    required this.child,
    this.minWidth = 900,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < minWidth
              ? minWidth
              : constraints.maxWidth,
          child: child,
        ),
      ),
    );
  }
}
