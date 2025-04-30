import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import 'common.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import '../../providers/state_man.dart';
import '../../page_creator/client.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

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

  static const previewStr = 'Conveyor Preview';

  ConveyorConfig.preview()
      : key = previewStr,
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
                initialValue:
                    (widget.config.size.width * 100).toStringAsFixed(2),
                decoration:
                    const InputDecoration(suffixText: '%', isDense: true),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                initialValue:
                    (widget.config.size.height * 100).toStringAsFixed(2),
                decoration:
                    const InputDecoration(suffixText: '%', isDense: true),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                decoration:
                    const InputDecoration(suffixText: '°', isDense: true),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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

  Color _getConveyorColor(dynamic dynValue) {
    try {
      if (dynValue['p_stat_Frequency'].asInt != 0) {
        return Colors.green;
      }
      final state = dynValue['p_stat_State'].asString;
      if (state.contains('RDY') ||
          state.contains('NST') ||
          state.contains('RUN') ||
          state.contains('ACC') ||
          state.contains('DEC')) {
        return Colors.blue;
      }
      return Colors.red;
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.key == ConveyorConfig.previewStr) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildConveyorVisual(Colors.grey, context),
          const SizedBox(width: 12), // spacing between box and text
          const Text('Conveyor preview'),
        ],
      );
    }
    return StreamBuilder<DynamicValue>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
          (stateMan) => stateMan
              .subscribe(widget.config.key)
              .asStream()
              .switchMap((s) => s)),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _log.e('Error fetching dynamic value for ${widget.config.key}',
              error: snapshot.error);
        }
        _log.d('Dynamic value for ${widget.config.key}: ${snapshot.data}');
        final dynValue = snapshot.data;
        final color =
            dynValue != null ? _getConveyorColor(dynValue) : Colors.grey;

        return GestureDetector(
          onTap: () => _showDetailsDialog(context),
          child: _buildConveyorVisual(color, context),
        );
      },
    );
  }

  Widget _buildConveyorVisual(Color color, BuildContext context) {
    return Align(
      alignment: FractionalOffset(
          widget.config.coordinates.x, widget.config.coordinates.y),
      child: Transform.rotate(
        angle: widget.config.angle * pi / 180,
        child: CustomPaint(
          size: widget.config.size.toSize(MediaQuery.of(context).size),
          painter: _ConveyorPainter(color: color),
        ),
      ),
    );
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => StreamBuilder<(StateMan, DynamicValue)>(
        stream: ref.watch(stateManProvider.future).asStream().switchMap(
            (stateMan) => stateMan
                .subscribe(widget.config.key)
                .asStream()
                .map((stream) => Rx.combineLatest2(Stream.value(stateMan),
                    stream, (stateMan, value) => (stateMan, value)))
                .switchMap((stream) => stream)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return AlertDialog(
              title: const Text('Error'),
              content: Text(snapshot.error.toString()),
            );
          }

          var (stateMan, dynValue) = snapshot.data!;

          return AlertDialog(
            title: Text(widget.config.key),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status header
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RawMaterialButton(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(8),
                          onHighlightChanged: (isPressed) async {
                            if (dynValue['p_stat_ManualStopOnRelease'].asBool) {
                              dynValue['p_cmd_JogBwd'] = isPressed;
                              await stateMan.write(widget.config.key, dynValue);
                            }
                          },
                          onPressed: () {
                            if (!dynValue['p_stat_ManualStopOnRelease']
                                .asBool) {
                              dynValue['p_cmd_JogBwd'] = true;
                              stateMan.write(widget.config.key, dynValue);
                            }
                          },
                          child: Icon(
                            Icons.arrow_back,
                            color: dynValue['p_stat_JogBwd'].asBool
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                        const Text('Manual'),
                        RawMaterialButton(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(8),
                          onHighlightChanged: (isPressed) async {
                            if (dynValue['p_stat_ManualStopOnRelease'].asBool) {
                              dynValue['p_cmd_JogFwd'] = isPressed;
                              await stateMan.write(widget.config.key, dynValue);
                            }
                          },
                          onPressed: () {
                            if (!dynValue['p_stat_ManualStopOnRelease']
                                .asBool) {
                              dynValue['p_cmd_JogFwd'] = true;
                              stateMan.write(widget.config.key, dynValue);
                            }
                          },
                          child: Icon(
                            Icons.arrow_forward,
                            color: dynValue['p_stat_JogFwd'].asBool
                                ? Colors.green
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Fault reset toggle
                  Row(
                    children: [
                      RawMaterialButton(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(8),
                        onPressed: () {
                          dynValue['p_cmd_FaultReset'] = true;
                          stateMan.write(widget.config.key, dynValue);
                        },
                        child: Icon(
                          Icons.circle,
                          color: dynValue['p_stat_FaultReset'].asBool
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('Fault reset'),
                    ],
                  ),

                  // Manual stop on release toggle
                  Row(
                    children: [
                      RawMaterialButton(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(8),
                        onPressed: () {
                          dynValue['p_cmd_ManualStopOnRelease'] = true;
                          stateMan.write(widget.config.key, dynValue);
                        },
                        child: Icon(
                          Icons.circle,
                          color: dynValue['p_stat_ManualStopOnRelease'].asBool
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('Manual stop on release'),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Reset run hours
                  Row(
                    children: [
                      RawMaterialButton(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(8),
                        onPressed: () {
                          dynValue['p_cmd_ResetRunHours'] = true;
                          stateMan.write(widget.config.key, dynValue);
                        },
                        child: const Icon(
                          Icons.circle,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('Reset run hours'),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Statistics columns
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HMIS'),
                          Text('Last Fault'),
                          Text('Frequency'),
                          Text('Run hours'),
                          Text('Current'),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(dynValue['p_stat_State'].asString),
                          Text(dynValue['p_stat_LastFault'].asString),
                          Text(dynValue['p_stat_Frequency'].asString),
                          Text(
                            Duration(
                              minutes: dynValue['p_stat_RunMinutes'].asInt,
                            ).toString(),
                          ),
                          Text(dynValue['p_stat_Current'].asString),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Graph placeholder
                  SizedBox(
                    width: double.infinity,
                    height: 120,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black54),
                      ),
                      child: const Center(child: Text('Graph view')),
                    ),
                  ),
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
      ),
    );
  }
}

class _ConveyorPainter extends CustomPainter {
  final Color color;
  _ConveyorPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final borderRadius =
        Radius.circular(size.shortestSide * 0.2); // 20% of the shortest side
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
  }

  @override
  bool shouldRepaint(covariant _ConveyorPainter oldDelegate) =>
      oldDelegate.color != color;
}
