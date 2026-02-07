import 'dart:math';

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/page_creator/assets/led.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:rxdart/rxdart.dart';

part 'speedbatcher.g.dart';

@JsonSerializable()
class SpeedBatcherConfig extends BaseAsset {
  @override
  String get displayName => 'Speed Batcher';
  @override
  String get category => 'Application';

  String label;
  String key;

  SpeedBatcherConfig({
    required this.label,
    required this.key,
  });

  // Preview constructor: just shows text
  SpeedBatcherConfig.preview()
      : label = "SpeedBatcher preview",
        key = "";

  factory SpeedBatcherConfig.fromJson(Map<String, dynamic> json) => _$SpeedBatcherConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$SpeedBatcherConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return SpeedBatcher(config: this);
  }

  @override
  Widget configure(BuildContext context) => _SpeedBatcherConfigEditor(config: this);
}

class _SpeedBatcherConfigEditor extends StatefulWidget {
  final SpeedBatcherConfig config;
  const _SpeedBatcherConfigEditor({required this.config});

  @override
  State<_SpeedBatcherConfigEditor> createState() => _SpeedBatcherConfigEditorState();
}

class _SpeedBatcherConfigEditorState extends State<_SpeedBatcherConfigEditor> {
  late TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.config.label);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (value) => setState(() => widget.config.label = value),
          ),
          const SizedBox(height: 16),
          KeyField(
            label: 'Speedbatcher key',
            initialValue: widget.config.key,
            onChanged: (v) => setState(() => widget.config.key = v),
          ),
          const SizedBox(height: 8),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (size) => setState(() => widget.config.size = size),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            initialValue: widget.config.coordinates,
            onChanged: (v) => setState(() => widget.config.coordinates = v),
          ),
        ],
      ),
    );
  }
}

class SpeedBatcher extends ConsumerWidget {
  final SpeedBatcherConfig config;
  const SpeedBatcher({super.key, required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<DynamicValue>(
      stream: ref
          .watch(stateManProvider.future)
          .asStream()
          .asyncExpand((stateMan) => stateMan.subscribe(config.key).asStream().switchMap((s) => s)),
      builder: (context, snapshot) {
        if (snapshot.hasError || snapshot.hasData == false) {
          return speedBatcher([null, null, null, null]);
        }
        final dyn = snapshot.data!;
        return speedBatcher([
          dyn['p_stat_Running'].asBool,
          dyn['p_stat_Cleaning'].asBool,
          dyn['p_stat_BatchReady'].asBool,
          dyn['p_stat_Dropped'].asBool
        ]);
      },
    );
  }

  Widget speedBatcher(List<bool?> values) {
    assert(values.length == 4);

    // Build your LEDConfig list exactly as before
    final ledConfigs = <LEDConfig>[
      for (final e in ['Running', 'Cleaning', 'Batch ready', 'Dropped Batch'])
        LEDConfig(
          key: "",
          onColor: (e == 'Cleaning') ? Colors.blue : Colors.green,
          offColor: Colors.white,
        )
          ..text = e
          ..size = config.size
          ..textPos = TextPos.right,
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // Force this widget to be square (1:1 aspect ratio),
      // so it will expand as much as possible within its parent.
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blueGrey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          // We want 5 equally‐spaced “rows”: 4 for LED/status, 1 for the label.
          children: [
            for (int i = 0; i < 4; i++)
              Expanded(
                flex: 1, // Each LED row is 1/5 of the square’s height
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 10% of the row’s width is given to the LED, and it's forced to be a square via AspectRatio
                    Expanded(
                      flex: 10, // 10 parts out of 100
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: LedRaw(
                          ledConfigs[i],
                          value: values[i],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // The remaining 90% of the row’s width is for the text.
                    Expanded(
                      flex: 90,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(ledConfigs[i].text!),
                      ),
                    ),
                  ],
                ),
              ),

            // The 5th “row” is the label, also taking up 1/5 of the height
            Expanded(
              flex: 1,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    config.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

@JsonSerializable()
class GateStatusConfig extends BaseAsset {
  String key;

  GateStatusConfig({
    required this.key,
  });

  GateStatusConfig.preview() : key = "";

  factory GateStatusConfig.fromJson(Map<String, dynamic> json) => _$GateStatusConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$GateStatusConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return GateStatus(config: this);
  }

  @override
  Widget configure(BuildContext context) => _GateStatusConfigEditor(config: this);
}

class _GateStatusConfigEditor extends StatefulWidget {
  final GateStatusConfig config;
  const _GateStatusConfigEditor({required this.config});

  @override
  State<_GateStatusConfigEditor> createState() => _GateStatusConfigEditorState();
}

class _GateStatusConfigEditorState extends State<_GateStatusConfigEditor> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyField(
            label: 'key',
            initialValue: widget.config.key,
            onChanged: (v) => setState(() => widget.config.key = v),
          ),
          const SizedBox(height: 8),
          SizeField(
            initialValue: widget.config.size,
            onChanged: (size) => setState(() => widget.config.size = size),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            enableAngle: true,
            initialValue: widget.config.coordinates,
            onChanged: (v) => setState(() => widget.config.coordinates = v),
          ),
        ],
      ),
    );
  }
}

class GateStatus extends ConsumerWidget {
  final GateStatusConfig config;
  const GateStatus({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (config.key.isEmpty) {
      return CustomPaint(
        painter: GatePainter(color: Colors.grey),
      );
    }

    return StreamBuilder<DynamicValue>(
      stream: ref
          .watch(stateManProvider.future)
          .asStream()
          .asyncExpand((stateMan) => stateMan.subscribe(config.key).asStream().switchMap((s) => s)),
      builder: (context, snapshot) {
        final color = !snapshot.hasData
            ? Colors.grey
            : snapshot.data!.asBool
                ? Colors.red
                : Colors.green;
        return Transform.rotate(
          angle: (config.coordinates.angle ?? 0.0) * pi / 180,
          child: CustomPaint(
            painter: GatePainter(color: color),
          ),
        );
      },
    );
  }
}

class GatePainter extends CustomPainter {
  final Color color;
  GatePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final double circleRadius = size.width * 0.25;
    final double topCenterY = size.height * 0.15;
    final double bottomCenterY = size.height * 0.85;

    // Draw top bubble
    canvas.drawCircle(Offset(size.width / 2, topCenterY), circleRadius, paint);
    // Draw bottom bubble
    canvas.drawCircle(Offset(size.width / 2, bottomCenterY), circleRadius, paint);

    // Draw line: start/end inside the circles
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.15
      ..strokeCap = StrokeCap.round;

    // Start a bit inside the top circle, end a bit inside the bottom circle
    final double lineStartY = topCenterY + circleRadius * 0.2;
    final double lineEndY = bottomCenterY - circleRadius * 0.2;

    canvas.drawLine(
      Offset(size.width / 2, lineStartY),
      Offset(size.width / 2, lineEndY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(GatePainter oldDelegate) => color != oldDelegate.color;
}
