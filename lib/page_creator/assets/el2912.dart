/// Beckhoff EL2912 — the TwinSAFE terminal carrying two fail-safe 24 V
/// outputs with 2.3 A and its own TwinSAFE Logic. Every station has one:
/// `ST301.A1.09`, `ST302.A1.12`, `ST310.A1.08`, and two more on ST301's
/// device 5.
///
/// **What the PLC can see is almost nothing.** The safety half of this
/// terminal is FSoE: the outputs are driven by TwinSAFE Logic inside the
/// terminal and the standard PLC never touches them. What the EtherCAT GVL
/// links out of an EL2912 is two bits, off `Module 3 (DEVICEIO)`:
///
///     ST301_A1_09_Fieldvoltage_Underrange AT %I* : BOOL;
///     ST301_A1_09_Fieldvoltage_Overrange  AT %I* : BOOL;
///
/// Two loose BOOLs, not a struct — which is why this asset takes two keys
/// rather than the one an EL9222 takes.
///
/// So the face says the one thing it honestly can: whether the field voltage
/// feeding the safety outputs is inside range. The terminal's own Output and
/// Error lamps stay dark, because nothing publishes them and a lamp guessed
/// at is worse than a lamp missing. The pane says as much out loud.
library;

import 'package:flutter/material.dart';

import '../../painter/beckhoff/io8.dart' show IOState;
import '../../theme.dart' show HmiStateColors;
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
import 'led.dart' show LEDPainter, LEDType;

/// The eight terminal points of an EL2912, in [IO8Painter] order — which is
/// left column then right column, i.e. points 1, 5, 2, 6, 3, 7, 4, 8.
///
/// Points 2/6 and 3/7 carry the power contacts through, so the field voltage
/// the outputs switch is the same 24 V the rest of the rack sits on. That is
/// what the two bits this asset reads are measuring.
const List<String> el2912IoLabels = [
  'O1',
  'O2',
  '24V',
  '24V',
  '0V',
  '0V',
  'GND1',
  'GND2',
];

/// Where the field voltage sits relative to the terminal's window.
enum El2912FieldVoltage {
  /// Above the valid range. The safety outputs are not to be relied on.
  overrange,

  /// Below the valid range — the usual cause is the 24 V rail sagging or a
  /// blown feed, and the outputs cannot switch their load.
  underrange,

  /// Inside the window. Neither bit is set.
  inRange,

  /// Neither bit has been published: no keys configured, or the link is
  /// down.
  unknown,
}

/// One EL2912 as the terminal last reported it.
///
/// Both bits are nullable, and a bit the server never served stays null. A
/// terminal reporting "not underrange" because nothing arrived looks exactly
/// like a healthy one, and that is the distinction this asset exists to keep.
@immutable
class El2912Status {
  const El2912Status({required this.underrange, required this.overrange});

  /// `Fieldvoltage Underrange`, or null when unpublished.
  final bool? underrange;

  /// `Fieldvoltage Overrange`, or null when unpublished.
  final bool? overrange;

  /// Nothing configured, nothing received.
  const El2912Status.unknown()
      : underrange = null,
        overrange = null;

  bool get isUnknown => underrange == null && overrange == null;

  El2912FieldVoltage get fieldVoltage {
    if (isUnknown) return El2912FieldVoltage.unknown;
    if (overrange ?? false) return El2912FieldVoltage.overrange;
    if (underrange ?? false) return El2912FieldVoltage.underrange;
    return El2912FieldVoltage.inRange;
  }

  /// True when the field voltage is outside its window either way — the one
  /// condition that takes the safety outputs with it.
  bool get outOfRange =>
      fieldVoltage == El2912FieldVoltage.overrange ||
      fieldVoltage == El2912FieldVoltage.underrange;
}

/// The chip the pane header shows.
PaneStatus el2912PaneStatus(El2912FieldVoltage state) => switch (state) {
      El2912FieldVoltage.overrange => const PaneStatus.fault('Field V high'),
      El2912FieldVoltage.underrange => const PaneStatus.fault('Field V low'),
      El2912FieldVoltage.inRange => const PaneStatus.running('Field V OK'),
      El2912FieldVoltage.unknown => const PaneStatus.unknown('No data'),
    };

