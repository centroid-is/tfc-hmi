// A number assets
// Subscribe to key
// Can have label above, below, left, right
// We should have config for number of digits, size, angle, textPos and key

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import 'common.dart';
import '../../providers/state_man.dart';

part 'number.g.dart';

@JsonSerializable()
class NumberConfig extends BaseAsset {
  String key;
  bool showDecimalPoint;
  int decimalPlaces;
  String? units; // Optional units to display after the number
  @ColorConverter()
  Color textColor;

  NumberConfig({
    required this.key,
    this.showDecimalPoint = true,
    this.decimalPlaces = 2,
    this.units,
    this.textColor = Colors.black,
  });

  NumberConfig.preview()
      : key = "Number preview",
        showDecimalPoint = true,
        decimalPlaces = 2,
        units = "units",
        textColor = Colors.black;

  factory NumberConfig.fromJson(Map<String, dynamic> json) =>
      _$NumberConfigFromJson(json);
  Map<String, dynamic> toJson() => _$NumberConfigToJson(this);

  @override
  Widget build(BuildContext context) => NumberWidget(config: this);

  @override
  Widget configure(BuildContext context) => _NumberConfigEditor(config: this);
}

class _NumberConfigEditor extends StatefulWidget {
  final NumberConfig config;
  const _NumberConfigEditor({required this.config});

  @override
  State<_NumberConfigEditor> createState() => _NumberConfigEditorState();
}

class _NumberConfigEditorState extends State<_NumberConfigEditor> {
  late TextEditingController _unitsController;

  @override
  void initState() {
    super.initState();
    _unitsController = TextEditingController(text: widget.config.units);
  }

  @override
  void dispose() {
    _unitsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyField(
            initialValue: widget.config.key,
            onChanged: (value) => setState(() => widget.config.key = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: widget.config.text,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (value) => setState(() => widget.config.text = value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
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
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _unitsController,
            decoration: const InputDecoration(labelText: 'Units'),
            onChanged: (value) => setState(() => widget.config.units = value),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Show Decimal Point'),
            value: widget.config.showDecimalPoint,
            onChanged: (value) =>
                setState(() => widget.config.showDecimalPoint = value),
          ),
          const SizedBox(height: 16),
          DropdownButton<TextPos>(
            value: widget.config.textPos ?? TextPos.right,
            isExpanded: true,
            onChanged: (value) =>
                setState(() => widget.config.textPos = value!),
            items: TextPos.values
                .map((e) =>
                    DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
                .toList(),
          ),
          const SizedBox(height: 16),
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
        ],
      ),
    );
  }
}

class NumberWidget extends ConsumerWidget {
  final NumberConfig config;
  const NumberWidget({super.key, required this.config});

  String _formatNumber(num value) {
    if (!config.showDecimalPoint) {
      return value.toInt().toString();
    }

    final formatted = value.toStringAsFixed(config.decimalPlaces);
    final parts = formatted.split('.');
    final integerPart = parts[0].padLeft(config.decimalPlaces - 1, '0');
    final decimalPart =
        parts.length > 1 ? parts[1] : '0' * config.decimalPlaces;

    return '$integerPart.$decimalPart';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (config.key == "Number preview") {
      return _buildDisplay(context, "123.45");
    }

    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
          (stateMan) =>
              stateMan.subscribe(config.key).asStream().switchMap((s) => s)),
      builder: (context, snapshot) {
        String displayValue = "---";

        if (snapshot.hasData) {
          final value = snapshot.data!;
          if (value.isDouble || value.isInteger) {
            displayValue = _formatNumber(value.asDouble);
          }
        }

        return _buildDisplay(context, displayValue);
      },
    );
  }

  Widget _buildDisplay(BuildContext context, String value) {
    final displayText = config.units != null ? '$value ${config.units}' : value;

    return FittedBox(
      fit: BoxFit.contain,
      child: Transform.rotate(
        angle: (config.coordinates.angle ?? 0) * math.pi / 180,
        child: Text(
          displayText,
          style: TextStyle(
            color: config.textColor,
          ),
        ),
      ),
    );
  }
}
