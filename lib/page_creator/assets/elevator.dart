import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import '../../providers/state_man.dart';
import 'common.dart';
import 'elevator_layout.dart';
import 'elevator_painter.dart';
import 'registry.dart';

part 'elevator.g.dart';

// ---------------------------------------------------------------------------
// Polymorphic child JSON helpers
// ---------------------------------------------------------------------------

/// Deserialise a polymorphic child asset for an [ElevatorChildEntry].
///
/// Walks the existing [AssetRegistry.parse] path so any registered asset
/// type Just Works without elevator-side switching (Anti-Pattern 1 from
/// research/ARCHITECTURE.md).
///
/// The `{'wrapped_child': json}` envelope makes [AssetRegistry.parse]'s
/// JSON-tree crawl find exactly one asset (the child) without bare-Map
/// ambiguity — `parse` skips the outer Map (no `asset_name` key on it)
/// and recurses into the single value, where it finds the registered
/// `asset_name` and dispatches to the matching factory.
///
/// REGRESSION GUARD: Locked by the polymorphic round-trip tests in
/// `test/page_creator/assets/elevator_config_test.dart` group
/// 'Polymorphic child round-trip' (3 tests, including a heterogeneous
/// SensorConfig + ConveyorGateConfig fixture). If you change this
/// helper, those tests must continue to pass.
///
/// FAIL-LOUD CONTRACT (T-02-04): When [AssetRegistry.parse] returns an
/// empty list — meaning the JSON's `asset_name` is not registered in
/// [AssetRegistry] — this throws [FormatException] with the offending
/// name. This is intentional: silent drop would let saved pages lose
/// children invisibly (counter to Pitfall 5).
BaseAsset _childFromJson(Map<String, dynamic> json) {
  final assets = AssetRegistry.parse(<String, dynamic>{'wrapped_child': json});
  if (assets.isEmpty) {
    throw FormatException(
      'ElevatorChildEntry.child JSON did not match any registered '
      'asset_name in AssetRegistry: ${json[constAssetName]}',
    );
  }
  return assets.first as BaseAsset;
}

Map<String, dynamic> _childToJson(BaseAsset child) => child.toJson();

// ---------------------------------------------------------------------------
// Children list legacy / forward-compat shim
// ---------------------------------------------------------------------------

/// Legacy / forward-compat shim for the children list. Locked in
/// Phase 2 from day one (ROADMAP key decision) to avoid the
/// wrapper-promotion migration trap (PITFALLS Pitfall 5).
///
/// Today: returns [] for missing / null and parses each entry as a
/// new-format ElevatorChildEntry. Future schema evolutions add
/// branches here without touching the public type — exact same
/// pattern as conveyor.dart:_gatesFromJson.
List<ElevatorChildEntry> _childrenFromJson(List<dynamic>? json) {
  if (json == null) return <ElevatorChildEntry>[];
  return json
      .map((item) => ElevatorChildEntry.fromJson(item as Map<String, dynamic>))
      .toList();
}

List<Map<String, dynamic>> _childrenToJson(List<ElevatorChildEntry> list) =>
    list.map((e) => e.toJson()).toList();

// ---------------------------------------------------------------------------
// ElevatorChildEntry — locked wrapper schema
// ---------------------------------------------------------------------------

/// Wrapper for a child asset attached to an Elevator's platform.
///
/// Schema locked in Phase 2 (ROADMAP key decision) from day one — even
/// though the children list is empty in this phase, future Phase 3
/// extensions add to the children list without changing the wrapper
/// shape. The `id` is used as a `ValueKey<String>` in Phase 3 to keep
/// child widget identity stable across position changes (Pitfall 1).
@JsonSerializable(explicitToJson: true)
class ElevatorChildEntry {
  /// Stable identity for ValueKey use (Pitfall 1 — Phase 3).
  /// Defaults to microsecond-resolution timestamp; switch to
  /// `package:uuid` only if a real collision risk surfaces.
  String id;