/// What the state means and what to do about it.
String el2912Explanation(El2912FieldVoltage state) => switch (state) {
      El2912FieldVoltage.overrange =>
        'The 24 V feeding this terminal\'s safety outputs is above its valid '
            'range. Check the supply on this rail before trusting anything '
            'the outputs are holding.',
      El2912FieldVoltage.underrange =>
        'The 24 V feeding this terminal\'s safety outputs has dropped below '
            'its valid range. The outputs cannot switch their load. Look at '
            'the supply feeding this rack — a tripped breaker upstream shows '
            'up here first.',
      El2912FieldVoltage.inRange =>
        'The field voltage is inside its window. This says the outputs have '
            'something to switch with; it does not say what they are doing.',
      El2912FieldVoltage.unknown =>
        'Neither field-voltage bit has arrived. Either no keys are '
            'configured for this terminal or the PLC link is down.',
    };

/// The six lamps on the module face, in `IO6LedBlockPainter` order.
///
///     ┌──────────────┐
///     │      A       │  A = field voltage in range          (green)
///     ├──────┬───────┤
///     │  B   │   C   │  B, C = Output 1, Error 1   — dark
///     ├──────┼───────┤
///     │  D   │   E   │  D, E = Output 2, Error 2   — dark
///     ├──────┴───────┤
///     │      F       │  F = field voltage out of range      (red)
///     └──────────────┘
///
/// B through E are the terminal's own per-channel lamps, and they stay dark
/// on purpose: the outputs are driven over FSoE by TwinSAFE Logic and no
/// standard-PLC variable carries their state, so there is nothing to light
/// them with. Better an unlit lamp than an invented one.
List<IOState> el2912FaceLeds(El2912Status status) => [
      status.fieldVoltage == El2912FieldVoltage.inRange
          ? IOState.high
          : IOState.low,
      IOState.low,
      IOState.low,
      IOState.low,
      IOState.low,
      status.outOfRange ? IOState.error : IOState.low,
    ];

// ---------------------------------------------------------------------------
// Operator surface
// ---------------------------------------------------------------------------

/// The EL2912 pane body.
///
/// A plain [StatelessWidget] fed values — the subscription belongs to the
/// asset, which outlives the overlay this is built into.
class El2912PaneBody extends StatelessWidget {
  const El2912PaneBody({super.key, required this.status, this.description});

  final El2912Status status;

  /// What this terminal's outputs hold — the guard circuit, the gate lock.
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HmiStateColors.of(context);
    final state = status.fieldVoltage;

    return PaneBody(
      sections: [
        PaneBodySection.status(
          title: 'Field voltage',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (description != null) ...[
                Text(description!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
              ],
              PaneExplainRow(
                label: 'State',
                value: el2912PaneStatus(state).label,
                valueColor: el2912PaneStatus(state).color,
                initiallyExpanded: status.outOfRange,
                explanationBuilder: (context) => Text(
                  el2912Explanation(state),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              _bit(context, colors, 'Below range', status.underrange),
              _bit(context, colors, 'Above range', status.overrange),
            ],
          ),
        ),
        PaneBodySection.details(
          title: 'Safety outputs',
          child: Text(
            'The two fail-safe outputs are driven by the TwinSAFE Logic '
            'inside this terminal, over FSoE. The standard PLC never sees '
            'them, so this pane cannot say whether either output is on — '
            'only whether it has the field voltage it would need. Read the '
            'output state from the TwinSAFE project.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// One diagnostic bit. Both are faults when set, so both go red — and
  /// neither is dressed as good news when it is merely absent.
  Widget _bit(
    BuildContext context,
    HmiStateColors colors,
    String label,
    bool? value,
  ) {
    return PaneDetailRow(
      crossAxisAlignment: CrossAxisAlignment.center,
      label: label,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CustomPaint(
          painter: LEDPainter(
            color: switch (value) {
              null => null,
              true => colors.red,
              false => Colors.white,
            },
            ledType: LEDType.circle,
          ),
        ),
      ),
    );
  }
}

/// Opens the EL2912 pane.
///
/// [stream] feeds the whole pane, so one subscription covers it and dies with
/// the pane.
void showEl2912Pane({
  required BuildContext context,
  required String id,
  required String title,
  required Stream<({El2912Status status, String? description})> stream,
}) {
  showSidePane(
    context: context,
    id: id,
    builder: (paneContext) =>
        StreamBuilder<({El2912Status status, String? description})>(
      stream: stream,
      builder: (context, snap) {
        final data = (snap.hasData && !snap.hasError) ? snap.data : null;
        final status = data?.status ?? const El2912Status.unknown();

        return SidePane(
          title: title,
          // 'Beckhoff · TwinSAFE output' truncated to 'Beckhoff · TwinSA…'
          // beside the status chip. The pane's own sections say the rest.
          subtitle: 'Beckhoff · safety',
          icon: Icons.shield,
          status: el2912PaneStatus(status.fieldVoltage),
          child: El2912PaneBody(
            status: status,
            description: data?.description,
          ),
        );
      },
    ),
  );
}
