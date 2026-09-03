/// The side pane for one EtherCAT cable.
///
/// What an operator wants from a cable is not "is it up" — the colour on the
/// mimic already said that — but *should I go and look at it*. So the pane
/// leads with the two numbers that answer it: how long this link has held, and
/// how much it has been erroring lately.
///
/// Totals since commissioning are deliberately not the headline. A cable that
/// collected forty CRC errors two years ago is fine; one collecting them this
/// hour is not, and only the rolling figure separates them.
library;

import 'package:flutter/material.dart';

import '../../theme.dart' show HmiStateColors;
import '../../widgets/panes/pane_chrome.dart';
import 'ethercat_link.dart';
import 'ethercat_link_painter.dart';

/// The chip at the top of the pane.
PaneStatus etherCatLinkPaneStatus(LinkHealth health) => switch (health) {
      LinkHealth.healthy => const PaneStatus.running('Connected'),
      LinkHealth.degraded => const PaneStatus.warning('Errors'),
      LinkHealth.down => const PaneStatus.fault('No link'),
      LinkHealth.idle => const PaneStatus.stopped('Not monitored'),
      LinkHealth.unknown => const PaneStatus.stopped('No data'),
    };

/// A plain widget fed values — the subscription belongs to the asset, which
/// outlives the overlay this is built into.
class EtherCatLinkPaneBody extends StatelessWidget {
  const EtherCatLinkPaneBody({
    super.key,
    required this.state,
    required this.onResetCounters,
  });

  /// Null when nothing is subscribed, or the node is not the struct.
  final EtherCatLinkState? state;

  /// Pulses `p_cmd_xResetCounters`. Completes when the pulse is over so the
  /// button can show it running.
  final Future<void> Function()? onResetCounters;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final theme = Theme.of(context);
    if (s == null) {
      return PaneBody(sections: [
        PaneBodySection.status(
          child: Text(
            'No diagnostics for this cable. It is drawn here to document the '
            'wiring; give it a link struct key to see how it is holding up.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ]);
    }

    final states =
        theme.extension<HmiStateColors>() ?? HmiStateColors.solarizedLight;

    return PaneBody(
      sections: [
        PaneBodySection.status(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.stale)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'These figures have stopped updating, so they describe '
                    'the past rather than now.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: states.violet),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PaneMetricTile(
                    label: 'Connected for',
                    value: s.linkUp
                        ? formatDaysHoursMinutes(s.connectedMinutes)
                        : '--',
                    icon: Icons.timelapse,
                    valueColor: s.linkUp ? null : states.red,
                  ),
                  PaneMetricTile(
                    label: 'Connections',
                    value: '${s.connectCount}',
                    icon: Icons.link,
                  ),
                  PaneMetricTile(
                    label: 'Errors / hour',
                    value: '${s.errorsLastHour}',
                    icon: Icons.warning_amber,
                    valueColor: s.degraded ? states.yellow : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PaneMetricTile(
                    label: 'Longest run',
                    value: formatDaysHoursMinutes(s.longestMinutes),
                    icon: Icons.trending_up,
                  ),
                  PaneMetricTile(
                    label: 'Clean for',
                    value: formatDaysHoursMinutes(s.minutesSinceError),
                    icon: Icons.check_circle_outline,
                  ),
                  PaneMetricTile(
                    label: 'Available',
                    value: s.availabilityPct.toStringAsFixed(1),
                    unit: '%',
                    icon: Icons.percent,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _blame(s),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (onResetCounters != null)
          PaneBodySection.manual(
            title: 'Counters',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ResetButton(onReset: onResetCounters!),
                const SizedBox(height: 8),
                Text(
                  'Zeroes the connection count, the error totals and the '
                  'longest run. The cable is not disturbed and the current '
                  'connection keeps counting.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// One line saying which way the evidence points.
  ///
  /// The forwarded count is the useful half of it: frames that arrived here
  /// already broken are not this cable's fault, and a run with plenty of them
  /// is a witness rather than a suspect.
  static String _blame(EtherCatLinkState s) {
    if (!s.linkUp) {
      return 'No link on this cable. The devices at either end will be '
          'unreachable, and everything downstream of them with it.';
    }
    if (s.crcErrors == 0) {
      return 'No errors counted on this cable since the last reset.';
    }
    if (s.forwardedErrors >= s.crcErrors) {
      return 'Most of what this cable has seen arrived already broken, so the '
          'damage is upstream of it rather than on it.';
    }
    if (s.lostLinks > s.connectCount) {
      return 'The controller has counted more link drops than the PLC scan '
          'saw, which means this link is flapping faster than the cycle time.';
    }
    return 'Errors are being counted on this cable itself.';
  }
}

class _ResetButton extends StatefulWidget {
  const _ResetButton({required this.onReset});

  final Future<void> Function() onReset;

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await widget.onReset();
              } finally {
                // The pane can close while the pulse is still going.
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.restart_alt),
      label: const Text('Reset counters'),
    );
  }
}
