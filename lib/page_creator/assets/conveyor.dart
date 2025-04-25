import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import 'common.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import '../../providers/state_man.dart';

part 'conveyor.g.dart';

@JsonSerializable(explicitToJson: true)
class ConveyorConfig extends BaseAsset {
  String key;
  @JsonKey(name: 'angle')
  double angle;

  ConveyorConfig({
    required this.key,
    this.angle = 0.0,
  });

  ConveyorConfig.preview()
      : key = 'Conveyor Preview',
        angle = 0.0;

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

  factory ConveyorConfig.fromJson(Map<String, dynamic> json) => _$ConveyorConfigFromJson(json);
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
        TextFormField(
          initialValue: widget.config.key,
          decoration: const InputDecoration(labelText: 'Key'),
          onChanged: (val) => setState(() => widget.config.key = val),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Width (%):'),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: (widget.config.size.width * 100).toStringAsFixed(2),
                decoration: const InputDecoration(suffixText: '%', isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) {
                  final pct = double.tryParse(val) ?? 0.0;
                  if (pct >= 0.01 && pct <= 100) {
                    setState(() {
                      widget.config.size = RelativeSize(
                        width: pct / 100,
                        height: widget.config.size.height,
                      );
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Height (%):'),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: (widget.config.size.height * 100).toStringAsFixed(2),
                decoration: const InputDecoration(suffixText: '%', isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) {
                  final pct = double.tryParse(val) ?? 0.0;
                  if (pct >= 0.01 && pct <= 100) {
                    setState(() {
                      widget.config.size = RelativeSize(
                        width: widget.config.size.width,
                        height: pct / 100,
                      );
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Angle (°):'),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: widget.config.angle.toStringAsFixed(0),
                decoration: const InputDecoration(suffixText: '°', isDense: true),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  final deg = double.tryParse(value) ?? 0.0;
                  setState(() {
                    widget.config.angle = deg;
                  });
                },
              ),
            ),
          ],
        ),
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

class _ConveyorState extends ConsumerState<Conveyor> {
  static final _log = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 2,
      lineLength: 80,
      colors: true,
      printEmojis: false,
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Placeholder: future data fetch or subscription
    return GestureDetector(
      onTap: () => _showDetailsDialog(context),
      child: Align(
        alignment: FractionalOffset(
            widget.config.coordinates.x, widget.config.coordinates.y),
        child: Transform.rotate(
          angle: widget.config.angle * pi / 180,
          child: CustomPaint(
            size: widget.config.size.toSize(MediaQuery.of(context).size),
            painter: _ConveyorPainter(),
          ),
        ),
      ),
    );
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Conveyor: ${widget.config.key}'),
        content: const Text('Batch details will be shown here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ConveyorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);

    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
