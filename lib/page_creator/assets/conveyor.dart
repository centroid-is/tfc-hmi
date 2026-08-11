import 'dart:ui' show PathMetric, Tangent;

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/providers/collector.dart';
import 'dart:math';
import 'common.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import '../../providers/state_man.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import '../../widgets/graph.dart';
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
import 'auger_conveyor_painter.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/collector.dart';
import '../page.dart';
import 'conveyor_gate.dart';

part 'conveyor.g.dart';

/// Deserialize gates list with backward compatibility for old format.
///
/// Old format: gate config at root level with "asset_name" key.
/// New format: ChildGateEntry with "position", "side", and "gate" sub-object.
List<ChildGateEntry> _gatesFromJson(List<dynamic>? json) {
  if (json == null) return [];
  return json.map((item) {
    final map = item as Map<String, dynamic>;
    // Old format: gate config at root level with "asset_name" key
    if (map.containsKey('asset_name') && !map.containsKey('gate')) {
      final position = (map['position'] as num?)?.toDouble() ?? 0.5;
      final side = map['side'] != null
          ? GateSide.values.firstWhere(
              (e) => e.name == map['side'],
              orElse: () => GateSide.left,
            )
          : GateSide.left;
      return ChildGateEntry(
        position: position,
        side: side,
        gate: ConveyorGateConfig.fromJson(map),
      );
    }
    // New format: ChildGateEntry with "gate" sub-object
    return ChildGateEntry.fromJson(map);
  }).toList();
}

List<Map<String, dynamic>> _gatesToJson(List<ChildGateEntry> gates) =>
    gates.map((e) => e.toJson()).toList();

/// A bend in the conveyor belt.
///
/// The belt runs straight until [position] (fraction of the configured belt
/// length), then follows a circular arc of [radius] belt-widths sweeping
/// [angle] degrees, and continues straight in the new direction. Positive
/// angles turn towards the bottom of the screen, negative towards the top
/// (before the asset's own rotation is applied).
@JsonSerializable()
class ConveyorTurnEntry {
  /// Fractional position along the belt where the turn starts (0.0 = start).
  double position;

  /// Sweep of the turn in degrees. Positive = down/clockwise on screen.
  double angle;

  /// Turn radius expressed in belt widths (the conveyor's cross dimension).
  double radius;

  ConveyorTurnEntry({
    this.position = 0.5,
    this.angle = 45,
    this.radius = 1.5,
  });

  factory ConveyorTurnEntry.fromJson(Map<String, dynamic> json) =>
      _$ConveyorTurnEntryFromJson(json);
  Map<String, dynamic> toJson() => _$ConveyorTurnEntryToJson(this);
}

/// Centerline geometry of a conveyor with one or more [ConveyorTurnEntry]
/// bends, fitted into the asset's bounding box.
///
/// The centerline is built in "natural" units where the belt length equals the
/// box width and the belt width equals the box height (matching the straight
/// rendering), then uniformly scaled and centered so the whole belt stays
/// inside the box. Fractional belt positions (batches, gates) map onto the
/// path through its [PathMetric].
class ConveyorPathGeometry {
  final Path path;
  final double beltWidth;
  final double scale;
  final PathMetric _metric;

  ConveyorPathGeometry._(this.path, this.beltWidth, this.scale, this._metric);

  double get length => _metric.length;

  Tangent tangentAt(double fraction) =>
      _metric.getTangentForOffset(fraction.clamp(0.0, 1.0) * length) ??
      Tangent(Offset.zero, const Offset(1, 0));

  Path extractFraction(double from, double to) => _metric.extractPath(
      from.clamp(0.0, 1.0) * length, to.clamp(0.0, 1.0) * length);

  static ConveyorPathGeometry? build(
    List<ConveyorTurnEntry> turns,
    Size size, {
    double thicknessFactor = 1.0,
  }) {
    if (turns.isEmpty || size.width <= 0 || size.height <= 0) return null;
    // Belt thickness relative to the box height. A bend needs a taller box to
    // fit, which would otherwise force a fat belt — the factor lets e.g. an
    // L-shaped conveyor in a square box keep a thin belt.
    final beltWidth = size.height * thicknessFactor.clamp(0.05, 1.0);
    final targetLength = size.width;
    final sorted = List<ConveyorTurnEntry>.of(turns)
      ..sort((a, b) => a.position.compareTo(b.position));

    final path = Path()..moveTo(0, 0);
    var point = Offset.zero;
    var heading = 0.0;
    var distance = 0.0;

    void straight(double len) {
      if (len <= 0) return;
      point += Offset(cos(heading), sin(heading)) * len;
      path.lineTo(point.dx, point.dy);
      distance += len;
    }

    for (final turn in sorted) {
      final sweep = turn.angle * pi / 180;
      if (sweep == 0) continue;
      final radius = max(turn.radius, 0.1) * beltWidth;
      straight(turn.position.clamp(0.0, 1.0) * targetLength - distance);
      // Arc center sits perpendicular to the travel direction, on the side
      // the belt turns towards (screen coordinates, y down).
      final centerDir = heading + (sweep > 0 ? pi / 2 : -pi / 2);
      final center = point + Offset(cos(centerDir), sin(centerDir)) * radius;
      final startAngle = centerDir + pi;
      path.arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
      );
      heading += sweep;
      point = center +
          Offset(cos(startAngle + sweep), sin(startAngle + sweep)) * radius;
      distance += radius * sweep.abs();
    }
    straight(targetLength - distance);

    // Fit the belt outline (centerline inflated by half the belt width plus
    // the border stroke) into the box, uniformly scaled and centered.
    final bounds = path.getBounds().inflate(beltWidth / 2 + 2);
    if (bounds.width <= 0 || bounds.height <= 0) return null;
    final fit = min(size.width / bounds.width, size.height / bounds.height);
    // Uniform scale by `fit`, then translate the bounds center to the box
    // center (column-major 4x4).
    final dx = size.width / 2 - bounds.center.dx * fit;
    final dy = size.height / 2 - bounds.center.dy * fit;
    final matrix = Matrix4(
      fit, 0, 0, 0, //
      0, fit, 0, 0, //
      0, 0, 1, 0, //
      dx, dy, 0, 1,
    );
    final fitted = path.transform(matrix.storage);
    final metrics = fitted.computeMetrics().toList();
    if (metrics.isEmpty) return null;
    return ConveyorPathGeometry._(fitted, beltWidth * fit, fit, metrics.first);
  }
}

