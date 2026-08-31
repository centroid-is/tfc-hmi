/// Beckhoff EtherCAT Box — the IP67 modules bolted to the machines instead of
/// racked in a cabinet. Two types are fitted on this plant, and they share an
/// asset because they share a housing.
///
///  * **EP2338-1002** — 8-channel digital combi, every socket usable either
///    way. ST301 alone carries eight of them, and the PLC comments name what
///    each one is: `ST301_RM04` the strapping machine, `ST301_RM05` the box
///    erector, `ST301_RM08` the control buttons on the column. Each is an
///    `ST_EP2338_0002` — `I0..I7` on `%I*`, `O0..O7` on `%Q*` — so its
///    sockets are lit from live data.
///
///  * **EP1918-0002** — TwinSAFE, 8 safe digital inputs, yellow housing.
///    `ST301.EM01`, `ST301.EM02` and one on device 5. It publishes nothing:
///    the safe inputs are consumed by TwinSAFE logic inside the network and
///    no station's EtherCAT GVL so much as names one. Its sockets stay dark,
///    and its pane says why rather than showing eight lamps that mean
///    nothing.
///
/// This library holds the variants, the decode and the operator surface. The
/// subscription lives with the asset in `beckhoff.dart`.
library;

import 'package:flutter/material.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import '../../painter/beckhoff/ep_box.dart' show epBoxChannelCount;
import '../../painter/beckhoff/io8.dart'
    show IOState, bodyColor, twinSafeBodyColor;
import '../../theme.dart' show HmiStateColors;
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
import 'led.dart' show LEDPainter, LEDType;

/// Which box this asset is drawing.
///
/// A field rather than two asset classes because the two differ in a label, a
/// housing colour and whether there is anything to subscribe to — and an
/// electrician swapping one for the other on a page should not have to delete
/// the asset and re-place it.
enum EPBoxVariant {
  /// 8-channel digital combi, M12. Live off `ST_EP2338_0002`.
  ep2338('EP2338', '8-channel digital combi', 'I/O box'),

  /// TwinSAFE, 8 safe digital inputs, M12. No process data.
  ep1918('EP1918', 'TwinSAFE, 8 safe inputs', 'safe inputs');

  const EPBoxVariant(this.model, this.blurb, this.paneSubtitle);

  /// Printed on the housing and used in the palette.
  final String model;

  /// The line beside the model in the configure form's picker, where there
  /// is room to say what the box actually is.
  final String blurb;

  /// What the pane header calls it, after `Beckhoff · `.
  ///
  /// Deliberately shorter than [blurb]: the subtitle shares its row with the
  /// status chip in a 380 px pane, and '8-channel digital combi' came out as
  /// '8-channe…'.
  final String paneSubtitle;

  /// True when the PLC publishes a struct for this box, i.e. when a state
  /// key means anything.
  bool get isLive => this == EPBoxVariant.ep2338;

  /// Beckhoff paints TwinSAFE hardware yellow and everything else cream.
  Color get housingColor =>
      this == EPBoxVariant.ep1918 ? twinSafeBodyColor : bodyColor;
}

/// One socket of an EP2338 as the box last reported it.
///
/// Both bits are nullable. The box is a combi and the struct carries an input
/// and an output member for every channel regardless of how the channel is
/// configured, so an unpublished member and a low one are genuinely different
/// things.
@immutable
class EpBoxChannel {
  const EpBoxChannel({
    required this.channel,
    required this.input,
    required this.output,
  });

  /// 1..8, as printed beside the socket.
  final int channel;

  /// `I{n}` — the channel read as an input.
  final bool? input;

  /// `O{n}` — the channel driven as an output.
  final bool? output;

  /// Reads channel [channel] out of a subscribed `ST_EP2338_0002`. The
  /// struct indexes from zero and the sockets are numbered from one.
  factory EpBoxChannel.read(DynamicValue? struct, int channel) {
    assert(channel >= 1 && channel <= epBoxChannelCount);
    bool? bit(String member) {
      if (struct == null || !struct.contains(member)) return null;
      return struct[member].asBool;
    }

    return EpBoxChannel(
      channel: channel,
      input: bit('I${channel - 1}'),
      output: bit('O${channel - 1}'),
    );
  }

  bool get isUnknown => input == null && output == null;

  /// True when the socket is carrying a signal either way. What the lamp
  /// beside it shows.
  bool get active => (input ?? false) || (output ?? false);
}

/// Every socket of a box, unknown, for a box with no key or nothing received.
List<EpBoxChannel> epBoxUnknownChannels() => [
      for (int c = 1; c <= epBoxChannelCount; c++) EpBoxChannel.read(null, c),
    ];

