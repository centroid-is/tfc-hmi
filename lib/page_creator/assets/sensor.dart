import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/converter/color_converter.dart';

import '../../providers/state_man.dart';
import 'common.dart';
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
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

  /// `Asset.text` is what `AssetStack` (in `lib/pages/page_view.dart`) reads
  /// to paint the label OUTSIDE the asset's rotated subtree. By aliasing
  /// `text` onto `tag` here, the sensor label rides the same path as Button's
  /// caption (`ButtonConfig.labelColor => textColor`) and stays upright
  /// regardless of `Coordinates.angle` — which supersedes the in-painter
  /// label machinery (counterRotateLabel / _paintLabel) introduced as a
  /// 180° hack in 5509d610.
  @override
  String? get text => tag;

  /// Setter accepts non-null writes only. The generated `fromJson` calls
  /// `..text = json['text']` AFTER the constructor has already set `tag`
  /// from the JSON `tag` key. Legacy persisted pages have `text: null` and
  /// a non-null `tag` — adopting `null` here would clobber that tag and
  /// silently erase the operator's label on first load. Non-null adoption
  /// preserves both the legacy load path and the new round-trip (where
  /// `text` and `tag` hold the same value because the getter aliases them).
  @override
  set text(String? value) {
    if (value != null) tag = value;
  }

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
        inactiveColor = inactiveColor ?? Colors.grey.shade400 {
    // Default label position — matches LED/Button convention (those default
    // to TextPos.right). Sensors carry short tag labels and read most
    // naturally below the glyph on a busy HMI canvas.
    textPos = TextPos.below;
  }

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

  /// Returns the body of the configure dialog. The dialog chrome is
  /// supplied by the page editor's `showDialog` caller — this method
  /// returns the editor *body* only (matches `_ConveyorGateConfigEditor`
  /// pattern in `conveyor_gate.dart`).
  @override
  Widget configure(BuildContext context) {
    return _SensorConfigEditor(config: this);
  }
}

