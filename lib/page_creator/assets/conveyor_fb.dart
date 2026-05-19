// FB-binding Conveyor asset.
//
// This asset auto-binds to a single PLC function-block instance and
// renders its standard members (running / fault / mode / runtime) plus
// three bit-aliased color indicators (red / grey / green) sourced from
// a parent WORD via the BitAliasDecoder seam.
//
// Two-layer architecture:
//   1. `ConveyorFb`        — Riverpod-aware ConsumerWidget that subscribes
//                            to StateMan streams for the FB instance and
//                            parent word. Resolves the decoder from
//                            `bitAliasDecoderProvider`.
//   2. `ConveyorFbView`    — Pure StatelessWidget that takes already-fetched
//                            inputs and renders. Easy to unit-test without
//                            a live StateMan / PLC.
//
// Bit-alias contract (see `package:tfc_dart/core/umas_bit_alias.dart`):
//   - decodeBit(parentWord, alias) -> bool? where null means "unknown"
//   - Unknown aliases render the indicator as "?" (NOT off, NOT crash).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';
import 'package:tfc_dart/core/umas_bit_alias.dart';

import '../../providers/state_man.dart';
import 'common.dart';

part 'conveyor_fb.g.dart';

/// Riverpod hook for the bit-alias decoder.
///
/// Defaults to [StubBitAliasDecoder] (everything -> null -> "?" in UI).
/// The real `UmasBitAliasDecoder` is wired up by the
/// `bitalias-impl` agent in a sibling task; once that lands its provider
/// override can be applied at the top of the widget tree (e.g. in
/// `main.dart`'s ProviderScope) without changing this file.
final bitAliasDecoderProvider = Provider<BitAliasDecoder>((ref) {
  return const StubBitAliasDecoder();
});

/// Standard FB member field names this asset knows how to render.
///
/// Order is significant — this is the row order in the rendered view.
const List<String> kConveyorFbFieldNames = [
  'running',
  'fault',
  'mode',
  'runtime',
];

/// The three color-indicator alias names rendered as a status strip
/// below the FB field list.
const List<String> kConveyorFbIndicatorAliases = ['red', 'grey', 'green'];

/// Page-creator config for a Conveyor that auto-binds to a PLC FB instance.
@JsonSerializable(explicitToJson: true)
class ConveyorFbConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor (FB-bound)';
  @override
  String get category => 'Visualization';

  /// The bound PLC function-block instance key (StateMan key).
  /// When set, the widget subscribes to this key and resolves
  /// `running`, `fault`, `mode`, `runtime` as members of the
  /// resulting DynamicValue.
  String? fbInstanceName;

  /// Optional key for the parent WORD that carries the bit-aliased
  /// color indicators (red / grey / green). Sub-bits inside this
  /// word are extracted by [BitAliasDecoder.decodeBit].
  String? parentWordKey;

  ConveyorFbConfig({
    this.fbInstanceName,
    this.parentWordKey,
  });

  static const previewStr = 'ConveyorFb preview';

  ConveyorFbConfig.preview()
      : fbInstanceName = previewStr,
        parentWordKey = null;

  @override
  Widget build(BuildContext context) => ConveyorFb(config: this);

  @override
  Widget configure(BuildContext context) => SingleChildScrollView(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(16),
          child: _ConveyorFbConfigContent(config: this),
        ),
      );

  factory ConveyorFbConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorFbConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ConveyorFbConfigToJson(this);
}

class _ConveyorFbConfigContent extends StatefulWidget {
  final ConveyorFbConfig config;
  const _ConveyorFbConfigContent({required this.config});

  @override
  State<_ConveyorFbConfigContent> createState() =>
      _ConveyorFbConfigContentState();
}

class _ConveyorFbConfigContentState extends State<_ConveyorFbConfigContent> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyField(
          initialValue: widget.config.fbInstanceName,
          label: 'FB Instance Key',
          onChanged: (v) => setState(() => widget.config.fbInstanceName = v),
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.parentWordKey,
          label: 'Parent WORD Key (indicators)',
          onChanged: (v) => setState(() => widget.config.parentWordKey = v),
        ),
        const SizedBox(height: 16),
        SizeField(
          initialValue: widget.config.size,
          onChanged: (size) => setState(() => widget.config.size = size),
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (c) => setState(() => widget.config.coordinates = c),
          enableAngle: true,
        ),
      ],
    );
  }
}

