import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/converter/color_converter.dart';

import '../../providers/state_man.dart';
import 'common.dart';
import 'sensor_painter.dart';

part 'sensor.g.dart';

/// The kind of sensor — drives painter dispatch and glyph appearance.
@JsonEnum()
enum SensorKind {
  redLight,
  opticField,
  inductiveField,
}

/// Configuration for a sensor asset.
///
/// Pure data model — JSON-serialisable, no widget/painter wiring. The widget,
/// painter, registry registration, and config dialog are introduced in
/// Plans 02–05 of the same phase.
@JsonSerializable(explicitToJson: true)
class SensorConfig extends BaseAsset {
  @override
  String get displayName => 'Sensor';

  @override
  String get category => 'Visualization';

  /// Sensor kind — determines which painter renders the glyph.
  @JsonKey(unknownEnumValue: SensorKind.redLight)
  SensorKind kind;

  /// State key emitting the raw detection bool.
  String detectionKey;

  /// When true, the visual `isActive` is the inverse of the raw bool.
  bool invertActivePolarity;

  /// State key carrying the rising-edge delay (ms). Display-only.
  String risingEdgeDelayKey;

  /// State key carrying the falling-edge delay (ms). Display-only.
  String fallingEdgeDelayKey;

  /// Per-instance active colour. Default `Colors.green` matches `led.dart`.
  @ColorConverter()
  Color activeColor;

  /// Per-instance inactive colour. Default `Colors.grey.shade400`.
  @ColorConverter()
  Color inactiveColor;

  /// Optional human-readable label (e.g. `"PE-101A"`).
  String? tag;

  SensorConfig({
    this.kind = SensorKind.redLight,
    this.detectionKey = '',
    this.invertActivePolarity = false,
    this.risingEdgeDelayKey = '',
    this.fallingEdgeDelayKey = '',
    Color? activeColor,
    Color? inactiveColor,
    this.tag,
  })  : activeColor = activeColor ?? Colors.green,
        inactiveColor = inactiveColor ?? Colors.grey.shade400;

  /// Preview factory with reasonable defaults for the asset palette.
  SensorConfig.preview() : this();

  factory SensorConfig.fromJson(Map<String, dynamic> json) =>
      _$SensorConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$SensorConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return Sensor(config: this);
  }

  /// Returns the body of the configure dialog. Plan 05 will replace this
  /// placeholder with the real editor (kind selector, key fields, colour
  /// pickers, polarity switch). Today this exists only so Plan 03's
  /// tap-to-configure widget test can assert that an `AlertDialog` with the
  /// title "Configure Sensor" appears on tap.
  @override
  Widget configure(BuildContext context) {
    return const AlertDialog(
      title: Text('Configure Sensor'),
      content: Text('Configuration UI — Plan 05'),
    );
  }
}

/// Apply polarity inversion to a raw detection bool.
///
/// Locked formula (per `01-UI-SPEC.md` §Polarity inversion semantics):
/// `isActive = invertActivePolarity ? !rawBool : rawBool`.
///
/// The tooltip and label are NOT affected by polarity inversion — polarity is
/// purely a visual-mapping concern.
bool sensorIsActive({
  required bool rawBool,
  required bool invertActivePolarity,
}) {
  return invertActivePolarity ? !rawBool : rawBool;
}

// ---------------------------------------------------------------------------
// Sensor widget — runtime entry point.
// ---------------------------------------------------------------------------

/// Live sensor widget driven by a bool detection state key.
///
/// Subscribes to `config.detectionKey` via `stateManProvider`. The stream is
/// hoisted to `initState` (Pitfall 2 — no resubscribe storm under high-
/// frequency rebuilds). Visual flips immediately on bool change — no client-
/// side animation, no tween, no debounce, no smoothing (SENS-05). The
/// `StreamBuilder` rebuild is the entire flip mechanism; this property is
/// grep-guarded by a regression test on the source text.
/// Renders neutral grey when the key is empty, the stream has no value yet,
/// or the stream errors (SENS-14, three stale paths).
///
/// Honours `Coordinates.angle` via `LayoutRotatedBox`. Tap opens the config
/// dialog through a real `GestureDetector` with `HitTestBehavior.opaque`
/// (UI-SPEC §Interaction Contract); this survives a translating ancestor
/// (Phase 3 forward-compat — sensor as elevator child).
class Sensor extends ConsumerStatefulWidget {
  final SensorConfig config;
  const Sensor({super.key, required this.config});

  @override
  ConsumerState<Sensor> createState() => _SensorState();
}

class _SensorState extends ConsumerState<Sensor> {
  /// The bool stream constructed once per mount (or per detectionKey change).
  /// `null` indicates the stale path: empty detectionKey — no stream needed.
  Stream<bool>? _detectionStream;

