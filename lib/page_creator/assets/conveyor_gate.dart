import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:rxdart/rxdart.dart';

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/conveyor_gate_painter.dart';
import 'package:tfc/providers/state_man.dart';

part 'conveyor_gate.g.dart';

/// Color helpers for JSON serialization of Color objects.
int _colorToJson(Color c) => c.value;
Color _colorFromJson(int v) => Color(v);

/// The type of gate mechanism.
@JsonEnum()
enum GateVariant {
  pneumatic,
  slider,
  pusher,
}

/// Which side the gate flap hinges from.
@JsonEnum()
enum GateSide {
  left,
  right,
}

/// Configuration for a conveyor gate asset.
///
/// Extends [BaseAsset] with fields specific to the pneumatic diverter gate:
/// variant type, hinge side, OPC UA state key, opening angle, animation timing,
/// and configurable open/closed colors.
@JsonSerializable(explicitToJson: true)
class ConveyorGateConfig extends BaseAsset {
  @override
  String get displayName => 'Conveyor Gate';

  @override
  String get category => 'Visualization';

  @JsonKey(unknownEnumValue: GateVariant.pneumatic)
  GateVariant gateVariant;

  @JsonKey(unknownEnumValue: GateSide.left)
  GateSide side;

  String stateKey;

  double openAngleDegrees;

  int openTimeMs;

  int? closeTimeMs;

  @JsonKey(fromJson: _colorFromJson, toJson: _colorToJson)
  Color openColor;

  @JsonKey(fromJson: _colorFromJson, toJson: _colorToJson)
  Color closedColor;

  ConveyorGateConfig({
    this.gateVariant = GateVariant.pneumatic,
    this.side = GateSide.left,
    this.stateKey = '',
    this.openAngleDegrees = 45.0,
    this.openTimeMs = 800,
    this.closeTimeMs,
    this.openColor = Colors.green,
    this.closedColor = Colors.white,
  });

  /// Preview factory with reasonable defaults for the asset palette.
  ConveyorGateConfig.preview()
      : gateVariant = GateVariant.pneumatic,
        side = GateSide.left,
        stateKey = '',
        openAngleDegrees = 45.0,
        openTimeMs = 800,
        closeTimeMs = null,
        openColor = Colors.green,
        closedColor = Colors.white;

  factory ConveyorGateConfig.fromJson(Map<String, dynamic> json) =>
      _$ConveyorGateConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ConveyorGateConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return ConveyorGate(config: this);
  }

  @override
  Widget configure(BuildContext context) =>
      _ConveyorGateConfigEditor(config: this);
}

// ---------------------------------------------------------------------------
// Runtime widget with animation and OPC UA data binding
// ---------------------------------------------------------------------------

/// Animated conveyor gate driven by an OPC UA boolean state key.
///
/// The gate subscribes to [ConveyorGateConfig.stateKey] via [stateManProvider]
/// and smoothly animates between open (true) and closed (false) positions using
/// an ease-out curve. When the key is empty or OPC UA data is unavailable, the
/// gate renders in grey.
class ConveyorGate extends ConsumerStatefulWidget {
  final ConveyorGateConfig config;
  const ConveyorGate({super.key, required this.config});

  @override
  ConsumerState<ConveyorGate> createState() => _ConveyorGateState();
}

