import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:cristalyse/cristalyse.dart' as cs;
import 'package:tfc_dart/core/database.dart';

import 'graph.dart';
import '../providers/collector.dart';
import '../models/history_models.dart';

// -----------------------------------------------------------------------------
// Graph pane (realtime or range) – uses collectorProvider for history
// -----------------------------------------------------------------------------
class HistoryGraphPane extends ConsumerStatefulWidget {
  final List<String> keys;
  final bool realtime;
  final DateTimeRange? range;
  final Duration realtimeDuration;
  final Map<String, GraphKeyConfig> graphConfigs;
  final Map<int, GraphDisplayConfig> graphDisplayConfigs;
  final void Function(int graphIndex)? onEditGraph;
  final void Function(int graphIndex)? onSelectGraph;
  final void Function(int fromIndex, int toIndex)? onSwapGraphs;
  final int targetGraphIndex;

  const HistoryGraphPane({
    super.key,
    required this.keys,
    required this.realtime,
    required this.range,
    required this.realtimeDuration,
    required this.graphConfigs,
    required this.graphDisplayConfigs,
    this.onEditGraph,
    this.onSelectGraph,
    this.onSwapGraphs,
    this.targetGraphIndex = 0,
  });

  @override
  ConsumerState<HistoryGraphPane> createState() => _HistoryGraphPaneState();
}

