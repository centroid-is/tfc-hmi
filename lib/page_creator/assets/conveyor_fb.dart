// FB-binding Conveyor asset (vendor-schema picker on FB DynamicValue).
//
// This asset auto-binds to a single PLC function-block instance and
// renders a *canonical set of conveyor concepts* (running, fault, mode,
// color indicators, runtime, velocity, thermal faults) by translating
// them to the vendor-specific member names defined by the configured
// [ConveyorSchema].
//
// The bound FB exposes a flat `{member: value}` DynamicValue (via the
// existing browse-tree expansion in `umas_browse.dart` /
// `modbus_device_client.dart` — this asset does NOT change that
// subscription path). The asset's job is purely:
//   1. Pick the vendor schema (Beckhoff / Schneider).
//   2. For each canonical conveyor concept, read the schema's mapped
//      member key out of the DynamicValue map.
//   3. Render each concept appropriately (BOOL → lamp, num → digits,
//      missing → "?"  — never a crash).
//
// Schema choice replaces the earlier free-form `displayedMembers`
// toggle UI. This is a deliberate breaking change for the config
// schema: saved configs with `displayedMembers` set will silently lose
// that field — the schema picker is the new way to control which
// members the asset reads. Custom user-defined schemas are out of
// scope for this iteration.
//
// Two-layer architecture (unchanged):
//   1. `ConveyorFb`     — Riverpod-aware ConsumerWidget that subscribes
//                         to the StateMan stream for the FB instance
//                         and forwards the latest DynamicValue map
//                         into the pure view.
//   2. `ConveyorFbView` — Pure StatelessWidget that takes an already-
//                         fetched DynamicValue + a schema and renders.
//                         Easy to unit-test without a live StateMan /
//                         PLC.
//
// Bit-aliased members (e.g. `HMI.Color.red`) are expected to surface as
// first-class entries in the FB DynamicValue map once the named-bit-
// decoder agent lands; until then they are simply missing from the map
// and the view renders them as "?". No further asset changes will be
// needed when the decoder is wired up — the schema mapping already
// references the canonical member paths.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import '../../providers/state_man.dart';
import 'common.dart';

part 'conveyor_fb.g.dart';

/// Vendor convention the bound FB conforms to. The schema decides which
/// member names the asset reads from the live DynamicValue map for each
/// canonical conveyor concept.
///
/// Custom / user-defined schemas are deliberately out of scope for this
/// iteration; the picker is a fixed two-value enum.
@JsonEnum()
enum ConveyorSchema {
  /// Beckhoff / TwinCAT 3 convention. Members are flat on the FB root
  /// with Hungarian prefixes (`b`/`r`/`n`/`i`/`di`/`s`).
  beckhoff,

  /// Schneider / Control Expert convention (e.g. `FB_ATV320`). HMI-facing
  /// members live in an inner `HMI` sub-FB and use `p_Stat_*` /
  /// `p_Mode_*` prefixes. Bit-aliased status colors are surfaced as
  /// `HMI.Color.{red,grey,green,...}`.
  schneider,
}

/// The canonical conveyor concepts the asset can render. Every schema
/// supplies *some subset* of these — the view falls back to "?" when a
/// schema does not define a mapping or when the live FB map does not
/// contain the mapped key.
///
/// These names are the stable identity surfaced in the cell's ValueKey
/// (`conveyor-fb-member:<concept>:...`), so tests and pages don't
/// depend on the vendor-specific member path.
enum _ConveyorConcept {
  running,
  fault,
  mode,
  colorRed,
  colorGrey,
  colorGreen,
  runtime,
  velocity,
  thermalFaults,
}

extension on _ConveyorConcept {
  /// String name used in widget keys + cell labels. Matches the enum
  /// `name` (lowerCamelCase) for stability.
  String get id => name;
}

