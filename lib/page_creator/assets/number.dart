// A number assets
// Subscribe to key
// Can have label above, below, left, right
// We should have config for number of digits, size, angle, textPos and key

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import 'common.dart';
import '../../providers/state_man.dart';
import '../../core/state_man.dart';
import '../../converter/color_converter.dart';
import 'graph.dart';

part 'number.g.dart';

@JsonSerializable()
class NumberConfig extends BaseAsset {
  String key;
  bool showDecimalPoint;
  int decimalPlaces;
  double? scale;
  String? units; // Optional units to display after the number
  @ColorConverter()
  Color textColor;

  @JsonKey(name: 'graph_config')
  GraphAssetConfig? graphConfig;

  /// If true, number is editable by tapping it (dialog opens).
  /// When true, graphConfig must be null.
  @JsonKey(defaultValue: false)
  bool writable;

  NumberConfig({
    required this.key,
    this.showDecimalPoint = true,
    this.decimalPlaces = 2,
    this.units,
    this.textColor = Colors.black,
    this.graphConfig,
    this.scale,
    this.writable = false,
  });

  NumberConfig.preview()
      : key = "Number preview",
        showDecimalPoint = true,
        decimalPlaces = 2,
        units = "units",
        textColor = Colors.black,
        graphConfig = GraphAssetConfig.preview(),
        writable = false;

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
  bool showGraph = false;

  @override
  void initState() {
    super.initState();
    _unitsController = TextEditingController(text: widget.config.units);
    showGraph = widget.config.graphConfig != null;
  }

  @override
  void dispose() {
    _unitsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          MediaQuery.of(context).size.height * 0.8, // Use 80% of screen height
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT COLUMN: Number config fields
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KeyField(
                    initialValue: widget.config.key,
                    onChanged: (value) =>
                        setState(() => widget.config.key = value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: widget.config.text,
                    decoration: const InputDecoration(labelText: 'Label'),
                    onChanged: (value) =>
                        setState(() => widget.config.text = value),
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
                              setState(
                                  () => widget.config.decimalPlaces = places);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: widget.config.scale?.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Scale',
                            helperText: 'Scale the number, 1.0 is normal',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            final scale = double.tryParse(value);
                            if (scale != null) {
                              setState(() => widget.config.scale = scale);
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
                    onChanged: (value) =>
                        setState(() => widget.config.units = value),
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
                        .map((e) => DropdownMenuItem<TextPos>(
                            value: e, child: Text(e.name)))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  CoordinatesField(
                    initialValue: widget.config.coordinates,
                    onChanged: (c) =>
                        setState(() => widget.config.coordinates = c),
                    enableAngle: true,
                  ),
                  const SizedBox(height: 16),
                  SizeField(
                    initialValue: widget.config.size,
                    onChanged: (size) =>
                        setState(() => widget.config.size = size),
                  ),
                  const SizedBox(height: 16),

                  // Writable toggle (mutually exclusive with graph)
                  SwitchListTile(
                    title: const Text('Writable (tap number to edit)'),
                    subtitle: const Text('Disables graph'),
                    value: widget.config.writable,
                    onChanged: (v) => setState(() {
                      widget.config.writable = v;
                      if (v) {
                        showGraph = false;
                        widget.config.graphConfig = null;
                      }
                    }),
                  ),

                  // Graph toggle
                  SwitchListTile(
                    title: const Text('Include Graph'),
                    subtitle: const Text('Make number clickable to show graph'),
                    value: showGraph,
                    onChanged: (value) => setState(() {
                      showGraph = value;
                      if (value) {
                        widget.config.writable = false; // enforce exclusivity
                        if (widget.config.graphConfig == null) {
                          widget.config.graphConfig =
                              GraphAssetConfig.preview();
                        }
                      } else {
                        widget.config.graphConfig = null;
                      }
                    }),
                  ),
                ],
              ),
            ),
            // RIGHT COLUMN: Graph config
            if (showGraph && widget.config.graphConfig != null)
              const SizedBox(width: 24),
            if (showGraph && widget.config.graphConfig != null)
              Expanded(
                flex: 3,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Graph Configuration',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        GraphContentConfig(config: widget.config.graphConfig!),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
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
    if (config.scale != null) {
      value = value * config.scale!;
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

        return _buildDisplay(context, displayValue,
            ref: ref, rawSnapshot: snapshot.data);
      },
    );
  }

