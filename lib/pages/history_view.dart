import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
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
// NEW: Saved Periods per View
// -----------------------------------------------------------------------------
class SavedPeriod {
  final int id;
  final int viewId;
  final String name;
  final DateTime start;
  final DateTime end;
  SavedPeriod({
    required this.id,
    required this.viewId,
    required this.name,
    required this.start,
    required this.end,
  });
}

final savedPeriodsProvider =
    FutureProvider.family<List<SavedPeriod>, int>((ref, viewId) async {
  final dbWrap = await ref.watch(databaseProvider.future);
  if (dbWrap == null) return [];
  final rows = await dbWrap.db.listHistoryViewPeriods(viewId);
  return [
    for (final r in rows)
      SavedPeriod(
        id: r.id,
        viewId: r.viewId,
        name: r.name,
        start: r.startAt,
        end: r.endAt,
      )
  ]..sort((a, b) => a.start.compareTo(b.start));
});

// A best-effort "global" retention horizon (oldest timestamp we likely still have)
// If null, retention is unknown (no icon/warning).
final retentionHorizonProvider = FutureProvider<DateTime?>((ref) async {
  final dbWrap = await ref.watch(databaseProvider.future);
  if (dbWrap == null) return null;
  try {
    return await dbWrap.db.getGlobalRetentionHorizon();
  } catch (_) {
    return null;
  }
});

enum PeriodValidity { valid, partial, invalid, unknown }

PeriodValidity validityForRange(DateTimeRange r, DateTime? horizon) {
  if (horizon == null) return PeriodValidity.unknown;
  if (r.end.isBefore(horizon)) return PeriodValidity.invalid;
  if (r.start.isBefore(horizon)) return PeriodValidity.partial;
  return PeriodValidity.valid;
}

