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
  final adb = dbWrap.db; // AppDatabase helpers you added
  final rows = await adb.selectHistoryViews();
  final out = <SavedHistoryView>[];
  for (final v in rows) {
    final keys = await adb.getHistoryViewKeys(v.id);
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

  const _HistoryGraphPane({
    required this.keys,
    required this.realtime,
    required this.range,
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

            final List<Map<GraphDataConfig, List<List<double>>>> graphData = [];
            for (int i = 0; i < widget.keys.length; i++) {
              final seriesKey = widget.keys[i];
              final seriesData = data[i];
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

              graphData.add({
                GraphDataConfig(
                  label: seriesKey,
                  mainAxis: true,
                  color: GraphConfig.colors[i % GraphConfig.colors.length],
                ): points,
              });
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
                    data: graphData,
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

  late final TabController _tab = TabController(length: 2, vsync: this);

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
            // Left pane: Key search + list
            Expanded(
              flex: 2,
              child: _buildKeyPicker(context),
            ),
            const SizedBox(width: 24),
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

    return Wrap(
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
              dropdownValue =
                  uniqueViews.where((v) => v.id == _activeView!.id).firstOrNull;
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
        // Delete view
        ElevatedButton.icon(
          icon: const Icon(Icons.delete),
          label: const Text('Delete view'),
          onPressed: _activeView == null ? null : _deleteView,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
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
    );
  }

  Future<void> _saveView() async {
    final dbWrap = await ref.read(databaseProvider.future);
    if (!context.mounted) return;
    if (dbWrap == null) {
      _toast(context, 'Database not ready yet.');
      return;
    }
    final adb = dbWrap.db;

    final name = await _askName(context,
        initial: _activeView?.name ?? '',
        title: _activeView == null ? 'Save View' : 'Update View');
    if (name == null || name.trim().isEmpty) return;

    if (_activeView == null) {
      final id = await adb.createHistoryView(name.trim(), _selected.toList());
      setState(() => _activeView = SavedHistoryView(
          id: id, name: name.trim(), keys: _selected.toList()));
    } else {
      await adb.updateHistoryView(
          _activeView!.id, name.trim(), _selected.toList());
      setState(() => _activeView = SavedHistoryView(
          id: _activeView!.id, name: name.trim(), keys: _selected.toList()));
    }
    ref.invalidate(savedViewsProvider);
    _toast(context, 'Saved "${name.trim()}"');
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

    final id = await adb.createHistoryView(name.trim(), _selected.toList());
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

    await adb.updateHistoryView(_activeView!.id, name, _selected.toList());

    setState(() => _activeView = SavedHistoryView(
        id: _activeView!.id, name: name, keys: _selected.toList()));
    ref.invalidate(savedViewsProvider);
    _toast(context, 'Updated "${name}"');
  }
}