  Widget _buildDisplay(BuildContext context, String value,
      {WidgetRef? ref, DynamicValue? rawSnapshot}) {
    final displayText = config.units != null ? '$value ${config.units}' : value;

    Widget displayWidget = FittedBox(
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

    // Make clickable: writable OR graph (mutually exclusive in config UI)
    if (config.writable) {
      displayWidget = GestureDetector(
        onTap: () => _showWriteDialog(context, ref!),
        child: displayWidget,
      );
    } else if (config.graphConfig != null) {
      displayWidget = GestureDetector(
        onTap: () => _showGraphDialog(context),
        child: displayWidget,
      );
    }

    return displayWidget;
  }

  void _showGraphDialog(BuildContext context) {
    if (config.graphConfig == null) return;

    showDialog(
      context: context,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        return Dialog(
          child: Container(
            width: size.width * 0.8,
            height: size.height * 0.8,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      config.graphConfig?.headerText ??
                          config.text ??
                          config.key,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GraphAsset(
                    config.graphConfig!,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showWriteDialog(BuildContext context, WidgetRef ref) {
    if (config.key == "Number preview") return;

    showDialog(
      context: context,
      builder: (_) => _NumberWriteDialog(config: config),
    );
  }
}

class _NumberWriteDialog extends ConsumerStatefulWidget {
  final NumberConfig config;
  const _NumberWriteDialog({required this.config});

  @override
  ConsumerState<_NumberWriteDialog> createState() => _NumberWriteDialogState();
}

class _NumberWriteDialogState extends ConsumerState<_NumberWriteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _isInteger = false; // inferred from current value type
  double? _currentRaw; // raw value (unscaled)
  bool _hasValue = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _writeValue() async {
    final key = widget.config.key;
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a value to write.')),
      );
      return;
    }

    num? parsed;
    if (_isInteger) {
      parsed = int.tryParse(_controller.text.trim());
    } else {
      parsed = double.tryParse(_controller.text.trim());
    }
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid number.')),
      );
      return;
    }

    final sm = await ref.read(stateManProvider.future);
    final dv = await sm.read(key);

    // preserve underlying type when possible
    if (_isInteger) {
      dv.value = parsed as int;
    } else {
      dv.value = parsed as double;
    }
    await sm.write(key, dv);

    if (mounted) Navigator.of(context).pop();
  }

  String _formatDisplayed(double raw) {
    final scale = widget.config.scale ?? 1.0;
    final v = raw * scale;
    if (!widget.config.showDecimalPoint) {
      return v.toInt().toString();
    }
    final fixed = v.toStringAsFixed(widget.config.decimalPlaces);
    final parts = fixed.split('.');
    final integerPart = parts[0].padLeft(widget.config.decimalPlaces - 1, '0');
    final decimalPart =
        parts.length > 1 ? parts[1] : '0' * widget.config.decimalPlaces;
    return '$integerPart.$decimalPart';
  }

  @override
  Widget build(BuildContext context) {
    Stream<DynamicValue> value$ = ref
        .watch(stateManProvider.future)
        .asStream()
        .switchMap((sm) =>
            sm.subscribe(widget.config.key).asStream().switchMap((s) => s));

    return AlertDialog(
      title: FutureBuilder<StateMan>(
        future: ref.watch(stateManProvider.future),
        builder: (context, snapshot) {
          final resolvedKey = snapshot.hasData
              ? snapshot.data!.resolveKey(widget.config.key)
              : widget.config.key;
          return Text(widget.config.text?.isNotEmpty == true
              ? widget.config.text!
              : (resolvedKey ?? 'Number'));
        },
      ),
      content: StreamBuilder<DynamicValue>(
        stream: value$,
        builder: (context, snap) {
          _hasValue =
              snap.hasData && (snap.data!.isDouble || snap.data!.isInteger);
          if (_hasValue) {
            _currentRaw = snap.data!.asDouble;
            _isInteger = snap.data!.isInteger;
          }

          final units = widget.config.units ?? '';
          final rawText = _hasValue
              ? _currentRaw!.toStringAsFixed(_isInteger ? 0 : 3)
              : '---';
          final displayedText =
              _hasValue ? _formatDisplayed(_currentRaw!) : '---';
          final typeText =
              _hasValue ? (_isInteger ? 'Integer' : 'Double') : 'Unknown';

          // prefill once
          if (_hasValue && _controller.text.isEmpty) {
            _controller.text = _isInteger
                ? _currentRaw!.toStringAsFixed(0)
                : _currentRaw!.toStringAsFixed(3);
          }

          final inputFormatters = <TextInputFormatter>[
            FilteringTextInputFormatter.allow(
              _isInteger ? RegExp(r'[0-9-]') : RegExp(r'[0-9\.\-]'),
            ),
          ];

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Current value card (RAW + Displayed)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.speed,
                            color: Theme.of(context).primaryColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current (raw): $rawText ${units.isNotEmpty && widget.config.scale == null ? units : ''}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.visibility, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Displayed: $displayedText ${units.isNotEmpty ? units : ''}',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                              if (widget.config.scale != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Scale: ×${widget.config.scale}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.grey[700]),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Type: $typeText',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(fontStyle: FontStyle.italic),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Input field
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _controller,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: !_isInteger,
                      signed: true,
                    ),
                    inputFormatters: inputFormatters,
                    decoration: InputDecoration(
                      labelText: 'New value',
                      helperText:
                          _isInteger ? 'Enter an integer' : 'Enter a decimal',
                      suffixText: units,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter a value';
                      }
                      return _isInteger
                          ? (int.tryParse(v.trim()) == null
                              ? 'Invalid integer'
                              : null)
                          : (double.tryParse(v.trim()) == null
                              ? 'Invalid number'
                              : null);
                    },
                    onFieldSubmitted: (_) async {
                      if (_formKey.currentState?.validate() == true) {
                        await _writeValue();
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Write'),
          onPressed: () async {
            if (_formKey.currentState?.validate() == true) {
              await _writeValue();
            }
          },
        ),
      ],
    );
  }
}
