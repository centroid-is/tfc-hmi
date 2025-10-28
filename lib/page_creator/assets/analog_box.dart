import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import 'common.dart';
import '../../providers/state_man.dart';
import '../../core/state_man.dart';
import '../../converter/color_converter.dart';
import 'graph.dart';

part 'analog_box.g.dart';

/// CONFIG

@JsonSerializable(explicitToJson: true)
class AnalogBoxConfig extends BaseAsset {
  /// Live analog value source
  @JsonKey(name: 'analog_key')
  String analogKey;

  @JsonKey(name: 'analog_sensor_range_min_key')
  String? analogSensorRangeMinKey;
  @JsonKey(name: 'analog_sensor_range_max_key')
  String? analogSensorRangeMaxKey;

  /// Optional keys for setpoints / hysteresis (writeable)
  @JsonKey(name: 'setpoint1_key')
  String? setpoint1Key;
  @JsonKey(name: 'setpoint1_hysteresis_key')
  String? setpoint1HysteresisKey; // +/- around setpoint1
  @JsonKey(name: 'setpoint2_key')
  String? setpoint2Key;

  /// Min/max scaling
  @JsonKey(name: 'min_value')
  double minValue;
  @JsonKey(name: 'max_value')
  double maxValue;

  /// Visual / UX
  String? units;
  @JsonKey(name: 'range_units')
  String? rangeUnits; // Units for range min/max, falls back to units
  @JsonKey(name: 'border_radius_pct')
  double borderRadiusPct; // relative to shortest side (0..0.5)
  bool vertical; // vertical tank-style; if false, horizontal bar
  @JsonKey(name: 'reverse_fill')
  bool
      reverseFill; // low at bottom vs top (for vertical), left vs right (horizontal)

  /// Colors
  @JsonKey(name: 'bg_color')
  @ColorConverter()
  Color bgColor;
  @JsonKey(name: 'fill_color')
  @ColorConverter()
  Color fillColor;
  @JsonKey(name: 'sp1_color')
  @ColorConverter()
  Color setpoint1Color;
  @JsonKey(name: 'sp2_color')
  @ColorConverter()
  Color setpoint2Color;
  @JsonKey(name: 'hyst_color')
  @ColorConverter()
  Color hysteresisColor;

  /// Dialog: include mini-graph
  @JsonKey(name: 'graph_config')
  GraphAssetConfig? graphConfig;

  AnalogBoxConfig({
    required this.analogKey,
    this.analogSensorRangeMinKey,
    this.analogSensorRangeMaxKey,
    this.setpoint1Key,
    this.setpoint1HysteresisKey,
    this.setpoint2Key,
    this.minValue = 0,
    this.maxValue = 100,
    this.units,
    this.rangeUnits,
    this.borderRadiusPct = .15,
    this.vertical = true,
    this.reverseFill = false,
    this.bgColor = const Color(0xFFEFEFEF),
    this.fillColor = const Color(0xFF6EC1E4),
    this.setpoint1Color = Colors.red,
    this.setpoint2Color = Colors.orange,
    this.hysteresisColor = const Color(0x44FF0000),
    this.graphConfig,
  });

  AnalogBoxConfig.preview()
      : analogKey = 'AnalogBox preview',
        minValue = 0,
        maxValue = 100,
        units = 'bar',
        rangeUnits = null,
        borderRadiusPct = .18,
        vertical = true,
        reverseFill = false,
        bgColor = const Color(0xFFEFEFEF),
        fillColor = const Color(0xFF6EC1E4),
        setpoint1Color = Colors.red,
        setpoint2Color = Colors.orange,
        hysteresisColor = const Color(0x44FF0000),
        graphConfig = GraphAssetConfig.preview();

  factory AnalogBoxConfig.fromJson(Map<String, dynamic> json) =>
      _$AnalogBoxConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AnalogBoxConfigToJson(this);

  @override
  Widget build(BuildContext context) => AnalogBox(config: this);