Icon _validityIcon(BuildContext context, PeriodValidity v) {
  switch (v) {
    case PeriodValidity.valid:
      return Icon(Icons.check_circle,
          size: 18, color: Theme.of(context).colorScheme.tertiary);
    case PeriodValidity.partial:
      return Icon(Icons.warning_amber_rounded,
          size: 18, color: Theme.of(context).colorScheme.secondary);
    case PeriodValidity.invalid:
      return Icon(Icons.error_outline,
          size: 18, color: Theme.of(context).colorScheme.error);
    case PeriodValidity.unknown:
    default:
      return Icon(Icons.help_outline,
          size: 18, color: Theme.of(context).colorScheme.outline);
  }
}

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

        final streams = widget.keys.map((k) {
          if (widget.realtime) {
            return collector.collectStream(k, since: since);
          } else {
            return Stream.fromFuture(collector.database.queryTimeseriesData(
                k, widget.range!.end,
                from: widget.range!.start));
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
                      type: GraphType.timeseries,
                      xAxis: GraphAxisConfig(unit: ''),
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

        final streams = keys.map((k) {
          if (realtime) {
            return collector.collectStream(k, since: since);
          } else {
            print('querying $k from ${range!.start} to ${range!.end}');
            return Stream.fromFuture(collector.database
                .queryTimeseriesData(k, range!.end, from: range!.start));
          }
        }).toList();

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
                      s.time.isAfter(range!.end)) {
                    continue;
                  }
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
// Tree node model
// -----------------------------------------------------------------------------
class KeyTreeNode {
  final String name;
  final String? fullKey; // null for folder nodes, non-null for leaf nodes
  final Map<String, KeyTreeNode> children;
  final bool isExpanded;

  KeyTreeNode({
    required this.name,
    this.fullKey,
    required this.children,
    this.isExpanded = false,
  });

  bool get isLeaf => fullKey != null;
  bool get isFolder => !isLeaf;
}

// Build a hierarchical tree from dotted keys: "plc.motor.speed"
final keyTreeProvider = FutureProvider<KeyTreeNode>((ref) async {
  final sm = await ref.watch(stateManProvider.future);
  final keys = List<String>.from(sm.keys);
  keys.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return _buildKeyTree(keys);
});

KeyTreeNode _buildKeyTree(List<String> keys) {
  final root = KeyTreeNode(name: 'root', children: {});
  for (final key in keys) {
    final parts = key.split('.');
    KeyTreeNode current = root;
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      current.children.putIfAbsent(
        part,
        () =>
            KeyTreeNode(name: part, fullKey: isLast ? key : null, children: {}),
      );
      current = current.children[part]!;
      // If an intermediate node was created as a leaf by a weird key, force folder
      if (!isLast && current.fullKey != null) {
        current.children.putIfAbsent(
          '__leaf__${current.fullKey}',
          () => KeyTreeNode(
            name: current.name,
            fullKey: current.fullKey,
            children: {},
          ),
        );
        current = KeyTreeNode(
            name: current.name, fullKey: null, children: current.children);
      }
    }
  }
  return root;
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

  // Maintain expand/collapse per folder path (e.g., "root/plc/motor")
  final Set<String> _expandedPaths = {'root'};

  // Left pane collapse
  bool _leftPaneExpanded = true;

  // Saved periods UI state
  SavedPeriod? _activePeriod;

  // Rename to avoid conflict with the widget's GraphConfig
  final Map<String, GraphKeyConfig> _keyConfigs = <String, GraphKeyConfig>{};
  final Map<int, GraphDisplayConfig> _graphConfigs =
      <int, GraphDisplayConfig>{};

  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _updateGraphConfigs();
    _updateKeyConfigs();
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
      _graphConfigs.putIfAbsent(
        i,
        () => GraphDisplayConfig(index: i, yAxisUnit: '', yAxis2Unit: ''),
      );
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
            // Left pane: Key search + tree (now properly recursive)
            if (_leftPaneExpanded)
              Expanded(
                flex: 2,
                child: _buildKeyPicker(context),
              )
            else
              SizedBox(
                width: 60,
                child: _buildCollapsedLeftPane(context),
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

  // Collapsed left pane
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

  // Left pane: search + filters + header + recursive tree
  Widget _buildKeyPicker(BuildContext context) {
    final collectedAsync = ref.watch(collectedKeysProvider);
    final dbAsync = ref.watch(databaseProvider);
    final keyTreeAsync = ref.watch(keyTreeProvider);

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
              const Expanded(
                flex: 3,
                child: Text(
                  'Key Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(
                width: 90,
                child: Text(
                  'Collected',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(
                width: 48,
                child: Text(
                  'View',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Expand all',
                onPressed: () => setState(() => _expandedPaths.add('__ALL__')),
                icon: const Icon(Icons.unfold_more),
              ),
              IconButton(
                tooltip: 'Collapse all',
                onPressed: () => setState(() => _expandedPaths
                  ..clear()
                  ..add('root')),
                icon: const Icon(Icons.unfold_less),
              ),
            ],
          ),
        ),
        // Recursive tree
        Expanded(
          child: keyTreeAsync.when(
            data: (root) {
              final collected = collectedAsync.valueOrNull ?? const <String>{};
              return _KeyTreeList(
                root: root,
                collected: collected,
                search: _search,
                onlyCollected: _onlyCollected,
                selected: _selected,
                expandedPaths: _expandedPaths,
                onToggleFolder: (path) {
                  setState(() {
                    if (_expandedPaths.contains(path)) {
                      _expandedPaths.remove(path);
                    } else {
                      _expandedPaths.add(path);
                    }
                  });
                },
                onToggleKey: (key) {
                  setState(() {
                    if (_selected.contains(key)) {
                      _selected.remove(key);
                    } else {
                      _selected.add(key);
                    }
                    _updateKeyConfigs();
                  });
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
        if (dbAsync.isLoading) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  // Top controls (right pane header)
  Widget _buildTopControls(BuildContext context) {
    final viewsAsync = ref.watch(savedViewsProvider);

    return Row(
      children: [
        // Left side: existing controls (+ new saved periods controls)
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
                    for (final v in uniqueViews) {
                      if (v.id == _activeView!.id) {
                        dropdownValue = v;
                        break;
                      }
                    }
                  }

                  return DropdownButton<SavedHistoryView?>(
                    value: dropdownValue,
                    hint: const Text('Load saved view…'),
                    onChanged: (v) {
                      setState(() {
                        _activeView = v;
                        _activePeriod = null;
                        _selected
                          ..clear()
                          ..addAll(v?.keys ?? const []);
                        _updateKeyConfigs();
                        // Load graph configs from database
                        if (v != null) {
                          _loadGraphConfigsFromView(v.id);
                        } else {
                          _graphConfigs.clear();
                          _updateGraphConfigs();
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

              // Configure button
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

              // --- NEW: Saved Periods picker + delete + "save current period" ---
              if (_activeView != null)
                Consumer(builder: (context, ref, _) {
                  final periodsAsync =
                      ref.watch(savedPeriodsProvider(_activeView!.id));
                  final horizonAsync = ref.watch(retentionHorizonProvider);

                  return periodsAsync.when(
                    data: (periods) {
                      final horizon = horizonAsync.valueOrNull;
                      SavedPeriod? dropdownValue = _activePeriod == null
                          ? null
                          : periods.firstWhere(
                              (p) => p.id == _activePeriod!.id,
                              orElse: () => _activePeriod!,
                            );

                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButton<SavedPeriod?>(
                            value: dropdownValue,
                            hint: const Text('Saved periods…'),
                            onChanged: (p) {
                              setState(() {
                                _activePeriod = p;
                                if (p != null) {
                                  _realtime = false;
                                  _range =
                                      DateTimeRange(start: p.start, end: p.end);
                                }
                              });
                            },
                            items: [
                              for (final p in periods)
                                DropdownMenuItem(
                                  value: p,
                                  child: Row(
                                    children: [
                                      _validityIcon(
                                        context,
                                        validityForRange(
                                          DateTimeRange(
                                              start: p.start, end: p.end),
                                          horizon,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(p.name),
                                      const SizedBox(width: 8),
                                      Text(
                                        '(${_fmtDT(p.start)} → ${_fmtDT(p.end)})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Save current range as period',
                            child: IconButton(
                              onPressed: (_activeView != null &&
                                      !_realtime &&
                                      _range != null)
                                  ? _saveCurrentRangeAsPeriod
                                  : null,
                              icon: const Icon(Icons.bookmark_add_outlined),
                            ),
                          ),
                          Tooltip(
                            message: 'Delete selected period',
                            child: IconButton(
                              onPressed: (_activeView != null &&
                                      _activePeriod != null)
                                  ? () => _deletePeriod(
                                      _activePeriod!, horizonAsync.valueOrNull)
                                  : null,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox(
                      width: 120,
                      height: 20,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                    error: (e, _) => Text('Periods err: $e'),
                  );
                }),

              const SizedBox(width: 12),

              // Realtime toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: _realtime,
                    onChanged: (v) => setState(() {
                      _realtime = v;
                      if (v) {
                        _range = null;
                        _activePeriod = null;
                      }
                    }),
                  ),
                  const Text('Realtime'),
                ],
              ),

              // DateRange when NOT realtime (with seconds)
              if (!_realtime)
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(_range == null
                      ? 'Pick date & time range'
                      : '${_rangeLabel(_range!)}'),
                  onPressed: () async {
                    final picked =
                        await _pickDateTimeRangeWithSeconds(context, _range);
                    if (picked != null) {
                      setState(() {
                        _range = picked;
                        _activePeriod = null; // manual pick overrides saved
                      });
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

  // ---- DB ops & dialogs ------------------------------------------------------

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
    setState(() {
      _activeView = null;
      _activePeriod = null;
    });
    ref.invalidate(savedViewsProvider);
    _toast(context, 'Deleted');
  }

  Future<void> _saveCurrentRangeAsPeriod() async {
    if (_activeView == null || _range == null) return;
    final name = await _askName(context, title: 'Save period', initial: '');
    if (name == null || name.trim().isEmpty) return;

    final dbWrap = await ref.read(databaseProvider.future);
    if (dbWrap == null) {
      _toast(context, 'Database not ready yet.');
      return;
    }
    final id = await dbWrap.db.addHistoryViewPeriod(
      _activeView!.id,
      name.trim(),
      _range!.start,
      _range!.end,
    );
    setState(() {
      _activePeriod = SavedPeriod(
          id: id,
          viewId: _activeView!.id,
          name: name.trim(),
          start: _range!.start,
          end: _range!.end);
    });
    ref.invalidate(savedPeriodsProvider(_activeView!.id));
    _toast(context, 'Saved period "$name"');
  }

  Future<void> _deletePeriod(SavedPeriod p, DateTime? retentionHorizon) async {
    final validity = validityForRange(
        DateTimeRange(start: p.start, end: p.end), retentionHorizon);

    final warn = switch (validity) {
      PeriodValidity.invalid =>
        '\n\nNote: This period is already invalid due to retention.',
      PeriodValidity.partial =>
        '\n\nWarning: Part of this period is older than retention.',
      _ => '',
    };

    final ok = await _confirm(context, 'Delete saved period "${p.name}"?$warn');
    if (!ok) return;

    final dbWrap = await ref.read(databaseProvider.future);
    if (dbWrap == null) {
      _toast(context, 'Database not ready yet.');
      return;
    }
    await dbWrap.db.deleteHistoryViewPeriod(p.id);
    if (!mounted) return;
    if (_activePeriod?.id == p.id) {
      setState(() => _activePeriod = null);
    }
    ref.invalidate(savedPeriodsProvider(p.viewId));
    _toast(context, 'Deleted period "${p.name}"');
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
            labelText: 'Name',
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

  // Load graph configs for a saved view
  Future<void> _loadGraphConfigsFromView(int viewId) async {
    final dbWrap = await ref.read(databaseProvider.future);
    if (dbWrap == null) return;

    final rawKeyConfigs = await dbWrap.db.getHistoryViewKeys(viewId);
    final rawGraphConfigs = await dbWrap.db.getHistoryViewGraphs(viewId);

    setState(() {
      _keyConfigs.clear();
      for (final entry in rawKeyConfigs.entries) {
        final raw = entry.value;
        _keyConfigs[entry.key] = GraphKeyConfig(
          key: raw['key'] as String? ?? entry.key,
          alias: (raw['alias'] as String?) ?? entry.key,
          useSecondYAxis: (raw['useSecondYAxis'] as bool?) ?? false,
          graphIndex: (raw['graphIndex'] as int?) ?? 0,
        );
      }

      _graphConfigs.clear();
      for (final entry in rawGraphConfigs.entries) {
        final raw = entry.value;
        _graphConfigs[entry.key] = GraphDisplayConfig(
          index: entry.key,
          yAxisUnit: (raw['yAxisUnit'] as String?) ?? '',
          yAxis2Unit: (raw['yAxis2Unit'] as String?) ?? '',
        );
      }
      _updateGraphConfigs(); // ensure 0..4 exist
    });
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

    setState(() {
      _activeView = newView;
      _activePeriod = null;
    });
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
    _toast(context, 'Updated "$name"');
  }

  // Configuration dialog
  Future<void> _showConfigureDialog() async {
    if (_selected.isEmpty) return;

    // Update configs to match current selection
    _updateGraphConfigs();
    _updateKeyConfigs();

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => _GraphConfigurationDialog(
        keyConfigs: Map.from(_keyConfigs),
        graphConfigs: Map.from(_graphConfigs),
        onSave: (keyConfigs, graphConfigs) async {
          setState(() {
            _keyConfigs
              ..clear()
              ..addAll(keyConfigs);
            _graphConfigs
              ..clear()
              ..addAll(graphConfigs);
          });

          // Save configurations to database if we have an active view
          if (_activeView != null) {
            await _updateView();
          }
        },
      ),
    );
  }

  // Page help dialog
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
              Text(
                  '• Pick specific date ranges for historical data (with seconds)'),
              Text('• Save named periods and re-apply them later'),
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
                'Retention & Periods:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('• Saved periods show status vs. retention'),
              Text(
                  '• Green: fully valid; Yellow: partially valid; Red: invalid'),
              Text(
                  '• Invalid periods can still be kept for reference or deleted'),
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

  // ---- DateTime range picker with seconds -----------------------------------

  Future<DateTimeRange?> _pickDateTimeRangeWithSeconds(
      BuildContext context, DateTimeRange? initial) async {
    final res = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => _DateTimeRangeDialog(initial: initial),
    );
    return res;
  }

  static String _fmtDT(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.year)}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _rangeLabel(DateTimeRange r) =>
      '${_fmtDT(r.start)} → ${_fmtDT(r.end)}';
}

// -----------------------------------------------------------------------------
// Recursive tree list (flat ListView built from recursion)
// -----------------------------------------------------------------------------
class _KeyTreeList extends StatelessWidget {
  final KeyTreeNode root;
  final Set<String> collected;
  final String search;
  final bool onlyCollected;
  final Set<String> selected;
  final Set<String> expandedPaths;
  final void Function(String path) onToggleFolder;
  final void Function(String key) onToggleKey;

  const _KeyTreeList({
    required this.root,
    required this.collected,
    required this.search,
    required this.onlyCollected,
    required this.selected,
    required this.expandedPaths,
    required this.onToggleFolder,
    required this.onToggleKey,
  });

  bool _leafVisible(KeyTreeNode node) {
    if (!node.isLeaf) return false;
    if (search.isNotEmpty) {
      final hit =
          (node.fullKey ?? '').toLowerCase().contains(search.toLowerCase());
      if (!hit) return false;
    }
    if (onlyCollected) {
      return collected.contains(node.fullKey);
    }
    return true;
  }

  /// Returns (visibleCount, anyVisible)
  (int, bool) _countVisibleLeaves(KeyTreeNode node) {
    if (node.isLeaf) {
      final v = _leafVisible(node) ? 1 : 0;
      return (v, v > 0);
    }
    int count = 0;
    bool any = false;
    for (final child in node.children.values) {
      final (c, a) = _countVisibleLeaves(child);
      count += c;
      any = any || a;
    }
    return (count, any);
  }

  List<Widget> _buildItems(
    BuildContext context,
    KeyTreeNode node, {
    required String path,
    required int depth,
  }) {
    // Skip root: build its children directly
    if (path == 'root') {
      final children = node.children.values.toList()
        ..sort((a, b) {
          // Folders first, then leaves, then alpha
          if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

      final items = <Widget>[];
      for (final child in children) {
        items.addAll(_buildItems(
          context,
          child,
          path: '$path/${child.name}',
          depth: depth,
        ));
      }
      return items;
    }

    // Leaf
    if (node.isLeaf) {
      if (!_leafVisible(node)) return const <Widget>[];
      final keyName = node.fullKey!;
      final displayName = keyName.split('.').last;
      return [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 16.0 * depth, right: 8),
          title: Text(
            displayName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 90, child: _CollectorToggle(keyName: keyName)),
              const SizedBox(width: 8),
              Checkbox(
                value: selected.contains(keyName),
                onChanged: (_) => onToggleKey(keyName),
              ),
            ],
          ),
          onTap: () => onToggleKey(keyName),
        )
      ];
    }

    // Folder
    final (visibleCount, anyVisible) = _countVisibleLeaves(node);
    if (!anyVisible) return const <Widget>[];

    // auto-expand when searching to show matches
    final autoExpandedFromSearch = search.isNotEmpty;
    final expanded = autoExpandedFromSearch ||
        expandedPaths.contains('__ALL__') ||
        expandedPaths.contains(path);

    final header = ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 16.0 * depth, right: 8),
      leading:
          Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 20),
      title: Row(
        children: [
          Icon(Icons.folder,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              node.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '($visibleCount)',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () => onToggleFolder(path),
    );

    final items = <Widget>[header];
    if (expanded) {
      final children = node.children.values.toList()
        ..sort((a, b) {
          if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      for (final child in children) {
        items.addAll(_buildItems(
          context,
          child,
          path: '$path/${child.name}',
          depth: depth + 1,
        ));
      }
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(context, root, path: 'root', depth: 0);
    if (items.isEmpty) {
      return const Center(child: Text('No keys match the current filters.'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}

// -----------------------------------------------------------------------------
// Graph configuration dialog
// -----------------------------------------------------------------------------
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
        width: 1000,
        height: 600,
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
                      width: 333,
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

// -----------------------------------------------------------------------------
// DateTimeRange editor dialog with unified H:M:S picker
// -----------------------------------------------------------------------------
class _DateTimeRangeDialog extends StatefulWidget {
  final DateTimeRange? initial;
  const _DateTimeRangeDialog({this.initial});

  @override
  State<_DateTimeRangeDialog> createState() => _DateTimeRangeDialogState();
}

class _DateTimeRangeDialogState extends State<_DateTimeRangeDialog> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  int _startSec = 0;

  late DateTime _endDate;
  late TimeOfDay _endTime;
  int _endSec = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final init = widget.initial ??
        DateTimeRange(
          start: now.subtract(const Duration(hours: 1)),
          end: now,
        );
    _startDate = DateTime(init.start.year, init.start.month, init.start.day);
    _startTime = TimeOfDay(hour: init.start.hour, minute: init.start.minute);
    _startSec = init.start.second;

    _endDate = DateTime(init.end.year, init.end.month, init.end.day);
    _endTime = TimeOfDay(hour: init.end.hour, minute: init.end.minute);
    _endSec = init.end.second;
  }

  DateTime _compose(DateTime d, TimeOfDay t, int s) =>
      DateTime(d.year, d.month, d.day, t.hour, t.minute, s.clamp(0, 59));

  Future<void> _pickDate({required bool start}) async {
    final base = start ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: base,
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickTimeHms({required bool start}) async {
    final initial = Duration(
      hours: start ? _startTime.hour : _endTime.hour,
      minutes: start ? _startTime.minute : _endTime.minute,
      seconds: start ? _startSec : _endSec,
    );

    final picked = await showDialog<Duration>(
      context: context,
      builder: (context) => _HmsTimePickerDialog(initial: initial),
    );

    if (picked != null) {
      setState(() {
        final h = picked.inHours % 24;
        final m = picked.inMinutes % 60;
        final s = picked.inSeconds % 60;
        if (start) {
          _startTime = TimeOfDay(hour: h, minute: m);
          _startSec = s;
        } else {
          _endTime = TimeOfDay(hour: h, minute: m);
          _endSec = s;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final startDT = _compose(_startDate, _startTime, _startSec);
    final endDT = _compose(_endDate, _endTime, _endSec);
    final valid = !endDT.isBefore(startDT);

    return AlertDialog(
      title: const Text('Pick date & time range'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(context,
                label: 'Start',
                date: _startDate,
                time: _startTime,
                secs: _startSec,
                onPickDate: () => _pickDate(start: true),
                onPickTimeHms: () => _pickTimeHms(start: true)),
            const SizedBox(height: 12),
            _row(context,
                label: 'End',
                date: _endDate,
                time: _endTime,
                secs: _endSec,
                onPickDate: () => _pickDate(start: false),
                onPickTimeHms: () => _pickTimeHms(start: false)),
            if (!valid)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'End must be after start',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: valid
                ? () => Navigator.pop(
                      context,
                      DateTimeRange(start: startDT, end: endDT),
                    )
                : null,
            child: const Text('Apply')),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required DateTime date,
    required TimeOfDay time,
    required int secs,
    required VoidCallback onPickDate,
    required VoidCallback onPickTimeHms,
  }) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onPickDate,
          icon: const Icon(Icons.event),
          label: Text('${date.year}-${two(date.month)}-${two(date.day)}'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onPickTimeHms,
          icon: const Icon(Icons.schedule),
          label: Text('${two(time.hour)}:${two(time.minute)}:${two(secs)}'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Fancy Material HMS time picker dialog
// - Two modes: "Wheel" (ListWheelScrollView) and "Numeric" (steppers)
// - Syncs both ways; switch modes anytime
// - Touch-friendly sizes, optional haptic feedback
// -----------------------------------------------------------------------------
class _HmsTimePickerDialog extends StatefulWidget {
  final Duration initial;
  const _HmsTimePickerDialog({required this.initial});

  @override
  State<_HmsTimePickerDialog> createState() => _HmsTimePickerDialogState();
}

enum _PickerMode { wheel, numeric }

class _HmsTimePickerDialogState extends State<_HmsTimePickerDialog> {
  // canonical state
  late int _h;
  late int _m;
  late int _s;

  // wheel controllers
  late FixedExtentScrollController _hCtrl;
  late FixedExtentScrollController _mCtrl;
  late FixedExtentScrollController _sCtrl;

  // numeric controllers
  late final TextEditingController _hText;
  late final TextEditingController _mText;
  late final TextEditingController _sText;

  _PickerMode _mode = _PickerMode.wheel;

  @override
  void initState() {
    super.initState();
    _h = widget.initial.inHours % 24;
    _m = widget.initial.inMinutes % 60;
    _s = widget.initial.inSeconds % 60;

    _hCtrl = FixedExtentScrollController(initialItem: _h);
    _mCtrl = FixedExtentScrollController(initialItem: _m);
    _sCtrl = FixedExtentScrollController(initialItem: _s);

    _hText = TextEditingController(text: _two(_h));
    _mText = TextEditingController(text: _two(_m));
    _sText = TextEditingController(text: _two(_s));
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    _sCtrl.dispose();
    _hText.dispose();
    _mText.dispose();
    _sText.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _animateWheel(FixedExtentScrollController c, int v) async {
    // clamp to safe range; caller already ensures bounds
    final target = v.clamp(0, 9999); // controller guards anyway
    if (!mounted) return;
    await c.animateToItem(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _setH(int v, {bool fromWheel = false, bool fromField = false}) {
    v = v.clamp(0, 23);
    if (_h == v) return;
    setState(() => _h = v);
    if (!fromWheel) _animateWheel(_hCtrl, v);
    if (!fromField) _hText.text = _two(v);
    _haptic();
  }

  void _setM(int v, {bool fromWheel = false, bool fromField = false}) {
    v = v.clamp(0, 59);
    if (_m == v) return;
    setState(() => _m = v);
    if (!fromWheel) _animateWheel(_mCtrl, v);
    if (!fromField) _mText.text = _two(v);
    _haptic();
  }

  void _setS(int v, {bool fromWheel = false, bool fromField = false}) {
    v = v.clamp(0, 59);
    if (_s == v) return;
    setState(() => _s = v);
    if (!fromWheel) _animateWheel(_sCtrl, v);
    if (!fromField) _sText.text = _two(v);
    _haptic();
  }

  void _haptic() {
    // optional: requires import 'package:flutter/services.dart';
    // HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final itemExtent = 48.0; // bigger touch targets
    final textStyle = Theme.of(context).textTheme.titleMedium;

    return AlertDialog(
      title: const Text('Select time (HH:MM:SS)'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _modeToggle(context),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _mode == _PickerMode.wheel
                  ? _wheelContent(itemExtent, textStyle)
                  : _numericContent(textStyle),
            ),
            const SizedBox(height: 12),
            _previewChip(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              Duration(hours: _h, minutes: _m, seconds: _s),
            );
          },
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _modeToggle(BuildContext context) {
    return ToggleButtons(
      isSelected: [
        _mode == _PickerMode.wheel,
        _mode == _PickerMode.numeric,
      ],
      onPressed: (i) {
        setState(() {
          _mode = i == 0 ? _PickerMode.wheel : _PickerMode.numeric;
        });
      },
      borderRadius: BorderRadius.circular(8),
      children: const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('Wheel'),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text('Numeric'),
        ),
      ],
    );
  }

  Widget _previewChip(BuildContext context) {
    final s = '${_two(_h)}:${_two(_m)}:${_two(_s)}';
    return Align(
      alignment: Alignment.centerRight,
      child: Chip(
        label: Text(
          s,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }

  // ---------- Wheel mode ----------
  Widget _wheelContent(double itemExtent, TextStyle? textStyle) {
    return SizedBox(
      height: 240,
      child: Row(
        key: const ValueKey('wheel'),
        children: [
          Expanded(
            child: _wheel(
              count: 24,
              controller: _hCtrl,
              onSelected: (v) => _setH(v, fromWheel: true),
              itemExtent: itemExtent,
              textStyle: textStyle,
            ),
          ),
          _colon(context),
          Expanded(
            child: _wheel(
              count: 60,
              controller: _mCtrl,
              onSelected: (v) => _setM(v, fromWheel: true),
              itemExtent: itemExtent,
              textStyle: textStyle,
            ),
          ),
          _colon(context),
          Expanded(
            child: _wheel(
              count: 60,
              controller: _sCtrl,
              onSelected: (v) => _setS(v, fromWheel: true),
              itemExtent: itemExtent,
              textStyle: textStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _colon(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(':', style: Theme.of(context).textTheme.headlineSmall),
      );

  Widget _wheel({
    required int count,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onSelected,
    required double itemExtent,
    required TextStyle? textStyle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: itemExtent,
          physics: const FixedExtentScrollPhysics(),
          useMagnifier: true,
          magnification: 1.12,
          diameterRatio: 2.0, // flatter for readability
          overAndUnderCenterOpacity: 0.45,
          onSelectedItemChanged: onSelected,
          childDelegate: ListWheelChildBuilderDelegate(
            builder: (context, index) {
              if (index < 0 || index >= count) return null;
              return Center(
                child: Text(
                  _two(index),
                  style: textStyle,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------- Numeric (stepper) mode ----------
  Widget _numericContent(TextStyle? textStyle) {
    return Row(
      key: const ValueKey('numeric'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _StepperField(
            label: 'HH',
            controller: _hText,
            min: 0,
            max: 23,
            onChanged: (v) => _setH(v, fromField: true),
          ),
        ),
        _colon(context),
        Expanded(
          child: _StepperField(
            label: 'MM',
            controller: _mText,
            min: 0,
            max: 59,
            onChanged: (v) => _setM(v, fromField: true),
          ),
        ),
        _colon(context),
        Expanded(
          child: _StepperField(
            label: 'SS',
            controller: _sText,
            min: 0,
            max: 59,
            onChanged: (v) => _setS(v, fromField: true),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Stepper text field (00-59 style) with up/down arrow buttons and press&hold
// -----------------------------------------------------------------------------
class _StepperField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperField({
    required this.label,
    required this.controller,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_StepperField> createState() => _StepperFieldState();
}

class _StepperFieldState extends State<_StepperField> {
  Timer? _holdTimer;

  int get _value => int.tryParse(widget.controller.text) ?? widget.min;

  void _update(int v) {
    final clamped = v.clamp(widget.min, widget.max);
    if (mounted) {
      widget.controller.text = clamped.toString().padLeft(2, '0');
      widget.onChanged(clamped);
      // HapticFeedback.selectionClick(); // optional haptic
    }
  }

  void _startHold(bool up) {
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      _update(_value + (up ? 1 : -1));
    });
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  @override
  void dispose() {
    _stopHold();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 85,
      child: Column(
        children: [
          Text(widget.label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _HoldableIconButton(
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Increase',
                  onTap: () => _update(_value + 1),
                  onHoldStart: () => _startHold(true),
                  onHoldEnd: _stopHold,
                ),
                Expanded(
                  child: TextFormField(
                    controller: widget.controller,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    ),
                    onChanged: (txt) {
                      final v = int.tryParse(txt) ?? widget.min;
                      if (txt.length <= 2) {
                        // don’t clamp while typing unless out of range wildly
                        final clamped = v.clamp(widget.min, widget.max);
                        widget.onChanged(clamped);
                      }
                    },
                    onEditingComplete: () {
                      final v =
                          int.tryParse(widget.controller.text) ?? widget.min;
                      _update(v);
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
                _HoldableIconButton(
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Decrease',
                  onTap: () => _update(_value - 1),
                  onHoldStart: () => _startHold(false),
                  onHoldEnd: _stopHold,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Small helper for press & hold repetition on icon buttons
class _HoldableIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  const _HoldableIconButton({
    required this.icon,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = IconButton(
      icon: Icon(icon),
      onPressed: onTap,
      tooltip: tooltip,
    );
    return GestureDetector(
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      child: btn,
    );
  }
}