  /// Lateral position on the platform (0.0 = far left, 1.0 = far
  /// right). Default 0.5 = centre.
  double offsetX;

  /// Polymorphic child asset. Round-trips via [AssetRegistry.parse].
  @JsonKey(fromJson: _childFromJson, toJson: _childToJson)
  BaseAsset child;

  ElevatorChildEntry({
    String? id,
    this.offsetX = 0.5,
    required this.child,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  factory ElevatorChildEntry.fromJson(Map<String, dynamic> json) =>
      _$ElevatorChildEntryFromJson(json);

  Map<String, dynamic> toJson() => _$ElevatorChildEntryToJson(this);
}

// ---------------------------------------------------------------------------
// ElevatorConfig — pure data model
// ---------------------------------------------------------------------------

/// Configuration for the Elevator asset.
///
/// Pure data model — JSON-serialisable, no widget/painter wiring.
/// The widget, painter, registry registration, and config dialog
/// are introduced in Plans 02-03..02-05 of this phase.
@JsonSerializable(explicitToJson: true)
class ElevatorConfig extends BaseAsset {
  @override
  String get displayName => 'Elevator';

  @override
  String get category => 'Visualization';

  /// PLC state key emitting the raw 0..100% position float.
  String positionKey;

  /// Tween animation duration in ms. Default 250 (CONTEXT specifics).
  int tweenDurationMs;

  /// Child assets riding the platform. Phase 2 ships with [] —
  /// Phase 3 fills the list via the config-dialog dropdown.
  @JsonKey(fromJson: _childrenFromJson, toJson: _childrenToJson)
  List<ElevatorChildEntry> children;

  ElevatorConfig({
    this.positionKey = '',
    this.tweenDurationMs = 250,
    List<ElevatorChildEntry>? children,
  }) : children =
            children != null ? List<ElevatorChildEntry>.of(children) : [];

  /// Preview factory for the asset palette.
  ElevatorConfig.preview() : this();

  factory ElevatorConfig.fromJson(Map<String, dynamic> json) =>
      _$ElevatorConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ElevatorConfigToJson(this);

  /// Returns positionKey (if non-empty) + each child's allKeys flat-mapped,
  /// deduplicated.
  ///
  /// Required override (ARCHITECTURE Anti-Pattern 6 — default
  /// `BaseAsset.allKeys` introspects only top-level JSON field names matching
  /// the key pattern. It does NOT recurse into the children wrapper list, so
  /// without this override alarms and collectors silently miss every state
  /// key configured on a child asset (sensor detection keys, conveyor
  /// batches keys, etc.).
  ///
  /// Order: positionKey first (if non-empty), then children in declaration
  /// order. Duplicates are removed (a key configured on both parent and a
  /// child appears exactly once).
  ///
  /// REGRESSION GUARD: locked by
  /// `test/page_creator/assets/elevator_config_test.dart` group
  /// 'allKeys flat-map (ELEV-13)' (6 tests). If you change the order or
  /// dedup semantics, those tests must continue to pass.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> get allKeys {
    // Order: positionKey first, then each child's allKeys flat-mapped via
    // `children.expand((e) => e.child.allKeys)` — recursive walk into the
    // polymorphic child without any switch on runtimeType.
    //
    // Dedup + empty-filter via a Set<String> literal (LinkedHashSet, so
    // insertion order is preserved → parent first, then children in
    // declaration order).
    return <String>{
      if (positionKey.isNotEmpty) positionKey,
      for (final k in children.expand((e) => e.child.allKeys))
        if (k.isNotEmpty) k,
    }.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Elevator(config: this);
  }

  /// Returns the body of the configure dialog. The dialog chrome is
  /// applied by `_ElevatorState._openConfigDialog` (a `Dialog`) so the
  /// `TextFormField`/`KeyField`/etc. inside the editor find a `Material`
  /// ancestor — mirrors the `Sensor` precedent.
  @override
  Widget configure(BuildContext context) {
    return _ElevatorConfigEditor(config: this);
  }
}

// ---------------------------------------------------------------------------
// Elevator widget — runtime entry point.
// ---------------------------------------------------------------------------

/// Live elevator widget — runtime entry point.
///
/// Subscribes to `config.positionKey` via `stateManProvider`. The stream
/// is hoisted to `initState` (Pitfall 2 — no resubscribe storm under
/// high-frequency rebuilds). The position is fed through
/// [platformProgress] (clamp + normalise) into a [ValueNotifier<double>]
/// that the painter listens to via `super(repaint:)`. Smooth motion is
/// applied by a `TweenAnimationBuilder<double>` wrapper added in
/// Cycle C (Plan 02-04 Tasks 5-6).
///
/// Stale rendering covers three paths: empty positionKey, stream pre-
/// data, stream error (mirrors sensor.dart precedent — ELEV-14).
///
/// Tap opens the config dialog through a real `GestureDetector` wrapping
/// the painter — survives a translating ancestor (forward-compat for
/// Phase 3, where the elevator may be embedded in another moving widget).
class Elevator extends ConsumerStatefulWidget {
  final ElevatorConfig config;
  const Elevator({super.key, required this.config});

