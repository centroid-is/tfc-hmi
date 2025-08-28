// TRIGGER

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../widgets/base_scaffold.dart';
import '../widgets/graph.dart'; // Graph, GraphConfig, GraphDataConfig, GraphAxisConfig, GraphType

import '../providers/state_man.dart'; // stateManProvider
import '../providers/collector.dart'; // collectorProvider
import '../providers/database.dart'; // databaseProvider (Future<Database?>)
import '../providers/preferences.dart'; // preferencesProvider

import '../core/state_man.dart'; // KeyMappingEntry, KeyMappings
import '../core/database.dart'; // TimeseriesData, Database wrapper class

// Use the dialog from your "common" assets
import '../page_creator/assets/common.dart' show KeyMappingEntryDialog;

// -----------------------------------------------------------------------------
// Keys from StateMan (uses sm.keys)
// -----------------------------------------------------------------------------
final stateKeysProvider = FutureProvider<List<String>>((ref) async {
  final sm = await ref.watch(stateManProvider.future);
  final keys = List<String>.from(sm.keys);
  keys.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return keys;
});

// -----------------------------------------------------------------------------
// Collected keys (based on key_mappings.collect != null)
// -----------------------------------------------------------------------------
final collectedKeysProvider = FutureProvider<Set<String>>((ref) async {
  final sm = await ref.watch(stateManProvider.future);
  final set = <String>{};
  for (final e in sm.keyMappings.nodes.entries) {
    if (e.value.collect != null) set.add(e.key);
  }
  return set;
});

// Quick check if a key is "collected" (has collect config)
final isKeyCollectedProvider =
    FutureProvider.family<bool, String>((ref, key) async {
  final ks = await ref.watch(collectedKeysProvider.future);
  return ks.contains(key);
});

