// FB-binding Conveyor asset (member-toggle UI on FB DynamicValue).
//
// This asset auto-binds to a single PLC function-block instance and
// renders a *configurable subset* of its members as live indicators.
// The bound FB exposes a flat `{member: value}` DynamicValue (via the
// existing browse-tree expansion in `umas_browse.dart` /
// `modbus_device_client.dart` — this asset does NOT change that
// subscription path). The asset's job is purely "filter the map down
// to selected members and render each one appropriately".
//
// Bit-aliased members (Color.red, Color.grey, Color.green, …) are
// surfaced by the FB-browse-tree expansion as first-class entries in
// the DynamicValue map and are rendered the same way as scalar
// members.
//
// Two-layer architecture:
//   1. `ConveyorFb`     — Riverpod-aware ConsumerWidget that subscribes
//                         to the StateMan stream for the FB instance
//                         and forwards the latest DynamicValue map
//                         into the pure view.
//   2. `ConveyorFbView` — Pure StatelessWidget that takes an already-
//                         fetched DynamicValue + a list of selected
//                         member names and renders. Easy to unit-test
//                         without a live StateMan / PLC.
//
// Back-compat: existing saved JSON without `displayedMembers` populates
// the starter set ([kConveyorFbDefaultMembers]) so old pages keep
// loading. The legacy `parentWordKey` field is preserved (the
// bit-alias decoder seam in `lib/providers/umas.dart` is still in use
// by the browse-tree expansion machinery — this asset just no longer
// hard-codes which bits to surface).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';
import 'package:tfc_dart/core/state_man.dart' show StateMan;

import '../../providers/state_man.dart';
import 'common.dart';

part 'conveyor_fb.g.dart';

/// Default set of FB members rendered when an asset is configured
/// without an explicit `displayedMembers` list — i.e. a freshly created
/// Conveyor or an old saved page loaded after the upgrade.
///
/// Names match the public/HMI section of a typical Schneider FB on the
/// M580 (e.g. `FB_ATV320`). Each entry is just a default — the operator
/// is free to deselect any of these and pick others from the live FB
/// member list via the config editor's multi-select picker.
///
/// Bit-aliased members (`red`, `grey`, `green`) appear as first-class
/// entries in the FB DynamicValue map because of the browse-tree
/// `_expandVariable` fix — no separate decoder pass needed at render
/// time.
const List<String> kConveyorFbDefaultMembers = [
  'p_Stat_xRunningFwd',
  'p_Stat_xFault',
  'p_Mode_xAuto',
  'red',
  'grey',
  'green',
];