  @override
  ConsumerState<Elevator> createState() => _ElevatorState();
}

class _ElevatorState extends ConsumerState<Elevator> {
  /// Target progress 0..1, written by stream emissions; the painter
  /// listens via super(repaint:).
  late final ValueNotifier<double> _progress;

  /// Per-frame animation notifier. The painter's super(repaint:) listens
  /// to this; the TweenAnimationBuilder writes to it on every frame so
  /// the painter sees smooth motion without rebuilding above the
  /// CustomPaint subtree (ARCHITECTURE Pattern 3).
  late final ValueNotifier<double> _animProgress;

  /// The double stream constructed once per mount (or per positionKey
  /// change). Null when positionKey is empty (stale path 1).
  Stream<DynamicValue>? _positionStream;

  /// Subscription to _positionStream; null when no stream hoisted.
  StreamSubscription<DynamicValue>? _streamSub;

  /// The positionKey that _positionStream was constructed for. Compared
  /// against widget.config.positionKey in didUpdateWidget so we re-hoist
  /// even when the editor mutates the same ElevatorConfig instance
  /// in-place (matches the sensor.dart precedent — `oldWidget.config`
  /// and `widget.config` are the same reference, so we cannot rely on
  /// `oldWidget.config.positionKey` to reflect the previous value).
  String? _hoistedKey;

  /// True while the stream has not yet emitted a usable double, or has
  /// errored. Flipped to false on the first valid emission. The painter
  /// receives this OR'd with `config.positionKey.isEmpty`.
  bool _isStreamStale = true;

  @override
  void initState() {
    super.initState();
    _progress = ValueNotifier<double>(0.0);
    _animProgress = ValueNotifier<double>(0.0);
    _hoistStream();
  }

  @override
  void didUpdateWidget(covariant Elevator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-hoist only when the key actually changes — preserves stream
    // identity across rebuilds with same config (Pitfall 2 invariant).
    // Compare against the stored `_hoistedKey` rather than
    // `oldWidget.config.positionKey` because the editor mutates the
    // same config instance in-place, so `oldWidget.config` and
    // `widget.config` are the same reference.
    if (_hoistedKey != widget.config.positionKey) {
      _hoistStream();
    }
  }

