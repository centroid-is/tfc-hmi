import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';
import 'common.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import '../../providers/state_man.dart';
import '../../core/state_man.dart';
import 'package:rxdart/rxdart.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' as intl;

part 'conveyor.g.dart';

@JsonSerializable(explicitToJson: true)
class ConveyorConfig extends BaseAsset {
  String key;
  String? batchesKey;
  bool? simulateBatches;

  ConveyorConfig({required this.key, this.batchesKey, this.simulateBatches});

  static const previewStr = 'Conveyor Preview';

  ConveyorConfig.preview() : key = previewStr;

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
        ),
        const SizedBox(height: 8),
        KeyField(
          initialValue: widget.config.batchesKey,
          onChanged: (val) => setState(() => widget.config.batchesKey = val),
          label: 'Batches key',
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
  final Map<String, Batch> _batches = {};
  // periodic timer for batches
  Timer? _simulateBatchesTimer;

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

  Color _getConveyorColor(dynamic dynValue) {
    try {
      if (dynValue['p_stat_Error'].asBool) {
        return Colors.red;
      }

      if (dynValue['p_stat_Frequency'].asInt != 0) {
        return Colors.green;
      }
      return Colors.blue;
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
          _buildConveyorVisual(context, Colors.grey),
          const SizedBox(width: 12), // spacing between box and text
          const Text('Conveyor preview'),
        ],
      );
    }
    return StreamBuilder<Map<String, DynamicValue>>(
      stream: ref.watch(stateManProvider.future).asStream().asyncExpand(
            (stateMan) => CombineLatestStream(
              [
                stateMan
                    .subscribe(widget.config.key)
                    .asStream()
                    .switchMap((s) => s),
                if (widget.config.batchesKey != null)
                  stateMan
                      .subscribe(widget.config.batchesKey!)
                      .asStream()
                      .switchMap((s) => s),
              ],
              (List<DynamicValue> values) => {
                'drive': values[0],
                if (widget.config.batchesKey != null) 'batches': values[1],
              },
            ),
          ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _log.e(
            'Error fetching dynamic value for ${widget.config.key}, error: ${snapshot.error}',
          );
          return _buildConveyorVisual(context, Colors.grey, true);
        }
        if (!snapshot.hasData) {
          return _buildConveyorVisual(context, Colors.grey, true);
        }
        // _log.d('Dynamic value for ${widget.config.key}: ${snapshot.data}');
        final dynValue = snapshot.data!;
        final color = _getConveyorColor(dynValue['drive']);

        if (widget.config.simulateBatches ?? false) {
          _startSimulateBatchesTimer();
        } else {
          _stopSimulateBatchesTimer();
        }

        if (snapshot.data!['batches'] != null) {
          _updateBatches(snapshot.data!['batches']!);
        }

        return GestureDetector(
          onTap: () => _showDetailsDialog(context),
          child: _buildConveyorVisual(context, color),
        );
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
  ]) {
    return Align(
      alignment: FractionalOffset(
        widget.config.coordinates.x,
        widget.config.coordinates.y,
      ),
      child: Transform.rotate(
        angle: (widget.config.coordinates.angle ?? 0.0) * pi / 180,
        child: CustomPaint(
          size: widget.config.size.toSize(MediaQuery.of(context).size),
          painter: _ConveyorPainter(
            color: color,
            showExclamation: showExclamation ?? false,
            batches: _batches,
            angle: widget.config.coordinates.angle ?? 0.0,
          ),
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
                              await stateMan.write(
                                widget.config.key,
                                dynValue,
                              );
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
                            size: 48,
                          ),
                        ),
                        Text(
                          'Jog',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                        RawMaterialButton(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(8),
                          onHighlightChanged: (isPressed) async {
                            if (dynValue['p_stat_ManualStopOnRelease'].asBool) {
                              dynValue['p_cmd_JogFwd'] = isPressed;
                              await stateMan.write(
                                widget.config.key,
                                dynValue,
                              );
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
                            size: 48,
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
                          size: 48,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Fault reset',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
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
                          size: 48,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Manual stop on release',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
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
                          size: 48,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Reset run hours',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Statistics columns
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Labels
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HMIS',
                              style: Theme.of(context).textTheme.bodyLarge),
                          Text('Last Fault',
                              style: Theme.of(context).textTheme.bodyLarge),
                          Text('Frequency',
                              style: Theme.of(context).textTheme.bodyLarge),
                          Text('Run hours',
                              style: Theme.of(context).textTheme.bodyLarge),
                          Text('Current',
                              style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                      // Values
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(dynValue['p_stat_State'].toString(),
                              style: Theme.of(context).textTheme.bodyLarge),
                          Text(dynValue['p_stat_LastFault'].toString(),
                              style: Theme.of(context).textTheme.bodyLarge),
                          Text(
                              "${dynValue['p_stat_Frequency'].asDouble.toStringAsFixed(2)} Hz",
                              style: Theme.of(context).textTheme.bodyLarge),
                          Text(
                            "${dynValue['p_stat_RunMinutes'].asInt ~/ 60}:${dynValue['p_stat_RunMinutes'].asInt % 60} h:m",
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          Text(
                              "${dynValue['p_stat_Current'].asDouble.toStringAsFixed(2)} A",
                              style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                      // Editable fields
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 200,
                              child: TextFormField(
                                key: Key(
                                    'auto_freq_field-${dynValue['p_cfg_AutoFreq'].asString}'),
                                initialValue: dynValue['p_cfg_AutoFreq']
                                    .asDouble
                                    .toStringAsFixed(2),
                                decoration: const InputDecoration(
                                    labelText: 'Auto frequency',
                                    suffixText: 'Hz',
                                    suffixIcon: null),
                                onFieldSubmitted: (value) {
                                  if (value.isEmpty) {
                                    return;
                                  }
                                  dynValue['p_cfg_AutoFreq'] =
                                      double.parse(value);
                                  stateMan.write(widget.config.key, dynValue);
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 200,
                              child: TextFormField(
                                key: Key(
                                    'cleaning_freq_field-${dynValue['p_cfg_CleaningFreq'].asString}'),
                                initialValue: dynValue['p_cfg_CleaningFreq']
                                    .asDouble
                                    .toStringAsFixed(2),
                                decoration: const InputDecoration(
                                    labelText: 'Cleaning frequency',
                                    suffixText: 'Hz',
                                    suffixIcon: null),
                                onFieldSubmitted: (value) {
                                  if (value.isEmpty) {
                                    return;
                                  }
                                  dynValue['p_cfg_CleaningFreq'] =
                                      double.parse(value);
                                  stateMan.write(widget.config.key, dynValue);
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: 200,
                              child: TextFormField(
                                key: Key(
                                    'manual_freq_field-${dynValue['p_cfg_ManualFreq'].asString}'),
                                initialValue: dynValue['p_cfg_ManualFreq']
                                    .asDouble
                                    .toStringAsFixed(2),
                                decoration: const InputDecoration(
                                  labelText: 'Manual frequency',
                                  suffixText: 'Hz',
                                  suffixIcon: null,
                                ),
                                onFieldSubmitted: (value) {
                                  if (value.isEmpty) {
                                    return;
                                  }
                                  dynValue['p_cfg_ManualFreq'] =
                                      double.parse(value);
                                  stateMan.write(widget.config.key, dynValue);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Graph
                  SizedBox(
                    width: MediaQuery.of(context).size.width * 0.3,
                    height: MediaQuery.of(context).size.height * 0.3,
                    child: ConveyorStatsGraph(
                      stateMan: stateMan,
                      keyName: widget.config.key,
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

class Batch {
  double start; // 0…1 (can be <0 while entering)
  double end; // 0…1 (can be >1 while exiting)
  Color color;

  Batch({required this.start, required this.end, this.color = Colors.white});
}

class _ConveyorPainter extends CustomPainter {
  final Map<String, Batch> batches;
  final Color color;
  final bool showExclamation;
  final double angle;

  _ConveyorPainter(
      {required this.color,
      this.showExclamation = false,
      required this.batches,
      required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
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
      canvas.save();
      // Move origin to center of conveyor
      canvas.translate(size.width / 2, size.height / 2);
      // Counter-rotate
      canvas.rotate(-angle * pi / 180);
      // Draw exclamation mark centered at (0,0)
      final textPainter = TextPainter(
        text: TextSpan(
          text: '!',
          style: TextStyle(
            color: Colors.white,
            fontSize: size.shortestSide * 0.7,
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
  }

  @override
  bool shouldRepaint(covariant _ConveyorPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.showExclamation != showExclamation;
}

class ConveyorStatsGraph extends StatefulWidget {
  final StateMan stateMan;
  final String keyName;
  const ConveyorStatsGraph({
    required this.stateMan,
    required this.keyName,
    super.key,
  });

  @override
  State<ConveyorStatsGraph> createState() => _ConveyorStatsGraphState();
}

class _ConveyorStatsGraphState extends State<ConveyorStatsGraph> {
  @override
  void initState() {
    super.initState();
    widget.stateMan.collect(widget.keyName, 100);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    return StreamBuilder<List<CollectedSample>>(
      stream: widget.stateMan.collectStream(widget.keyName),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No data'));
        }
        final samples = snapshot.data!;
        final currentSpots = <FlSpot>[];
        final freqSpots = <FlSpot>[];
        final minTime = samples.first.time.millisecondsSinceEpoch.toDouble();
        final maxTime = samples.last.time.millisecondsSinceEpoch.toDouble();
        for (final sample in samples) {
          final v = sample.value;
          final current = v['p_stat_Current']?.asDouble ?? 0.0;
          final freq = v['p_stat_Frequency']?.asDouble ?? 0.0;
          final time = sample.time.millisecondsSinceEpoch.toDouble();
          currentSpots.add(FlSpot(time, current));
          freqSpots.add(FlSpot(time, freq));
        }

        // Find min/max for axes
        double minCurrent = currentSpots
            .map((e) => e.y)
            .fold<double>(double.infinity, (a, b) => a < b ? a : b);
        double maxCurrent = currentSpots
            .map((e) => e.y)
            .fold<double>(-double.infinity, (a, b) => a > b ? a : b);
        double minFreq = freqSpots
            .map((e) => e.y)
            .fold<double>(double.infinity, (a, b) => a < b ? a : b);
        double maxFreq = freqSpots
            .map((e) => e.y)
            .fold<double>(-double.infinity, (a, b) => a > b ? a : b);

        // Add some padding
        minCurrent = minCurrent.isFinite ? minCurrent : 0;
        maxCurrent = maxCurrent.isFinite ? maxCurrent : 1;
        minFreq = minFreq.isFinite ? minFreq : 0;
        maxFreq = maxFreq.isFinite ? maxFreq : 1;

        // For dual axes, fl_chart uses yAxis for each LineChartBarData (0=left, 1=right)
        return Padding(
          padding: const EdgeInsets.all(0),
          child: SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                // These are for the default (left) axis, but we set min/max for both axes below
                minY: minCurrent < minFreq ? minCurrent : minFreq,
                maxY: maxCurrent > maxFreq ? maxCurrent : maxFreq,
                lineBarsData: [
                  // Current (primary color, left axis)
                  LineChartBarData(
                    spots: currentSpots,
                    isCurved: false,
                    color: primary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                    //yAxis: 0,
                  ),
                  // Frequency (secondary color, right axis)
                  LineChartBarData(
                    spots: freqSpots,
                    isCurved: false,
                    color: secondary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                    //yAxis: 1,
                  ),
                ],
                lineTouchData: const LineTouchData(enabled: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        'Current (A)',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(1),
                        style: TextStyle(color: primary, fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: AxisTitles(
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        'Frequency (Hz)',
                        style: TextStyle(
                          color: secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(1),
                        style: TextStyle(color: secondary, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text('Time'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: ((maxTime - minTime) / 4).clamp(
                        1,
                        double.infinity,
                      ),
                      getTitlesWidget: (value, meta) {
                        final dt = DateTime.fromMillisecondsSinceEpoch(
                          value.toInt(),
                        );
                        final formatted = intl.DateFormat.Hms().format(dt);
                        return Text(
                          formatted,
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: true),
                //minYForEachAxis: [minCurrent, minFreq],
                //maxYForEachAxis: [maxCurrent, maxFreq],
              ),
            ),
          ),
        );
      },
    );
  }
}