/// Riverpod-wired wrapper. Subscribes to the FB instance + parent word
/// streams (when configured) and feeds the result into [ConveyorFbView].
class ConveyorFb extends ConsumerWidget {
  final ConveyorFbConfig config;
  const ConveyorFb({required this.config, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decoder = ref.watch(bitAliasDecoderProvider);

    // Preview mode — no live streams; render with empty data so the
    // asset is selectable in the page editor.
    if (config.fbInstanceName == null ||
        config.fbInstanceName!.isEmpty ||
        config.fbInstanceName == ConveyorFbConfig.previewStr) {
      return ConveyorFbView(
        fbInstanceName: config.fbInstanceName ?? '(unset)',
        fbValue: null,
        parentWordValue: null,
        decoder: decoder,
      );
    }

    return FutureBuilder(
      future: ref.watch(stateManProvider.future),
      builder: (context, smSnap) {
        if (!smSnap.hasData) {
          return ConveyorFbView(
            fbInstanceName: config.fbInstanceName!,
            fbValue: null,
            parentWordValue: null,
            decoder: decoder,
          );
        }
        final stateMan = smSnap.data!;

        // Build the FB stream.
        final fbStream =
            stateMan.subscribe(config.fbInstanceName!).asStream().switchMap(
                  (s) => s,
                );

        // Build the parent-word stream (optional).
        Stream<DynamicValue?> parentStream;
        if (config.parentWordKey != null && config.parentWordKey!.isNotEmpty) {
          parentStream = stateMan
              .subscribe(config.parentWordKey!)
              .asStream()
              .switchMap((s) => s.map<DynamicValue?>((v) => v));
        } else {
          parentStream = Stream<DynamicValue?>.value(null);
        }

        return StreamBuilder<DynamicValue>(
          stream: fbStream,
          builder: (context, fbSnap) {
            return StreamBuilder<DynamicValue?>(
              stream: parentStream,
              builder: (context, parentSnap) {
                int? parentWord;
                final parentValue = parentSnap.data;
                if (parentValue != null) {
                  try {
                    parentWord = parentValue.asInt;
                  } catch (_) {
                    parentWord = null;
                  }
                }
                return ConveyorFbView(
                  fbInstanceName: config.fbInstanceName!,
                  fbValue: fbSnap.data,
                  parentWordValue: parentWord,
                  decoder: decoder,
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Pure renderer — takes already-fetched data and a decoder. No streams,
/// no Riverpod, no PLC. This is the unit-testable surface for
/// the conveyor FB asset.
class ConveyorFbView extends StatelessWidget {
  final String fbInstanceName;
  final DynamicValue? fbValue;
  final int? parentWordValue;
  final BitAliasDecoder decoder;

  const ConveyorFbView({
    super.key,
    required this.fbInstanceName,
    required this.fbValue,
    required this.parentWordValue,
    required this.decoder,
  });

  /// Looks up [field] inside [fbValue] and renders its value as a
  /// human-readable string. Returns "—" (em-dash) when the field is
  /// missing or the value cannot be stringified.
  static String _fieldText(DynamicValue? fb, String field) {
    if (fb == null) return '—';
    try {
      if (!fb.contains(field)) return '—';
      final v = fb[field];
      // Prefer the most readable representation. Bools stringify as
      // 'true'/'false', ints as digits, strings raw, doubles formatted.
      final raw = v.value;
      if (raw == null) return '—';
      if (raw is bool) return raw.toString();
      if (raw is num) return raw.toString();
      return raw.toString();
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Colors.black, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — FB instance name.
          Text(
            fbInstanceName,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(height: 8),
          // Standard FB fields.
          for (final field in kConveyorFbFieldNames)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(child: Text(field)),
                  Text(
                    _fieldText(fbValue, field),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          const Divider(height: 8),
          // Color indicator strip.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final alias in kConveyorFbIndicatorAliases)
                ConveyorFbIndicator(
                  alias: alias,
                  state: parentWordValue == null
                      ? null
                      : decoder.decodeBit(parentWordValue!, alias),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Single color-indicator dot. Carries both a Semantics label and a
/// ValueKey for testability:
///
///   - ValueKey('conveyor-fb-indicator:$alias:$state-label')
///     where state-label is 'on' | 'off' | 'unknown'
///
/// Tests assert against the key so the contract is robust to widget
/// shuffling.
class ConveyorFbIndicator extends StatelessWidget {
  final String alias;
  final bool? state;

  const ConveyorFbIndicator({
    super.key,
    required this.alias,
    required this.state,
  });

  Color _aliasColor() {
    switch (alias) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'grey':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  static String stateLabel(bool? state) =>
      state == null ? 'unknown' : (state ? 'on' : 'off');

  static String keyFor(String alias, bool? state) =>
      'conveyor-fb-indicator:$alias:${stateLabel(state)}';

  @override
  Widget build(BuildContext context) {
    final s = state;
    final stateText = stateLabel(s);

    final dotColor = s == null
        ? Colors.transparent
        : (s ? _aliasColor() : _aliasColor().withValues(alpha: 0.2));

    return Container(
      key: ValueKey(keyFor(alias, s)),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: dotColor,
        border: Border.all(color: Colors.black, width: 1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Semantics(
        label: '$alias: $stateText',
        child: s == null
            ? const Text(
                '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