  /// Construct the position stream once. Called from `initState` and
  /// `didUpdateWidget` only when `positionKey` changes. NEVER called
  /// from `build()` — that would recreate the stream every frame and
  /// trigger an OPC UA monitored-item create/cancel storm (Pitfall 2).
  ///
  /// LOCKED — Pitfall 2 regression guard:
  ///   100 rebuilds with the same positionKey MUST preserve
  ///   `_positionStream` reference identity. Enforced by
  ///   `test/page_creator/assets/elevator_widget_test.dart`,
  ///   group 'Stream lifecycle (Pitfall 2)', test
  ///   '100 rebuilds with same positionKey: stream identity preserved'.
  ///   If you change this method, that test must continue to pass.
  ///
  ///   Equally locked: 'changing positionKey re-hoists stream
  ///   (different identity)' — re-hoist guard via `_hoistedKey`.
  ///
  ///   And: 'unmount disposes ValueNotifier and cancels subscription'
  ///   — `_streamSub.cancel()` before re-hoisting closes Pitfall 10.
  void _hoistStream() {
    // Cancel any prior subscription before re-hoisting.
    _streamSub?.cancel();
    _streamSub = null;

    final key = widget.config.positionKey;
    _hoistedKey = key;
    if (key.isEmpty) {
      _positionStream = null;
      // Empty key — stale path 1 — no setState needed during initState
      // because _isStreamStale is already true. didUpdateWidget guards
      // the redundant flip via the equality check inside the listener.
      if (mounted && !_isStreamStale) {
        setState(() => _isStreamStale = true);
      }
      return;
    }
    _positionStream = ref
        .read(stateManProvider.future)
        .asStream()
        .asyncExpand((sm) => sm.subscribe(key).asStream())
        .asyncExpand((s) => s);

    _streamSub = _positionStream!.listen(
      _onStreamData,
      onError: _onStreamError,
    );
    // Initial state: stale until first emission.
    if (mounted && !_isStreamStale) {
      setState(() => _isStreamStale = true);
    }
  }

  void _onStreamData(DynamicValue dv) {
    // Guard for non-double / non-integer values (per analog_box.dart
    // precedent). `.asDouble` throws or coerces depending on type;
    // require explicit guard.
    final raw = _coerceDouble(dv);
    if (raw == null) {
      if (!_isStreamStale && mounted) {
        setState(() => _isStreamStale = true);
      }
      return;
    }
    _progress.value = platformProgress(raw);
    if (_isStreamStale && mounted) {
      setState(() => _isStreamStale = false);
    }
  }

  void _onStreamError(Object error, StackTrace st) {
    if (!_isStreamStale && mounted) {
      setState(() => _isStreamStale = true);
    }
  }

  /// Coerces a [DynamicValue] to a double if it carries a numeric
  /// payload; returns null otherwise (stale path).
  double? _coerceDouble(DynamicValue dv) {
    try {
      return dv.asDouble;
    } catch (_) {
      return null;
    }
  }

  /// Test seam — production code MUST NOT depend on this getter.
  /// Used by the Pitfall 2 stream-lifecycle regression test in
  /// `elevator_widget_test.dart` (Cycle B) to assert
  /// `identical(oldStream, newStream)` across rebuilds with same
  /// positionKey.
  @visibleForTesting
  Stream<DynamicValue>? get debugPositionStream => _positionStream;

  /// Test seam — exposes the live ValueNotifier so animation tests
  /// can assert progress.value reflects the most recent emission
  /// without poking into private state.
  @visibleForTesting
  ValueListenable<double> get debugProgress => _progress;

  /// Effective stale flag fed to the painter — true when no key is
  /// configured OR the stream has not produced a usable double yet OR
  /// the stream errored.
  bool get _isStaleEffective =>
      widget.config.positionKey.isEmpty || _isStreamStale;

