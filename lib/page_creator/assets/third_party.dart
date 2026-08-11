import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tfc/converter/color_converter.dart';

import '../../providers/state_man.dart';
import 'common.dart';
import 'led.dart' show LEDPainter, LEDType;
import 'third_party_painter.dart';

part 'third_party.g.dart';

/// The piece of third-party equipment this asset stands for.
///
/// Drives painter dispatch — one simplified top view per kind. Adding a value
/// here is a compile error in `_createPainter` until a painter is wired up,
/// which is deliberate.
@JsonEnum()
enum ThirdPartyEquipmentKind {
  multivac,
  speedBatcher,

  /// TODO(product-name): the make/model of the box erector on the line has not
  /// been identified yet. Rename this value (and its label + painter) once it
  /// is — every other kind is named after its manufacturer.
  boxErector,

  strappingLine,
}

/// Operator-facing metadata for each kind. Kept out of the enum so the
/// persisted JSON stays a stable identifier while the display text can change
/// freely.
extension ThirdPartyEquipmentKindInfo on ThirdPartyEquipmentKind {
  /// Name shown in the kind dropdown and as the details-dialog title.
  String get label {
    switch (this) {
      case ThirdPartyEquipmentKind.multivac:
        return 'Multivac thermoformer';
      case ThirdPartyEquipmentKind.speedBatcher:
        return 'Marel SpeedBatcher';
      case ThirdPartyEquipmentKind.boxErector:
        return 'Box erector (TODO: product name)';
      case ThirdPartyEquipmentKind.strappingLine:
        return 'Afak / Strapex strapping line';
    }
  }

  /// Real machine footprint, shown in the details dialog. Length x width in
  /// plan, from the manufacturer's spec sheet — see the source notes at the
  /// top of `third_party_painter.dart`.
  String get footprint {
    switch (this) {
      case ThirdPartyEquipmentKind.multivac:
        return '~5437 x 1002 mm (R 245)';
      case ThirdPartyEquipmentKind.speedBatcher:
        return '~2311 x 1270 mm (SBM3000)';
      case ThirdPartyEquipmentKind.boxErector:
        return '~2395 x 2083 mm (generic RSC erector)';
      case ThirdPartyEquipmentKind.strappingLine:
        return '~2665 x 1815 mm (SL-15-3)';
    }
  }

  /// Plan-view aspect ratio (length / width) of the real machine.
  ///
  /// The painters are authored at these proportions. Sizing an asset well away
  /// from its kind's ratio squashes the layout — the Multivac especially, at
  /// 5.4:1. Used for the config-editor preview so what you see there is
  /// undistorted.
  double get aspectRatio {
    switch (this) {
      case ThirdPartyEquipmentKind.multivac:
        return 5437 / 1002;
      case ThirdPartyEquipmentKind.speedBatcher:
        return 2311 / 1270;
      case ThirdPartyEquipmentKind.boxErector:
        return 2395 / 2083;
      case ThirdPartyEquipmentKind.strappingLine:
        return 2665 / 1815;
    }
  }
}

/// A piece of equipment we do NOT control, shown on the line overview so the
/// operator can see the handshake between our PLC and the neighbouring
/// machine.
///
/// Renders a simplified top view of the selected machine inside a dotted
/// boundary box — the dotted line is the visual convention for "outside our
/// scope of supply". One LED in the top-left corner reports run status; tap
/// anywhere in the box for the details dialog.
///
/// Scope note: run status is the ONLY live signal for now. Richer handshake
/// state (ready / fault / demand) can be added as extra keys later without
/// changing the layout — the header strip has room for more LEDs.
@JsonSerializable(explicitToJson: true)
class ThirdPartyEquipmentConfig extends BaseAsset {
  @override
  String get displayName => '3rd Party Equipment';

  @override
  String get category => 'Third Party';

  /// Which machine this asset represents.
  @JsonKey(unknownEnumValue: ThirdPartyEquipmentKind.multivac)
  ThirdPartyEquipmentKind kind;

