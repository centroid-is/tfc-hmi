// Advantys STB module asset configs + their live ConsumerStatefulWidgets.
//
// Phase 1 (this file): `STBDDI3725Config` — 16-channel digital-input module.
// Phase 2: `STBDDO3705Config` — 16-channel digital-output module.
// Phase 3: `STBNIP2311Config` — Modbus network interface module.
// Phase 4: `STBPDT3100Config` — 24V DC power distribution module.
// Phase 5: `AdvantysSTBStackConfig` — composite stack asset.
//
// Conventions locked by Plan 01:
// - Bit-to-channel mapping comes from `kSTBChannelBitOrder` in
//   `package:tfc/painter/advantys_stb/io16.dart` (LSB-first locked default).
// - LED rendering goes through `bitmaskToLedStates(raw, forceValues: ...)`
//   from the same file — painters and widgets never re-derive bit math.
// - Schneider cream `bodyColor` is imported from
//   `package:tfc/painter/advantys_stb/io16.dart` (re-exported from Beckhoff
//   in Plan 01 to keep the brownfield import boundary clean).
//
// Plan 02 ships:
// - `STBDDI3725Config` data class + JSON round-trip.
// - `_STBDDI3725` ConsumerStatefulWidget with the `_combinedStream` hoisted to
//   `initState` (QUAL-03 / PITFALL M-03).
// - `STBDDI3725BodyPainter` + `STBDDI3725Widget` in
//   `lib/painter/advantys_stb/ddi3725.dart`.
// - 5 KeyField editor body (Task 3).
// - 10 golden PNGs under `test/page_creator/assets/goldens/advantys_stb/` (Task 5).
//
// Plan 03 will replace the onTap stub with the real per-channel detail dialog.
// Plan 04 will register the asset in `registry.dart` + add the leak test.

import 'dart:collection' show LinkedHashMap;

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';

import 'common.dart';
import '../../providers/state_man.dart';
import '../../painter/advantys_stb/io16.dart';
import '../../painter/advantys_stb/ddi3725.dart';
import '../../painter/beckhoff/io8.dart' show IOState;

part 'advantys_stb.g.dart';

// ---------------------------------------------------------------------------
// STBDDI3725Config — Schneider Advantys STB 16-channel digital-input module.
// ---------------------------------------------------------------------------

/// Schneider Advantys STB DDI3725 — 16-channel digital input module.
///
/// Five optional state keys (raw bitmask + force values + on/off filter ms +
/// descriptions) drive the live LED block and the detail dialog. All keys are
/// nullable; `BaseAsset.allKeys` picks them up automatically via the `Key$`
/// regex (no override needed) and filters out empty strings.
@JsonSerializable()
class STBDDI3725Config extends BaseAsset {
  @override
  String get displayName => 'STBDDI3725 (16-Ch DI)';
  @override
  String get category => 'Advantys STB';

  @JsonKey(defaultValue: '1')
  String nameOrId;

  String? rawStateKey;
  String? forceValuesKey;
  String? onFiltersKey;
  String? offFiltersKey;
  String? descriptionsKey;

  STBDDI3725Config({
    this.nameOrId = '1',
    this.rawStateKey,
    this.forceValuesKey,
    this.onFiltersKey,
    this.offFiltersKey,
    this.descriptionsKey,
  });

  STBDDI3725Config.preview()
      : nameOrId = '1',
        rawStateKey = null,
        forceValuesKey = null,
        onFiltersKey = null,
        offFiltersKey = null,
        descriptionsKey = null,
        super();

  factory STBDDI3725Config.fromJson(Map<String, dynamic> json) =>
      _$STBDDI3725ConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$STBDDI3725ConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: _STBDDI3725(config: this),
    );
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9;
    final maxHeight = media.height * 0.8;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          minWidth: 320,
          minHeight: 200,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _STBDDI3725ConfigEditor(config: this),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live widget — _STBDDI3725
//
// ConsumerStatefulWidget so `_combinedStream` can be hoisted to `initState`
// per PITFALL M-03 / QUAL-03. The stream is built ONCE per widget instance
// after the StateMan future resolves; subsequent parent rebuilds re-use the
// cached stream and do not trigger fresh OPC UA subscriptions.
// ---------------------------------------------------------------------------

class _STBDDI3725 extends ConsumerStatefulWidget {
  final STBDDI3725Config config;
  const _STBDDI3725({required this.config});

  @override
  ConsumerState<_STBDDI3725> createState() => _STBDDI3725State();
}

class _STBDDI3725State extends ConsumerState<_STBDDI3725> {
  Stream<Map<String, DynamicValue>>? _combinedStreamCache;
  StateMan? _stateMan;