  /// Opens the config dialog. Wraps the asset's `configure(context)`
  /// in a `Dialog` so the editor's Material widgets (TextField,
  /// KeyField, SizeField, CoordinatesField — all inheriting TextField
  /// somewhere) find a Material ancestor. Mirrors sensor.dart's
  /// _openConfigDialog precedent (sensor.dart:256-263).
  void _openConfigDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: widget.config.configure(context),
      ),
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _progress.dispose();
    _animProgress.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Phase 3 — child composition
  //
  // CONTEXT §Hit-Test Through Translation: children's hit-test follows
  // their `Positioned.top` value — Flutter's hit-test walks the layout
  // tree, so Positioned-driven layout means taps land on the rendered
  // glyph regardless of platform position. This is the user's locked
  // directive (ELEV-19 / Pitfall 7) — DO NOT replace Positioned with
  // Transform.translate around children.
  //
  // CONTEXT §Child Layout & Identity:
  //   - Stack(clipBehavior: Clip.none) so children may extend outside
  //     the elevator bbox during translation without being clipped.
  //   - Each child wrapper carries ValueKey<String>(entry.id) — the UUID
  //     locked in Plan 02-02's ElevatorChildEntry schema (ELEV-12).
  //   - Each child renders via entry.child.build(context) — the elevator
  //     NEVER switches on child runtime type (ELEV-11, ARCHITECTURE
  //     Anti-Pattern 1).
  //   - Each child's bottom edge sits on the platform's top edge:
  //     `top = platformOffsetTop(progress, bboxH, platformH) - childH`.
  // ---------------------------------------------------------------------------