/// Per-schema mapping of canonical concept → vendor member key in the
/// FB DynamicValue map.
///
/// Schneider mapping is anchored on the `FB_ATV320` shape seen on the
/// live M580: HMI sub-FB with `p_Stat_*` / `p_Mode_*` members plus a
/// `Color` sub-record with named bit aliases.
///
/// Beckhoff mapping uses the TwinCAT 3 Hungarian-prefix convention
/// (`bRunning`, `bFault`, ... `rActSpeed`). The convention is broadly
/// consistent across Beckhoff FB libraries but is NOT a hard standard
/// the way the Schneider HMI sub-FB is — see the comments on each
/// concept for which entries are best-effort. Beckhoff FBs typically
/// do NOT encode status colors as named bit aliases (they expose
/// individual status BOOLs directly), so Color.* concepts are
/// intentionally absent from the Beckhoff schema and will render as
/// "?" — that's the correct UX (operator sees the running/fault BOOLs
/// instead).
const Map<ConveyorSchema, Map<_ConveyorConcept, String>> _kSchemaMembers = {
  ConveyorSchema.schneider: {
    // Either-direction running. The Schneider HMI block exposes
    // both `p_Stat_xRunningFwd` and `p_Stat_xRunningRev`; for a
    // single-direction conveyor visualization the forward bit is the
    // operator-facing "running" lamp.
    _ConveyorConcept.running: 'HMI.p_Stat_xRunningFwd',
    _ConveyorConcept.fault: 'HMI.p_Stat_xFault',
    // `p_Mode_xMan` true → manual mode active; rendered as a BOOL lamp
    // (on = manual, off = auto). p_Mode_xAuto is the inverse signal
    // and is not surfaced — one lamp is enough.
    _ConveyorConcept.mode: 'HMI.p_Mode_xMan',
    // The named-bit-decoder agent (commit a7d3de2d) will surface these
    // keys as first-class entries on the FB DynamicValue map. Until it
    // lands they will be missing → "?" placeholder (no crash).
    _ConveyorConcept.colorRed: 'HMI.Color.red',
    _ConveyorConcept.colorGrey: 'HMI.Color.grey',
    _ConveyorConcept.colorGreen: 'HMI.Color.green',
    _ConveyorConcept.runtime: 'HMI.p_Stat_diRuntime',
    _ConveyorConcept.velocity: 'HMI.p_Stat_rVelocity',
    _ConveyorConcept.thermalFaults: 'HMI.p_Stat_iThermalFaults',
  },
  ConveyorSchema.beckhoff: {
    // TwinCAT Hungarian-prefix members on the FB root.
    _ConveyorConcept.running: 'bRunning',
    // `bFault` is the broad TwinCAT convention; some Beckhoff
    // libraries use `bError` instead. If a customer's FB exposes the
    // error name we'll need a follow-up schema variant — deliberately
    // not adding the variant yet to keep this iteration tight.
    _ConveyorConcept.fault: 'bFault',
    // Best-effort mode flag. TwinCAT libraries vary on the exact
    // name; `bMan` is the most common (true = manual mode). Falls
    // back to "?" if the FB doesn't carry it.
    _ConveyorConcept.mode: 'bMan',
    // Beckhoff FBs do NOT typically expose Color.red/grey/green
    // status alias bits (that's a Schneider-FB-ATV320 convention).
    // Omitting these from the mapping means they render as "?",
    // which is the correct UX for a Beckhoff binding.
    // No Color.* entries here.
    //
    // `rActSpeed` mirrors the `oop_motor.st` fixture in
    // packages/tfc_mcp_server. There is no universal Beckhoff name
    // for runtime hours / thermal faults — best-effort guesses
    // (`nRunTime`, `iThermalFaults`) would be invention rather than
    // observation, so they are intentionally absent and render "?".
    _ConveyorConcept.velocity: 'rActSpeed',
  },
};

/// Page-creator config for a Conveyor that auto-binds to a PLC FB instance.
///
/// Breaking change vs. the prior version: the `displayedMembers` list
/// field has been removed in favor of a single [schema] enum picker.
/// Old saved JSON with `displayedMembers` still loads, but that data is
/// dropped — the operator must pick a schema after the upgrade.
@JsonSerializable(explicitToJson: true)
class ConveyorFbConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor (FB-bound)';
  @override
  String get category => 'Visualization';

  /// The bound PLC function-block instance key (StateMan key). When set,
  /// the widget subscribes to this key and pulls a `{member: value}`
  /// DynamicValue map out of the stream.
  String? fbInstanceName;

  /// Legacy field. Carried for backward-compat with old saved configs
  /// that referenced a parent WORD for bit-aliased indicators. The new
  /// model surfaces bit-aliased members as first-class entries in the
  /// FB DynamicValue map via browse-tree expansion, so this field is
  /// no longer required to render `red`/`grey`/`green`. Kept so future
  /// iterations (e.g. batched bit-alias decode against a sibling WORD)
  /// can re-light up without bumping schema.
  String? parentWordKey;

  /// Vendor schema the bound FB conforms to. When null, the asset
  /// renders a "pick a schema" config hint instead of attempting to
  /// pull any member values — old saved configs and freshly created
  /// assets both start here.
  ///
  /// `unknownEnumValue: null` means an old JSON record that somehow
  /// carries an unrecognized string just resets to null (the safe
  /// default) instead of crashing the page load.
  @JsonKey(unknownEnumValue: null)
  ConveyorSchema? schema;

  ConveyorFbConfig({
    this.fbInstanceName,
    this.parentWordKey,
    this.schema,
  });

  static const previewStr = 'ConveyorFb preview';

  ConveyorFbConfig.preview()
      : fbInstanceName = previewStr,
        parentWordKey = null,
        // Preview ships with a sensible default so the page-editor
        // catalogue thumbnail isn't just a config-hint card.
        schema = ConveyorSchema.schneider;

  @override
  Widget build(BuildContext context) => ConveyorFb(config: this);

  @override
  Widget configure(BuildContext context) => SingleChildScrollView(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          child: _ConveyorFbConfigContent(config: this),
        ),
      );

  factory ConveyorFbConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorFbConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ConveyorFbConfigToJson(this);
}