  /// The detectionKey that `_detectionStream` was constructed for. Compared
  /// against `widget.config.detectionKey` in `didUpdateWidget` so we re-hoist
  /// even when the editor mutates the same `SensorConfig` instance in-place
  /// (the case where `oldWidget.config` and `widget.config` are identical
  /// references and we cannot rely on `oldWidget.config.detectionKey` to
  /// reflect the previous value).
  String? _hoistedKey;

  @override
  void initState() {
    super.initState();
    _hoistStream();
  }

  @override
  void didUpdateWidget(covariant Sensor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-hoist only when the key actually changes — preserves stream identity
    // across rebuilds with same config (Pitfall 2 invariant). Compare against
    // the stored `_hoistedKey` rather than `oldWidget.config.detectionKey`
    // because the editor mutates the same config instance in-place, so
    // `oldWidget.config` and `widget.config` are the same reference.
    if (_hoistedKey != widget.config.detectionKey) {
      _hoistStream();
    }
  }

  /// Construct the bool stream once. Called from `initState` and from
  /// `didUpdateWidget` only when `detectionKey` changes. NEVER called from
  /// `build()` — that would recreate the stream every frame and trigger an
  /// OPC UA monitored-item create/cancel storm (Pitfall 2).
  void _hoistStream() {
    final key = widget.config.detectionKey;
    _hoistedKey = key;
    if (key.isEmpty) {
      _detectionStream = null;
      return;
    }
    _detectionStream = ref
        .read(stateManProvider.future)
        .asStream()
        .asyncExpand((sm) => sm.subscribe(key).asStream())
        .asyncExpand((s) => s)
        .map((dv) => dv.asBool);
  }

  /// Test-only window: resolves the painter `isActive` from a raw stream
  /// bool by applying `widget.config.invertActivePolarity` via
  /// [sensorIsActive]. Public-via-annotation only — production code should
  /// continue to read polarity through the `StreamBuilder` path in
  /// [build]. Used by polarity-through-widget tests in
  /// `test/page_creator/assets/sensor_widget_test.dart` to assert that the
  /// widget honours the polarity flag without a real `StateMan`.
  @visibleForTesting
  bool resolveIsActive(bool rawBool) => sensorIsActive(
        rawBool: rawBool,
        invertActivePolarity: widget.config.invertActivePolarity,
      );

  /// Test-only window onto the hoisted stream identity. Production code
  /// must NOT depend on this — it exists so the Pitfall 2 stream-lifecycle
  /// regression tests can assert `identical(oldStream, newStream)` across
  /// rebuilds (no resubscribe storm) and a fresh stream after a
  /// `detectionKey` change.
  @visibleForTesting
  Stream<bool>? get debugDetectionStream => _detectionStream;

  /// Per-kind painter dispatch — exhaustive switch (no `default` clause so
  /// adding a future SensorKind value is a compile error here, not a runtime
  /// surprise). One painter class per kind closes Pitfall 3.
  ///
  /// `config.tag` flows through `label:` on every painter; the painter's
  /// `_paintLabel` helper short-circuits when the value is null/empty, so
  /// passing it unconditionally is safe (SENS-13).
  CustomPainter _createPainter({
    required bool isActive,
    required bool isStale,
  }) {
    final label = widget.config.tag;
    switch (widget.config.kind) {
      case SensorKind.redLight:
        return RedLightBeamPainter(
          isActive: isActive,
          activeColor: widget.config.activeColor,
          inactiveColor: widget.config.inactiveColor,
          label: label,
          isStale: isStale,
        );
      case SensorKind.opticField:
        return OpticFieldPainter(
          isActive: isActive,
          activeColor: widget.config.activeColor,
          inactiveColor: widget.config.inactiveColor,
          label: label,
          isStale: isStale,
        );
      case SensorKind.inductiveField:
        return InductiveFieldPainter(
          isActive: isActive,
          activeColor: widget.config.activeColor,
          inactiveColor: widget.config.inactiveColor,
          label: label,
          isStale: isStale,
        );
    }
  }