  /// Builds the Stack that composes the elevator visuals: painter at
  /// index 0, then one Positioned per ElevatorChildEntry. Driven by
  /// `_animProgress` so children translate in lock-step with the
  /// platform.
  Widget _buildStack(Size paintSize, bool isStale, Color activeColor) {
    // Platform deck height — MUST match `kPlatformHeightFraction` in
    // elevator_painter.dart so children anchor exactly to the painted
    // platform's top edge. The fraction is the painter's source of
    // truth; we import the constant directly to keep the two values
    // welded together.
    final platformH = paintSize.height * kPlatformHeightFraction;
    final children = <Widget>[
      CustomPaint(
        size: paintSize,
        painter: ElevatorPainter(
          progress: _animProgress,
          isStale: isStale,
          activeColor: activeColor,
        ),
      ),
      for (final entry in widget.config.children)
        _buildPositionedChild(entry, paintSize, platformH),
    ];
    return SizedBox(
      width: paintSize.width,
      height: paintSize.height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  /// Builds a Positioned wrapper for a single child entry. The child
  /// subtree is built ONCE and cached as the inner ValueListenableBuilder's
  /// `child:` parameter — only the Positioned (and its `top`) rebuilds
  /// per `_animProgress` change. This preserves the child's State
  /// identity across frames (Pitfall 1: 50 progress changes → 1 initState
  /// call). The KeyedSubtree carrying the `ValueKey<String>(entry.id)`
  /// is what Flutter's element-reconciliation algorithm uses to
  /// recognise the subtree as the same instance even if the child list
  /// is mutated.
  Widget _buildPositionedChild(
    ElevatorChildEntry entry,
    Size paintSize,
    double platformH,
  ) {
    final intrinsic = entry.child.size.toSize(paintSize);
    final childW = intrinsic.width <= 0
        ? paintSize.shortestSide / 4
        : intrinsic.width;
    final childH = intrinsic.height <= 0
        ? paintSize.shortestSide / 4
        : intrinsic.height;
    final left = entry.offsetX * paintSize.width - childW / 2;
    return ValueListenableBuilder<double>(
      valueListenable: _animProgress,
      child: KeyedSubtree(
        key: ValueKey<String>(entry.id),
        child: SizedBox(
          width: childW,
          height: childH,
          child: entry.child.build(context),
        ),
      ),
      builder: (ctx, animProgress, builtChild) {
        final top =
            platformOffsetTop(animProgress, paintSize.height, platformH) -
                childH;
        return Positioned(
          left: left,
          top: top,
          width: childW,
          height: childH,
          child: builtChild!,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final angleDeg = widget.config.coordinates.angle ?? 0.0;
    final activeColor = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openConfigDialog(context),
      child: LayoutRotatedBox(
        angle: angleDeg * pi / 180,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final Size paintSize;
            if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
              paintSize = Size(constraints.maxWidth, constraints.maxHeight);
            } else {
              paintSize =
                  widget.config.size.toSize(MediaQuery.of(context).size);
            }
            // Animation pipeline (ELEV-06):
            //   _progress (target 0..1, written by stream listener)
            //   → ValueListenableBuilder<double>
            //     → TweenAnimationBuilder<double>
            //       → _animProgress (per-frame interpolated value)
            //         → ElevatorPainter.progress (super(repaint:))
            //
            // The Tween's `Tween(begin: target, end: target)` idiom (per
            // CONTEXT decisions §Visual & Position Pipeline) lets each
            // change in _progress.value drive a fresh interpolation toward
            // the new target — no animation while values are equal, smooth
            // glide when the target moves. Curves.linear matches operator
            // expectation for industrial position lifts (no overshoot).
            return ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (ctx, target, _) {
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: target, end: target),
                  duration: Duration(
                    milliseconds: widget.config.tweenDurationMs,
                  ),
                  curve: Curves.linear,
                  builder: (ctx, animValue, _) {
                    // Push the animated value into the per-frame notifier
                    // so the painter's super(repaint:) sees changes
                    // without rebuilding the CustomPaint subtree itself.
                    _animProgress.value = animValue;
                    return _buildStack(
                      paintSize,
                      _isStaleEffective,
                      activeColor,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Config editor — the body of the configure dialog.
// ---------------------------------------------------------------------------

/// Editor body for `ElevatorConfig`. Mirrors `_SensorConfigEditor` but
/// skips colour/kind/preview controls (elevator has only one variant
/// and no per-instance colour overrides in this phase). The "Children"
/// section is a read-only placeholder in Phase 2 — the schema is locked
/// (Plan 02-02) but the list-management UI lands in Phase 3.
///
/// All edits are mutations on the live `widget.config` instance — the
/// page editor reuses the same config object across rebuilds, so the
/// parent's page model picks the changes up automatically (see
/// `Elevator.didUpdateWidget` for the matching invariant on the runtime
/// side — re-hoists position stream when `positionKey` changes).
class _ElevatorConfigEditor extends StatefulWidget {
  final ElevatorConfig config;
  const _ElevatorConfigEditor({required this.config});

  @override
  State<_ElevatorConfigEditor> createState() => _ElevatorConfigEditorState();
}

class _ElevatorConfigEditorState extends State<_ElevatorConfigEditor> {
  late TextEditingController _tweenController;

  @override
  void initState() {
    super.initState();
    _tweenController =
        TextEditingController(text: widget.config.tweenDurationMs.toString());
  }

  @override
  void dispose() {
    _tweenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24), // mirrors sensor.dart UI-SPEC lg = 24
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Position State Key (ELEV-04 surface) --
            KeyField(
              label: 'Position State Key (0-100%)',
              initialValue: config.positionKey,
              onChanged: (v) => setState(() => config.positionKey = v),
            ),
            const SizedBox(height: 16),

            // -- Tween Duration (ms) --
            TextFormField(
              controller: _tweenController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Tween Duration (ms)',
                hintText: '250',
                helperText: 'Smoothing for platform position changes',
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null && parsed >= 0) {
                  setState(() => config.tweenDurationMs = parsed);
                }
                // Empty / non-numeric input: leave config.tweenDurationMs
                // unchanged so the runtime keeps the last valid value.
              },
            ),
            const SizedBox(height: 16),

            // -- Size --
            SizeField(
              initialValue: config.size,
              onChanged: (v) => setState(() => config.size = v),
            ),
            const SizedBox(height: 16),

            // -- Coordinates (includes angle slider — enableAngle: true,
            //    same as Sensor / Conveyor) --
            CoordinatesField(
              initialValue: config.coordinates,
              onChanged: (c) => setState(() => config.coordinates = c),
              enableAngle: true,
            ),
            const SizedBox(height: 16),
            const Divider(),

            // -- Children (read-only placeholder; Phase 3 replaces with
            //    add/edit/delete UI per the conveyor.dart precedent) --
            Text('Children', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              'Children: ${config.children.length} (managed in Phase 3)',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