/// Page-creator config for a Conveyor that auto-binds to a PLC FB instance.
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

  /// Members of the bound FB to render. Order is preserved (this is
  /// the row order in the rendered view). Empty list → renders a
  /// "no members selected" hint.
  ///
  /// JsonKey `defaultValue` keeps `fromJson` happy for old saved
  /// configs that pre-date this field — they load with the starter
  /// set ([kConveyorFbDefaultMembers]).
  @JsonKey(defaultValue: kConveyorFbDefaultMembers)
  List<String> displayedMembers;

  ConveyorFbConfig({
    this.fbInstanceName,
    this.parentWordKey,
    List<String>? displayedMembers,
  }) : displayedMembers =
            displayedMembers ?? List<String>.from(kConveyorFbDefaultMembers);

  static const previewStr = 'ConveyorFb preview';

  ConveyorFbConfig.preview()
      : fbInstanceName = previewStr,
        parentWordKey = null,
        displayedMembers = List<String>.from(kConveyorFbDefaultMembers);

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
          'Displayed Members',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        _DisplayedMembersPicker(
          fbInstanceName: widget.config.fbInstanceName,
          selected: widget.config.displayedMembers,
          onChanged: (next) {
            setState(() {
              widget.config.displayedMembers
                ..clear()
                ..addAll(next);
            });
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

/// Multi-select picker over the FB's member list. Discovery is async
/// via the live FB DynamicValue stream (same browse mechanism as the
/// runtime widget). When discovery fails / hasn't returned yet, falls
/// back to a free-text-entry mode so the user is never blocked from
/// configuring while the PLC is offline.
class _DisplayedMembersPicker extends ConsumerStatefulWidget {
  final String? fbInstanceName;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const _DisplayedMembersPicker({
    required this.fbInstanceName,
    required this.selected,
    required this.onChanged,
  });

  @override
  ConsumerState<_DisplayedMembersPicker> createState() =>
      _DisplayedMembersPickerState();
}

class _DisplayedMembersPickerState
    extends ConsumerState<_DisplayedMembersPicker> {
  final _addCtrl = TextEditingController();

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _toggle(String name, bool? on) {
    final next = List<String>.from(widget.selected);
    if (on == true) {
      if (!next.contains(name)) next.add(name);
    } else {
      next.remove(name);
    }
    widget.onChanged(next);
  }

  void _addFreeText() {
    final raw = _addCtrl.text.trim();
    if (raw.isEmpty) return;
    if (widget.selected.contains(raw)) {
      _addCtrl.clear();
      return;
    }
    final next = List<String>.from(widget.selected)..add(raw);
    widget.onChanged(next);
    _addCtrl.clear();
  }

  Widget _buildFreeText() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _addCtrl,
            decoration: const InputDecoration(
              labelText: 'Add member name',
              isDense: true,
            ),
            onSubmitted: (_) => _addFreeText(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add member',
          onPressed: _addFreeText,
        ),
      ],
    );
  }

  Widget _buildChecklist(Set<String> discovered) {
    // Union of discovered + currently-selected names so previously
    // configured members that are not (yet) visible on the live FB
    // still surface for the operator to manage.
    final all = <String>{...discovered, ...widget.selected}.toList()
      ..sort();
    if (all.isEmpty) {
      return Text(
        'No members discovered yet — add members by name below.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: Scrollbar(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final name in all)
              CheckboxListTile(
                key: ValueKey('conveyor-fb-member-checkbox:$name'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(name),
                value: widget.selected.contains(name),
                onChanged: (on) => _toggle(name, on),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fb = widget.fbInstanceName;
    if (fb == null || fb.isEmpty || fb == ConveyorFbConfig.previewStr) {
      // No FB bound — only free-text entry makes sense.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChecklist(const <String>{}),
          const SizedBox(height: 8),
          _buildFreeText(),
        ],
      );
    }

    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, smSnap) {
        if (!smSnap.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildChecklist(widget.selected.toSet()),
              const SizedBox(height: 8),
              _buildFreeText(),
            ],
          );
        }
        final stateMan = smSnap.data!;
        final stream = stateMan.subscribe(fb).asStream().switchMap(
              (s) => s,
            );
        return StreamBuilder<DynamicValue>(
          stream: stream,
          builder: (context, snap) {
            final discovered = <String>{};
            final v = snap.data;
            if (v != null && v.isObject) {
              discovered.addAll(v.asObject.keys);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildChecklist(discovered),
                const SizedBox(height: 8),
                _buildFreeText(),
              ],
            );
          },
        );
      },
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
    // Preview mode — no live streams; render with empty data so the
    // asset is selectable in the page editor.
    if (config.fbInstanceName == null ||
        config.fbInstanceName!.isEmpty ||
        config.fbInstanceName == ConveyorFbConfig.previewStr) {
      return ConveyorFbView(
        fbInstanceName: config.fbInstanceName ?? '(unset)',
        fbValue: null,
        displayedMembers: config.displayedMembers,
      );
    }

    return FutureBuilder(
      future: ref.watch(stateManProvider.future),
      builder: (context, smSnap) {
        if (!smSnap.hasData) {
          return ConveyorFbView(
            fbInstanceName: config.fbInstanceName!,
            fbValue: null,
            displayedMembers: config.displayedMembers,
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
              displayedMembers: config.displayedMembers,
            );
          },
        );
      },
    );
  }
}

/// Pure renderer — takes an already-fetched FB DynamicValue map plus
/// the list of selected member names. No streams, no Riverpod, no PLC.
/// This is the unit-testable surface for the conveyor FB asset.
class ConveyorFbView extends StatelessWidget {
  final String fbInstanceName;
  final DynamicValue? fbValue;
  final List<String> displayedMembers;

  const ConveyorFbView({
    super.key,
    required this.fbInstanceName,
    required this.fbValue,
    required this.displayedMembers,
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
          if (displayedMembers.isEmpty)
            Padding(
              key: const ValueKey('conveyor-fb-empty-hint'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No members selected — open this asset\'s config to '
                'choose which FB members to display.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final name in displayedMembers)
                  ConveyorFbMemberCell(
                    name: name,
                    rawValue: _resolveRaw(fbValue, name),
                    present: _isPresent(fbValue, name),
                  ),
              ],
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
  /// Member name (relative to the bound FB).
  final String name;

  /// The raw inner Dart value from the FB DynamicValue map (i.e.
  /// `fbValue[name].value`). Null when the member is missing or the FB
  /// hasn't loaded yet.
  final dynamic rawValue;

  /// Whether [name] is actually present as a key in the FB map (used
  /// to disambiguate "present but null" from "missing"; today we treat
  /// both as unknown but the flag is kept so future iterations can
  /// surface the distinction).
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
