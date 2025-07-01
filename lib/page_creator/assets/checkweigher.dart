// similar to number, but clickable
// shows a dialog with graph and buttons to tare, zero and calibrate and other things mentioned below
// the graph should show accepted pieces weight as green dots and rejected pieces weight as red dots
// we should show the ratio between accepted and rejected pieces for the last 100(configurable) pieces
// we should show the upper and lower limits of the target weight
// we should show the target weight
// we should show the current weight
// I would like to use https://pub.dev/packages/community_charts_flutter for the graph
// configurable reject and accept keys
// tare, zero and calibrate keys

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import 'common.dart';
import '../../providers/state_man.dart';
import '../../converter/color_converter.dart';
part 'checkweigher.g.dart';

class WeightSample {
  final double weight;
  final bool accepted;
  final DateTime timestamp;

  WeightSample({
    required this.weight,
    required this.accepted,
    required this.timestamp,
  });
}

@JsonSerializable()
class CheckweigherConfig extends BaseAsset {
  String currentWeightKey;
  String? acceptKey;
  String? rejectKey;
  String? tareKey;
  String? zeroKey;
  String? calibrateKey;
  String? targetWeightKey;
  String? upperLimitKey;
  String? lowerLimitKey;
  int sampleSize;
  int decimalPlaces;
  @ColorConverter()
  Color textColor;

  CheckweigherConfig({
    required this.currentWeightKey,
    this.acceptKey,
    this.rejectKey,
    this.tareKey,
    this.zeroKey,
    this.calibrateKey,
    this.targetWeightKey,
    this.upperLimitKey,
    this.lowerLimitKey,
    this.sampleSize = 100,
    this.decimalPlaces = 2,
    this.textColor = Colors.black,
  });

  CheckweigherConfig.preview()
      : currentWeightKey = "",
        sampleSize = 100,
        decimalPlaces = 2,
        textColor = Colors.black;

  factory CheckweigherConfig.fromJson(Map<String, dynamic> json) =>
      _$CheckweigherConfigFromJson(json);
  Map<String, dynamic> toJson() => _$CheckweigherConfigToJson(this);

  @override
  Widget build(BuildContext context) => CheckweigherWidget(config: this);

  @override
  Widget configure(BuildContext context) =>
      _CheckweigherConfigEditor(config: this);
}

class _CheckweigherConfigEditor extends StatefulWidget {
  final CheckweigherConfig config;
  const _CheckweigherConfigEditor({required this.config});

  @override
  State<_CheckweigherConfigEditor> createState() =>
      _CheckweigherConfigEditorState();
}

class _CheckweigherConfigEditorState extends State<_CheckweigherConfigEditor> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoordinatesField(
            initialValue: widget.config.coordinates,
            onChanged: (c) => setState(() => widget.config.coordinates = c),
            enableAngle: true,
          ),
          const SizedBox(height: 16),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (size) => setState(() => widget.config.size = size),
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.currentWeightKey,
            onChanged: (value) =>
                setState(() => widget.config.currentWeightKey = value),
            label: 'Current Weight Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.acceptKey,
            onChanged: (value) =>
                setState(() => widget.config.acceptKey = value),
            label: 'Accepted weight Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.rejectKey,
            onChanged: (value) =>
                setState(() => widget.config.rejectKey = value),
            label: 'Rejected weight Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.tareKey,
            onChanged: (value) => setState(() => widget.config.tareKey = value),
            label: 'Tare Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.zeroKey,
            onChanged: (value) => setState(() => widget.config.zeroKey = value),
            label: 'Zero Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.calibrateKey,
            onChanged: (value) =>
                setState(() => widget.config.calibrateKey = value),
            label: 'Calibrate Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.targetWeightKey,
            onChanged: (value) =>
                setState(() => widget.config.targetWeightKey = value),
            label: 'Target Weight Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.upperLimitKey,
            onChanged: (value) =>
                setState(() => widget.config.upperLimitKey = value),
            label: 'Upper Limit Key',
          ),
          const SizedBox(height: 16),
          KeyField(
            initialValue: widget.config.lowerLimitKey,
            onChanged: (value) =>
                setState(() => widget.config.lowerLimitKey = value),
            label: 'Lower Limit Key',
          ),
          TextFormField(
            initialValue: widget.config.sampleSize.toString(),
            decoration: const InputDecoration(
              labelText: 'Sample Size',
              helperText: 'Number of samples to show in graph',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final size = int.tryParse(value);
              if (size != null && size > 0) {
                setState(() => widget.config.sampleSize = size);
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.decimalPlaces.toString(),
            decoration: const InputDecoration(
              labelText: 'Decimal Places',
              helperText: 'Range: 0-5',
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final places = int.tryParse(value);
              if (places != null && places >= 0 && places <= 5) {
                setState(() => widget.config.decimalPlaces = places);
              }
            },
          ),
        ],
      ),
    );
  }
}

class CheckweigherWidget extends ConsumerStatefulWidget {
  final CheckweigherConfig config;
  const CheckweigherWidget({super.key, required this.config});

  @override
  ConsumerState<CheckweigherWidget> createState() => _CheckweigherWidgetState();
}