  @override
  void initState() {
    super.initState();
    // Resolve StateMan once. After it lands, construct the combined stream
    // ONCE and stash it in `_combinedStreamCache`. The build() method reads
    // the cache; it never reconstructs the stream. This is the QUAL-03 /
    // PITFALL M-03 contract.
    ref.read(stateManProvider.future).then((sm) {
      if (!mounted) return;
      setState(() {
        _stateMan = sm;
        _combinedStreamCache = _combinedStream(
          LinkedHashMap<String, String?>.from(<String, String?>{
            'raw': widget.config.rawStateKey,
            'force': widget.config.forceValuesKey,
          }),
          sm,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_combinedStreamCache == null) {
      return _buildShell(
        ledStates: List<IOState>.filled(16, IOState.low),
        isStale: true,
      );
    }
    return StreamBuilder<Map<String, DynamicValue>>(
      stream: _combinedStreamCache,
      builder: (context, snap) {
        final data = (snap.hasData && !snap.hasError) ? snap.data : null;
        if (data == null) {
          return _buildShell(
            ledStates: List<IOState>.filled(16, IOState.low),
            isStale: true,
          );
        }
        final rawDv = data['raw'];
        final raw = rawDv?.asInt ?? 0;
        final forceList = _forceArrayFromDynamicValue(data['force']);
        final leds = bitmaskToLedStates(raw, forceValues: forceList);
        return _buildShell(ledStates: leds, isStale: false);
      },
    );
  }

  Widget _buildShell({
    required List<IOState> ledStates,
    required bool isStale,
  }) {
    return GestureDetector(
      // QUAL-05: opaque hit-test so taps register on transparent gaps in the
      // body (the body painter has empty regions between LEDs and terminal
      // blocks). Without this, taps on those gaps would fall through.
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // STUB — Plan 03 replaces this with the real per-channel detail dialog
        // (`_showDetailDialog(context, _stateMan!)`).
        if (_stateMan == null) return;
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
            content: Text('Detail dialog — implemented in Plan 03.'),
          ),
        );
      },
      child: STBDDI3725Widget(
        ledStates: ledStates,
        isStale: isStale,
        isDisconnected: false,
        animation: const AlwaysStoppedAnimation<int>(0),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Configure dialog body — _STBDDI3725ConfigEditor
// ---------------------------------------------------------------------------

class _STBDDI3725ConfigEditor extends StatefulWidget {
  final STBDDI3725Config config;
  const _STBDDI3725ConfigEditor({required this.config});

  @override
  State<_STBDDI3725ConfigEditor> createState() =>
      _STBDDI3725ConfigEditorState();
}

class _STBDDI3725ConfigEditorState extends State<_STBDDI3725ConfigEditor> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizeField(
          initialValue: widget.config.size,
          onChanged: (size) => widget.config.size = size,
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (coordinates) => widget.config.coordinates = coordinates,
          enableAngle: false,
        ),
        const SizedBox(height: 16),
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'Name or ID',
            border: OutlineInputBorder(),
          ),
          initialValue: widget.config.nameOrId,
          onChanged: (value) => widget.config.nameOrId = value,
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.rawStateKey,
          onChanged: (value) => widget.config.rawStateKey = value,
          label: 'Raw State Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.forceValuesKey,
          onChanged: (value) => widget.config.forceValuesKey = value,
          label: 'Force Values Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.onFiltersKey,
          onChanged: (value) => widget.config.onFiltersKey = value,
          label: 'On Filters Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.offFiltersKey,
          onChanged: (value) => widget.config.offFiltersKey = value,
          label: 'Off Filters Key',
        ),
        const SizedBox(height: 16),
        KeyField(
          initialValue: widget.config.descriptionsKey,
          onChanged: (value) => widget.config.descriptionsKey = value,
          label: 'Descriptions Key',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Combine N nullable state-keys into a single stream emitting a map of
/// `{logical-name → DynamicValue}`. Mirrors the Beckhoff `_combinedStream` at
/// `lib/page_creator/assets/beckhoff.dart` (ARCHITECTURE §9.3 advises to
/// duplicate rather than refactor — Beckhoff conventions remain isolated).
CombineLatestStream<DynamicValue, Map<String, DynamicValue>> _combinedStream(
  LinkedHashMap<String, String?> keys,
  StateMan stateMan,
) {
  return CombineLatestStream<DynamicValue, Map<String, DynamicValue>>(
    [
      for (final entry in keys.entries)
        if (entry.value != null)
          stateMan.subscribe(entry.value!).asStream().asyncExpand((s) => s),
    ],
    (values) {
      final map = <String, DynamicValue>{};
      int i = 0;
      for (final entry in keys.entries) {
        if (entry.value != null) {
          map[entry.key] = values[i++];
        }
      }
      return map;
    },
  );
}

/// Extracts a per-channel `int8[16]` force-values array from a [DynamicValue].
///
/// CONTEXT.md D-ForceValues locks the wire format to `int8[16]`. The expected
/// runtime shape is `dv.isArray == true` with `dv.asArray` being a
/// `List<DynamicValue>` of length 16, each entry's `.asInt` in `{0, 1, 2}`.
///
/// Returns `null` if `dv == null` or `dv.isArray == false`. Returns a list of
/// up to 16 ints otherwise; `bitmaskToLedStates` tolerates a short list
/// (treated as auto on remaining channels) per its Plan 01 contract.
///
/// PITFALL M-04 / M-02 trip-wire: if `dv` arrives as a packed int instead of
/// an array (Beckhoff convention — `forceValuesKey` is a single integer where
/// `.asInt` encodes all eight channels), this returns null and the LED block
/// silently renders raw bits only. The commissioning-time fix is to align the
/// backend wire format with CONTEXT.md D-ForceValues (int8[16] array per
/// channel), not to patch the painter. Carried forward in SUMMARY.md.
List<int>? _forceArrayFromDynamicValue(DynamicValue? dv) {
  if (dv == null) return null;
  if (!dv.isArray) return null;
  final list = dv.asArray;
  final out = <int>[];
  for (int i = 0; i < list.length && i < 16; i++) {
    out.add(list[i].asInt);
  }
  return out;
}