class _ConveyorGateState extends ConsumerState<ConveyorGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final ValueNotifier<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.config.openTimeMs),
    );
    _progress = ValueNotifier<double>(0.0);
    _controller.addListener(() {
      _progress.value = Curves.easeOut.transform(_controller.value);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// Trigger animation toward open or closed.
  ///
  /// Sets the appropriate duration before animating so that open and close
  /// speeds can differ. Called on every OPC UA state change, including after
  /// reconnects, ensuring the visual always matches the live state.
  void _onStateChanged(bool isOpen) {
    if (isOpen) {
      _controller.duration =
          Duration(milliseconds: widget.config.openTimeMs);
      _controller.forward();
    } else {
      _controller.duration = Duration(
        milliseconds:
            widget.config.closeTimeMs ?? widget.config.openTimeMs,
      );
      _controller.reverse();
    }
  }

  Widget _buildGate(Color stateColor) {
    return LayoutRotatedBox(
      angle: (widget.config.coordinates.angle ?? 0.0) * pi / 180,
      child: CustomPaint(
        size: widget.config.size.toSize(MediaQuery.of(context).size),
        painter: PneumaticDiverterPainter(
          progress: _progress,
          stateColor: stateColor,
          openAngleDegrees: widget.config.openAngleDegrees,
          side: widget.config.side,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When no state key is configured, render in grey (DATA-06).
    if (widget.config.stateKey.isEmpty) {
      return _buildGate(Colors.grey);
    }

    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
            (stateMan) => stateMan
                .subscribe(widget.config.stateKey)
                .asStream()
                .switchMap((s) => s),
          ),
      builder: (context, snapshot) {
        final Color color;
        if (!snapshot.hasData) {
          color = Colors.grey; // DATA-06: grey when disconnected
        } else if (snapshot.data!.asBool) {
          color = widget.config.openColor;
        } else {
          color = widget.config.closedColor;
        }

        _onStateChanged(snapshot.hasData && snapshot.data!.asBool);

        return _buildGate(color);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Config editor widget with live preview
// ---------------------------------------------------------------------------

class _ConveyorGateConfigEditor extends StatefulWidget {
  final ConveyorGateConfig config;
  const _ConveyorGateConfigEditor({required this.config});

  @override
  State<_ConveyorGateConfigEditor> createState() =>
      _ConveyorGateConfigEditorState();
}

class _ConveyorGateConfigEditorState extends State<_ConveyorGateConfigEditor>
    with SingleTickerProviderStateMixin {
  /// Progress notifier drives the PneumaticDiverterPainter repaint.
  late final ValueNotifier<double> _previewProgress;

  /// Animation controller for the "play" preview cycle.
  late final AnimationController _animController;

  late TextEditingController _openTimeController;
  late TextEditingController _closeTimeController;

  @override
  void initState() {
    super.initState();
    _previewProgress = ValueNotifier<double>(0.5);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(() {
        // Forward 0->1 then reverse 1->0 via a ping-pong curve.
        _previewProgress.value = _animController.value;
      });

    _openTimeController = TextEditingController(
      text: widget.config.openTimeMs.toString(),
    );
    _closeTimeController = TextEditingController(
      text: widget.config.closeTimeMs?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _previewProgress.dispose();
    _animController.dispose();
    _openTimeController.dispose();
    _closeTimeController.dispose();
    super.dispose();
  }

  void _playPreview() {
    if (_animController.isAnimating) {
      _animController.stop();
      return;
    }
    _animController.forward().then((_) {
      if (mounted) _animController.reverse();
    });
  }

  void _showColorPicker(
    BuildContext context,
    Color current,
    ValueChanged<Color> onChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (color) => onChanged(color),
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

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- Live preview --
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CustomPaint(
                    painter: PneumaticDiverterPainter(
                      progress: _previewProgress,
                      stateColor: config.openColor,
                      openAngleDegrees: config.openAngleDegrees,
                      side: config.side,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _animController.isAnimating
                        ? Icons.stop
                        : Icons.play_arrow,
                  ),
                  tooltip: 'Play open/close animation',
                  onPressed: _playPreview,
                ),
              ],
            ),
          ),
          const Divider(),

          // -- OPC UA State Key --
          KeyField(
            label: 'OPC UA State Key',
            initialValue: config.stateKey,
            onChanged: (v) => setState(() => config.stateKey = v),
          ),
          const SizedBox(height: 16),

          // -- Gate Side --
          Text('Gate Side', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          SegmentedButton<GateSide>(
            segments: const [
              ButtonSegment(value: GateSide.left, label: Text('Left')),
              ButtonSegment(value: GateSide.right, label: Text('Right')),
            ],
            selected: {config.side},
            onSelectionChanged: (selection) {
              setState(() => config.side = selection.first);
            },
          ),
          const SizedBox(height: 16),

          // -- Opening Angle --
          Text(
            'Opening Angle: ${config.openAngleDegrees.round()}\u00B0',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Slider(
            min: 0,
            max: 90,
            divisions: 90,
            value: config.openAngleDegrees,
            label: '${config.openAngleDegrees.round()}\u00B0',
            onChanged: (v) => setState(() => config.openAngleDegrees = v),
          ),
          const SizedBox(height: 8),

          // -- Open Time --
          TextFormField(
            controller: _openTimeController,
            decoration: const InputDecoration(
              labelText: 'Open Time (ms)',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              final parsed = int.tryParse(v);
              if (parsed != null && parsed > 0) {
                setState(() => config.openTimeMs = parsed);
              }
            },
          ),
          const SizedBox(height: 8),

          // -- Close Time --
          TextFormField(
            controller: _closeTimeController,
            decoration: const InputDecoration(
              labelText: 'Close Time (ms)',
              hintText: 'Same as open time',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              setState(() {
                config.closeTimeMs = v.isEmpty ? null : int.tryParse(v);
              });
            },
          ),
          const SizedBox(height: 16),

          // -- Open Color --
          GestureDetector(
            onTap: () => _showColorPicker(
              context,
              config.openColor,
              (color) => setState(() => config.openColor = color),
            ),
            child: Row(
              children: [
                _colorSwatch(config.openColor),
                const SizedBox(width: 8),
                const Text('Open Color'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // -- Closed Color --
          GestureDetector(
            onTap: () => _showColorPicker(
              context,
              config.closedColor,
              (color) => setState(() => config.closedColor = color),
            ),
            child: Row(
              children: [
                _colorSwatch(config.closedColor),
                const SizedBox(width: 8),
                const Text('Closed Color'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // -- Size --
          SizeField(
            initialValue: config.size,
            onChanged: (size) => setState(() => config.size = size),
          ),
          const SizedBox(height: 16),

          // -- Coordinates --
          CoordinatesField(
            initialValue: config.coordinates,
            onChanged: (v) => setState(() => config.coordinates = v),
          ),
        ],
      ),
    );
  }
}