class _CheckweigherWidgetState extends ConsumerState<CheckweigherWidget> {
  final List<WeightSample> _samples = [];

  String _formatNumber(num value) {
    final formatted = value.toStringAsFixed(widget.config.decimalPlaces);
    final parts = formatted.split('.');
    final integerPart = parts[0].padLeft(widget.config.decimalPlaces - 1, '0');
    final decimalPart =
        parts.length > 1 ? parts[1] : '0' * widget.config.decimalPlaces;

    return '$integerPart.$decimalPart';
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Checkweigher Details'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            child: Column(
              children: [
                _buildGraph(),
                const SizedBox(height: 16),
                _buildStats(),
                const SizedBox(height: 16),
                _buildControls(),
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
      },
    );
  }

  Widget _buildGraph() {
    // final data = [
    //   charts.Series<WeightSample, DateTime>(
    //     id: 'Accepted',
    //     colorFn: (_, __) => charts.MaterialPalette.green.shadeDefault,
    //     domainFn: (WeightSample sample, _) => sample.timestamp,
    //     measureFn: (WeightSample sample, _) => sample.weight,
    //     data: _samples.where((s) => s.accepted).toList(),
    //   ),
    //   charts.Series<WeightSample, DateTime>(
    //     id: 'Rejected',
    //     colorFn: (_, __) => charts.MaterialPalette.red.shadeDefault,
    //     domainFn: (WeightSample sample, _) => sample.timestamp,
    //     measureFn: (WeightSample sample, _) => sample.weight,
    //     data: _samples.where((s) => !s.accepted).toList(),
    //   ),
    // ];

    return SizedBox(height: 300, child: CircularProgressIndicator()
        // charts.TimeSeriesChart(
        //   data,
        //   animate: true,
        //   defaultRenderer: charts.PointRendererConfig<DateTime>(),
        // behaviors: [
        //   charts.RangeAnnotation([
        //     charts.LineAnnotationSegment(
        //       widget.config.targetWeight,
        //       charts.RangeAnnotationAxisType.measure,
        //       strokeWidth: 2,
        //       color: charts.MaterialPalette.blue.shadeDefault,
        //     ),
        //     charts.LineAnnotationSegment(
        //       widget.config.upperLimit,
        //       charts.RangeAnnotationAxisType.measure,
        //       strokeWidth: 1,
        //       color: charts.MaterialPalette.red.shadeDefault,
        //     ),
        //     charts.LineAnnotationSegment(
        //       widget.config.lowerLimit,
        //       charts.RangeAnnotationAxisType.measure,
        //       strokeWidth: 1,
        //       color: charts.MaterialPalette.red.shadeDefault,
        //     ),
        //   ]),
        // ],
        // ),
        );
  }

  Widget _buildStats() {
    final total = _samples.length;
    final accepted = _samples.where((s) => s.accepted).length;
    final ratio = total > 0 ? (accepted / total * 100) : 0;

    return Column(
      children: [
        Text('Accept Rate: ${ratio.toStringAsFixed(1)}%'),
        // Text('Target: ${_formatNumber(widget.config.targetWeight)}'),
        // Text(
        //     'Limits: ${_formatNumber(widget.config.lowerLimit)} - ${_formatNumber(widget.config.upperLimit)}'),
      ],
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (widget.config.tareKey != null)
          ElevatedButton(
            onPressed: () async {
              final value = DynamicValue(value: true);
              await (await ref.read(stateManProvider.future))
                  .write(widget.config.tareKey!, value);
            },
            child: const Text('Tare'),
          ),
        if (widget.config.zeroKey != null)
          ElevatedButton(
            onPressed: () async {
              final value = DynamicValue(value: true);
              await (await ref.read(stateManProvider.future))
                  .write(widget.config.zeroKey!, value);
            },
            child: const Text('Zero'),
          ),
        if (widget.config.calibrateKey != null)
          ElevatedButton(
            onPressed: () async {
              final value = DynamicValue(value: true);
              await (await ref.read(stateManProvider.future))
                  .write(widget.config.calibrateKey!, value);
            },
            child: const Text('Calibrate'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.currentWeightKey == "Checkweigher preview") {
      return _buildDisplay(context, "100.00");
    }

    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
          (stateMan) => stateMan
              .subscribe(widget.config.currentWeightKey)
              .asStream()
              .switchMap((s) => s)),
      builder: (context, snapshot) {
        String displayValue = "---";

        if (snapshot.hasData) {
          if (snapshot.data!.isDouble || snapshot.data!.isInteger) {
            displayValue = _formatNumber(snapshot.data!.asDouble);
          }
        }

        return GestureDetector(
          onTap: () async {
            _showDetailsDialog(context);
          },
          child: _buildDisplay(context, displayValue),
        );
      },
    );
  }

  Widget _buildDisplay(BuildContext context, String value) {
    return FittedBox(
      fit: BoxFit.contain,
      child: Transform.rotate(
        angle: (widget.config.coordinates.angle ?? 0) * math.pi / 180,
        child: Text(
          value,
          style: TextStyle(
            color: widget.config.textColor,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