  void _openConfigDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => widget.config.configure(context),
    );
  }

  /// Wraps the painter in a Tooltip + tap-receiving GestureDetector + a
  /// rotating layout box. The GestureDetector is the single tap source —
  /// never painter hit-testing (UI-SPEC §Interaction Contract).
  ///
  /// Layering order (outer → inner):
  ///   Tooltip → GestureDetector → LayoutRotatedBox → LayoutBuilder → CustomPaint
  ///
  /// Tooltip is the OUTERMOST wrapper (UI-SPEC §Tooltip trigger): hover
  /// (desktop) and long-press (touch) both fire the tooltip without
  /// consuming the tap. The Tooltip's content widget mounts on open and
  /// unmounts on dismiss — this is what scopes the rising/falling delay
  /// subscriptions to the open lifetime (CONTEXT lock §Tooltip subscription
  /// lifecycle).
  ///
  /// The GestureDetector lives OUTSIDE LayoutRotatedBox because
  /// `LayoutRotatedBox._RenderLayoutRotatedBox.hitTest` (in `common.dart`)
  /// does not forward hits to its child — it only adds a self-entry. This
  /// matches the existing `_buildGate` pattern in `conveyor_gate.dart` where
  /// every `GestureDetector` wraps `LayoutRotatedBox` from the outside, not
  /// the inside. Tap-through-`Transform.translate` (UI-SPEC §Interaction
  /// Contract — Phase 3 forward-compat) is unaffected: `Transform.translate`
  /// defaults `transformHitTests: true`.
  ///
  /// The inner `LayoutBuilder` propagates the parent's bounded constraints
  /// into `CustomPaint.size:` so the painter fills the asset rect — and so
  /// the GestureDetector has a non-zero hit-test box. Mirrors the
  /// `_buildGate` pattern in `conveyor_gate.dart`.
  Widget _buildPaint(CustomPainter painter) {
    final angleDeg = widget.config.coordinates.angle ?? 0.0;
    return Tooltip(
      richMessage: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _SensorTooltipContent(config: widget.config),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openConfigDialog(context),
        child: LayoutRotatedBox(
          angle: angleDeg * pi / 180,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // When placed inside a parent with bounded constraints (the
              // asset rect), use them directly. Otherwise fall back to the
              // config size resolved against the screen — standalone path.
              final Size paintSize;
              if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
                paintSize = Size(constraints.maxWidth, constraints.maxHeight);
              } else {
                paintSize =
                    widget.config.size.toSize(MediaQuery.of(context).size);
              }
              return CustomPaint(
                size: paintSize,
                painter: painter,
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Stale path #1: empty key — no stream constructed in initState.
    if (_detectionStream == null) {
      return _buildPaint(_createPainter(isActive: false, isStale: true));
    }

    return StreamBuilder<bool>(
      stream: _detectionStream,
      builder: (context, snapshot) {
        // Stale path #2 + #3: stream emitted nothing yet, or errored.
        if (!snapshot.hasData || snapshot.hasError) {
          return _buildPaint(_createPainter(isActive: false, isStale: true));
        }
        final isActive = sensorIsActive(
          rawBool: snapshot.data!,
          invertActivePolarity: widget.config.invertActivePolarity,
        );
        return _buildPaint(_createPainter(isActive: isActive, isStale: false));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tooltip content
// ---------------------------------------------------------------------------

/// Tooltip content for the Sensor asset.
///
/// Subscribes to rising/falling edge-delay state keys ONLY while this widget
/// is mounted. Flutter mounts tooltip content widgets when the tooltip opens
/// and unmounts them on dismiss — this satisfies the locked subscribe-on-open,
/// cancel-on-close contract from `01-CONTEXT.md` §Tooltip lifecycle without
/// explicit subscription bookkeeping.
///
/// Locked copy (UI-SPEC §Copywriting Contract):
/// - Empty `detectionKey` → "Detection key not set"
/// - Both delay rows when key is empty → `"<label>: —"` (em-dash)
/// - Configured key without value yet → `"<label>: …"` (ellipsis)
/// - Configured key with value → `"<label>: <ms>ms"`
class _SensorTooltipContent extends ConsumerWidget {
  final SensorConfig config;
  const _SensorTooltipContent({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Stale path: no detection key configured. UI-SPEC locks this string.
    if (config.detectionKey.isEmpty) {
      return const Text('Detection key not set');
    }

    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall ??
          const TextStyle(color: Colors.white, fontSize: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DelayRow(label: 'Rising', stateKey: config.risingEdgeDelayKey),
          _DelayRow(label: 'Falling', stateKey: config.fallingEdgeDelayKey),
        ],
      ),
    );
  }
}

/// Single-line `"Rising: <ms>ms"` / `"Rising: —"` / `"Rising: …"` row.
///
/// `stateKey` (not `key` — that name is reserved for `Widget.key`) is the
/// PLC state key from `SensorConfig.risingEdgeDelayKey` /
/// `fallingEdgeDelayKey`. When empty, the row short-circuits to the em-dash
/// without subscribing — preserves the lifecycle contract for unconfigured
/// keys (no monitored item created at all).
class _DelayRow extends ConsumerWidget {
  final String label;
  final String stateKey;
  const _DelayRow({required this.label, required this.stateKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stateKey.isEmpty) {
      return Text('$label: —');
    }
    return StreamBuilder<num>(
      stream: ref
          .read(stateManProvider.future)
          .asStream()
          .asyncExpand((sm) => sm.subscribe(stateKey).asStream())
          .asyncExpand((s) => s)
          .map((dv) => dv.asInt),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('$label: —');
        }
        if (!snapshot.hasData) {
          return Text('$label: …');
        }
        return Text('$label: ${snapshot.data}ms');
      },
    );
  }
}