class _ConveyorFbConfigContent extends ConsumerStatefulWidget {
  final ConveyorFbConfig config;
  const _ConveyorFbConfigContent({required this.config});

  @override
  ConsumerState<_ConveyorFbConfigContent> createState() =>
      _ConveyorFbConfigContentState();
}

class _ConveyorFbConfigContentState
    extends ConsumerState<_ConveyorFbConfigContent> {
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
          label: 'Parent WORD Key (optional, legacy)',
          onChanged: (v) => setState(() => widget.config.parentWordKey = v),
        ),
        const SizedBox(height: 16),
        Text(
          'FB Schema',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        DropdownButton<ConveyorSchema?>(
          key: const ValueKey('conveyor-fb-schema-dropdown'),
          value: widget.config.schema,
          isExpanded: true,
          hint: const Text('Pick a schema…'),
          items: const [
            DropdownMenuItem<ConveyorSchema?>(
              value: null,
              child: Text('— None —'),
            ),
            DropdownMenuItem<ConveyorSchema?>(
              value: ConveyorSchema.beckhoff,
              child: Text('Beckhoff (TwinCAT)'),
            ),
            DropdownMenuItem<ConveyorSchema?>(
              value: ConveyorSchema.schneider,
              child: Text('Schneider (Control Expert)'),
            ),
          ],
          onChanged: (next) {
            setState(() => widget.config.schema = next);
          },
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

/// Riverpod-wired wrapper. Subscribes to the FB instance stream (when
/// configured) and forwards the latest DynamicValue map into the pure
/// [ConveyorFbView].
class ConveyorFb extends ConsumerWidget {
  final ConveyorFbConfig config;
  const ConveyorFb({required this.config, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Preview mode / unbound — no live streams; render with empty data
    // so the asset is selectable in the page editor.
    if (config.fbInstanceName == null ||
        config.fbInstanceName!.isEmpty ||
        config.fbInstanceName == ConveyorFbConfig.previewStr) {
      return ConveyorFbView(
        fbInstanceName: config.fbInstanceName ?? '(unset)',
        fbValue: null,
        schema: config.schema,
      );
    }

    return FutureBuilder(
      future: ref.watch(stateManProvider.future),
      builder: (context, smSnap) {
        if (!smSnap.hasData) {
          return ConveyorFbView(
            fbInstanceName: config.fbInstanceName!,
            fbValue: null,
            schema: config.schema,
          );
        }
        final stateMan = smSnap.data!;

        // Same subscription mechanism as the FB inspection view — we
        // do NOT rewire this; just consume the stream.
        final fbStream =
            stateMan.subscribe(config.fbInstanceName!).asStream().switchMap(
                  (s) => s,
                );

        return StreamBuilder<DynamicValue>(
          stream: fbStream,
          builder: (context, fbSnap) {
            return ConveyorFbView(
              fbInstanceName: config.fbInstanceName!,
              fbValue: fbSnap.data,
              schema: config.schema,
            );
          },
        );
      },
    );
  }
}

/// Pure renderer — takes an already-fetched FB DynamicValue map plus a
/// vendor schema. No streams, no Riverpod, no PLC. This is the unit-
/// testable surface for the conveyor FB asset.
class ConveyorFbView extends StatelessWidget {
  final String fbInstanceName;
  final DynamicValue? fbValue;
  final ConveyorSchema? schema;

  const ConveyorFbView({
    super.key,
    required this.fbInstanceName,
    required this.fbValue,
    required this.schema,
  });

  /// Resolve [name] inside [fb] without throwing. Returns null when the
  /// FB is null, the FB isn't an object map, the key is missing, or the
  /// inner value is null.
  static dynamic _resolveRaw(DynamicValue? fb, String name) {
    if (fb == null) return null;
    if (!fb.isObject) return null;
    if (!fb.contains(name)) return null;
    try {
      final v = fb[name];
      return v.value;
    } catch (_) {
      return null;
    }
  }

  static bool _isPresent(DynamicValue? fb, String name) {
    if (fb == null) return false;
    if (!fb.isObject) return false;
    return fb.contains(name);
  }

  /// Build the list of cells the view should render for [schema]. The
  /// order matches the [_ConveyorConcept] enum declaration (running →
  /// fault → mode → color* → runtime → velocity → thermalFaults).
  ///
  /// Concepts whose schema entry is missing from [_kSchemaMembers] are
  /// included as "?" cells so the operator can see that the schema
  /// doesn't surface them (e.g. Beckhoff schema for `colorRed`).
  List<ConveyorFbMemberCell> _cellsFor(ConveyorSchema s) {
    final mapping = _kSchemaMembers[s] ?? const {};
    return [
      for (final concept in _ConveyorConcept.values)
        _buildCell(concept, mapping[concept]),
    ];
  }

  ConveyorFbMemberCell _buildCell(_ConveyorConcept concept, String? memberKey) {
    if (memberKey == null) {
      // Schema doesn't define this concept → render as unknown.
      return ConveyorFbMemberCell(
        name: concept.id,
        rawValue: null,
        present: false,
      );
    }
    return ConveyorFbMemberCell(
      name: concept.id,
      rawValue: _resolveRaw(fbValue, memberKey),
      present: _isPresent(fbValue, memberKey),
    );
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
          Text(
            fbInstanceName,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(height: 8),
          if (schema == null)
            Padding(
              key: const ValueKey('conveyor-fb-schema-hint'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No FB schema selected — open this asset\'s config to '
                'pick Beckhoff or Schneider.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _cellsFor(schema!),
            ),
        ],
      ),
    );
  }
}

/// Single member cell. Renders a name + an indicator/value pair
/// chosen by the runtime Dart type of [rawValue]:
///
///   - BOOL → colored circle (green = on, grey = off)
///   - num (int / double) → numeric badge (REAL formatted to 1 decimal)
///   - String → text badge
///   - Unknown / missing → "?" placeholder
///
/// The cell carries a stable ValueKey under
/// `conveyor-fb-member:$name:$shape[:$state]` so tests can assert
/// against the contract without depending on painter internals.
class ConveyorFbMemberCell extends StatelessWidget {
  /// Concept name (`running`, `fault`, `colorRed`, ...). This is the
  /// canonical id, not the vendor-specific member path.
  final String name;

  /// The raw inner Dart value from the FB DynamicValue map (i.e.
  /// `fbValue[vendorMemberKey].value`). Null when the member is missing
  /// or the FB hasn't loaded yet.
  final dynamic rawValue;

  /// Whether the vendor member key is actually present in the FB map
  /// (used to disambiguate "present but null" from "missing"; today we
  /// treat both as unknown but the flag is kept so future iterations
  /// can surface the distinction).
  final bool present;

  const ConveyorFbMemberCell({
    super.key,
    required this.name,
    required this.rawValue,
    required this.present,
  });

  static String _keyFor(String name, String shape, [String? state]) {
    final tail = state == null ? '' : ':$state';
    return 'conveyor-fb-member:$name:$shape$tail';
  }

  @override
  Widget build(BuildContext context) {
    final raw = rawValue;
    if (!present || raw == null) {
      return _MemberBox(
        cellKey: ValueKey(_keyFor(name, 'unknown')),
        label: name,
        valueWidget: const _UnknownDot(),
      );
    }
    if (raw is bool) {
      final state = raw ? 'on' : 'off';
      return _MemberBox(
        cellKey: ValueKey(_keyFor(name, 'bool', state)),
        label: name,
        valueWidget: _BoolDot(on: raw),
      );
    }
    if (raw is double) {
      return _MemberBox(
        cellKey: ValueKey(_keyFor(name, 'real')),
        label: name,
        valueWidget: _ValueBadge(text: raw.toStringAsFixed(1)),
      );
    }
    if (raw is num) {
      return _MemberBox(
        cellKey: ValueKey(_keyFor(name, 'num')),
        label: name,
        valueWidget: _ValueBadge(text: raw.toString()),
      );
    }
    if (raw is String) {
      return _MemberBox(
        cellKey: ValueKey(_keyFor(name, 'string')),
        label: name,
        valueWidget: _ValueBadge(text: raw),
      );
    }
    // Anything else (e.g. raw bytes, lists) — fall back to unknown.
    return _MemberBox(
      cellKey: ValueKey(_keyFor(name, 'unknown')),
      label: name,
      valueWidget: const _UnknownDot(),
    );
  }
}

class _MemberBox extends StatelessWidget {
  final ValueKey<String> cellKey;
  final String label;
  final Widget valueWidget;
  const _MemberBox({
    required this.cellKey,
    required this.label,
    required this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cellKey,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          valueWidget,
        ],
      ),
    );
  }
}

class _BoolDot extends StatelessWidget {
  final bool on;
  const _BoolDot({required this.on});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: on ? Colors.green : Colors.grey.shade400,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1),
      ),
    );
  }
}

class _UnknownDot extends StatelessWidget {
  const _UnknownDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: const Text(
        '?',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ValueBadge extends StatelessWidget {
  final String text;
  const _ValueBadge({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
      ),
    );
  }
}