/// Apply polarity inversion to a raw detection bool.
///
/// Locked formula (per `01-UI-SPEC.md` §Polarity inversion semantics):
/// `isActive = invertActivePolarity ? !rawBool : rawBool`.
///
/// The label is NOT affected by polarity inversion — polarity is purely a
/// visual-mapping concern.
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
  /// The painter no longer draws the label — that is handled by `AssetStack`
  /// in `lib/pages/page_view.dart` via `Asset.text` (aliased onto `tag` by
  /// `SensorConfig`). Routing the label outside the rotated subtree means
  /// it stays upright at any `Coordinates.angle`, which obsoletes the
  /// in-painter `counterRotateLabel` hack from 5509d610.
  CustomPainter _createPainter({
    required bool isActive,
    required bool isStale,
  }) {
    switch (widget.config.kind) {
      case SensorKind.redLight:
        return RedLightBeamPainter(
          isActive: isActive,
          activeColor: widget.config.activeColor,
          inactiveColor: widget.config.inactiveColor,
          isStale: isStale,
        );
      case SensorKind.opticField:
        return OpticFieldPainter(
          isActive: isActive,
          activeColor: widget.config.activeColor,
          inactiveColor: widget.config.inactiveColor,
          isStale: isStale,
        );
      case SensorKind.inductiveField:
        return InductiveFieldPainter(
          isActive: isActive,
          activeColor: widget.config.activeColor,
          inactiveColor: widget.config.inactiveColor,
          isStale: isStale,
        );
    }
  }

  /// Opens the read-only details dialog (Plan 04-05 / SENS-01).
  ///
  /// Operators tap the sensor at runtime to inspect current state — kind,
  /// detection key, polarity, edge-delay keys, tag. The dialog is purely
  /// informational: no PLC writes, no config edits. Configuration is
  /// editor-only and routed through `page_editor.dart` →
  /// `SensorConfig.configure(context)`. Mirrors the
  /// `_ConveyorState._showDetailsDialog` precedent (conveyor.dart:902)
  /// in spirit while staying simpler — sensors have no jog buttons or
  /// other operator actions.
  ///
  /// Dialog content uses [_DetailRow] for label/value layout. The
  /// "Detection state" row falls back to a placeholder string rather
  /// than re-plumbing the live stream into the dialog (the painter glyph
  /// already surfaces live state visually — wiring it twice is not worth
  /// the complexity for a polish-phase feature).
  String get _paneId => 'sensor:${identityHashCode(widget.config)}';

  void _showDetailsPane(BuildContext context) {
    showSidePane(
      context: context,
      id: _paneId,
      builder: (_) => SidePane(
        title: 'Sensor',
        subtitle: widget.config.kind.name,
        icon: Icons.sensors,
        status: widget.config.detectionKey.isEmpty
            ? const PaneStatus.unknown('No key')
            : const PaneStatus.running('Live'),
        child: PaneSection(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PaneDetailRow(label: 'Kind', value: widget.config.kind.name),
              PaneDetailRow(
                label: 'Detection key',
                value: widget.config.detectionKey.isEmpty
                    ? '—'
                    : widget.config.detectionKey,
              ),
              PaneDetailRow(
                label: 'Detection state',
                value: widget.config.detectionKey.isEmpty
                    ? 'no key configured'
                    : '(see glyph)',
              ),
              PaneDetailRow(
                label: 'Active polarity inverted',
                value: widget.config.invertActivePolarity ? 'yes' : 'no',
              ),
              PaneDetailRow(
                label: 'Rising edge delay key',
                value: widget.config.risingEdgeDelayKey.isEmpty
                    ? '—'
                    : widget.config.risingEdgeDelayKey,
              ),
              PaneDetailRow(
                label: 'Falling edge delay key',
                value: widget.config.fallingEdgeDelayKey.isEmpty
                    ? '—'
                    : widget.config.fallingEdgeDelayKey,
              ),
              if (widget.config.tag != null && widget.config.tag!.isNotEmpty)
                PaneDetailRow(label: 'Tag', value: widget.config.tag!),
            ],
          ),
        ),
      ),
    );
  }

  /// Wraps the painter in a tap-receiving GestureDetector + a rotating
  /// layout box. The GestureDetector is the single tap source — never
  /// painter hit-testing (UI-SPEC §Interaction Contract).
  ///
  /// Layering order (outer → inner):
  ///   GestureDetector → LayoutRotatedBox → LayoutBuilder → CustomPaint
  ///
  /// The hover tooltip path was removed — operators read full state via
  /// `_showDetailsPane` on tap. No floating panel sits above the sensor
  /// on a busy HMI canvas.
  ///
  /// The GestureDetector lives OUTSIDE LayoutRotatedBox because
  /// `LayoutRotatedBox._RenderLayoutRotatedBox.hitTest` (in `common.dart`)
  /// does not forward hits to its child — it only adds a self-entry. This
  /// matches the existing `_buildGate` pattern in `conveyor_gate.dart`.
  /// Tap-through-`Transform.translate` (Phase 3 forward-compat) is
  /// unaffected: `Transform.translate` defaults `transformHitTests: true`.
  ///
  /// The inner `LayoutBuilder` propagates the parent's bounded constraints
  /// into `CustomPaint.size:` so the painter fills the asset rect — and so
  /// the GestureDetector has a non-zero hit-test box.
  Widget _buildPaint(CustomPainter painter) {
    final angleDeg = widget.config.coordinates.angle ?? 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDetailsPane(context),
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
// Details rows (Plan 04-05 / SENS-01)
// ---------------------------------------------------------------------------
//
// The private `_DetailRow` helper that used to live here is now
// `PaneDetailRow` in widgets/panes/pane_chrome.dart, shared by every pane and
// dialog.

// ---------------------------------------------------------------------------
// Config editor — the body of the configure dialog.
// ---------------------------------------------------------------------------

/// Editor body for `SensorConfig`. Mirrors `_ConveyorGateConfigEditor` but
/// without animation (sensor has no animated state) and with the locked
/// field order from `01-UI-SPEC.md` §Config Dialog Layout.
///
/// All edits are mutations on the live `widget.config` instance — the page
/// editor reuses the same config object across rebuilds, so the parent's
/// page model picks the changes up automatically (see `Sensor.didUpdateWidget`
/// for the matching invariant on the runtime side).
class _SensorConfigEditor extends StatefulWidget {
  final SensorConfig config;
  const _SensorConfigEditor({required this.config});

  @override
  State<_SensorConfigEditor> createState() => _SensorConfigEditorState();
}

class _SensorConfigEditorState extends State<_SensorConfigEditor> {
  late TextEditingController _tagController;

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.config.tag ?? '');
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _showColorPicker(
    BuildContext context,
    Color current,
    ValueChanged<Color> onChanged,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Select Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: onChanged,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(Color color) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade600),
      ),
    );
  }

  /// Per-kind painter dispatch for the live preview. Mirrors the runtime
  /// dispatch in `_SensorState._createPainter` but always renders
  /// `isActive: true` so the preview shows the active visual. The preview
  /// glyph is intentionally label-free — operators can read the tag in the
  /// adjacent `TextFormField` below.
  CustomPainter _previewPainter(SensorConfig config) {
    switch (config.kind) {
      case SensorKind.redLight:
        return RedLightBeamPainter(
          isActive: true,
          activeColor: config.activeColor,
          inactiveColor: config.inactiveColor,
        );
      case SensorKind.opticField:
        return OpticFieldPainter(
          isActive: true,
          activeColor: config.activeColor,
          inactiveColor: config.inactiveColor,
        );
      case SensorKind.inductiveField:
        return InductiveFieldPainter(
          isActive: true,
          activeColor: config.activeColor,
          inactiveColor: config.inactiveColor,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24), // UI-SPEC lg = 24
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Live preview (150x150) — no Play button (sensor has no animation) --
            Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(painter: _previewPainter(config)),
              ),
            ),
            const Divider(),

            // -- Sensor Kind --
            Text('Sensor Kind', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            SegmentedButton<SensorKind>(
              segments: const [
                ButtonSegment(
                    value: SensorKind.redLight, label: Text('Red Light')),
                ButtonSegment(
                    value: SensorKind.opticField, label: Text('Optic Field')),
                ButtonSegment(
                    value: SensorKind.inductiveField,
                    label: Text('Inductive Field')),
              ],
              selected: {config.kind},
              onSelectionChanged: (selection) {
                setState(() => config.kind = selection.first);
              },
            ),
            const SizedBox(height: 16),

            // -- Detection State Key --
            KeyField(
              label: 'Detection State Key',
              initialValue: config.detectionKey,
              onChanged: (v) => setState(() => config.detectionKey = v),
            ),
            const SizedBox(height: 16),

            // -- Invert Active Polarity (locked subtitle copy contract) --
            SwitchListTile(
              title: const Text('Invert Active Polarity'),
              subtitle: Text(
                config.invertActivePolarity
                    ? 'Active when state is false'
                    : 'Active when state is true',
              ),
              value: config.invertActivePolarity,
              onChanged: (v) => setState(() => config.invertActivePolarity = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

            // -- Rising / Falling Edge Delay Keys (paired — 8px between) --
            KeyField(
              label: 'Rising Edge Delay Key',
              initialValue: config.risingEdgeDelayKey,
              onChanged: (v) => setState(() => config.risingEdgeDelayKey = v),
            ),
            const SizedBox(height: 8),
            KeyField(
              label: 'Falling Edge Delay Key',
              initialValue: config.fallingEdgeDelayKey,
              onChanged: (v) => setState(() => config.fallingEdgeDelayKey = v),
            ),
            const SizedBox(height: 16),

            // -- Active Color --
            GestureDetector(
              onTap: () => _showColorPicker(
                context,
                config.activeColor,
                (c) => setState(() => config.activeColor = c),
              ),
              child: Row(children: [
                _colorSwatch(config.activeColor),
                const SizedBox(width: 8),
                const Text('Active Color'),
              ]),
            ),
            const SizedBox(height: 8),

            // -- Inactive Color --
            GestureDetector(
              onTap: () => _showColorPicker(
                context,
                config.inactiveColor,
                (c) => setState(() => config.inactiveColor = c),
              ),
              child: Row(children: [
                _colorSwatch(config.inactiveColor),
                const SizedBox(width: 8),
                const Text('Inactive Color'),
              ]),
            ),
            const SizedBox(height: 16),

            // -- Tag --
            TextFormField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: 'Tag (e.g. PE-101A)',
                hintText: 'Optional',
              ),
              onChanged: (v) {
                setState(() {
                  config.tag = v.isEmpty ? null : v;
                });
              },
            ),
            const SizedBox(height: 16),

            // -- Label Position (mirrors button.dart:758 / led.dart:164) --
            Text('Label Position',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            DropdownButton<TextPos>(
              // Coalesce null → TextPos.below for legacy persisted pages
              // that pre-date this picker (text_pos: null in JSON).
              value: config.textPos ?? TextPos.below,
              isExpanded: true,
              onChanged: (value) {
                setState(() {
                  config.textPos = value!;
                });
              },
              items: TextPos.values
                  .map((e) => DropdownMenuItem<TextPos>(
                        value: e,
                        child: Text(e.name),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // -- Size --
            SizeField(
              initialValue: config.size,
              onChanged: (v) => setState(() => config.size = v),
            ),
            const SizedBox(height: 16),

            // -- Coordinates (includes angle field — SENS-15;
            //    enableAngle: true exposes the angle slider) --
            CoordinatesField(
              initialValue: config.coordinates,
              onChanged: (c) => setState(() => config.coordinates = c),
              enableAngle: true,
            ),
          ],
        ),
      ),
    );
  }
}