  /// State key carrying the machine's run status as a bool.
  ///
  /// Empty key, no value yet, or a stream error all render the LED grey with
  /// the `!` glyph (`LEDPainter`'s unknown state) rather than claiming the
  /// machine is stopped.
  String runKey;

  /// When true the visual run state is the inverse of the raw bool — for
  /// equipment that hands us a "stopped" contact rather than a "running" one.
  bool invertRunPolarity;

  /// LED colour while the machine is running.
  @ColorConverter()
  Color runningColor;

  /// LED colour while the machine is stopped.
  @ColorConverter()
  Color stoppedColor;

  /// Outline colour of the machine drawing. The dotted boundary uses the same
  /// colour at reduced opacity.
  @ColorConverter()
  Color outlineColor;

  /// Outline stroke width in logical pixels.
  double strokeWidth;

  /// Optional human-readable label (e.g. `"MV-01"`).
  String? tag;

  /// Free-text notes surfaced in the details dialog — supplier contact, line
  /// position, interlock quirks, whatever the operator needs at 03:00.
  String? notes;

  /// `Asset.text` is what `AssetStack` (in `lib/pages/page_view.dart`) reads to
  /// paint the label OUTSIDE the asset's rotated subtree. Aliasing `text` onto
  /// `tag` — the same trick `SensorConfig` uses — keeps the label upright
  /// regardless of `Coordinates.angle`.
  @override
  String? get text => tag;

  /// Non-null writes only. The generated `fromJson` assigns `..text =` AFTER
  /// the constructor has set `tag`; adopting a null `text` from a legacy page
  /// would wipe a perfectly good tag. Mirrors `SensorConfig.text`.
  @override
  set text(String? value) {
    if (value != null) tag = value;
  }

  ThirdPartyEquipmentConfig({
    this.kind = ThirdPartyEquipmentKind.multivac,
    this.runKey = '',
    this.invertRunPolarity = false,
    Color? runningColor,
    Color? stoppedColor,
    Color? outlineColor,
    this.strokeWidth = 2.0,
    this.tag,
    this.notes,
  })  : runningColor = runningColor ?? Colors.green,
        stoppedColor = stoppedColor ?? Colors.red,
        outlineColor = outlineColor ?? Colors.blueGrey {
    textPos = TextPos.below;
    // These machines are wide; the BaseAsset 3%×3% default would squash the
    // top view into an unreadable stamp. `fromJson` assigns `..size` after the
    // constructor, so persisted sizes still win.
    size = const RelativeSize(width: 0.16, height: 0.10);
  }

  ThirdPartyEquipmentConfig.preview() : this();

  factory ThirdPartyEquipmentConfig.fromJson(Map<String, dynamic> json) =>
      _$ThirdPartyEquipmentConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ThirdPartyEquipmentConfigToJson(this);

  @override
  Widget build(BuildContext context) => ThirdPartyEquipment(config: this);

  @override
  Widget configure(BuildContext context) =>
      _ThirdPartyEquipmentConfigEditor(config: this);
}

/// Apply polarity inversion to a raw run bool.
///
/// `isRunning = invertRunPolarity ? !rawBool : rawBool`. Mirrors
/// `sensorIsActive` in `sensor.dart`.
bool thirdPartyIsRunning({
  required bool rawBool,
  required bool invertRunPolarity,
}) {
  return invertRunPolarity ? !rawBool : rawBool;
}

/// Picks the painter for [kind].
///
/// Exhaustive switch with no `default` — a new [ThirdPartyEquipmentKind] must
/// come with a painter or this stops compiling. Shared by the runtime widget
/// and the config-editor preview so the two can never drift.
ThirdPartyMachinePainter thirdPartyPainterFor(
  ThirdPartyEquipmentKind kind, {
  required Color color,
  required double strokeWidth,
}) {
  switch (kind) {
    case ThirdPartyEquipmentKind.multivac:
      return MultivacPainter(color: color, strokeWidth: strokeWidth);
    case ThirdPartyEquipmentKind.speedBatcher:
      return SpeedBatcherPainter(color: color, strokeWidth: strokeWidth);
    case ThirdPartyEquipmentKind.boxErector:
      return BoxErectorPainter(color: color, strokeWidth: strokeWidth);
    case ThirdPartyEquipmentKind.strappingLine:
      return StrappingLinePainter(color: color, strokeWidth: strokeWidth);
  }
}