/// Reads all eight sockets out of one subscribed struct.
List<EpBoxChannel> epBoxChannelsOf(DynamicValue? struct) => [
      for (int c = 1; c <= epBoxChannelCount; c++) EpBoxChannel.read(struct, c),
    ];

/// The lamp beside each socket on the face.
List<IOState> epBoxFaceLeds(List<EpBoxChannel> channels) => [
      for (final channel in channels)
        channel.active ? IOState.high : IOState.low,
    ];

/// The chip the pane header shows.
///
/// A digital I/O box has no state of its own worth a headline — it is not
/// running or stopped, it is a set of sockets. So the chip answers the only
/// question the box itself can: is anything arriving from it.
PaneStatus epBoxPaneStatus(
  EPBoxVariant variant,
  List<EpBoxChannel> channels,
) {
  if (!variant.isLive) return const PaneStatus.unknown('No process data');
  if (channels.every((c) => c.isUnknown)) {
    return const PaneStatus.unknown('No data');
  }
  final live = channels.where((c) => c.active).length;
  return live == 0
      ? const PaneStatus.stopped('All quiet')
      : PaneStatus.running('$live of ${channels.length} on');
}

// ---------------------------------------------------------------------------
// Operator surface
// ---------------------------------------------------------------------------

/// The EtherCAT Box pane body.
///
/// A plain [StatelessWidget] fed values — the subscription belongs to the
/// asset, which outlives the overlay this is built into.
class EpBoxPaneBody extends StatelessWidget {
  const EpBoxPaneBody({
    super.key,
    required this.variant,
    required this.channels,
    this.descriptions = const [],
  });

  final EPBoxVariant variant;

  /// Socket 1 first.
  final List<EpBoxChannel> channels;

  /// What each socket is wired to, when the page supplies a descriptions key.
  /// Short of eight entries is fine — a socket without one shows its number.
  final List<String> descriptions;

  String? _descriptionFor(int channel) {
    final index = channel - 1;
    if (index >= descriptions.length) return null;
    final text = descriptions[index].trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = HmiStateColors.of(context);

    if (!variant.isLive) {
      return PaneBody(
        sections: [
          PaneBodySection.details(
            title: 'Safe inputs',
            child: Text(
              'This is a TwinSAFE box. Its eight safe inputs are read by the '
              'TwinSAFE logic on the safety network, not by the standard '
              'PLC, so nothing about their state reaches this page — there '
              'is no variable to subscribe to. The box is drawn here so it '
              'can be found and identified; read its inputs from the '
              'TwinSAFE project.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    return PaneBody(
      sections: [
        PaneBodySection.status(
          title: 'Sockets',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final channel in channels)
                PaneDetailRow(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  label: _descriptionFor(channel.channel) ??
                      'Socket ${channel.channel}',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _diode(colors, channel.input, isOutput: false),
                      const SizedBox(width: 8),
                      _diode(colors, channel.output, isOutput: true),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Every socket on this box can be wired either way, and the '
                'terminal publishes both bits for all eight regardless. The '
                'left diode is the socket read as an input, the right one is '
                'the socket driven as an output; an unlit pair is a socket '
                'that is wired but idle.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _diode(HmiStateColors colors, bool? value, {required bool isOutput}) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: LEDPainter(
          color: switch (value) {
            null => null,
            // Outputs are the HMI's own side of the wire, so they take the
            // yellow this repo gives commanded state; an input is the plant
            // telling us something and stays green.
            true => isOutput ? colors.yellow : colors.green,
            false => Colors.white,
          },
          ledType: isOutput ? LEDType.square : LEDType.circle,
        ),
      ),
    );
  }
}

/// Opens the EtherCAT Box pane.
void showEpBoxPane({
  required BuildContext context,
  required String id,
  required String title,
  required EPBoxVariant variant,
  required Stream<({List<EpBoxChannel> channels, List<String> descriptions})>
      stream,
}) {
  showSidePane(
    context: context,
    id: id,
    builder: (paneContext) => StreamBuilder<
        ({List<EpBoxChannel> channels, List<String> descriptions})>(
      stream: stream,
      builder: (context, snap) {
        final data = (snap.hasData && !snap.hasError) ? snap.data : null;
        final channels = data?.channels ?? epBoxUnknownChannels();

        return SidePane(
          title: title,
          subtitle: 'Beckhoff · ${variant.paneSubtitle}',
          icon: Icons.developer_board,
          status: epBoxPaneStatus(variant, channels),
          child: EpBoxPaneBody(
            variant: variant,
            channels: channels,
            descriptions: data?.descriptions ?? const [],
          ),
        );
      },
    ),
  );
}