// -----------------------------------------------------------------------------
// Saved Views (DB) - uses your AppDatabase helpers
// -----------------------------------------------------------------------------
class SavedHistoryView {
  final int id;
  final String name;
  final List<String> keys;
  SavedHistoryView({required this.id, required this.name, required this.keys});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SavedHistoryView && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

final savedViewsProvider = FutureProvider<List<SavedHistoryView>>((ref) async {
  final dbWrap = await ref.watch(databaseProvider.future);
  if (dbWrap == null) return [];
  final adb = dbWrap.db;
  final rows = await adb.selectHistoryViews();
  final out = <SavedHistoryView>[];
  for (final v in rows) {
    final keys =
        await adb.getHistoryViewKeyNames(v.id); // Use the key names method
    out.add(SavedHistoryView(id: v.id, name: v.name, keys: keys));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
});

// -----------------------------------------------------------------------------
// Collector toggle (enable/disable collection for a key)
// -----------------------------------------------------------------------------
class _CollectorToggle extends ConsumerWidget {
  final String keyName;
  const _CollectorToggle({required this.keyName, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCollectedAsync = ref.watch(isKeyCollectedProvider(keyName));
    return isCollectedAsync.when(
      data: (isOn) {
        return IconButton(
          tooltip: isOn ? 'Disable collection' : 'Enable collection',
          icon: Icon(
            isOn ? Icons.power_settings_new : Icons.power_settings_new_outlined,
            color: isOn
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).iconTheme.color,
          ),
          onPressed: () => _toggle(context, ref, isOn),
        );
      },
      loading: () => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (e, _) => const IconButton(
        tooltip: 'Collector',
        icon: Icon(Icons.error_outline),
        onPressed: null,
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool isOn) async {
    final sm = await ref.read(stateManProvider.future);
    final prefs = await ref.read(preferencesProvider.future);
    final km = sm.keyMappings;
    final entry = km.nodes[keyName];

    // Helper to persist key mappings and refresh providers
    Future<void> persist(KeyMappings updated) async {
      await prefs.setString('key_mappings', jsonEncode(updated.toJson()));
      ref.invalidate(stateManProvider);
      ref.invalidate(collectedKeysProvider);
    }

    if (!isOn) {
      // Enable: if no collect config, open dialog to create one
      if (entry?.collect == null) {
        if (!context.mounted) return;
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => KeyMappingEntryDialog(
            initialKey: keyName,
            initialKeyMappingEntry: entry,
          ),
        );
        if (result == null) return;

        final newKey = result['key'] as String;
        final newEntry = result['entry'] as KeyMappingEntry;

        if (newKey != keyName) {
          // if renamed, move mapping
          km.nodes.remove(keyName);
        }
        km.nodes[newKey] = newEntry;
        await persist(km);

        // Start foreground collection as well (optional UX nicety)
        try {
          final collector = await ref.read(collectorProvider.future);
          if (collector != null && newEntry.collect != null) {
            await collector.collectEntry(newEntry.collect!);
          }
        } catch (_) {}

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Collect enabled on "$newKey"')));
        }
      } else {
        // Already has collect config but was deemed "off": try to start foreground collection
        try {
          final collector = await ref.read(collectorProvider.future);
          if (collector != null && entry!.collect != null) {
            await collector.collectEntry(entry.collect!);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Collect enabled on "$keyName"')));
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Failed: $e')));
          }
        }
      }
    } else {
      // Disable: confirm; stop foreground collection and remove collect config
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Disable collection?'),
              content: Text(
                  'This will remove the collection settings for "$keyName".'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Disable')),
              ],
            ),
          ) ??
          false;
      if (!ok) return;

      try {
        final collector = await ref.read(collectorProvider.future);
        if (collector != null && entry?.collect != null) {
          collector.stopCollect(entry!.collect!);
        }
      } catch (_) {}

      if (entry != null) {
        km.nodes[keyName] =
            KeyMappingEntry(opcuaNode: entry.opcuaNode, collect: null)
              ..io = entry.io;
        await persist(km);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Collect disabled on "$keyName"')));
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Graph pane (realtime or range) – uses collectorProvider for history
// -----------------------------------------------------------------------------
class _HistoryGraphPane extends ConsumerStatefulWidget {
  final List<String> keys;
  final bool realtime;
  final DateTimeRange? range;
  final Map<String, GraphKeyConfig> graphConfigs; // Add this parameter

  const _HistoryGraphPane({
    required this.keys,
    required this.realtime,
    required this.range,
    required this.graphConfigs, // Add this parameter
  });

  @override
  ConsumerState<_HistoryGraphPane> createState() => _HistoryGraphPaneState();
}

class _HistoryGraphPaneState extends ConsumerState<_HistoryGraphPane> {
  bool _paused = false;
  DateTime? _pausedAt;
  List<List<dynamic>>? _pausedData;

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
        if (widget.realtime) {
          since = const Duration(minutes: 10);
        } else {
          if (widget.range == null) {
            return const Center(child: Text('Pick a start & end date'));
          }
          since = DateTime.now().difference(widget.range!.start);
        }

        final streams = widget.keys
            .map((k) => collector.collectStream(k, since: since))
            .toList();

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

            for (int i = 0; i < widget.keys.length; i++) {
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
                }
                if (y != null) {
                  if (!widget.realtime && widget.range != null) {
                    final dt =
                        DateTime.fromMillisecondsSinceEpoch(time.toInt());
                    if (dt.isBefore(widget.range!.start) ||
                        dt.isAfter(widget.range!.end)) {
                      continue;
                    }
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
                ? const Duration(minutes: 10)
                : (widget.range != null
                    ? widget.range!.end.difference(widget.range!.start)
                    : const Duration(minutes: 10));

            return Stack(
              children: [
                GestureDetector(
                  onTapDown: (_) {
                    if (widget.realtime) {
                      setState(() {
                        _paused = true;
                        _pausedAt = DateTime.now();
                      });
                    }
                  },
                  onPanStart: (_) {
                    if (widget.realtime) {
                      setState(() {
                        _paused = true;
                        _pausedAt = DateTime.now();
                      });
                    }
                  },
                  child: Graph(
                    config: GraphConfig(
                      type: GraphType.line,
                      xAxis: GraphAxisConfig(unit: 's'),
                      yAxis: GraphAxisConfig(unit: ''),
                      yAxis2: null,
                      xSpan: xSpan,
                    ),
                    data: graphDataByIndex[0] ??
                        [], // Only show one graph for now
                    showDate: _paused,
                  ),
                ),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
}

// -----------------------------------------------------------------------------
// Table pane – merges selected keys by nearest timestamp
// -----------------------------------------------------------------------------
class _HistoryTablePane extends ConsumerWidget {
  final List<String> keys;
  final bool realtime;
  final DateTimeRange? range;
  final int rows;

  const _HistoryTablePane({
    required this.keys,
    required this.realtime,
    required this.range,
    this.rows = 50,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectorAsync = ref.watch(collectorProvider);

    return collectorAsync.when(
      data: (collector) {
        if (collector == null) {
          return const Center(child: Text('No collector available'));
        }
        if (keys.isEmpty) {
          return const Center(child: Text('Select keys to view history'));
        }

        Duration since;
        if (realtime) {
          since = const Duration(minutes: 10);
        } else {
          if (range == null) {
            return const Center(child: Text('Pick a start & end date'));
          }
          since = DateTime.now().difference(range!.start);
        }

        final streams =
            keys.map((k) => collector.collectStream(k, since: since)).toList();

        return StreamBuilder<List<List<TimeseriesData<dynamic>>>>(
          stream: Rx.combineLatestList(streams),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final lists = snap.data!;

            final allTs = <DateTime>{};
            for (final l in lists) {
              for (final s in l) {
                if (!realtime && range != null) {
                  if (s.time.isBefore(range!.start) ||
                      s.time.isAfter(range!.end)) continue;
                }
                allTs.add(s.time);
              }
            }

            final ordered = allTs.toList()..sort((a, b) => b.compareTo(a));
            final kept = ordered.take(rows).toList().reversed.toList();

            const epsilon = Duration(seconds: 5);
            final tableRows = <Map<String, dynamic>>[];

            for (final t in kept) {
              final row = <String, dynamic>{'Timestamp': t};
              for (int i = 0; i < keys.length; i++) {
                final key = keys[i];
                final list = lists[i];
                TimeseriesData<dynamic>? best;
                var bestDt = epsilon + const Duration(days: 999);
                for (final s in list) {
                  final d = s.time.difference(t).abs();
                  if (d <= epsilon && d < bestDt) {
                    best = s;
                    bestDt = d;
                  }
                }
                row[key] = best?.value;
              }
              tableRows.add(row);
            }

            final columns = ['Timestamp', ...keys];

            return LayoutBuilder(
              builder: (context, constraints) {
                final hasFiniteH = constraints.hasBoundedHeight &&
                    constraints.maxHeight.isFinite;
                final rowH = hasFiniteH
                    ? (constraints.maxHeight /
                            math.max(2, tableRows.length + 1))
                        .clamp(28.0, 60.0)
                    : 36.0;
                final fontSize = (rowH * 0.6).clamp(10.0, 18.0).toDouble();

                final table = DataTable(
                  columns: columns
                      .map((c) => DataColumn(
                            label: Text(
                              c,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: fontSize),
                            ),
                          ))
                      .toList(),
                  rows: tableRows
                      .map(
                        (r) => DataRow(
                          cells: columns.map((c) {
                            if (c == 'Timestamp') {
                              final ts = r['Timestamp'] as DateTime;
                              final txt =
                                  '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
                              return DataCell(Text(txt,
                                  style: TextStyle(fontSize: fontSize)));
                            }
                            return DataCell(Text(_fmt(r[c]),
                                style: TextStyle(fontSize: fontSize)));
                          }).toList(),
                        ),
                      )
                      .toList(),
                  dataRowMinHeight: rowH,
                  dataRowMaxHeight: rowH,
                  headingRowHeight: rowH,
                );

                if (hasFiniteH) {
                  return FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: table,
                    ),
                  );
                } else {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: table,
                  );
                }
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  static String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is num) {
      if (v is double) return v.toStringAsFixed(2);
      return v.toString();
    }
    if (v is bool) return v ? 'true' : 'false';
    return v.toString();
  }
}

class GraphKeyConfig {
  final String key;
  final String alias;
  final bool useSecondYAxis;
  final int graphIndex; // 0-4 for up to 5 graphs

  GraphKeyConfig({
    required this.key,
    required this.alias,
    this.useSecondYAxis = false,
    this.graphIndex = 0,
  });

  GraphKeyConfig copyWith({
    String? key,
    String? alias,
    bool? useSecondYAxis,
    int? graphIndex,
  }) {
    return GraphKeyConfig(
      key: key ?? this.key,
      alias: alias ?? this.alias,
      useSecondYAxis: useSecondYAxis ?? this.useSecondYAxis,
      graphIndex: graphIndex ?? this.graphIndex,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GraphKeyConfig &&
        other.key == key &&
        other.alias == alias &&
        other.useSecondYAxis == useSecondYAxis &&
        other.graphIndex == graphIndex;
  }

  @override
  int get hashCode => Object.hash(key, alias, useSecondYAxis, graphIndex);
}

// Rename to avoid conflict with imported GraphConfig
class GraphDisplayConfig {
  final int index;
  final String yAxisUnit;
  final String yAxis2Unit;

  GraphDisplayConfig({
    required this.index,
    this.yAxisUnit = '',
    this.yAxis2Unit = '',
  });

  GraphDisplayConfig copyWith({
    int? index,
    String? yAxisUnit,
    String? yAxis2Unit,
  }) {
    return GraphDisplayConfig(
      index: index ?? this.index,
      yAxisUnit: yAxisUnit ?? this.yAxisUnit,
      yAxis2Unit: yAxis2Unit ?? this.yAxis2Unit,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GraphDisplayConfig &&
        other.index == index &&
        other.yAxisUnit == yAxisUnit &&
        other.yAxis2Unit == yAxis2Unit;
  }

  @override
  int get hashCode => Object.hash(index, yAxisUnit, yAxis2Unit);
}

// -----------------------------------------------------------------------------
// Main Page
// -----------------------------------------------------------------------------
class HistoryViewPage extends ConsumerStatefulWidget {
  const HistoryViewPage({super.key});

  @override
  ConsumerState<HistoryViewPage> createState() => _HistoryViewPageState();
}

class _HistoryViewPageState extends ConsumerState<HistoryViewPage>
    with SingleTickerProviderStateMixin {
  String _search = '';
  final _selected = <String>{};
  bool _realtime = true;
  DateTimeRange? _range;
  SavedHistoryView? _activeView;
  bool _onlyCollected = true;
  bool _leftPaneExpanded = true;

  // Rename to avoid conflict with the widget's GraphConfig
  final Map<String, GraphKeyConfig> _keyConfigs = <String, GraphKeyConfig>{};
  final Map<int, GraphDisplayConfig> _graphConfigs =
      <int, GraphDisplayConfig>{};

  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _updateGraphConfigs();
    _updateKeyConfigs(); // Add this method
  }

  void _updateKeyConfigs() {
    // Remove configs for keys that are no longer selected
    _keyConfigs.removeWhere((key, _) => !_selected.contains(key));

    // Add default configs for newly selected keys
    for (final key in _selected) {
      if (!_keyConfigs.containsKey(key)) {
        _keyConfigs[key] = GraphKeyConfig(
          key: key,
          alias: key,
          useSecondYAxis: false,
          graphIndex: 0,
        );
      }
    }
  }

  void _updateGraphConfigs() {
    // Initialize default graph configs for graphs 0-4
    for (int i = 0; i < 5; i++) {
      if (!_graphConfigs.containsKey(i)) {
        _graphConfigs[i] = GraphDisplayConfig(
          index: i,
          yAxisUnit: '',
          yAxis2Unit: '',
        );
      }
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'History',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left pane: Key search + list (now foldable)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: _leftPaneExpanded ? null : 60,
              child: _leftPaneExpanded
                  ? Expanded(
                      flex: 2,
                      child: _buildKeyPicker(context),
                    )
                  : _buildCollapsedLeftPane(context),
            ),
            // Collapse/expand button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: IconButton(
                onPressed: () {
                  setState(() {
                    _leftPaneExpanded = !_leftPaneExpanded;
                  });
                },
                icon: Icon(
                  _leftPaneExpanded ? Icons.chevron_left : Icons.chevron_right,
                  size: 20,
                ),
                tooltip: _leftPaneExpanded
                    ? 'Collapse left pane'
                    : 'Expand left pane',
                style: IconButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Right pane: Controls + Graph/Table
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopControls(context),
                  const SizedBox(height: 8),
                  TabBar(
                    controller: _tab,
                    tabs: const [
                      Tab(icon: Icon(Icons.show_chart), text: 'Graph'),
                      Tab(icon: Icon(Icons.table_chart), text: 'Table'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _HistoryGraphPane(
                          keys: _selected.toList(),
                          realtime: _realtime,
                          range: _range,
                          graphConfigs: _keyConfigs,
                        ),
                        _HistoryTablePane(
                          keys: _selected.toList(),
                          realtime: _realtime,
                          range: _range,
                          rows: 80,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Add this new method for the collapsed left pane
  Widget _buildCollapsedLeftPane(BuildContext context) {
    return Container(
      width: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Selected count indicator
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_selected.length}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Active view indicator (if any)
          if (_activeView != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _activeView!.name.length > 8
                    ? '${_activeView!.name.substring(0, 8)}...'
                    : _activeView!.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Collection status indicator
          Consumer(
            builder: (context, ref, child) {
              final collectedAsync = ref.watch(collectedKeysProvider);
              return collectedAsync.when(
                data: (collected) {
                  final collectedCount =
                      _selected.where((k) => collected.contains(k)).length;
                  final totalCount = _selected.length;
                  if (totalCount == 0) return const SizedBox.shrink();

                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: collectedCount == totalCount
                          ? Theme.of(context).colorScheme.tertiaryContainer
                          : Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      collectedCount == totalCount
                          ? Icons.check_circle
                          : Icons.warning,
                      color: collectedCount == totalCount
                          ? Theme.of(context).colorScheme.onTertiaryContainer
                          : Theme.of(context).colorScheme.onErrorContainer,
                      size: 20,
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
          const Spacer(),
          // Quick actions
          if (_selected.isNotEmpty) ...[
            IconButton(
              onPressed: () => _saveAsNewView(),
              icon: const Icon(Icons.save, size: 20),
              tooltip: 'Save as new view',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_activeView != null) ...[
            IconButton(
              onPressed: () => _updateView(),
              icon: const Icon(Icons.update, size: 20),
              tooltip: 'Update view',
              style: IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildKeyPicker(BuildContext context) {
    final keysAsync = ref.watch(stateKeysProvider);
    final collectedAsync = ref.watch(collectedKeysProvider);
    final dbAsync = ref.watch(databaseProvider); // AsyncValue<Database?>

    final canSave = _selected.isNotEmpty && (dbAsync.valueOrNull != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search keys…',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _search = v.trim()),
        ),
        const SizedBox(height: 8),
        // Filter "only collected"
        Row(
          children: [
            FilterChip(
              label: const Text('Only collected'),
              selected: _onlyCollected,
              onSelected: (v) => setState(() => _onlyCollected = v),
            ),
            const SizedBox(width: 8),
            Chip(label: Text('Selected: ${_selected.length}')),
          ],
        ),
        const SizedBox(height: 8),
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withAlpha(200),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Key Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  'Collected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  'View',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Keys list
        Expanded(
          child: keysAsync.when(
            data: (allKeys) {
              final Set<String> collected =
                  collectedAsync.valueOrNull ?? const <String>{};

              // Apply filters
              final filtered = allKeys.where((k) {
                final matches = _search.isEmpty ||
                    k.toLowerCase().contains(_search.toLowerCase());
                final passCollected = !_onlyCollected || collected.contains(k);
                return matches && passCollected;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('No matching keys'));
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final keyName = filtered[i];
                  final selected = _selected.contains(keyName);
                  return ListTile(
                    dense: true,
                    title: Text(
                      keyName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ⚡ collector toggle (now wider)
                        SizedBox(
                          width: 90,
                          child: _CollectorToggle(keyName: keyName),
                        ),
                        const SizedBox(width: 8),
                        // selection checkbox
                        Checkbox(
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(keyName);
                            } else {
                              _selected.remove(keyName);
                            }
                          }),
                        ),
                      ],
                    ),
                    onTap: () => setState(() {
                      if (selected) {
                        _selected.remove(keyName);
                      } else {
                        _selected.add(keyName);
                      }
                    }),
                  );
                },
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(child: Text('Error loading keys: $e')),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
                onPressed: () => setState(_selected.clear),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save as new view'),
                onPressed: canSave ? _saveAsNewView : null,
              ),
            ),
          ],
        ),
        if (_activeView != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.update),
                  label: Text('Update "${_activeView!.name}"'),
                  onPressed: canSave ? _updateView : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (dbAsync.isLoading) const SizedBox(height: 8),
        if (dbAsync.isLoading)
          const LinearProgressIndicator(minHeight: 2), // DB opening feedback
      ],
    );
  }

  Widget _buildTopControls(BuildContext context) {
    final viewsAsync = ref.watch(savedViewsProvider);

    return Row(
      children: [
        // Left side: existing controls
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Saved view picker
              viewsAsync.when(
                data: (views) {
                  // Filter out any duplicate views to prevent the assertion error
                  final uniqueViews = <SavedHistoryView>[];
                  final seenIds = <int>{};

                  for (final view in views) {
                    if (!seenIds.contains(view.id)) {
                      seenIds.add(view.id);
                      uniqueViews.add(view);
                    }
                  }

                  // Find the matching view instance from the list to avoid assertion error
                  SavedHistoryView? dropdownValue;
                  if (_activeView != null) {
                    dropdownValue = uniqueViews
                        .where((v) => v.id == _activeView!.id)
                        .firstOrNull;
                  }

                  return DropdownButton<SavedHistoryView?>(
                    value:
                        dropdownValue, // Use the found instance instead of _activeView
                    hint: const Text('Load saved view…'),
                    onChanged: (v) {
                      setState(() {
                        _activeView = v;
                        _selected
                          ..clear()
                          ..addAll(v?.keys ?? const []);
                        // Load graph configs from database
                        if (v != null) {
                          _loadGraphConfigsFromView(v.id);
                        } else {
                          _graphConfigs.clear();
                        }
                      });
                    },
                    items: [
                      for (final v in uniqueViews)
                        DropdownMenuItem(
                          value: v,
                          child: Text(v.name),
                        ),
                    ],
                  );
                },
                loading: () => const SizedBox(
                  width: 140,
                  height: 20,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
                error: (e, _) => Text('Views err: $e'),
              ),
              // Configure button (new)
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Configure'),
                onPressed: _selected.isEmpty ? null : _showConfigureDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.tertiaryContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
              // Delete view
              ElevatedButton.icon(
                icon: const Icon(Icons.delete),
                label: const Text('Delete view'),
                onPressed: _activeView == null ? null : _deleteView,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(width: 12),
              // Realtime toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _realtime,
                    onChanged: (v) => setState(() {
                      _realtime = v;
                      if (v) _range = null;
                    }),
                  ),
                  const Text('Realtime'),
                ],
              ),
              // DateRange when NOT realtime
              if (!_realtime)
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_range == null
                      ? 'Pick range'
                      : '${_range!.start.toLocal()} → ${_range!.end.toLocal()}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final initial = _range ??
                        DateTimeRange(
                          start: now.subtract(const Duration(hours: 1)),
                          end: now,
                        );
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: now.add(const Duration(days: 1)),
                      initialDateRange: initial,
                    );
                    if (picked != null) {
                      setState(() => _range = picked);
                    }
                  },
                ),
            ],
          ),
        ),

        // Right side: info button
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => _showPageHelpDialog(context),
          tooltip: 'How this page works',
          style: IconButton.styleFrom(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Future<void> _deleteView() async {
    final v = _activeView!;
    final ok = await _confirm(context, 'Delete "${v.name}"?');
    if (!ok) return;

    final dbWrap = await ref.read(databaseProvider.future);
    if (!context.mounted) return;
    if (dbWrap == null) {
      _toast(context, 'Database not ready yet.');
      return;
    }
    final adb = dbWrap.db;
    await adb.deleteHistoryView(v.id);
    setState(() => _activeView = null);
    ref.invalidate(savedViewsProvider);
    _toast(context, 'Deleted');
  }

  Future<void> _editKey(BuildContext context, String oldKey) async {
    final sm = await ref.read(stateManProvider.future);
    final km = sm.keyMappings;
    final current = km.nodes[oldKey];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => KeyMappingEntryDialog(
        initialKey: oldKey,
        initialKeyMappingEntry: current,
      ),
    );

    if (result == null) return;

    final newKey = result['key'] as String;
    final newEntry = result['entry'] as KeyMappingEntry;

    final prefs = await ref.read(preferencesProvider.future);

    if (oldKey != newKey) {
      km.nodes.remove(oldKey);
    }
    km.nodes[newKey] = newEntry;

    await prefs.setString('key_mappings', jsonEncode(km.toJson()));

    setState(() {
      if (oldKey != newKey && _selected.remove(oldKey)) {
        _selected.add(newKey);
      }
    });

    // Start foreground collection if collect is present
    try {
      final collector = await ref.read(collectorProvider.future);
      if (collector != null && newEntry.collect != null) {
        await collector.collectEntry(newEntry.collect!);
      }
    } catch (_) {}

    ref.invalidate(stateManProvider);
    ref.invalidate(collectedKeysProvider);

    _toast(context, 'Saved "$newKey"');
  }

  Future<String?> _askName(BuildContext context,
      {required String title, String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'View name',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String msg) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes')),
        ],
      ),
    );
    return res ?? false;
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Add method to load graph configs from database
  Future<void> _loadGraphConfigsFromView(int viewId) async {
    final dbWrap = await ref.read(databaseProvider.future);
    if (dbWrap == null) return;

    final rawKeyConfigs = await dbWrap.db.getHistoryViewKeys(viewId);
    final rawGraphConfigs = await dbWrap.db.getHistoryViewGraphs(viewId);

    print('🔍 Loading configs for view $viewId:');
    print('  Key configs: $rawKeyConfigs');
    print('  Graph configs: $rawGraphConfigs');

    setState(() {
      _keyConfigs.clear();
      for (final entry in rawKeyConfigs.entries) {
        final raw = entry.value;
        _keyConfigs[entry.key] = GraphKeyConfig(
          key: raw['key'] as String,
          alias: raw['alias'] as String,
          useSecondYAxis: raw['useSecondYAxis'] as bool,
          graphIndex: raw['graphIndex'] as int,
        );
      }

      _graphConfigs.clear();
      for (final entry in rawGraphConfigs.entries) {
        final raw = entry.value;
        _graphConfigs[entry.key] = GraphDisplayConfig(
          index: entry.key,
          yAxisUnit: raw['yAxisUnit'] as String,
          yAxis2Unit: raw['yAxis2Unit'] as String,
        );
      }
    });

    print('  Loaded key configs: $_keyConfigs');
    print('  Loaded graph configs: $_graphConfigs');
  }

  Future<void> _saveAsNewView() async {
    final dbWrap = await ref.read(databaseProvider.future);
    if (!context.mounted) return;
    if (dbWrap == null) {
      _toast(context, 'Database not ready yet.');
      return;
    }
    final adb = dbWrap.db;

    final name =
        await _askName(context, initial: '', title: 'Save as new view');
    if (name == null || name.trim().isEmpty) return;

    // Convert GraphKeyConfig objects to primitive maps for database
    final rawKeyConfigs = <String, Map<String, dynamic>>{};
    for (final entry in _keyConfigs.entries) {
      final config = entry.value;
      rawKeyConfigs[entry.key] = {
        'alias': config.alias,
        'useSecondYAxis': config.useSecondYAxis,
        'graphIndex': config.graphIndex,
      };
    }

    // Convert GraphConfig objects to primitive maps for database
    final rawGraphConfigs = <String, Map<String, dynamic>>{};
    for (final entry in _graphConfigs.entries) {
      final config = entry.value;
      rawGraphConfigs[entry.key.toString()] = {
        'yAxisUnit': config.yAxisUnit,
        'yAxis2Unit': config.yAxis2Unit,
      };
    }

    final id = await adb.createHistoryView(
        name.trim(), _selected.toList(), rawKeyConfigs, rawGraphConfigs);
    final newView =
        SavedHistoryView(id: id, name: name.trim(), keys: _selected.toList());

    setState(() => _activeView = newView);
    ref.invalidate(savedViewsProvider);
    _toast(context, 'Saved "${name.trim()}" as new view');
  }

  Future<void> _updateView() async {
    if (_activeView == null) return;

    final dbWrap = await ref.read(databaseProvider.future);
    if (!context.mounted) return;
    if (dbWrap == null) {
      _toast(context, 'Database not ready yet.');
      return;
    }
    final adb = dbWrap.db;

    final name = _activeView!.name;

    // Convert GraphKeyConfig objects to primitive maps for database
    final rawKeyConfigs = <String, Map<String, dynamic>>{};
    for (final entry in _keyConfigs.entries) {
      final config = entry.value;
      rawKeyConfigs[entry.key] = {
        'alias': config.alias,
        'useSecondYAxis': config.useSecondYAxis,
        'graphIndex': config.graphIndex,
      };
    }

    // Convert GraphConfig objects to primitive maps for database
    final rawGraphConfigs = <String, Map<String, dynamic>>{};
    for (final entry in _graphConfigs.entries) {
      final config = entry.value;
      rawGraphConfigs[entry.key.toString()] = {
        'yAxisUnit': config.yAxisUnit,
        'yAxis2Unit': config.yAxis2Unit,
      };
    }

    await adb.updateHistoryView(_activeView!.id, name, _selected.toList(),
        rawKeyConfigs, rawGraphConfigs);

    setState(() => _activeView = SavedHistoryView(
        id: _activeView!.id, name: name, keys: _selected.toList()));
    ref.invalidate(savedViewsProvider);
    _toast(context, 'Updated "${name}"');
  }

  // Add this new method for the configuration dialog
  Future<void> _showConfigureDialog() async {
    if (_selected.isEmpty) return;

    // Update configs to match current selection
    _updateGraphConfigs();
    _updateKeyConfigs(); // Update key configs as well

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => _GraphConfigurationDialog(
        keyConfigs: Map.from(_keyConfigs),
        graphConfigs: Map.from(_graphConfigs),
        onSave: (keyConfigs, graphConfigs) async {
          setState(() {
            _keyConfigs.clear();
            _keyConfigs.addAll(keyConfigs);
            _graphConfigs.clear();
            _graphConfigs.addAll(graphConfigs);
          });

          // Save configurations to database if we have an active view
          if (_activeView != null) {
            await _updateView();
          }
        },
      ),
    );
  }

  // Add this new method for the page help dialog
  void _showPageHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How the History Page Works'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overview:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'This page allows you to view historical data from your system in real-time or for specific time ranges. You can save different views with custom configurations.',
              ),
              SizedBox(height: 16),
              Text(
                'Left Pane - Key Selection:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('• Search and filter available system keys'),
              Text('• Toggle collection on/off for individual keys'),
              Text('• Select which keys to include in your view'),
              Text('• Use the collapse button to save space'),
              SizedBox(height: 16),
              Text(
                'Top Controls:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('• Load saved views from the dropdown'),
              Text(
                  '• Configure how keys are displayed (aliases, graphs, Y-axes)'),
              Text('• Save current selection as a new view'),
              Text('• Update existing views'),
              Text('• Toggle between real-time and historical data'),
              Text('• Pick specific date ranges for historical data'),
              SizedBox(height: 16),
              Text(
                'Graph & Table Views:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('• Graph tab: Visual representation of data over time'),
              Text('• Table tab: Tabular data with timestamps'),
              Text('• Click/tap on real-time graphs to pause'),
              Text('• Resume button appears when paused'),
              SizedBox(height: 16),
              Text(
                'Configuration:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('• Set friendly aliases for keys'),
              Text('• Organize keys into up to 5 separate graphs'),
              Text('• Configure Y-axis units for each graph'),
              Text('• Use secondary Y-axes for different value scales'),
              Text('• All configurations are saved with your view'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// Update the dialog to handle both configurations
class _GraphConfigurationDialog extends StatefulWidget {
  final Map<String, GraphKeyConfig> keyConfigs;
  final Map<int, GraphDisplayConfig> graphConfigs;
  final Function(Map<String, GraphKeyConfig>, Map<int, GraphDisplayConfig>)
      onSave;

  const _GraphConfigurationDialog({
    required this.keyConfigs,
    required this.graphConfigs,
    required this.onSave,
  });

  @override
  State<_GraphConfigurationDialog> createState() =>
      _GraphConfigurationDialogState();
}

class _GraphConfigurationDialogState extends State<_GraphConfigurationDialog> {
  late Map<String, GraphKeyConfig> _keyConfigs;
  late Map<int, GraphDisplayConfig> _graphConfigs;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _keyConfigs = Map.from(widget.keyConfigs);
    _graphConfigs = Map.from(widget.graphConfigs);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Configure Graph Display')),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showHelpDialog(context),
            tooltip: 'Help',
          ),
        ],
      ),
      content: SizedBox(
        width: 1000, // Increased width for graph configs
        height: 600, // Increased height
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Key and Graph configuration sections side by side
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Graph Configuration section (left side - 1/3 width)
                    SizedBox(
                      width: 333, // Fixed width: 1000 * 0.33 ≈ 333
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Graph Configuration',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _getActiveGraphCount(),
                                  itemBuilder: (context, graphIndex) {
                                    final graphConfig =
                                        _graphConfigs[graphIndex]!;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Graph ${graphIndex + 1}:',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w500),
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            initialValue: graphConfig.yAxisUnit,
                                            decoration: const InputDecoration(
                                              labelText: 'Primary Y-Axis Unit',
                                              border: OutlineInputBorder(),
                                              hintText: 'e.g., °C, RPM, %',
                                            ),
                                            onChanged: (value) {
                                              setState(() {
                                                _graphConfigs[graphIndex] =
                                                    graphConfig.copyWith(
                                                  yAxisUnit: value,
                                                );
                                              });
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            initialValue:
                                                graphConfig.yAxis2Unit,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Secondary Y-Axis Unit',
                                              border: OutlineInputBorder(),
                                              hintText: 'e.g., bar, V',
                                            ),
                                            onChanged: (value) {
                                              setState(() {
                                                _graphConfigs[graphIndex] =
                                                    graphConfig.copyWith(
                                                  yAxis2Unit: value,
                                                );
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Key Configuration section (right side - 2/3 width)
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Key Configuration',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _keyConfigs.length,
                                  itemBuilder: (context, index) {
                                    final key =
                                        _keyConfigs.keys.elementAt(index);
                                    final config = _keyConfigs[key]!;

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Key: $key',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: TextFormField(
                                                    initialValue: config.alias,
                                                    decoration:
                                                        const InputDecoration(
                                                      labelText:
                                                          'Display Alias',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                    onChanged: (value) {
                                                      setState(() {
                                                        _keyConfigs[key] =
                                                            config.copyWith(
                                                                alias: value);
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child:
                                                      DropdownButtonFormField<
                                                          int>(
                                                    value: config.graphIndex,
                                                    decoration:
                                                        const InputDecoration(
                                                      labelText: 'Graph',
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                                    items: List.generate(
                                                      5,
                                                      (index) =>
                                                          DropdownMenuItem(
                                                        value: index,
                                                        child: Text(
                                                            'Graph ${index + 1}'),
                                                      ),
                                                    ),
                                                    onChanged: (value) {
                                                      if (value != null) {
                                                        setState(() {
                                                          _keyConfigs[key] =
                                                              config.copyWith(
                                                                  graphIndex:
                                                                      value);
                                                        });
                                                      }
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                SizedBox(
                                                  width: 120,
                                                  child: CheckboxListTile(
                                                    title: const Text(
                                                        '2nd Y-Axis'),
                                                    value:
                                                        config.useSecondYAxis,
                                                    onChanged: (value) {
                                                      setState(() {
                                                        _keyConfigs[key] =
                                                            config.copyWith(
                                                          useSecondYAxis:
                                                              value ?? false,
                                                        );
                                                      });
                                                    },
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              widget.onSave(_keyConfigs, _graphConfigs);
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configuration Help'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Graph Configuration:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('• Set units for each graph\'s Y-axes'),
            Text('• Primary Y-Axis Unit: Units for keys using the main Y-axis'),
            Text(
                '• Secondary Y-Axis Unit: Units for keys using the 2nd Y-axis'),
            Text('• Examples: °C, RPM, %, bar, V, A, m/s²'),
            SizedBox(height: 16),
            Text(
              'Key Configuration:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
                '• Display Alias: Set a friendly name for this key that will appear on graphs and tables'),
            Text('• Leave empty to use the original key name'),
            SizedBox(height: 8),
            Text(
                '• Graph: Choose which of the 5 graph panes this key should appear in'),
            Text('• Keys in the same graph will share the same time axis'),
            Text('• Graphs will be stacked vertically (one above the other)'),
            Text('• Graph 1 appears at the top, Graph 5 at the bottom'),
            SizedBox(height: 8),
            Text(
                '• 2nd Y-Axis: Enable to display this key on a secondary Y-axis'),
            Text('• Useful when combining values with different scales'),
            Text('• Primary Y-axis keys are shown in blue, secondary in green'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  // Helper method to determine how many graphs to show
  int _getActiveGraphCount() {
    final usedGraphs = <int>{};
    for (final config in _keyConfigs.values) {
      usedGraphs.add(config.graphIndex);
    }
    return usedGraphs.isEmpty
        ? 1
        : (usedGraphs.reduce((a, b) => a > b ? a : b) + 1);
  }
}