  @override
  Widget configure(BuildContext context) =>
      _AnalogBoxConfigEditor(config: this);
}

/// CONFIG UI

class _AnalogBoxConfigEditor extends StatefulWidget {
  final AnalogBoxConfig config;
  const _AnalogBoxConfigEditor({required this.config});

  @override
  State<_AnalogBoxConfigEditor> createState() => _AnalogBoxConfigEditorState();
}

class _AnalogBoxConfigEditorState extends State<_AnalogBoxConfigEditor> {
  bool showGraph = false;

  @override
  void initState() {
    super.initState();
    showGraph = widget.config.graphConfig != null;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT: core config
          Expanded(
            flex: 2,
            child: Column(
              children: [
                KeyField(
                  initialValue: widget.config.analogKey,
                  onChanged: (v) => setState(() => widget.config.analogKey = v),
                  label: 'Analog value key',
                ),
                const SizedBox(height: 12),
                KeyField(
                  initialValue: widget.config.analogSensorRangeMinKey,
                  onChanged: (v) =>
                      setState(() => widget.config.analogSensorRangeMinKey = v),
                  label: 'Analog sensor range min key (optional)',
                ),
                const SizedBox(height: 8),
                KeyField(
                  initialValue: widget.config.analogSensorRangeMaxKey,
                  onChanged: (v) =>
                      setState(() => widget.config.analogSensorRangeMaxKey = v),
                  label: 'Analog sensor range max key (optional)',
                ),
                const SizedBox(height: 8),
                KeyField(
                  initialValue: widget.config.setpoint1Key,
                  onChanged: (v) =>
                      setState(() => widget.config.setpoint1Key = v),
                  label: 'Setpoint 1 key (optional)',
                ),
                const SizedBox(height: 8),
                KeyField(
                  initialValue: widget.config.setpoint1HysteresisKey,
                  onChanged: (v) =>
                      setState(() => widget.config.setpoint1HysteresisKey = v),
                  label: 'Setpoint 1 hysteresis key (optional, ±)',
                ),
                const SizedBox(height: 8),
                KeyField(
                  initialValue: widget.config.setpoint2Key,
                  onChanged: (v) =>
                      setState(() => widget.config.setpoint2Key = v),
                  label: 'Setpoint 2 key (optional)',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: widget.config.minValue.toString(),
                        decoration: InputDecoration(
                          labelText: 'Min value',
                          helperText: widget.config.analogSensorRangeMinKey
                                      ?.isNotEmpty ==
                                  true
                              ? 'Using dynamic value from ${widget.config.analogSensorRangeMinKey}'
                              : null,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) {
                          final d = double.tryParse(v);
                          if (d != null) {
                            setState(() => widget.config.minValue = d);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: widget.config.maxValue.toString(),
                        decoration: InputDecoration(
                          labelText: 'Max value',
                          helperText: widget.config.analogSensorRangeMaxKey
                                      ?.isNotEmpty ==
                                  true
                              ? 'Using dynamic value from ${widget.config.analogSensorRangeMaxKey}'
                              : null,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) {
                          final d = double.tryParse(v);
                          if (d != null) {
                            setState(() => widget.config.maxValue = d);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: widget.config.units,
                  decoration: const InputDecoration(labelText: 'Units'),
                  onChanged: (v) => setState(() => widget.config.units = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: widget.config.rangeUnits,
                  decoration: InputDecoration(
                    labelText: 'Range units',
                    helperText:
                        'Optional: units for range min/max values (falls back to main units)',
                  ),
                  onChanged: (v) =>
                      setState(() => widget.config.rangeUnits = v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: .5,
                        divisions: 50,
                        label:
                            'Radius ${(widget.config.borderRadiusPct * 100).toStringAsFixed(0)}%',
                        value: widget.config.borderRadiusPct,
                        onChanged: (v) =>
                            setState(() => widget.config.borderRadiusPct = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Vertical'),
                  value: widget.config.vertical,
                  onChanged: (b) => setState(() => widget.config.vertical = b),
                ),
                SwitchListTile(
                  title: const Text('Reverse fill direction'),
                  subtitle: const Text(
                      'Top→bottom (vertical) / Right→left (horizontal)'),
                  value: widget.config.reverseFill,
                  onChanged: (b) =>
                      setState(() => widget.config.reverseFill = b),
                ),
                const SizedBox(height: 12),
                CoordinatesField(
                  initialValue: widget.config.coordinates,
                  onChanged: (c) =>
                      setState(() => widget.config.coordinates = c),
                  enableAngle: true,
                ),
                const SizedBox(height: 12),
                SizeField(
                  initialValue: widget.config.size,
                  onChanged: (s) => setState(() => widget.config.size = s),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Include Graph in dialog'),
                  value: showGraph,
                  onChanged: (v) => setState(() {
                    showGraph = v;
                    if (v && widget.config.graphConfig == null) {
                      widget.config.graphConfig = GraphAssetConfig.preview();
                    }
                    if (!v) widget.config.graphConfig = null;
                  }),
                ),
              ],
            ),
          ),

          // RIGHT: graph config (optional)
          if (showGraph && widget.config.graphConfig != null) ...[
            const SizedBox(width: 24),
            Expanded(
              flex: 3,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: GraphContentConfig(config: widget.config.graphConfig!),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// WIDGET

class AnalogBox extends ConsumerWidget {
  final AnalogBoxConfig config;
  const AnalogBox({required this.config, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = config.size.toSize(MediaQuery.of(context).size);

    // Preview
    if (config.analogKey == 'AnalogBox preview') {
      return SizedBox(
        width: size.width,
        height: size.height,
        child: GestureDetector(
          onTap: () => _showConfigDialog(context, ref),
          child: CustomPaint(
            painter: _AnalogBoxPainter(
              percent: .62,
              min: config.minValue,
              max: config.maxValue,
              bgColor: config.bgColor,
              fillColor: config.fillColor,
              setpoint1: 60,
              setpoint1Hyst: 4,
              setpoint2: 80,
              setpoint1Color: config.setpoint1Color,
              setpoint2Color: config.setpoint2Color,
              hysteresisColor: config.hysteresisColor,
              vertical: config.vertical,
              reverseFill: config.reverseFill,
              borderRadiusPct: config.borderRadiusPct,
              labelAngleDeg: config.coordinates.angle ?? 0,
            ),
          ),
        ),
      );
    }

    // Live streams
    final streams = <Stream<(String, DynamicValue)>>[];

    void addKey(String? key, String tag) {
      if (key == null || key.isEmpty) return;
      final s = ref
          .watch(stateManProvider.future)
          .asStream()
          .switchMap((sm) => sm.subscribe(key).asStream().switchMap((s) => s))
          .map((dv) => (tag, dv));
      streams.add(s);
    }

    addKey(config.analogKey, 'analog');
    addKey(config.analogSensorRangeMinKey, 'min');
    addKey(config.analogSensorRangeMaxKey, 'max');
    addKey(config.setpoint1Key, 'sp1');
    addKey(config.setpoint1HysteresisKey, 'hyst');
    addKey(config.setpoint2Key, 'sp2');

    if (streams.isEmpty) {
      // nothing configured
      return SizedBox(
        width: size.width,
        height: size.height,
        child: CustomPaint(
          painter: _AnalogBoxPainter(
            percent: 0,
            min: config.minValue,
            max: config.maxValue,
            bgColor: config.bgColor,
            fillColor: config.fillColor,
            setpoint1: null,
            setpoint1Hyst: null,
            setpoint2: null,
            setpoint1Color: config.setpoint1Color,
            setpoint2Color: config.setpoint2Color,
            hysteresisColor: config.hysteresisColor,
            vertical: config.vertical,
            reverseFill: config.reverseFill,
            borderRadiusPct: config.borderRadiusPct,
            labelAngleDeg: config.coordinates.angle ?? 0,
          ),
        ),
      );
    }

    final combined = CombineLatestStream.list(streams).map((list) {
      final map = <String, DynamicValue>{};
      for (final e in list) {
        map[e.$1] = e.$2;
      }
      return map;
    }).distinct((prev, curr) {
      // Only consider the analog value for change detection
      final prevAnalog = prev['analog'];
      final currAnalog = curr['analog'];

      if (prevAnalog == null || currAnalog == null) {
        return prevAnalog == currAnalog; // Both null or both not null
      }

      if (!prevAnalog.isDouble && !prevAnalog.isInteger) {
        return !currAnalog.isDouble && !currAnalog.isInteger;
      }

      if (!currAnalog.isDouble && !currAnalog.isInteger) {
        return false; // Different types
      }

      final prevValue = prevAnalog.asDouble;
      final currValue = currAnalog.asDouble;
      final prevPercent =
          _toPercent(prevValue, config.minValue, config.maxValue);
      final currPercent =
          _toPercent(currValue, config.minValue, config.maxValue);

      // Return true if values are "the same" (change < 1%)
      final change = (currPercent - prevPercent).abs();
      return change < 0.01; // 1% threshold
    });

    return StreamBuilder<Map<String, DynamicValue>>(
      stream: combined,
      builder: (context, snapshot) {
        double? analog;
        double? sp1;
        double? hyst;
        double? sp2;
        // double? dynamicMin;
        // double? dynamicMax;

        if (snapshot.hasData) {
          final m = snapshot.data!;
          if (m['analog'] case final v?) {
            if (v.isDouble || v.isInteger) analog = v.asDouble;
          }
          if (m['sp1'] case final v?) {
            if (v.isDouble || v.isInteger) sp1 = v.asDouble;
          }
          if (m['hyst'] case final v?) {
            if (v.isDouble || v.isInteger) hyst = v.asDouble;
          }
          if (m['sp2'] case final v?) {
            if (v.isDouble || v.isInteger) sp2 = v.asDouble;
          }
          // if (m['min'] case final v?) {
          //   if (v.isDouble || v.isInteger) dynamicMin = v.asDouble;
          // }
          // if (m['max'] case final v?) {
          //   if (v.isDouble || v.isInteger) dynamicMax = v.asDouble;
          // }
        }

        // Use dynamic min/max if available, otherwise fall back to config values
        final effectiveMin = config.minValue;
        final effectiveMax = config.maxValue;

        final pct = _toPercent(
          analog,
          effectiveMin,
          effectiveMax,
        );

        return GestureDetector(
          onTap: () => _showConfigDialog(context, ref),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: CustomPaint(
              painter: _AnalogBoxPainter(
                percent: pct,
                min: effectiveMin,
                max: effectiveMax,
                bgColor: config.bgColor,
                fillColor: config.fillColor,
                setpoint1: sp1,
                setpoint1Hyst: hyst,
                setpoint2: sp2,
                setpoint1Color: config.setpoint1Color,
                setpoint2Color: config.setpoint2Color,
                hysteresisColor: config.hysteresisColor,
                vertical: config.vertical,
                reverseFill: config.reverseFill,
                borderRadiusPct: config.borderRadiusPct,
                labelAngleDeg: config.coordinates.angle ?? 0,
              ),
            ),
          ),
        );
      },
    );
  }

  static double _toPercent(double? value, double min, double max) {
    if (value == null || max <= min) return 0;
    final p = (value - min) / (max - min);
    return p.clamp(0, 1);
  }

  void _showConfigDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _AnalogBoxDialog(config: config),
    );
  }
}

/// DIALOG (user config + graph)

class _AnalogBoxDialog extends ConsumerStatefulWidget {
  final AnalogBoxConfig config;
  const _AnalogBoxDialog({required this.config});

  @override
  ConsumerState<_AnalogBoxDialog> createState() => _AnalogBoxDialogState();
}

class _AnalogBoxDialogState extends ConsumerState<_AnalogBoxDialog> {
  bool showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    // Build separate streams for values we want to show/edit
    Stream<DynamicValue>? streamFor(String? key) {
      if (key == null || key.isEmpty) return null;
      return ref
          .watch(stateManProvider.future)
          .asStream()
          .switchMap((sm) => sm.subscribe(key).asStream().switchMap((s) => s));
    }

    final sp1$ = streamFor(widget.config.setpoint1Key);
    final hyst$ = streamFor(widget.config.setpoint1HysteresisKey);
    final sp2$ = streamFor(widget.config.setpoint2Key);
    final analog$ = streamFor(widget.config.analogKey);
    final min$ = streamFor(widget.config.analogSensorRangeMinKey);
    final max$ = streamFor(widget.config.analogSensorRangeMaxKey);

    Future<void> writeValue(String key, double val) async {
      final sm = await ref.read(stateManProvider.future);
      final currValue = await sm.read(key);
      currValue.value = val;
      await sm.write(key, currValue);
    }

    Widget valueField({
      required String label,
      required double? current,
      required void Function(double) onSubmitted,
      String? units,
    }) {
      final controller = TextEditingController(
        text: current?.toStringAsFixed(3) ?? '',
      );
      return SizedBox(
        width: 220,
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            suffixText: units ?? widget.config.units,
          ),
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: false),
          onFieldSubmitted: (v) {
            final d = double.tryParse(v);
            if (d != null) onSubmitted(d);
          },
        ),
      );
    }

    return AlertDialog(
      title: FutureBuilder<StateMan>(
        future: ref.watch(stateManProvider.future),
        builder: (context, snapshot) {
          final resolvedKey = snapshot.hasData
              ? snapshot.data!.resolveKey(widget.config.analogKey)
              : widget.config.analogKey;

          return Text(widget.config.text?.isNotEmpty == true
              ? widget.config.text!
              : (resolvedKey ?? 'AnalogBox'));
        },
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current value row with advanced toggle
            if (analog$ != null)
              StreamBuilder<DynamicValue>(
                stream: analog$,
                builder: (ctx, snap) {
                  final dv = (snap.data);
                  final val = (dv != null && (dv.isDouble || dv.isInteger))
                      ? dv.asDouble
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.speed,
                                color: Theme.of(context).primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Current: ${val?.toStringAsFixed(3) ?? '---'} ${widget.config.units ?? ''}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (widget.config.analogSensorRangeMinKey != null ||
                                widget.config.analogSensorRangeMaxKey != null)
                              _AdvancedSwitch(
                                value: showAdvanced,
                                onChanged: (value) {
                                  setState(() {
                                    showAdvanced = value;
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // Editable setpoints
            if (widget.config.setpoint1Key != null ||
                widget.config.setpoint2Key != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tune,
                              color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Setpoints',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          if (widget.config.setpoint1Key != null)
                            StreamBuilder<DynamicValue>(
                              stream: sp1$,
                              builder: (ctx, snap) {
                                final val = (snap.data != null &&
                                        (snap.data!.isDouble ||
                                            snap.data!.isInteger))
                                    ? snap.data!.asDouble
                                    : null;
                                return valueField(
                                  label: 'Setpoint 1',
                                  current: val,
                                  onSubmitted: (d) => writeValue(
                                      widget.config.setpoint1Key!, d),
                                );
                              },
                            ),
                          if (widget.config.setpoint1HysteresisKey != null)
                            StreamBuilder<DynamicValue>(
                              stream: hyst$,
                              builder: (ctx, snap) {
                                final val = (snap.data != null &&
                                        (snap.data!.isDouble ||
                                            snap.data!.isInteger))
                                    ? snap.data!.asDouble
                                    : null;
                                return valueField(
                                  label: 'SP1 Hysteresis (±)',
                                  current: val,
                                  onSubmitted: (d) => writeValue(
                                      widget.config.setpoint1HysteresisKey!, d),
                                );
                              },
                            ),
                          if (widget.config.setpoint2Key != null)
                            StreamBuilder<DynamicValue>(
                              stream: sp2$,
                              builder: (ctx, snap) {
                                final val = (snap.data != null &&
                                        (snap.data!.isDouble ||
                                            snap.data!.isInteger))
                                    ? snap.data!.asDouble
                                    : null;
                                return valueField(
                                  label: 'Setpoint 2',
                                  current: val,
                                  onSubmitted: (d) => writeValue(
                                      widget.config.setpoint2Key!, d),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Advanced: editable range keys (appears when toggle is on)
            if (showAdvanced &&
                (widget.config.analogSensorRangeMinKey != null ||
                    widget.config.analogSensorRangeMaxKey != null))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tune,
                              color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          const Text(
                            'Sensor range values',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          if (widget.config.analogSensorRangeMinKey != null)
                            StreamBuilder<DynamicValue>(
                              stream: min$,
                              builder: (ctx, snap) {
                                final val = (snap.data != null &&
                                        (snap.data!.isDouble ||
                                            snap.data!.isInteger))
                                    ? snap.data!.asDouble
                                    : null;
                                return valueField(
                                  label: 'Range Min',
                                  current: val,
                                  onSubmitted: (d) => writeValue(
                                      widget.config.analogSensorRangeMinKey!,
                                      d),
                                  units: widget.config.rangeUnits,
                                );
                              },
                            ),
                          if (widget.config.analogSensorRangeMaxKey != null)
                            StreamBuilder<DynamicValue>(
                              stream: max$,
                              builder: (ctx, snap) {
                                final val = (snap.data != null &&
                                        (snap.data!.isDouble ||
                                            snap.data!.isInteger))
                                    ? snap.data!.asDouble
                                    : null;
                                return valueField(
                                  label: 'Range Max',
                                  current: val,
                                  onSubmitted: (d) => writeValue(
                                      widget.config.analogSensorRangeMaxKey!,
                                      d),
                                  units: widget.config.rangeUnits,
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Graph (simple: one series of analogKey)
            if (widget.config.graphConfig != null &&
                widget.config.analogKey != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.show_chart,
                              color: Theme.of(context).primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'Historical Data',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (widget.config.graphConfig != null)
                        SizedBox(
                            width: 600,
                            height: 280,
                            child: GraphAsset(widget.config.graphConfig!))
                      else
                        const Center(child: Text('No graph config')),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// PAINTER

class _AnalogBoxPainter extends CustomPainter {
  final double percent; // 0..1
  final double min;
  final double max;

  final Color bgColor;
  final Color fillColor;

  final double? setpoint1;
  final double? setpoint1Hyst; // +/- around sp1
  final double? setpoint2;

  final Color setpoint1Color;
  final Color setpoint2Color;
  final Color hysteresisColor;

  final bool vertical;
  final bool reverseFill;
  final double borderRadiusPct;
  final double labelAngleDeg;

  _AnalogBoxPainter({
    required this.percent,
    required this.min,
    required this.max,
    required this.bgColor,
    required this.fillColor,
    required this.setpoint1,
    required this.setpoint1Hyst,
    required this.setpoint2,
    required this.setpoint1Color,
    required this.setpoint2Color,
    required this.hysteresisColor,
    required this.vertical,
    required this.reverseFill,
    required this.borderRadiusPct,
    required this.labelAngleDeg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.shortestSide * borderRadiusPct.clamp(0, .5));
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, r);

    // Background
    final bg = Paint()..color = bgColor;
    canvas.drawRRect(rrect, bg);

    // Fill clip
    final p = percent.clamp(0.0, 1.0);
    Rect fillRect;
    if (vertical) {
      final h = size.height * p.toDouble();
      final y = reverseFill ? 0.0 : size.height - h;
      fillRect = Rect.fromLTWH(0, y, size.width, h);
    } else {
      final w = size.width * p.toDouble();
      final x = reverseFill ? size.width - w : 0.0;
      fillRect = Rect.fromLTWH(x, 0, w, size.height);
    }
    final fill = Paint()..color = fillColor;
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(fillRect, fill);
    canvas.restore();

    // Hysteresis band around SP1
    if (setpoint1 != null && setpoint1Hyst != null && max > min) {
      final lo = ((setpoint1! - setpoint1Hyst!) - min) / (max - min);
      final hi = ((setpoint1! + setpoint1Hyst!) - min) / (max - min);
      _drawBand(canvas, size, lo.clamp(0.0, 1.0), hi.clamp(0.0, 1.0),
          hysteresisColor);
    }

    // Setpoint lines
    if (setpoint1 != null) {
      _drawSetpoint(canvas, size, setpoint1!, setpoint1Color);
    }
    if (setpoint2 != null) {
      _drawSetpoint(canvas, size, setpoint2!, setpoint2Color, dashed: true);
    }

    // Border
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;
    canvas.drawRRect(rrect, border);
  }

  void _drawSetpoint(Canvas canvas, Size size, double sp, Color color,
      {bool dashed = false}) {
    if (max <= min) return;
    final t = ((sp - min) / (max - min)).clamp(0.0, 1.0);
    final p1 = Paint()
      ..color = color
      ..strokeWidth = 2;

    if (vertical) {
      final y = size.height * (reverseFill ? t : 1 - t);
      if (dashed) {
        _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), p1);
      } else {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), p1);
      }
    } else {
      final x = size.width * (reverseFill ? 1 - t : t);
      if (dashed) {
        _drawDashedLine(canvas, Offset(x, 0), Offset(x, size.height), p1);
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), p1);
      }
    }
  }

  void _drawBand(Canvas canvas, Size size, double lo, double hi, Color color) {
    final paint = Paint()..color = color;
    if (vertical) {
      final y1 = size.height * (reverseFill ? lo : 1 - lo);
      final y2 = size.height * (reverseFill ? hi : 1 - hi);
      final top = math.min(y1, y2);
      final height = (y2 - y1).abs();
      canvas.drawRect(Rect.fromLTWH(0, top, size.width, height), paint);
    } else {
      final x1 = size.width * (reverseFill ? 1 - lo : lo);
      final x2 = size.width * (reverseFill ? 1 - hi : hi);
      final left = math.min(x1, x2);
      final width = (x2 - x1).abs();
      canvas.drawRect(Rect.fromLTWH(left, 0, width, size.height), paint);
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    double dash = 6,
    double gap = 4,
  }) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    double t = 0;
    while (t < total) {
      final t2 = math.min(t + dash, total);
      final p = a + dir * t;
      final q = a + dir * t2;
      canvas.drawLine(p, q, paint);
      t = t2 + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _AnalogBoxPainter old) {
    return percent != old.percent ||
        min != old.min ||
        max != old.max ||
        bgColor != old.bgColor ||
        fillColor != old.fillColor ||
        setpoint1 != old.setpoint1 ||
        setpoint1Hyst != old.setpoint1Hyst ||
        setpoint2 != old.setpoint2 ||
        vertical != old.vertical ||
        reverseFill != old.reverseFill ||
        borderRadiusPct != old.borderRadiusPct ||
        labelAngleDeg != old.labelAngleDeg;
  }
}

/// Custom switch with embedded text
class _AdvancedSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AdvancedSwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 110,
        height: 32,
        decoration: BoxDecoration(
          color: value ? Theme.of(context).primaryColor : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            // Text positioned dynamically based on switch state
            Positioned(
              left: value ? 12 : null, // Left side when ON
              right: value ? null : 12, // Right side when OFF
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  'Advanced',
                  style: TextStyle(
                    color: value ? Colors.white : Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Sliding circle
            AnimatedAlign(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 28,
                height: 28,
                margin: EdgeInsets.only(
                  left: value ? 0 : 2,
                  right: value ? 2 : 0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