// ---------------------------------------------------------------------------
// Runtime widget
// ---------------------------------------------------------------------------

/// Live third-party equipment widget driven by a bool run-status key.
///
/// The stream is hoisted to `initState` and only rebuilt when `runKey` changes
/// — building it in `build()` would create and cancel an OPC UA monitored item
/// every frame. Same lifecycle contract as `Sensor` in `sensor.dart`.
class ThirdPartyEquipment extends ConsumerStatefulWidget {
  final ThirdPartyEquipmentConfig config;
  const ThirdPartyEquipment({super.key, required this.config});

  @override
  ConsumerState<ThirdPartyEquipment> createState() =>
      _ThirdPartyEquipmentState();
}

class _ThirdPartyEquipmentState extends ConsumerState<ThirdPartyEquipment> {
  /// `null` means no stream is needed — the run key is empty.
  Stream<bool>? _runStream;

  /// The key `_runStream` was built for. Compared against the live config
  /// rather than `oldWidget.config.runKey` because the page editor mutates the
  /// same config instance in place, so both widgets hold the same reference.
  String? _hoistedKey;

  @override
  void initState() {
    super.initState();
    _hoistStream();
  }

  @override
  void didUpdateWidget(covariant ThirdPartyEquipment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hoistedKey != widget.config.runKey) {
      _hoistStream();
    }
  }

  void _hoistStream() {
    final key = widget.config.runKey;
    _hoistedKey = key;
    if (key.isEmpty) {
      _runStream = null;
      return;
    }
    _runStream = ref
        .read(stateManProvider.future)
        .asStream()
        .asyncExpand((sm) => sm.subscribe(key).asStream())
        .asyncExpand((s) => s)
        .map((dv) => dv.asBool);
  }

  /// Test-only window onto the hoisted stream identity, so the stream
  /// lifecycle can be asserted without a real `StateMan`.
  @visibleForTesting
  Stream<bool>? get debugRunStream => _runStream;

  /// Read-only details dialog — this is the "more information" behind the tap.
  ///
  /// No writes: we do not command third-party equipment from here, we only
  /// report what the handshake says.
  void _showDetailsDialog(BuildContext context, bool? isRunning) {
    final config = widget.config;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(config.kind.label),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow('Equipment', config.kind.label),
              _DetailRow('Footprint', config.kind.footprint),
              if (config.tag != null && config.tag!.isNotEmpty)
                _DetailRow('Tag', config.tag!),
              _DetailRow(
                'Run status key',
                config.runKey.isEmpty ? '—' : config.runKey,
              ),
              _DetailRow(
                'Run status',
                config.runKey.isEmpty
                    ? 'no key configured'
                    : isRunning == null
                        ? 'unknown'
                        : isRunning
                            ? 'running'
                            : 'stopped',
              ),
              _DetailRow(
                'Run polarity inverted',
                config.invertRunPolarity ? 'yes' : 'no',
              ),
              if (config.notes != null && config.notes!.isNotEmpty)
                _DetailRow('Notes', config.notes!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Machine drawing + dotted boundary + run LED, wrapped in the tap target.
  ///
  /// The `GestureDetector` sits OUTSIDE `LayoutRotatedBox` because
  /// `_RenderLayoutRotatedBox.hitTest` (in `common.dart`) does not forward hits
  /// to its child — same arrangement as `Sensor._buildPaint` and
  /// `_buildGate` in `conveyor_gate.dart`.
  Widget _buildBody(bool? isRunning) {
    final config = widget.config;
    final ledColor = isRunning == null
        ? null
        : (isRunning ? config.runningColor : config.stoppedColor);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDetailsDialog(context, isRunning),
      child: LayoutRotatedBox(
        angle: (config.coordinates.angle ?? 0.0) * pi / 180,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Prefer the bounded asset rect; fall back to the configured size
            // resolved against the screen for the standalone/preview path.
            final Size paintSize =
                constraints.hasBoundedWidth && constraints.hasBoundedHeight
                    ? Size(constraints.maxWidth, constraints.maxHeight)
                    : config.size.toSize(MediaQuery.of(context).size);

            return ThirdPartyEquipmentBody(
              painter: thirdPartyPainterFor(
                config.kind,
                color: config.outlineColor,
                strokeWidth: config.strokeWidth,
              ),
              paintSize: paintSize,
              ledColor: ledColor,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Stale path #1: no key configured, so no stream was ever built.
    if (_runStream == null) return _buildBody(null);

    return StreamBuilder<bool>(
      stream: _runStream,
      builder: (context, snapshot) {
        // Stale paths #2 and #3: nothing emitted yet, or the stream errored.
        if (!snapshot.hasData || snapshot.hasError) return _buildBody(null);
        return _buildBody(thirdPartyIsRunning(
          rawBool: snapshot.data!,
          invertRunPolarity: widget.config.invertRunPolarity,
        ));
      },
    );
  }
}

/// The painted body: machine glyph + dotted boundary, with the run LED
/// composited into the top-left header strip.
///
/// The LED is a real [LEDPainter] rather than a circle drawn by the machine
/// painter, so it matches every other LED on the page — including the grey `!`
/// it draws for an unknown value (`ledColor == null`).
///
/// Split out as its own widget so the config-editor preview and the golden
/// tests can render it without a `StateMan`.
class ThirdPartyEquipmentBody extends StatelessWidget {
  const ThirdPartyEquipmentBody({
    super.key,
    required this.painter,
    required this.paintSize,
    required this.ledColor,
  });

  final ThirdPartyMachinePainter painter;
  final Size paintSize;

  /// `null` renders the LED's unknown state.
  final Color? ledColor;

  @override
  Widget build(BuildContext context) {
    final boundary = thirdPartyBoundaryRect(paintSize);
    final led = thirdPartyLedDiameter(paintSize);
    final inset = thirdPartyLedInset(paintSize);

    return SizedBox(
      width: paintSize.width,
      height: paintSize.height,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: painter)),
          Positioned(
            left: boundary.left + inset,
            top: boundary.top + inset,
            width: led,
            height: led,
            child: CustomPaint(
              painter: LEDPainter(color: ledColor, ledType: LEDType.circle),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single label/value row for the details dialog. Values are selectable so
/// operators can copy a state key out while troubleshooting.
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 180,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Config editor
// ---------------------------------------------------------------------------

/// Editor body for [ThirdPartyEquipmentConfig]. Field order follows the
/// house pattern: preview, identity, live keys, colours, label, geometry.
class _ThirdPartyEquipmentConfigEditor extends StatefulWidget {
  final ThirdPartyEquipmentConfig config;
  const _ThirdPartyEquipmentConfigEditor({required this.config});

  @override
  State<_ThirdPartyEquipmentConfigEditor> createState() =>
      _ThirdPartyEquipmentConfigEditorState();
}

class _ThirdPartyEquipmentConfigEditorState
    extends State<_ThirdPartyEquipmentConfigEditor> {
  late TextEditingController _tagController;
  late TextEditingController _notesController;

  /// Bumped only by the "match proportions" button, and used as the
  /// `SizeField` key.
  ///
  /// `SizeField` seeds its text controllers in `initState` and never resyncs
  /// them, so writing `config.size` from outside would leave a stale height in
  /// the box — and the operator's next keystroke in either field would push
  /// that stale value straight back over the computed one. Changing the key
  /// remounts the field against the new size. It must NOT be derived from
  /// `config.size` itself: typing in the field also changes the size, and
  /// remounting mid-keystroke would reset the cursor.
  int _sizeFieldEpoch = 0;

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.config.tag ?? '');
    _notesController = TextEditingController(text: widget.config.notes ?? '');
  }

  @override
  void dispose() {
    _tagController.dispose();
    _notesController.dispose();
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

  Widget _colorRow(String label, Color color, ValueChanged<Color> onChanged) {
    return GestureDetector(
      onTap: () => _showColorPicker(context, color, onChanged),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    // Preview at the machine's TRUE plan aspect ratio, so the layout is
    // undistorted here even if the asset on the page is sized differently.
    // The floor keeps the Multivac (5.4:1) from collapsing to a hairline.
    const previewWidth = 300.0;
    final previewSize = Size(
      previewWidth,
      (previewWidth / config.kind.aspectRatio).clamp(56.0, 240.0),
    );

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ThirdPartyEquipmentBody(
                painter: thirdPartyPainterFor(
                  config.kind,
                  color: config.outlineColor,
                  strokeWidth: config.strokeWidth,
                ),
                paintSize: previewSize,
                // Preview always shows the running colour — the operator is
                // picking colours here, not reading live state.
                ledColor: config.runningColor,
              ),
            ),
            const Divider(),

            // -- Equipment kind --
            Text('Equipment', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            DropdownButton<ThirdPartyEquipmentKind>(
              value: config.kind,
              isExpanded: true,
              onChanged: (value) => setState(() => config.kind = value!),
              items: ThirdPartyEquipmentKind.values
                  .map((e) => DropdownMenuItem<ThirdPartyEquipmentKind>(
                        value: e,
                        child: Text(e.label),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // -- Run status key --
            KeyField(
              label: 'Run Status Key',
              initialValue: config.runKey,
              onChanged: (v) => setState(() => config.runKey = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Invert Run Polarity'),
              subtitle: Text(
                config.invertRunPolarity
                    ? 'Running when state is false'
                    : 'Running when state is true',
              ),
              value: config.invertRunPolarity,
              onChanged: (v) => setState(() => config.invertRunPolarity = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

            // -- Colours --
            _colorRow('Running Color', config.runningColor,
                (c) => setState(() => config.runningColor = c)),
            const SizedBox(height: 8),
            _colorRow('Stopped Color', config.stoppedColor,
                (c) => setState(() => config.stoppedColor = c)),
            const SizedBox(height: 8),
            _colorRow('Outline Color', config.outlineColor,
                (c) => setState(() => config.outlineColor = c)),
            const SizedBox(height: 16),

            // -- Stroke width --
            TextFormField(
              initialValue: config.strokeWidth.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stroke Width'),
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null && parsed > 0.0 && parsed <= 10.0) {
                  setState(() => config.strokeWidth = parsed);
                }
              },
            ),
            const SizedBox(height: 16),

            // -- Tag --
            TextFormField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: 'Tag (e.g. MV-01)',
                hintText: 'Optional',
              ),
              onChanged: (v) => setState(() => config.tag = v.isEmpty ? null : v),
            ),
            const SizedBox(height: 16),

            // -- Notes (details dialog) --
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Shown in the details dialog',
              ),
              onChanged: (v) =>
                  setState(() => config.notes = v.isEmpty ? null : v),
            ),
            const SizedBox(height: 16),

            // -- Label position --
            Text('Label Position',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            DropdownButton<TextPos>(
              value: config.textPos ?? TextPos.below,
              isExpanded: true,
              onChanged: (value) => setState(() => config.textPos = value!),
              items: TextPos.values
                  .map((e) =>
                      DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
                  .toList(),
            ),
            const SizedBox(height: 16),

            SizeField(
              key: ValueKey(_sizeFieldEpoch),
              initialValue: config.size,
              onChanged: (v) => setState(() => config.size = v),
            ),
            const SizedBox(height: 8),
            // The four kinds range from 1.15:1 to 5.4:1 in plan, so a size
            // that suits one squashes another. This keeps the width and
            // solves for the height that reproduces the real footprint on
            // screen.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.aspect_ratio, size: 18),
                label: Text('Match ${config.kind.label} proportions'),
                onPressed: () {
                  final screen = MediaQuery.of(context).size;
                  final height = config.size.width *
                      screen.width /
                      (config.kind.aspectRatio * screen.height);
                  setState(() {
                    config.size = RelativeSize(
                      width: config.size.width,
                      height: height,
                    );
                    _sizeFieldEpoch++;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

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
