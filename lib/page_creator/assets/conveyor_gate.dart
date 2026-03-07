import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue, NodeId;
import 'package:rxdart/rxdart.dart';
import 'package:tfc_dart/core/state_man.dart';

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

/// Wrapper for a gate placed as a child of a conveyor belt.
///
/// Holds conveyor-specific placement metadata (position along the belt and
/// which side the gate is on) separately from the gate's own configuration.
@JsonSerializable(explicitToJson: true)
class ChildGateEntry {
  /// Fractional position along conveyor belt (0.0 = start, 1.0 = end).
  double position;

  @JsonKey(unknownEnumValue: GateSide.left)
  GateSide side;

  @JsonKey(fromJson: _gateFromJson, toJson: _gateToJson)
  ConveyorGateConfig gate;

  ChildGateEntry({
    this.position = 0.5,
    this.side = GateSide.left,
    required this.gate,
  });

  factory ChildGateEntry.fromJson(Map<String, dynamic> json) =>
      _$ChildGateEntryFromJson(json);
  Map<String, dynamic> toJson() => _$ChildGateEntryToJson(this);
}

ConveyorGateConfig _gateFromJson(Map<String, dynamic> json) =>
    ConveyorGateConfig.fromJson(json);
Map<String, dynamic> _gateToJson(ConveyorGateConfig gate) => gate.toJson();

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

  /// OPC UA key to write a force-open command (DATA-02).
  String forceOpenKey;

  /// OPC UA key to subscribe for force-open active feedback (DATA-03).
  String forceOpenFeedbackKey;

  /// OPC UA key to write a force-close command (DATA-04).
  String forceCloseKey;

  /// OPC UA key to subscribe for force-close active feedback (DATA-05).
  String forceCloseFeedbackKey;

  ConveyorGateConfig({
    this.gateVariant = GateVariant.pneumatic,
    this.side = GateSide.left,
    this.stateKey = '',
    this.openAngleDegrees = 45.0,
    this.openTimeMs = 800,
    this.closeTimeMs,
    this.openColor = Colors.green,
    this.closedColor = Colors.white,
    this.forceOpenKey = '',
    this.forceOpenFeedbackKey = '',
    this.forceCloseKey = '',
    this.forceCloseFeedbackKey = '',
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
        closedColor = Colors.white,
        forceOpenKey = '',
        forceOpenFeedbackKey = '',
        forceCloseKey = '',
        forceCloseFeedbackKey = '';

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

/// Subscribe to a boolean OPC UA feedback key.
///
/// Returns a stream that emits `false` immediately and then tracks the live
/// value. When [key] is empty the stream emits a single `false` (no-op).
Stream<bool> _boolFeedback(StateMan sm, String key) {
  if (key.isEmpty) return Stream.value(false);
  return sm
      .subscribe(key)
      .asStream()
      .asyncExpand((s) => s)
      .map((v) => v.asBool)
      .startWith(false);
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

  /// Selects the correct painter based on [ConveyorGateConfig.gateVariant].
  CustomPainter _createPainter(Color stateColor) {
    switch (widget.config.gateVariant) {
      case GateVariant.pneumatic:
        return PneumaticDiverterPainter(
          progress: _progress,
          stateColor: stateColor,
          openAngleDegrees: widget.config.openAngleDegrees,
          side: widget.config.side,
        );
      case GateVariant.slider:
        return SliderGatePainter(
          progress: _progress,
          stateColor: stateColor,
          side: widget.config.side,
        );
      case GateVariant.pusher:
        return PusherGatePainter(
          progress: _progress,
          stateColor: stateColor,
          side: widget.config.side,
        );
    }
  }

  Widget _buildGate(Color stateColor) {
    return LayoutRotatedBox(
      angle: (widget.config.coordinates.angle ?? 0.0) * pi / 180,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // When placed inside a Positioned with explicit size (child-of-conveyor),
          // use the constraints directly. Otherwise fall back to config.size (standalone).
          final Size paintSize;
          if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
            paintSize = Size(constraints.maxWidth, constraints.maxHeight);
          } else {
            paintSize = widget.config.size.toSize(MediaQuery.of(context).size);
          }
          return CustomPaint(
            size: paintSize,
            painter: _createPainter(stateColor),
          );
        },
      ),
    );
  }

  /// Write a boolean value to an OPC UA force key.
  Future<void> _writeForce(String key, bool value) async {
    if (key.isEmpty) return;
    try {
      final client = await ref.read(stateManProvider.future);
      await client.write(
        key,
        DynamicValue(value: value, typeId: NodeId.boolean),
      );
    } catch (_) {
      // Log error but do not crash UI.
    }
  }

  /// Show the force-control dialog (INT-02).
  void _showForceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Force Gate'),
        content: _ForceDialogContent(
          config: widget.config,
          writeForce: _writeForce,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.config.forceOpenKey.isNotEmpty ||
        widget.config.forceCloseKey.isNotEmpty;

    // When no state key is configured, render in grey (DATA-06).
    if (widget.config.stateKey.isEmpty) {
      final gate = _buildGate(Colors.grey);
      return isInteractive
          ? GestureDetector(onTap: () => _showForceDialog(context), child: gate)
          : gate;
    }

    final forcedColor = Theme.of(context).colorScheme.tertiary;
    final hasForceFeedback =
        widget.config.forceOpenFeedbackKey.isNotEmpty ||
            widget.config.forceCloseFeedbackKey.isNotEmpty;

    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
            (stateMan) => stateMan
                .subscribe(widget.config.stateKey)
                .asStream()
                .switchMap((s) => s),
          ),
      builder: (context, snapshot) {
        // Resolve base color from OPC UA state.
        final bool isOpen = snapshot.hasData && snapshot.data!.asBool;
        _onStateChanged(isOpen);

        final Color baseColor;
        if (!snapshot.hasData) {
          baseColor = Colors.grey; // DATA-06: grey when disconnected
        } else if (isOpen) {
          baseColor = widget.config.openColor;
        } else {
          baseColor = widget.config.closedColor;
        }

        // If force feedback keys are configured, nest a second StreamBuilder
        // that overrides color when any force feedback is active (VIS-03).
        if (hasForceFeedback) {
          return StreamBuilder<bool>(
            stream:
                ref.watch(stateManProvider.future).asStream().asyncExpand(
              (sm) {
                return Rx.combineLatest2(
                  _boolFeedback(sm, widget.config.forceOpenFeedbackKey),
                  _boolFeedback(sm, widget.config.forceCloseFeedbackKey),
                  (a, b) => a || b,
                );
              },
            ),
            builder: (context, fbSnapshot) {
              final forceActive = fbSnapshot.data ?? false;
              final displayColor = forceActive ? forcedColor : baseColor;
              final gate = _buildGate(displayColor);
              return isInteractive
                  ? GestureDetector(
                      onTap: () => _showForceDialog(context), child: gate)
                  : gate;
            },
          );
        }

        // No force feedback -- use base color directly.
        final gate = _buildGate(baseColor);
        return isInteractive
            ? GestureDetector(
                onTap: () => _showForceDialog(context), child: gate)
            : gate;
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Force dialog content widget (shown inside AlertDialog)
// ---------------------------------------------------------------------------

class _ForceDialogContent extends ConsumerWidget {
  final ConveyorGateConfig config;
  final Future<void> Function(String key, bool value) writeForce;

  const _ForceDialogContent({
    required this.config,
    required this.writeForce,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedbackColor = Theme.of(context).colorScheme.tertiary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Current gate state indicator (read-only) --
        StreamBuilder<DynamicValue>(
          stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
                (sm) => config.stateKey.isEmpty
                    ? Stream<DynamicValue>.empty()
                    : sm
                        .subscribe(config.stateKey)
                        .asStream()
                        .switchMap((s) => s),
              ),
          builder: (context, snapshot) {
            final Color stateColor;
            final String stateLabel;
            if (!snapshot.hasData) {
              stateColor = Colors.grey;
              stateLabel = 'Disconnected';
            } else if (snapshot.data!.asBool) {
              stateColor = config.openColor;
              stateLabel = 'Open';
            } else {
              stateColor = config.closedColor;
              stateLabel = 'Closed';
            }
            return Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(stateLabel),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // -- Force Open button with feedback (INT-02, INT-03) --
        _forceButton(
          context: context,
          ref: ref,
          label: 'Force Open',
          writeKey: config.forceOpenKey,
          feedbackKey: config.forceOpenFeedbackKey,
          feedbackColor: feedbackColor,
        ),
        const SizedBox(height: 8),

        // -- Force Close button with feedback --
        _forceButton(
          context: context,
          ref: ref,
          label: 'Force Close',
          writeKey: config.forceCloseKey,
          feedbackKey: config.forceCloseFeedbackKey,
          feedbackColor: feedbackColor,
        ),
      ],
    );
  }

  Widget _forceButton({
    required BuildContext context,
    required WidgetRef ref,
    required String label,
    required String writeKey,
    required String feedbackKey,
    required Color feedbackColor,
  }) {
    return StreamBuilder<bool>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
        (sm) => _boolFeedback(sm, feedbackKey),
      ),
      builder: (context, fbSnapshot) {
        final isActive = fbSnapshot.data ?? false;
        return Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed:
                    writeKey.isEmpty ? null : () => writeForce(writeKey, true),
                child: Text(label),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: feedbackColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        );
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
  /// Progress notifier drives the gate painter repaint.
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

  /// Select the correct painter for the config editor live preview.
  CustomPainter _previewPainter(ConveyorGateConfig config) {
    switch (config.gateVariant) {
      case GateVariant.pneumatic:
        return PneumaticDiverterPainter(
          progress: _previewProgress,
          stateColor: config.openColor,
          openAngleDegrees: config.openAngleDegrees,
          side: config.side,
        );
      case GateVariant.slider:
        return SliderGatePainter(
          progress: _previewProgress,
          stateColor: config.openColor,
          side: config.side,
        );
      case GateVariant.pusher:
        return PusherGatePainter(
          progress: _previewProgress,
          stateColor: config.openColor,
          side: config.side,
        );
    }
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
                    painter: _previewPainter(config),
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

          // -- Gate Variant --
          Text('Gate Variant',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          SegmentedButton<GateVariant>(
            segments: const [
              ButtonSegment(
                  value: GateVariant.pneumatic, label: Text('Diverter')),
              ButtonSegment(
                  value: GateVariant.slider, label: Text('Slider')),
              ButtonSegment(
                  value: GateVariant.pusher, label: Text('Pusher')),
            ],
            selected: {config.gateVariant},
            onSelectionChanged: (selection) {
              setState(() => config.gateVariant = selection.first);
            },
          ),
          const SizedBox(height: 16),

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

          // -- Opening Angle (diverter only, Pitfall 4) --
          if (config.gateVariant == GateVariant.pneumatic) ...[
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
          ],

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

          // -- Force Controls --
          Text('Force Controls',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          KeyField(
            label: 'Force Open Key',
            initialValue: config.forceOpenKey,
            onChanged: (v) => setState(() => config.forceOpenKey = v),
          ),
          const SizedBox(height: 8),
          KeyField(
            label: 'Force Open Feedback Key',
            initialValue: config.forceOpenFeedbackKey,
            onChanged: (v) =>
                setState(() => config.forceOpenFeedbackKey = v),
          ),
          const SizedBox(height: 8),
          KeyField(
            label: 'Force Close Key',
            initialValue: config.forceCloseKey,
            onChanged: (v) => setState(() => config.forceCloseKey = v),
          ),
          const SizedBox(height: 8),
          KeyField(
            label: 'Force Close Feedback Key',
            initialValue: config.forceCloseFeedbackKey,
            onChanged: (v) =>
                setState(() => config.forceCloseFeedbackKey = v),
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