@JsonSerializable(explicitToJson: true)
class ConveyorColorPaletteConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor Palette';
  @override
  String get category => 'Visualization';

  ConveyorColorPaletteConfig();
  bool? preview = false;

  @override
  Widget build(BuildContext context) => ConveyorColorPalette(config: this);

  @override
  Widget configure(BuildContext context) {
    return Column(
      children: [
        SizeField(
          initialValue: size,
          onChanged: (size) => this.size = size,
        ),
        const SizedBox(height: 16),
        CoordinatesField(
          initialValue: coordinates,
          onChanged: (coordinates) => this.coordinates = coordinates,
          enableAngle: true,
        ),
      ],
    );
  }

  ConveyorColorPaletteConfig.preview() : preview = true;

  factory ConveyorColorPaletteConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorColorPaletteConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ConveyorColorPaletteConfigToJson(this);
}

class ConveyorColorPalette extends StatelessWidget {
  final ConveyorColorPaletteConfig config;
  const ConveyorColorPalette({required this.config});

  @override
  Widget build(BuildContext context) {
    // First, compute the exact width/height we want from config.size:
    final size = config.size.toSize(MediaQuery.of(context).size);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: Column(
        children: [
          // ─── Top "title" row ───
          const Expanded(
            flex: 1,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Conveyor colors',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildColorRow(Colors.green, 'Auto', textColor: Colors.white),
                _buildColorRow(Colors.blue, 'Clean', textColor: Colors.white),
                _buildColorRow(Colors.yellow, 'Manual',
                    textColor: Colors.blueGrey),
                _buildColorRow(Colors.grey, 'Stopped', textColor: Colors.white),
                _buildColorRow(Colors.red, 'Fault', textColor: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Helper that returns an Expanded widget wrapping a padded Container of a given color,
  /// with text that always fills/shrinks to fit that container.
  Widget _buildColorRow(Color background, String label,
      {required Color textColor}) {
    return Expanded(
      flex: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ConveyorConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor';
  @override
  String get category => 'Visualization';

  String? key;
  String? batchesKey;
  String? frequencyKey;
  String? tripKey;
  bool? simulateBatches;
  bool? bidirectional;
  bool? reverseDirection;
  bool? showFrequency;
  bool? showAuger;
  String? augerRpmKey;
  AugerOpenEnd? augerOpenEnd;

  @JsonKey(fromJson: _gatesFromJson, toJson: _gatesToJson)
  List<ChildGateEntry> gates;

  /// Bends along the belt; empty means a straight conveyor.
  List<ConveyorTurnEntry> turns;

  /// Belt thickness as a fraction of the box height (turned conveyors only).
  ///
  /// A bend needs a taller bounding box, which with the straight convention
  /// (belt thickness = box height) would force a fat belt. Defaults to 1.0.
  double? beltThickness;

  ConveyorConfig(
      {this.key,
      this.batchesKey,
      this.frequencyKey,
      this.tripKey,
      this.simulateBatches,
      this.bidirectional,
      this.reverseDirection,
      this.showFrequency,
      this.showAuger,
      this.augerRpmKey,
      this.augerOpenEnd,
      this.beltThickness,
      List<ChildGateEntry>? gates,
      List<ConveyorTurnEntry>? turns})
      : gates = gates != null ? List<ChildGateEntry>.of(gates) : [],
        turns = turns != null ? List<ConveyorTurnEntry>.of(turns) : [];

  static const previewStr = 'Conveyor Preview';

  ConveyorConfig.preview()
      : gates = [],
        turns = [],
        key = previewStr;

  @override
  Widget build(BuildContext context) => Conveyor(this);

  @override
  Widget configure(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: _ConveyorConfigContent(config: this),
      ),
    );
  }

  factory ConveyorConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ConveyorConfigToJson(this);
}

class _ConveyorConfigContent extends StatefulWidget {
  final ConveyorConfig config;
  const _ConveyorConfigContent({required this.config});

  @override
  State<_ConveyorConfigContent> createState() => _ConveyorConfigContentState();
}

class _ConveyorConfigContentState extends State<_ConveyorConfigContent> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyField(
          initialValue: widget.config.key,
          onChanged: (val) => setState(() => widget.config.key = val),
          label: 'Main key (optional)',
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.batchesKey,
          onChanged: (val) => setState(() => widget.config.batchesKey = val),
          label: 'Batches key',
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.frequencyKey,
          onChanged: (val) => setState(() => widget.config.frequencyKey = val),
          label: 'Frequency key',
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.tripKey,
          onChanged: (val) => setState(() => widget.config.tripKey = val),
          label: 'Trip key',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Simulate batches:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.simulateBatches ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.simulateBatches = val)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Bidirectional:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.bidirectional ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.bidirectional = val)),
          ],
        ),
        if (widget.config.bidirectional ?? false) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Reverse direction:'),
              const SizedBox(width: 8),
              Checkbox(
                  value: widget.config.reverseDirection ?? false,
                  onChanged: (val) =>
                      setState(() => widget.config.reverseDirection = val)),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Show frequency:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.showFrequency ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.showFrequency = val)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Auger conveyor:'),
            const SizedBox(width: 8),
            Checkbox(
                value: widget.config.showAuger ?? false,
                onChanged: (val) =>
                    setState(() => widget.config.showAuger = val)),
          ],
        ),
        if (widget.config.showAuger ?? false) ...[
          const SizedBox(height: 8),
          KeyField(
            initialValue: widget.config.augerRpmKey,
            onChanged: (val) => setState(() => widget.config.augerRpmKey = val),
            label: 'Output shaft RPM key',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Open end:'),
              const SizedBox(width: 8),
              DropdownButton<AugerOpenEnd?>(
                value: widget.config.augerOpenEnd,
                onChanged: (val) =>
                    setState(() => widget.config.augerOpenEnd = val),
                items: const [
                  DropdownMenuItem(
                      value: AugerOpenEnd.right, child: Text('Right')),
                  DropdownMenuItem(
                      value: AugerOpenEnd.left, child: Text('Left')),
                  DropdownMenuItem(value: null, child: Text('None')),
                ],
              ),
            ],
          ),
        ],
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
        const SizedBox(height: 16),
        const Divider(),
        Text('Gates', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              widget.config.gates
                  .add(ChildGateEntry(gate: ConveyorGateConfig()));
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Gate'),
        ),
        const SizedBox(height: 8),
        if (widget.config.gates.isEmpty)
          Text('No gates configured',
              style: Theme.of(context).textTheme.bodyMedium)
        else
          ...widget.config.gates.asMap().entries.map((mapEntry) {
            final entry = mapEntry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: variant name + edit/delete
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.gate.gateVariant.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Edit gate',
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Edit Gate'),
                              content: SizedBox(
                                width: 300,
                                child: entry.gate.configure(context),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Done'),
                                ),
                              ],
                            ),
                          ).then((_) => setState(() {})),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          tooltip: 'Remove gate',
                          onPressed: () => setState(() {
                            widget.config.gates.removeAt(
                              widget.config.gates.indexOf(entry),
                            );
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Side toggle: Top (left) / Bottom (right)
                    Text('Conveyor Side',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    SegmentedButton<GateSide>(
                      segments: const [
                        ButtonSegment(value: GateSide.left, label: Text('Top')),
                        ButtonSegment(
                            value: GateSide.right, label: Text('Bottom')),
                      ],
                      selected: {entry.side},
                      onSelectionChanged: (selection) {
                        setState(() => entry.side = selection.first);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Position slider
                    Text(
                      'Belt Position: ${(entry.position * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Slider(
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                      value: entry.position,
                      label: '${(entry.position * 100).round()}%',
                      onChanged: (v) => setState(() => entry.position = v),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
        const Divider(),
        Text('Turns', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              widget.config.turns.add(ConveyorTurnEntry());
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Turn'),
        ),
        const SizedBox(height: 8),
        if (widget.config.turns.isEmpty)
          Text('No turns configured — belt is straight',
              style: Theme.of(context).textTheme.bodyMedium)
        else ...[
          if (widget.config.showAuger ?? false)
            Text('Turns are ignored while "Auger conveyor" is enabled',
                style: Theme.of(context).textTheme.bodySmall),
          Text(
            'Belt thickness: '
            '${((widget.config.beltThickness ?? 1.0) * 100).round()}% of box height',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            min: 0.05,
            max: 1.0,
            divisions: 95,
            value: (widget.config.beltThickness ?? 1.0).clamp(0.05, 1.0),
            label: '${((widget.config.beltThickness ?? 1.0) * 100).round()}%',
            onChanged: (v) => setState(() => widget.config.beltThickness = v),
          ),
          ...widget.config.turns.asMap().entries.map((mapEntry) {
            final entry = mapEntry.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Turn ${mapEntry.key + 1}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          tooltip: 'Remove turn',
                          onPressed: () => setState(() {
                            widget.config.turns.remove(entry);
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Belt Position: ${(entry.position * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Slider(
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                      value: entry.position.clamp(0.0, 1.0),
                      label: '${(entry.position * 100).round()}%',
                      onChanged: (v) => setState(() => entry.position = v),
                    ),
                    Text(
                      'Angle: ${entry.angle.round()}° '
                      '(${entry.angle >= 0 ? 'down' : 'up'})',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Slider(
                      min: -180,
                      max: 180,
                      divisions: 72,
                      value: entry.angle.clamp(-180.0, 180.0),
                      label: '${entry.angle.round()}°',
                      onChanged: (v) => setState(() => entry.angle = v),
                    ),
                    Text(
                      'Radius: ${entry.radius.toStringAsFixed(1)} × belt width',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Slider(
                      min: 0.5,
                      max: 5.0,
                      divisions: 45,
                      value: entry.radius.clamp(0.5, 5.0),
                      label: entry.radius.toStringAsFixed(1),
                      onChanged: (v) => setState(() => entry.radius = v),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class Conveyor extends ConsumerStatefulWidget {
  final ConveyorConfig config;
  const Conveyor(this.config, {Key? key}) : super(key: key);

  @override
  ConsumerState<Conveyor> createState() => _ConveyorState();
}

class _ConveyorState extends ConsumerState<Conveyor>
    with TickerProviderStateMixin {
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 2,
      lineLength: 80,
      colors: true,
      printEmojis: false,
    ),
  );
  final Map<String, Batch> _batches = {};
  // periodic timer for batches
  Timer? _simulateBatchesTimer;

  // Auger animation — ValueNotifier repaints only the CustomPaint, no setState
  final ValueNotifier<double> _augerPhase = ValueNotifier(0.0);
  Timer? _augerAnimationTimer;
  double _augerRpm = 0.0;

  void _updateAugerAnimation(double rpm) {
    _augerRpm = rpm;
    if (rpm != 0 && _augerAnimationTimer == null) {
      _augerAnimationTimer =
          Timer.periodic(const Duration(milliseconds: 32), (_) {
        if (!mounted) {
          _augerAnimationTimer?.cancel();
          _augerAnimationTimer = null;
          return;
        }
        var phase = _augerPhase.value + _augerRpm / 60.0 * 2 * pi * 0.032;
        if (phase > 2 * pi) phase -= 2 * pi;
        if (phase < -2 * pi) phase += 2 * pi;
        _augerPhase.value = phase;
      });
    } else if (rpm == 0 && _augerAnimationTimer != null) {
      _augerAnimationTimer?.cancel();
      _augerAnimationTimer = null;
    }
  }

  @override
  void dispose() {
    // A docked pane outlives the route that opened it, so a page change must
    // not leave this conveyor's pane behind.
    closeSidePane(id: _paneId);
    _augerAnimationTimer?.cancel();
    _augerPhase.dispose();
    _simulateBatchesTimer?.cancel();
    super.dispose();
  }

  void _startSimulateBatchesTimer() {
    _simulateBatchesTimer ??=
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (_batches.isNotEmpty) {
        final batch = _batches.values.first;
        batch.start += 0.01;
        batch.end += 0.01;
        if (batch.start >= 1) {
          _batches.clear();
        }
      } else {
        // length 10 % of conveyor
        _batches['0'] = Batch(start: -0.1, end: 0, color: Colors.yellow);
      }
      if (mounted) {
        setState(() {});
      } else {
        _simulateBatchesTimer?.cancel();
      }
    });
  }

  void _stopSimulateBatchesTimer() {
    _simulateBatchesTimer?.cancel();
  }

  Color _getConveyorColor(
      {DynamicValue? driveValue,
      DynamicValue? frequencyValue,
      DynamicValue? tripValue}) {
    try {
      // Check trip condition first if trip key is provided
      if (tripValue != null) {
        try {
          final isTripped = tripValue.asBool;
          if (isTripped) {
            return Colors.red; // Trip condition overrides everything
          }
        } catch (_) {
          // If trip value can't be read as bool, continue with normal logic
        }
      }

      // If we have drive value, use the original logic
      if (driveValue != null) {
        final state = driveValue['p_stat_RunMode'].asInt;
        final fields = driveValue['p_stat_RunMode'].enumFields;
        final name = fields?[state]?.name;
        if (name == 'fault') {
          return Colors.red;
        } else if (name == 'stopped') {
          return Colors.grey;
        } else if (name == 'auto') {
          return Colors.green;
        } else if (name == 'manual') {
          return Colors.yellow;
        } else if (name == 'clean') {
          return Colors.blue;
        }
        return Colors.pink;
      }

      // If we only have frequency and trip, use frequency-based logic
      if (frequencyValue != null) {
        try {
          final frequency = frequencyValue.asDouble;
          if (frequency != 0) {
            return Colors.green; // Running
          } else {
            return Colors.grey; // Stopped
          }
        } catch (_) {
          return Colors.purple; // Error reading frequency
        }
      }

      return Colors.grey; // Default fallback
    } catch (_) {
      return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.key == ConveyorConfig.previewStr) {
      return _buildConveyorVisual(context, Colors.grey);
    }

    // The "Simulate batches" toggle is independent of any PLC stream — it
    // must drive the timer even when no keys are configured and even before
    // the first stream tick arrives. Evaluate it here, outside StreamBuilder.
    if (widget.config.simulateBatches ?? false) {
      _startSimulateBatchesTimer();
    } else {
      _stopSimulateBatchesTimer();
    }

    // Determine which streams to subscribe to
    final streams = <Stream<DynamicValue>>[];
    final streamLabels = <String>[];

    if (widget.config.key != null && widget.config.key!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.key!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('drive');
    }

    if (widget.config.batchesKey != null &&
        widget.config.batchesKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.batchesKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('batches');
    }

    if (widget.config.frequencyKey != null &&
        widget.config.frequencyKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.frequencyKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('frequency');
    }

    if (widget.config.tripKey != null && widget.config.tripKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.tripKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('trip');
    }

    if (widget.config.augerRpmKey != null &&
        widget.config.augerRpmKey!.isNotEmpty) {
      streams.add(ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.augerRpmKey!)
                .asStream()
                .switchMap((s) => s),
          ));
      streamLabels.add('augerRpm');
    }

    // If no streams are configured, show error state
    if (streams.isEmpty) {
      return _buildConveyorVisual(context, Colors.grey, true);
    }

    return StreamBuilder<Map<String, DynamicValue>>(
      stream: CombineLatestStream(
        streams,
        (List<DynamicValue> values) {
          final result = <String, DynamicValue>{};
          for (int i = 0; i < streamLabels.length; i++) {
            result[streamLabels[i]] = values[i];
          }
          return result;
        },
      ),
      builder: (context, snapshot) {
        if (widget.config.key == null || widget.config.key == '') {
          // print('no key');
        }
        if (snapshot.hasError) {
          _log.e(
            'Error fetching dynamic values, error: ${snapshot.error}',
          );
          return _buildConveyorVisual(context, Colors.grey, true);
        }
        if (!snapshot.hasData) {
          return _buildConveyorVisual(context, Colors.grey, true);
        }

        final dynValue = snapshot.data!;
        final color = _getConveyorColor(
          driveValue: dynValue['drive'],
          frequencyValue: dynValue['frequency'],
          tripValue: dynValue['trip'],
        );

        double? freq;
        // Try dedicated frequency key first
        if (dynValue['frequency'] != null) {
          try {
            freq = dynValue['frequency']!.asDouble;
          } catch (_) {}
        }
        // Fall back to p_stat_Frequency inside the main drive value
        if (freq == null && dynValue['drive'] != null) {
          try {
            freq = dynValue['drive']!['p_stat_Frequency'].asDouble;
          } catch (_) {}
        }

        // Update auger animation from RPM key, frequency, or default
        if (dynValue['augerRpm'] != null) {
          try {
            _updateAugerAnimation(dynValue['augerRpm']!.asDouble);
          } catch (_) {
            _updateAugerAnimation(0);
          }
        } else if (freq != null && freq != 0) {
          _updateAugerAnimation(freq);
        } else {
          _updateAugerAnimation(0);
        }

        // simulateBatches handled at top of build() — independent of streams.
        // When simulation is on, the periodic timer owns `_batches`. Skipping
        // _updateBatches here prevents an incoming snapshot (e.g. a configured
        // batchesKey emitting unoccupied slots) from clobbering the simulator
        // on every stream tick.
        if (!(widget.config.simulateBatches ?? false) &&
            dynValue['batches'] != null) {
          _updateBatches(dynValue['batches']!);
        }

        final hasMainKey =
            widget.config.key != null && widget.config.key!.isNotEmpty;
        if (hasMainKey) {
          return GestureDetector(
            onTap: () => _showDetailsPane(context),
            child: _buildConveyorVisual(context, color, null, freq),
          );
        }
        return _buildConveyorVisual(context, color, null, freq);
      },
    );
  }

  void _updateBatches(DynamicValue dynConveyor) {
    final conveyorLength = dynConveyor['p_stat_Length'].asDouble;
    const batchLength = 500; // todo variable mm
    var idx = 0;
    final batches = dynConveyor['p_stat_Batches'].asArray;
    for (final batchInfo in batches) {
      final occupied = batchInfo['xOccupied'].asBool;
      final backendOfBatch = batchInfo['position'].asDouble;
      final relativeStart = backendOfBatch / conveyorLength;
      final relativeEnd = (backendOfBatch + batchLength) / conveyorLength;
      if (occupied) {
        _batches[idx.toString()] =
            Batch(start: relativeStart, end: relativeEnd);
      } else {
        _batches.remove(idx.toString());
      }
      idx++;
    }
    if (mounted) {
      // setState(() {});
    }
  }

  Widget _buildConveyorVisual(
    BuildContext context,
    Color color, [
    bool? showExclamation,
    double? frequency,
  ]) {
    final paintSize = widget.config.size.toSize(MediaQuery.of(context).size);

    if (widget.config.showAuger ?? false) {
      return LayoutRotatedBox(
        angle: (widget.config.coordinates.angle ?? 0.0) * pi / 180,
        child: CustomPaint(
          size: paintSize,
          painter: AugerConveyorPainter(
            stateColor: color,
            phaseNotifier: _augerPhase,
            showAuger: !(showExclamation ?? false),
            openEnd: widget.config.augerOpenEnd,
          ),
        ),
      );
    }

    final geometry = ConveyorPathGeometry.build(
      widget.config.turns,
      paintSize,
      thicknessFactor: widget.config.beltThickness ?? 1.0,
    );

    final conveyorPaint = CustomPaint(
      size: paintSize,
      painter: ConveyorPainter(
        color: color,
        showExclamation: showExclamation ?? false,
        bidirectional: widget.config.bidirectional ?? false,
        reverseDirection: widget.config.reverseDirection ?? false,
        showFrequency: widget.config.showFrequency ?? false,
        frequency: frequency,
        batches: _batches,
        angle: widget.config.coordinates.angle ?? 0.0,
        geometry: geometry,
      ),
    );

    final gateEntries = widget.config.gates;

    final Widget content;
    if (gateEntries.isEmpty) {
      content = conveyorPaint;
    } else {
      content = SizedBox(
        width: paintSize.width,
        height: paintSize.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            conveyorPaint,
            for (final entry in gateEntries)
              _positionedChildGate(entry, paintSize, geometry),
          ],
        ),
      );
    }

    return LayoutRotatedBox(
      angle: (widget.config.coordinates.angle ?? 0.0) * pi / 180,
      child: content,
    );
  }

  Widget _positionedChildGate(
      ChildGateEntry entry, Size conveyorSize, ConveyorPathGeometry? geometry) {
    final beltHeight =
        geometry?.beltWidth ?? conveyorSize.height; // cross-belt dimension
    final gateSize = beltHeight; // square so flap spans belt width
    final xCenter = entry.position * conveyorSize.width;

    // Overhang: how far the gate extends outside the conveyor border.
    // Pusher uses pi/2 rotation so content spans full height — less overhang
    // keeps the actuator closer to the edge. Slider/pneumatic have centered
    // elements and need more overhang.
    final outsideOverhang = switch (entry.gate.gateVariant) {
      GateVariant.pusher => gateSize * 0.4,
      GateVariant.slider => gateSize * 0.57,
      GateVariant.pneumatic => gateSize * 0.6,
    };

    // Same rotation for both sides; bottom gates are mirrored, not rotated 180°.
    final rotation = switch (entry.gate.gateVariant) {
      GateVariant.slider => pi,
      GateVariant.pneumatic => entry.side == GateSide.left ? 0.0 : pi,
      GateVariant.pusher => pi / 2,
    };

    final isBottom = entry.side == GateSide.right;

    final child = SizedBox(
      width: gateSize,
      height: gateSize,
      child: Transform.flip(
        flipX: false,
        flipY: isBottom && entry.gate.gateVariant != GateVariant.pneumatic,
        child: Transform.rotate(
          angle: rotation,
          child: ConveyorGate(config: entry.gate),
        ),
      ),
    );

    if (geometry != null) {
      // Curved belt: place the gate along the centerline path, offset
      // perpendicular to the travel direction and rotated to follow it.
      final tangent = geometry.tangentAt(entry.position);
      final v = tangent.vector; // unit vector along travel, screen coords
      final leftNormal = Offset(v.dy, -v.dx); // "top" side of the belt
      final distFromCenter = beltHeight / 2 + outsideOverhang - gateSize / 2;
      final center = entry.side == GateSide.left
          ? tangent.position + leftNormal * distFromCenter
          : tangent.position - leftNormal * distFromCenter;
      return Positioned(
        left: center.dx - gateSize / 2,
        top: center.dy - gateSize / 2,
        width: gateSize,
        height: gateSize,
        child: Transform.rotate(
          angle: atan2(v.dy, v.dx),
          child: child,
        ),
      );
    }

    if (entry.side == GateSide.left) {
      return Positioned(
        left: xCenter - gateSize / 2,
        top: -outsideOverhang,
        width: gateSize,
        height: gateSize,
        child: child,
      );
    } else {
      return Positioned(
        left: xCenter - gateSize / 2,
        bottom: -outsideOverhang,
        width: gateSize,
        height: gateSize,
        child: child,
      );
    }
  }

  /// Identity of this conveyor's docked pane. Tapping the same conveyor
  /// twice toggles it; tapping another device replaces it.
  String get _paneId => 'conveyor:${identityHashCode(widget.config)}';

  /// Opens the operator pane for this conveyor.
  ///
  /// Since Plan 260811 this is a non-modal [SidePane] rather than an
  /// `AlertDialog`. It matters more here than anywhere else: jogging a belt
  /// is a hand-on-button, eyes-on-the-belt operation, and the old dialog put
  /// a barrier over the very mimic the operator was watching.
  ///
  /// The layout follows the house rule — headline numbers as tiles, commands
  /// pinned in the footer, and the stats trend behind a [PaneGraphTile] so
  /// the pane itself stays inside one screen. Tapping the trend opens it in a
  /// free-floating dialog the operator can drag onto the plant view.
  ///
  /// The subscription lives in a `StreamBuilder` inside the pane body, so it
  /// is released when the pane closes — same lifetime contract as the dialog
  /// it replaces.
  void _showDetailsPane(BuildContext context) {
    showSidePane(
      context: context,
      id: _paneId,
      builder: (paneContext) => Consumer(
        builder: (paneContext, ref, _) =>
            StreamBuilder<(StateMan, DynamicValue)>(
          stream: ref.watch(stateManProvider.future).asStream().switchMap(
                (stateMan) => stateMan
                    .subscribe(widget.config.key!)
                    .asStream()
                    .map(
                      (stream) => Rx.combineLatest2(
                        Stream.value(stateMan),
                        stream,
                        (stateMan, value) => (stateMan, value),
                      ),
                    )
                    .switchMap((stream) => stream),
              ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SidePane(
                title: widget.config.key!,
                subtitle: 'Conveyor',
                icon: Icons.conveyor_belt,
                status: const PaneStatus.unknown('Connecting'),
                child: const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (snapshot.hasError) {
              return SidePane(
                title: widget.config.key!,
                subtitle: 'Conveyor',
                icon: Icons.conveyor_belt,
                status: const PaneStatus.fault('Error'),
                child: PaneSection(
                  title: 'Subscription failed',
                  child: SelectableText(snapshot.error.toString()),
                ),
              );
            }

            final (stateMan, dynValue) = snapshot.data!;

            /// Copy-on-write helper — every command follows the same shape:
            /// clone the current value, set one field, write the whole thing
            /// back. Preserved verbatim from the dialog this replaced.
            void write(String field, Object? value) {
              final newValue = DynamicValue.from(dynValue);
              newValue[field] = value;
              stateMan.write(widget.config.key!, newValue);
            }

            final jogFwd = dynValue['p_stat_JogFwd'].asBool;
            final jogBwd = dynValue['p_stat_JogBwd'].asBool;
            final stopOnRelease = dynValue['p_stat_ManualStopOnRelease'].asBool;
            final frequency = dynValue['p_stat_Frequency'].asDouble;
            final runMinutes = dynValue['p_stat_RunMinutes'].asInt;

            return SidePane(
              title: widget.config.key!,
              subtitle: 'Conveyor',
              icon: Icons.conveyor_belt,
              status: (jogFwd || jogBwd)
                  ? const PaneStatus.running('Jogging')
                  : frequency.abs() > 0.01
                      ? const PaneStatus.running()
                      : const PaneStatus.stopped(),
              // One command in the footer: three buttons wrap onto two rows
              // in a 380px pane and the pinned bar stops reading as a bar.
              // 'Reset run hours' sits on the Status section instead, next to
              // the number it resets.
              actions: [
                PaneAction.destructive(
                  label: 'Fault reset',
                  icon: Icons.restart_alt,
                  onPressed: () => write('p_cmd_FaultReset', true),
                ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- Jog -------------------------------------------------
                  //
                  // `p_stat_ManualStopOnRelease` decides the gesture: when
                  // set, the belt runs only while the button is held (the
                  // press/release callbacks write true/false); when clear, a
                  // tap latches it. Both paths are unchanged from the dialog.
                  PaneSection(
                    title: 'Jog',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _JogButton(
                              icon: Icons.arrow_back,
                              label: 'Reverse',
                              active: jogBwd,
                              stopOnRelease: stopOnRelease,
                              onCommand: (v) => write('p_cmd_JogBwd', v),
                            ),
                            _JogButton(
                              icon: Icons.arrow_forward,
                              label: 'Forward',
                              active: jogFwd,
                              stopOnRelease: stopOnRelease,
                              onCommand: (v) => write('p_cmd_JogFwd', v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Compact row rather than a SwitchListTile: the pane
                        // has one screen of height and this is a mode flag,
                        // not a headline.
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                stopOnRelease
                                    ? 'Runs only while held'
                                    : 'Tap latches the belt on',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Switch(
                              value: stopOnRelease,
                              onChanged: (_) =>
                                  write('p_cmd_ManualStopOnRelease', true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // --- Live numbers ----------------------------------------
                  PaneSection(
                    title: 'Status',
                    trailing: TextButton(
                      onPressed: () => write('p_cmd_ResetRunHours', true),
                      child: const Text('Reset hours'),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PaneTileRow(
                          children: [
                            PaneMetricTile(
                              label: 'Frequency',
                              value: frequency.toStringAsFixed(2),
                              unit: 'Hz',
                              icon: Icons.speed,
                            ),
                            PaneMetricTile(
                              label: 'Current',
                              value: dynValue['p_stat_Current']
                                  .asDouble
                                  .toStringAsFixed(2),
                              unit: 'A',
                              icon: Icons.bolt,
                            ),
                            PaneMetricTile(
                              label: 'Run hours',
                              value:
                                  '${runMinutes ~/ 60}:${(runMinutes % 60).toString().padLeft(2, '0')}',
                              unit: 'h:m',
                              icon: Icons.schedule,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        PaneDetailRow(
                          label: 'HMIS',
                          value: dynValue['p_stat_State'].toString(),
                        ),
                        PaneDetailRow(
                          label: 'Last fault',
                          value: dynValue['p_stat_LastFault'].toString(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // --- Trend ------------------------------------------------
                  //
                  // A preview in the pane, the real chart in a floating
                  // dialog the operator can park next to the mimic.
                  PaneSection(
                    title: 'Trend',
                    child: PaneGraphTile(
                      label: 'Frequency (Hz) · Current (A)',
                      // Tall enough for a line chart with two axes to be
                      // readable rather than decorative.
                      height: 130,
                      preview: _ConveyorStatsGraphLoader(
                        keyName: widget.config.key!,
                        showButtons: false,
                        compact: true,
                        xSpan: const Duration(minutes: 5),
                      ),
                      expandedTitle: '${widget.config.key!} — trend',
                      expandedSize: const Size(820, 520),
                      expandedBuilder: (context) => _ConveyorStatsGraphLoader(
                        keyName: widget.config.key!,
                        xSpan: const Duration(minutes: 30),
                      ),
                    ),
                  ),
                  const Divider(height: 1),

                  // --- Setpoints --------------------------------------------
                  //
                  // Three frequency fields are a form, not a glance, so they
                  // live in a floating dialog the operator can park anywhere.
                  // Committed on submit (Enter / focus-out), never per
                  // keystroke — a half-typed frequency must not reach the
                  // drive. Keys embed the current value so a field resets when
                  // the PLC reports a different one.
                  PaneSection(
                    title: 'Setpoints',
                    child: PaneExpandTile(
                      label: 'Frequencies',
                      summary:
                          'Auto ${dynValue['p_cfg_AutoFreq'].asDouble.toStringAsFixed(2)} Hz · '
                          'Cleaning ${dynValue['p_cfg_CleaningFreq'].asDouble.toStringAsFixed(2)} Hz · '
                          'Manual ${dynValue['p_cfg_ManualFreq'].asDouble.toStringAsFixed(2)} Hz',
                      icon: Icons.tune,
                      expandedTitle: '${widget.config.key!} — setpoints',
                      expandedSize: const Size(420, 380),
                      expandedBuilder: (context) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FrequencyField(
                            fieldKey: 'auto_freq_field',
                            label: 'Auto frequency',
                            value: dynValue['p_cfg_AutoFreq'],
                            onSubmitted: (v) => write('p_cfg_AutoFreq', v),
                          ),
                          const SizedBox(height: 12),
                          _FrequencyField(
                            fieldKey: 'cleaning_freq_field',
                            label: 'Cleaning frequency',
                            value: dynValue['p_cfg_CleaningFreq'],
                            onSubmitted: (v) => write('p_cfg_CleaningFreq', v),
                          ),
                          const SizedBox(height: 12),
                          _FrequencyField(
                            fieldKey: 'manual_freq_field',
                            label: 'Manual frequency',
                            value: dynValue['p_cfg_ManualFreq'],
                            onSubmitted: (v) => write('p_cfg_ManualFreq', v),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One jog button — a large touch target with a label underneath.
///
/// [stopOnRelease] mirrors `p_stat_ManualStopOnRelease`: when true the
/// command follows the press state (true on press, false on release); when
/// false a tap writes a single latching `true`.
class _JogButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool stopOnRelease;
  final void Function(bool value) onCommand;

  const _JogButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.stopOnRelease,
    required this.onCommand,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.green : Theme.of(context).disabledColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RawMaterialButton(
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          onHighlightChanged: (isPressed) {
            if (stopOnRelease) onCommand(isPressed);
          },
          onPressed: () {
            if (!stopOnRelease) onCommand(true);
          },
          child: Icon(icon, color: color, size: 36),
        ),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// A frequency setpoint field. Submits on Enter/focus-out only.
class _FrequencyField extends StatelessWidget {
  final String fieldKey;
  final String label;
  final DynamicValue value;
  final void Function(double value) onSubmitted;

  const _FrequencyField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: Key('$fieldKey-${value.asString}'),
      initialValue: value.asDouble.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'Hz',
        isDense: true,
      ),
      onFieldSubmitted: (text) {
        if (text.isEmpty) return;
        final parsed = double.tryParse(text);
        if (parsed == null) return;
        onSubmitted(parsed);
      },
    );
  }
}

/// Resolves the [Collector] and hands it to [ConveyorStatsGraph].
///
/// Used for both the pane preview and the expanded floating chart, so the
/// two can never drift apart.
class _ConveyorStatsGraphLoader extends ConsumerWidget {
  final String keyName;
  final bool showButtons;
  final Duration xSpan;
  final bool compact;

  const _ConveyorStatsGraphLoader({
    required this.keyName,
    this.showButtons = true,
    this.xSpan = const Duration(minutes: 5),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Collector?>(
      future: ref.watch(collectorProvider.future),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ConveyorStatsGraph(
          collector: snapshot.data,
          keyName: keyName,
          showButtons: showButtons,
          xSpan: xSpan,
          compact: compact,
        );
      },
    );
  }
}

class Batch {
  double start; // 0…1 (can be <0 while entering)
  double end; // 0…1 (can be >1 while exiting)
  Color color;

  Batch({required this.start, required this.end, this.color = Colors.white});
}

class ConveyorPainter extends CustomPainter {
  final Map<String, Batch> batches;
  final Color color;
  final bool showExclamation;
  final bool bidirectional;
  final bool reverseDirection;
  final bool showFrequency;
  final double? frequency;
  final double angle;
  final ConveyorPathGeometry? geometry;

  ConveyorPainter(
      {required this.color,
      this.showExclamation = false,
      this.bidirectional = false,
      this.reverseDirection = false,
      this.showFrequency = false,
      this.frequency,
      required this.batches,
      required this.angle,
      this.geometry});

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry != null) {
      _paintTurnedBelt(canvas, size);
      return;
    }
    final rect = Offset.zero & size;
    final borderRadius = Radius.circular(
      size.shortestSide * 0.2,
    ); // 20% of the shortest side
    final rrect = RRect.fromRectAndRadius(rect, borderRadius);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, paint);

    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, border);

    // Draw exclamation mark if needed
    if (showExclamation) {
      _drawExclamation(canvas, size);
      return;
    }
    // 2) draw each batch segment as a plain box
    final paintBorder = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final batchHeight = size.height * 0.8;
    final batchRadius =
        Radius.circular(batchHeight * 0.2); // 20% of batch height

    for (final batch in batches.values) {
      final paintBatch = Paint()..color = batch.color;
      // clamp into [0..1] then to pixels
      final x0 = (batch.start.clamp(0.0, 1.0)) * size.width;
      final x1 = (batch.end.clamp(0.0, 1.0)) * size.width;
      final w = x1 - x0;
      if (w <= 0) continue; // not yet visible / already off

      final rect = Rect.fromLTWH(
        x0,
        (size.height - batchHeight) / 2,
        w,
        batchHeight,
      );
      final rrect = RRect.fromRectAndRadius(rect, batchRadius);

      // fill
      canvas.drawRRect(rrect, paintBatch);
      // border (optional)
      canvas.drawRRect(rrect, paintBorder);
    }

    _drawDirectionArrow(canvas, size);
    _drawFrequency(canvas, size);
  }

  /// Path-based rendering used when the conveyor has turns configured.
  ///
  /// The belt is the centerline stroked at full belt width (rounded caps give
  /// the rounded ends), batches are sub-paths of the same centerline stroked
  /// slightly narrower, so both follow the bends.
  void _paintTurnedBelt(Canvas canvas, Size size) {
    final g = geometry!;

    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.beltWidth + 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(g.path, borderPaint);

    final beltPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.beltWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(g.path, beltPaint);

    if (showExclamation) {
      _drawExclamation(canvas, size);
      return;
    }

    final batchWidth = g.beltWidth * 0.8;
    final batchBorderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = batchWidth + 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Round stroke caps extend half the stroke width past each end of the
    // extracted segment, so shrink the segment by the cap radius to keep the
    // painted batch at its true length.
    final capInset = batchWidth / 2 / g.length;

    for (final batch in batches.values) {
      var start = batch.start.clamp(0.0, 1.0);
      var end = batch.end.clamp(0.0, 1.0);
      if (end <= start) continue; // not yet visible / already off
      final mid = (start + end) / 2;
      // Keep a sliver of length so short batches render as a round dot
      // instead of disappearing.
      start = min(start + capInset, mid - 1e-4);
      end = max(end - capInset, mid + 1e-4);
      final segment = g.extractFraction(start, end);
      canvas.drawPath(segment, batchBorderPaint);
      canvas.drawPath(
        segment,
        Paint()
          ..color = batch.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = batchWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    _drawDirectionArrow(canvas, size);
    _drawFrequency(canvas, size);
  }

  /// Reference dimension for centered text: the belt width. For straight
  /// conveyors that is the box's short side; for turned conveyors the box is
  /// taller than the belt, so use the fitted belt width instead.
  double _textBasis(Size size) => geometry?.beltWidth ?? size.shortestSide;

  /// Anchor for centered overlays: box center for straight belts, the
  /// centerline midpoint for turned belts (the box center can be off-belt).
  Offset _overlayCenter(Size size) =>
      geometry?.tangentAt(0.5).position ??
      Offset(size.width / 2, size.height / 2);

  void _drawExclamation(Canvas canvas, Size size) {
    canvas.save();
    // Move origin to center of conveyor
    final center = _overlayCenter(size);
    canvas.translate(center.dx, center.dy);
    // Counter-rotate
    canvas.rotate(-angle * pi / 180);
    // Draw exclamation mark centered at (0,0)
    final textPainter = TextPainter(
      text: TextSpan(
        text: '!',
        style: TextStyle(
          color: Colors.white,
          fontSize: _textBasis(size) * 0.7,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final offset = Offset(
      -textPainter.width / 2,
      -textPainter.height / 2,
    );
    textPainter.paint(canvas, offset);
    canvas.restore();
  }

  void _drawDirectionArrow(Canvas canvas, Size size) {
    // Draw direction arrow for bidirectional conveyors
    if (!bidirectional || frequency == null || frequency == 0) return;
    canvas.save();
    final center = _overlayCenter(size);
    canvas.translate(center.dx, center.dy);

    final arrowLength = size.width * 0.4;
    final arrowSize = _textBasis(size) * 0.25;
    final arrowPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Determine direction: positive frequency = right, unless reversed
    final pointsRight = (frequency! > 0) ^ reverseDirection;

    // Shaft
    canvas.drawLine(
      Offset(-arrowLength / 2, 0),
      Offset(arrowLength / 2, 0),
      arrowPaint,
    );

    // Single arrowhead in the running direction
    if (pointsRight) {
      final head = Path()
        ..moveTo(arrowLength / 2 - arrowSize, -arrowSize * 0.5)
        ..lineTo(arrowLength / 2, 0)
        ..lineTo(arrowLength / 2 - arrowSize, arrowSize * 0.5);
      canvas.drawPath(head, arrowPaint);
    } else {
      final head = Path()
        ..moveTo(-arrowLength / 2 + arrowSize, -arrowSize * 0.5)
        ..lineTo(-arrowLength / 2, 0)
        ..lineTo(-arrowLength / 2 + arrowSize, arrowSize * 0.5);
      canvas.drawPath(head, arrowPaint);
    }

    canvas.restore();
  }

  void _drawFrequency(Canvas canvas, Size size) {
    // Draw frequency number in center
    if (!showFrequency || frequency == null) return;
    canvas.save();
    final center = _overlayCenter(size);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-angle * pi / 180);
    final textPainter = TextPainter(
      text: TextSpan(
        text: frequency!.toStringAsFixed(1),
        style: TextStyle(
          color: Colors.white,
          fontSize: _textBasis(size) * 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ConveyorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.showExclamation != showExclamation ||
      oldDelegate.bidirectional != bidirectional ||
      oldDelegate.showFrequency != showFrequency ||
      oldDelegate.frequency != frequency ||
      // Geometry is rebuilt each frame when turns are configured, so curved
      // conveyors repaint on every rebuild (needed for batch animation).
      !identical(oldDelegate.geometry, geometry);
}

/// Series colours for the conveyor trend, fixed so the small preview in the
/// pane and the full chart in the floating dialog read as the same chart.
const Map<String, Color> conveyorTrendColors = {
  'Frequency': Colors.blue,
  'Current': Colors.orange,
};

class ConveyorStatsGraph extends ConsumerStatefulWidget {
  final Collector? collector;
  final String keyName;

  /// Pan/zoom/now buttons. Off in the pane preview, on in the floating chart.
  final bool showButtons;

  /// Visible window. The preview shows a short span so the line has shape;
  /// the expanded chart shows more history.
  final Duration xSpan;

  /// Drops the units from the tick labels. In the pane preview there is only
  /// ~20px of gutter, so "48.20 Hz" wraps to four lines and eats the plot —
  /// the tile caption names the units instead.
  final bool compact;

  const ConveyorStatsGraph({
    required this.collector,
    required this.keyName,
    this.showButtons = true,
    this.xSpan = const Duration(minutes: 5),
    this.compact = false,
    super.key,
  });

  @override
  ConsumerState<ConveyorStatsGraph> createState() => _ConveyorStatsGraphState();
}

class _ConveyorStatsGraphState extends ConsumerState<ConveyorStatsGraph> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TimeseriesData<dynamic>>>(
      stream: widget.collector
          ?.collectStream(widget.keyName, since: const Duration(hours: 2)),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No data'));
        }

        final samples = snapshot.data!;
        final currentData = <List<double>>[];
        final freqData = <List<double>>[];

        double minFreq = 1000;
        double maxFreq = 0;
        double minCurrent = 1000;
        double maxCurrent = 0;

        for (final sample in samples) {
          final v = sample.value;
          final current = v['p_stat_Current'] ?? 0.0;
          final freq = v['p_stat_Frequency'] ?? 0.0;
          final time = sample.time.millisecondsSinceEpoch.toDouble();

          currentData.add([time, current]);
          freqData.add([time, freq]);

          if (freq < minFreq) minFreq = freq;
          if (freq > maxFreq) maxFreq = freq;
          if (current < minCurrent) minCurrent = current;
          if (current > maxCurrent) maxCurrent = current;
        }
        if (minCurrent == maxCurrent) {
          maxCurrent++;
        }
        if (minFreq == maxFreq) {
          maxFreq++;
        }

        // Time along the bottom, frequency on the LEFT axis and current on
        // the RIGHT — frequency is what an operator reads first, so it gets
        // the axis the eye lands on.
        final graphConfig = GraphConfig(
          type: GraphType.timeseries,
          xAxis: GraphAxisConfig(unit: widget.compact ? '' : 'Time'),
          yAxis: GraphAxisConfig(
            unit: widget.compact ? '' : 'Hz',
            min: minFreq,
            max: maxFreq,
          ),
          yAxis2: GraphAxisConfig(
            unit: widget.compact ? '' : 'A',
            min: minCurrent,
            max: maxCurrent,
          ),
          xSpan: widget.xSpan,
        );

        final List<Map<String, dynamic>> data = [];
        data.addAll(
            freqData.map((e) => {'x': e[0], 'y': e[1], 's': 'Frequency'}));
        data.addAll(
            currentData.map((e) => {'x': e[0], 'y2': e[1], 's': 'Current'}));

        return Graph(
          config: graphConfig,
          data: data,
          showButtons: widget.showButtons,
          categoryColors: conveyorTrendColors,
          chartTheme: ref.watch(chartThemeNotifierProvider),
          redraw: () {},
        ).build(context);
      },
    );
  }
}