class _HistoryGraphPaneState extends ConsumerState<HistoryGraphPane> {
  bool _paused = false;
  DateTime? _pausedAt;
  List<List<dynamic>>? _pausedData;
  cs.ChartTheme? _chartTheme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // todo this does not work properly
    _chartTheme = ref.watch(chartThemeNotifierProvider);
  }

  @override
  Widget build(BuildContext context) {
    final collectorAsync = ref.watch(collectorProvider);

    return collectorAsync.when(
      data: (collector) {
        if (collector == null) {
          return const Center(child: Text('No collector available'));
        }
        if (widget.keys.isEmpty) {
          return const Center(child: Text('Select keys to view history'));
        }

        Duration since;
        DateTimeRange? fetchRange;

        if (widget.realtime) {
          since = widget.realtimeDuration;
        } else {
          if (widget.range == null) {
            return const Center(child: Text('Pick a start & end date'));
          }
          since = DateTime.now().difference(widget.range!.start);

          final rangeDuration =
              widget.range!.end.difference(widget.range!.start);
          final extension = Duration(
            milliseconds: (rangeDuration.inMilliseconds * 0.5).round(),
          );

          fetchRange = DateTimeRange(
            start: widget.range!.start.subtract(extension),
            end: widget.range!.end.add(extension),
          );
        }

        final streams = widget.keys.map((k) {
          if (widget.realtime) {
            // Combine a DB backfill query (full window) with the live stream.
            // collectStream caches internally, so if the user increases the
            // window the cached stream won't have older data. The DB query
            // fills in the gap.
            final liveStream = collector.collectStream(k, since: since);
            final cutoff = DateTime.now().toUtc().subtract(since);
            final dbStream = Stream.fromFuture(
              collector.database.queryTimeseriesData(
                  k, DateTime.now().toUtc(),
                  from: cutoff),
            );
            return Rx.combineLatest2<List<TimeseriesData<dynamic>>,
                List<TimeseriesData<dynamic>>, List<dynamic>>(
              dbStream,
              liveStream,
              (dbData, liveData) {
                final merged = <int, TimeseriesData<dynamic>>{};
                for (final d in dbData) {
                  merged[d.time.millisecondsSinceEpoch] = d;
                }
                for (final d in liveData) {
                  merged[d.time.millisecondsSinceEpoch] = d;
                }
                final result = merged.values.toList()
                  ..sort((a, b) => a.time.compareTo(b.time));
                return result;
              },
            );
          } else {
            return Stream.fromFuture(collector.database.queryTimeseriesData(
                k, fetchRange!.end,
                from: fetchRange!.start));
          }
        }).toList();

        return StreamBuilder<List<List<dynamic>>>(
          stream: _paused ? null : Rx.combineLatestList(streams),
          builder: (context, snap) {
            List<List<dynamic>> data;
            if (_paused && _pausedData != null) {
              data = _pausedData!;
            } else if (snap.hasData) {
              data = snap.data!;
              _pausedData = data;
            } else {
              return const Center(child: CircularProgressIndicator());
            }

            // Group data by graph index
            final Map<int, List<Map<GraphDataConfig, List<List<double>>>>>
                graphDataByIndex = {};

            for (int i = 0;
                i < math.min(widget.keys.length, data.length);
                i++) {
              final seriesKey = widget.keys[i];
              final seriesData = data[i];
              final config = widget.graphConfigs[seriesKey];

              if (config == null) continue;

              final points = <List<double>>[];

              for (final sample in seriesData) {
                final value = sample.value;
                final time = sample.time.millisecondsSinceEpoch.toDouble();
                double? y;
                if (value is num) {
                  y = value.toDouble();
                } else if (value is Map && value['value'] is num) {
                  y = (value['value'] as num).toDouble();
                } else if (value is bool) {
                  y = value ? 1.0 : 0.0;
                }
                if (y != null) {
                  if (value is bool) {
                    points.add([time, !value ? 1.0 : 0.0]);
                  }
                  points.add([time, y]);
                }
              }

              final graphData = {
                GraphDataConfig(
                  label: config.alias,
                  mainAxis: !config.useSecondYAxis,
                  color: GraphConfig.colors[i % GraphConfig.colors.length],
                ): points,
              };

              graphDataByIndex
                  .putIfAbsent(config.graphIndex, () => [])
                  .add(graphData);
            }

            final Duration xSpan = widget.realtime
                ? widget.realtimeDuration
                : (widget.range != null
                    ? widget.range!.end.difference(widget.range!.start)
                    : const Duration(minutes: 10));

            // Include the target graph index so an empty placeholder appears
            final usedGraphIndices = <int>{
              ...graphDataByIndex.keys,
              widget.targetGraphIndex,
            }.toList()
              ..sort();

            return Stack(
              children: [
                Column(
                  children: [
                    ...usedGraphIndices.map((graphIndex) {
                      final graphData = graphDataByIndex[graphIndex] ?? [];
                      final graphDisplayConfig =
                          widget.graphDisplayConfigs[graphIndex];
                      final isTarget =
                          graphIndex == widget.targetGraphIndex;

                      return Expanded(
                        child: DragTarget<int>(
                          onWillAcceptWithDetails: (details) =>
                              details.data != graphIndex,
                          onAcceptWithDetails: (details) {
                            widget.onSwapGraphs
                                ?.call(details.data, graphIndex);
                          },
                          builder: (context, candidateData, _) {
                            final isDropTarget = candidateData.isNotEmpty;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isDropTarget
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withAlpha(200)
                                      : isTarget
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withAlpha(120)
                                          : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Stack(
                                children: [
                                  // Graph content
                                  graphData.isEmpty
                                      ? Center(
                                          child: Text(
                                            'Select keys in the left pane to display on this graph',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontSize: 13,
                                            ),
                                          ),
                                        )
                                      : Builder(
                                          builder: (context) {
                                            return _buildGraph(
                                              context,
                                              graphData,
                                              graphDisplayConfig,
                                              xSpan,
                                            );
                                          },
                                        ),
                                  // Overlay: label on top, drag + edit below
                                  Positioned(
                                    top: 4,
                                    left: 4,
                                    child: _buildGraphOverlay(
                                      context,
                                      graphIndex: graphIndex,
                                      label: graphDisplayConfig?.displayName ??
                                          'Graph ${graphIndex + 1}',
                                      isTarget: isTarget,
                                      showDrag:
                                          usedGraphIndices.length > 1 &&
                                              widget.onSwapGraphs != null,
                                      showEdit:
                                          widget.onEditGraph != null,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
                // Pause/resume overlay
                if (widget.realtime && _paused)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _paused = false;
                            _pausedAt = null;
                            _pausedData = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  size: 20),
                              const SizedBox(width: 4),
                              Text(
                                'Resume',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.realtime && _paused && _pausedAt != null)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Card(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withAlpha(200),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Text(
                          'Paused at ${_pausedAt!.toString().substring(11, 19)}',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildGraphOverlay(
    BuildContext context, {
    required int graphIndex,
    required String label,
    required bool isTarget,
    required bool showDrag,
    required bool showEdit,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = isTarget
        ? cs.primaryContainer.withAlpha(220)
        : cs.surfaceContainerHighest.withAlpha(180);
    final fgColor = isTarget ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Graph N label (select button)
          Material(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => widget.onSelectGraph?.call(graphIndex),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isTarget ? FontWeight.bold : FontWeight.normal,
                    color: fgColor,
                  ),
                ),
              ),
            ),
          ),
          // Drag handle + settings row
          if (showDrag || showEdit) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                if (showDrag)
                  Expanded(
                    child: Draggable<int>(
                      data: graphIndex,
                      feedback: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(4),
                        color: cs.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      childWhenDragging: Material(
                        color: cs.surfaceContainerHighest.withAlpha(100),
                        borderRadius: BorderRadius.circular(4),
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.drag_indicator,
                                size: 14, color: Colors.grey),
                          ),
                        ),
                      ),
                      child: Material(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(Icons.drag_indicator,
                                size: 14, color: fgColor),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showDrag && showEdit) const SizedBox(width: 2),
                if (showEdit)
                  Expanded(
                    child: Material(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => widget.onEditGraph!(graphIndex),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(Icons.settings,
                                size: 14, color: fgColor),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGraph(
    BuildContext context,
    List<Map<GraphDataConfig, List<List<double>>>> graphData,
    GraphDisplayConfig? displayCfg,
    Duration xSpan,
  ) {
    final flattened = <Map<String, dynamic>>[];
    for (final seriesMap in graphData) {
      final entry = seriesMap.entries.first;
      final gdc = entry.key;
      final pts = entry.value;
      final axisKey = gdc.mainAxis ? 'y' : 'y2';
      for (final p in pts) {
        if (p.length < 2) continue;
        flattened.add({
          'x': p[0],
          axisKey: p[1],
          's': gdc.label,
        });
      }
    }

    final cfg = GraphConfig(
      type: GraphType.timeseries,
      xAxis: const GraphAxisConfig(unit: ''),
      yAxis: GraphAxisConfig(
        unit: displayCfg?.yAxisUnit ?? '',
        title: (displayCfg?.yAxisUnit ?? '').isNotEmpty
            ? displayCfg!.yAxisUnit
            : 'Y',
      ),
      yAxis2: (displayCfg?.yAxis2Unit != null &&
              displayCfg!.yAxis2Unit!.isNotEmpty)
          ? GraphAxisConfig(
              unit: displayCfg.yAxis2Unit!,
              title: displayCfg.yAxis2Unit,
            )
          : graphData.any((m) => m.keys.any((k) => !k.mainAxis))
              ? const GraphAxisConfig(unit: '', title: 'Y2')
              : null,
      xSpan: widget.realtime ? xSpan : null,
      xRange: widget.realtime ? null : widget.range,
      pan: false,
    );

    final graph = Graph(
      chartTheme: _chartTheme,
      config: cfg,
      data: flattened,
      onPanStart: (_) {},
      onPanUpdate: (_) {},
      onPanEnd: (_) {},
      onNowPressed: () {},
      onSetDatePressed: () {},
      redraw: () {
        if (mounted) setState(() {});
      },
      showButtons: false,
    );

    graph.theme(ref.watch(chartThemeNotifierProvider));
    return graph.build(context);
  }
}
