import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:board_datetime_picker/board_datetime_picker.dart';

import '../widgets/button_graph.dart';
import '../widgets/base_scaffold.dart';
import '../widgets/history_graph_pane.dart';
import '../widgets/history_table_pane.dart';

import '../providers/state_man.dart'; // stateManProvider
import '../providers/database.dart'; // databaseProvider (Future<Database?>)

import '../models/history_models.dart';

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
  try {
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
  } catch (e, st) {
    Logger().e('savedViewsProvider error: $e', error: e, stackTrace: st);
    rethrow;
  }
});

// -----------------------------------------------------------------------------
// Saved Periods per View
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SavedPeriod && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
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

class _HistoryViewPageState extends ConsumerState<HistoryViewPage> {
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

  // Real-time window duration
  Duration _realtimeWindow = const Duration(minutes: 10);

  // Rename to avoid conflict with the widget's GraphConfig
  final Map<String, GraphKeyConfig> _keyConfigs = <String, GraphKeyConfig>{};
  final Map<int, GraphDisplayConfig> _graphConfigs =
      <int, GraphDisplayConfig>{};

  int _tabIndex = 0; // 0 = Graph, 1 = Table
  int _targetGraphIndex = 0; // Which graph new keys are assigned to

  @override
  void initState() {
    super.initState();
    _updateGraphConfigs();
    _updateKeyConfigs();
  }

  @override
  void dispose() {
    super.dispose();
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
          graphIndex: _targetGraphIndex,
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
                  const SizedBox(height: 4),
                  Expanded(
                    child: _tabIndex == 0
                        ? HistoryGraphPane(
                            keys: _selected.toList(),
                            realtime: _realtime,
                            range: _range,
                            realtimeDuration: _realtimeDuration,
                            graphConfigs: _keyConfigs,
                            graphDisplayConfigs: _graphConfigs,
                            onEditGraph: _showGraphEditDialog,
                            onSelectGraph: (i) =>
                                setState(() => _targetGraphIndex = i),
                            onSwapGraphs: _swapGraphs,
                            targetGraphIndex: _targetGraphIndex,
                          )
                        : HistoryTablePane(
                            keys: _selected.toList(),
                            realtime: _realtime,
                            range: _range,
                            realtimeDuration: _realtimeDuration,
                            graphConfigs: _keyConfigs,
                            rows: _realtime ? 100 : -1,
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

    final canSave = _selected.isNotEmpty &&
        dbAsync.when(
          data: (db) => db != null,
          loading: () => false,
          error: (_, __) => false,
        );

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
                child: Text(
                  'Keys',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
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
              final collected = collectedAsync.when(
                data: (data) => data,
                loading: () => const <String>{},
                error: (_, __) => const <String>{},
              );
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

        const Divider(height: 16),
        // View management
        Consumer(
          builder: (context, ref, _) {
            final viewsAsync = ref.watch(savedViewsProvider);
            return viewsAsync.when(
              data: (views) {
                final uniqueViews = <SavedHistoryView>[];
                final seenIds = <int>{};
                for (final view in views) {
                  if (!seenIds.contains(view.id)) {
                    seenIds.add(view.id);
                    uniqueViews.add(view);
                  }
                }

                SavedHistoryView? dropdownValue;
                if (_activeView != null) {
                  for (final v in uniqueViews) {
                    if (v.id == _activeView!.id) {
                      dropdownValue = v;
                      break;
                    }
                  }
                }

                return Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Saved view',
                          border: OutlineInputBorder(),
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: dropdownValue != null
                                ? dropdownValue.id
                                : -1,
                            isExpanded: true,
                            isDense: true,
                            onChanged: (id) {
                              setState(() {
                                if (id == null || id == -1) {
                                  _activeView = null;
                                  _activePeriod = null;
                                } else {
                                  final v = uniqueViews
                                      .firstWhere((v) => v.id == id);
                                  _activeView = v;
                                  _activePeriod = null;
                                  _selected
                                    ..clear()
                                    ..addAll(v.keys);
                                  _updateKeyConfigs();
                                  _loadGraphConfigsFromView(v.id);
                                }
                              });
                            },
                            items: [
                              const DropdownMenuItem(
                                value: -1,
                                child: Text('None',
                                    style: TextStyle(
                                        fontStyle: FontStyle.italic)),
                              ),
                              for (final v in uniqueViews)
                                DropdownMenuItem(
                                  value: v.id,
                                  child: Text(v.name),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_activeView != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: _deleteView,
                        tooltip: 'Delete view',
                        style: IconButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 20,
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (e, _) => Text('Views err: $e'),
            );
          },
        ),
        const SizedBox(height: 8),
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
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // ── View mode: Graph / Table ──
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Table')),
              ButtonSegment(value: 0, label: Text('Graph')),
            ],
            selected: {_tabIndex},
            onSelectionChanged: (v) => setState(() => _tabIndex = v.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),

          // ── Add graph (only in graph mode) ──
          if (_tabIndex == 0)
            IconButton(
              onPressed: _addGraph,
              icon: const Icon(Icons.add_chart, size: 20),
              tooltip: 'Add graph',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),

          const SizedBox(width: 12),

          // ── Time mode: Realtime / Historical ──
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Realtime')),
              ButtonSegment(value: false, label: Text('Historical')),
            ],
            selected: {_realtime},
            onSelectionChanged: (v) => setState(() {
              _realtime = v.first;
              if (_realtime) {
                _range = null;
                _activePeriod = null;
              }
            }),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // ── Time parameters ──
          if (_realtime)
            _buildWindowChip(context, cs),
          if (!_realtime) ...[
            Flexible(
              child: _buildDateRangeChip(context, cs),
            ),
            if (_activeView != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: _buildSavedPeriodsSection(context, cs),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDateRangeChip(BuildContext context, ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        final picked = await showSetDatePicker(context, _range);
        if (picked != null) {
          setState(() {
            _range = picked;
            _activePeriod = null;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline.withAlpha(80)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _range == null
                    ? 'Pick range…'
                    : _rangeLabel(_range!),
                style: TextStyle(fontSize: 12, color: cs.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  Widget _buildWindowChip(BuildContext context, ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        final now = DateTime.now();
        final initial = DateTime(now.year, now.month, now.day,
            _realtimeWindow.inHours, _realtimeWindow.inMinutes.remainder(60),
            _realtimeWindow.inSeconds.remainder(60));

        final result = await showBoardDateTimePicker(
          context: context,
          pickerType: DateTimePickerType.time,
          initialDate: initial,
          minimumDate: DateTime(now.year, now.month, now.day, 0, 0, 1),
          maximumDate: DateTime(now.year, now.month, now.day, 23, 59, 59),
          options: BoardDateTimeOptions(
            textColor: Theme.of(context).colorScheme.onSurface,
            activeTextColor: Theme.of(context).colorScheme.onTertiary,
            activeColor: Theme.of(context).colorScheme.tertiary,
            languages: const BoardPickerLanguages.en(),
            withSecond: true,
            boardTitle: 'Window Duration',
            pickerSubTitles: BoardDateTimeItemTitles(
              hour: 'Hours',
              minute: 'Minutes',
              second: 'Seconds',
            ),
          ),
        );

        if (result != null) {
          setState(() {
            _realtimeWindow = Duration(
              hours: result.hour,
              minutes: result.minute,
              seconds: result.second,
            );
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline.withAlpha(80)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Window: ${_fmtDuration(_realtimeWindow)}',
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedPeriodsSection(BuildContext context, ColorScheme cs) {
    return Consumer(builder: (context, ref, _) {
      final periodsAsync =
          ref.watch(savedPeriodsProvider(_activeView!.id));
      final horizonAsync = ref.watch(retentionHorizonProvider);

      return periodsAsync.when(
        data: (periods) {
          final horizon = horizonAsync.when(
            data: (data) => data,
            loading: () => null,
            error: (_, __) => null,
          );
          SavedPeriod? dropdownValue;
          if (_activePeriod != null) {
            for (final p in periods) {
              if (p.id == _activePeriod!.id) {
                dropdownValue = p;
                break;
              }
            }
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: DropdownButton<SavedPeriod?>(
                  value: dropdownValue,
                  hint: Text('Periods…',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  isExpanded: true,
                  icon: Icon(Icons.unfold_more, size: 16, color: cs.onSurfaceVariant),
                  onChanged: (p) {
                    setState(() {
                      _activePeriod = p;
                      if (p != null) {
                        _realtime = false;
                        _range = DateTimeRange(
                            start: p.start, end: p.end);
                      }
                    });
                  },
                  items: [
                    DropdownMenuItem<SavedPeriod?>(
                      value: null,
                      child: Text('None',
                          style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: cs.onSurfaceVariant)),
                    ),
                    for (final p in periods)
                      DropdownMenuItem(
                        value: p,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _validityIcon(
                              context,
                              validityForRange(
                                DateTimeRange(
                                    start: p.start, end: p.end),
                                horizon,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(p.name,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: (_activeView != null &&
                        !_realtime &&
                        _range != null)
                    ? _saveCurrentRangeAsPeriod
                    : null,
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                tooltip: 'Save current range as period',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              if (_activePeriod != null)
                IconButton(
                  onPressed: () => _deletePeriod(
                      _activePeriod!,
                      horizonAsync.when(
                        data: (data) => data,
                        loading: () => null,
                        error: (_, __) => null,
                      )),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete selected period',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          );
        },
        loading: () => const SizedBox(
          width: 80,
          height: 16,
          child: LinearProgressIndicator(minHeight: 2),
        ),
        error: (e, _) => Text('Err: $e', style: const TextStyle(fontSize: 11)),
      );
    });
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
          name: (raw['name'] as String?) ?? '',
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
        'name': config.name,
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
        'name': config.name,
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

  // ---- Per-graph edit dialog --------------------------------------------------

  void _showGraphEditDialog(int graphIndex) {
    _updateGraphConfigs();
    final graphConfig = _graphConfigs[graphIndex] ??
        GraphDisplayConfig(index: graphIndex);
    final nameCtrl = TextEditingController(text: graphConfig.name);
    final yUnitCtrl = TextEditingController(text: graphConfig.yAxisUnit);
    final y2UnitCtrl = TextEditingController(text: graphConfig.yAxis2Unit);

    // Keys on this graph
    final keysOnGraph = <String>{};
    for (final e in _keyConfigs.entries) {
      if (e.value.graphIndex == graphIndex) keysOnGraph.add(e.key);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final sortedKeysOnGraph = keysOnGraph.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          return AlertDialog(
            title: TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Graph ${graphIndex + 1}',
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: Theme.of(ctx).textTheme.headlineSmall,
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Y-axis units
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: yUnitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Y-axis unit',
                            border: OutlineInputBorder(),
                            hintText: 'e.g. °C, RPM',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: y2UnitCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Y2-axis unit',
                            border: OutlineInputBorder(),
                            hintText: 'e.g. bar, V',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Keys on this graph:',
                      style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (keysOnGraph.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No keys assigned to this graph yet.\nSelect this graph, then check keys in the left pane.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView(
                        shrinkWrap: true,
                        children: sortedKeysOnGraph.map((key) {
                          final config = _keyConfigs[key];
                          return ListTile(
                            dense: true,
                            title: Text(
                              config?.alias != key
                                  ? '${config?.alias ?? key}  ($key)'
                                  : key,
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Y1',
                                      style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('Y2',
                                      style: TextStyle(fontSize: 11)),
                                ),
                              ],
                              selected: {
                                config?.useSecondYAxis ?? false
                              },
                              onSelectionChanged: (v) {
                                setState(() {
                                  _keyConfigs[key] = config!
                                      .copyWith(useSecondYAxis: v.first);
                                });
                                setDialogState(() {});
                              },
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              // Remove graph (only if there are other graphs with keys)
              if (keysOnGraph.isNotEmpty || _keyConfigs.values.any((c) => c.graphIndex != graphIndex))
                TextButton(
                  onPressed: () {
                    final fallback = graphIndex == 0 ? 1 : 0;
                    setState(() {
                      // Move all keys from this graph to the fallback
                      for (final key in keysOnGraph) {
                        _keyConfigs[key] = _keyConfigs[key]!
                            .copyWith(graphIndex: fallback);
                      }
                      // Reset display config
                      _graphConfigs.remove(graphIndex);
                      _updateGraphConfigs();
                      if (_targetGraphIndex == graphIndex) {
                        _targetGraphIndex = fallback;
                      }
                    });
                    Navigator.pop(ctx);
                    if (_activeView != null) _updateView();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  child: const Text('Remove graph'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _graphConfigs[graphIndex] = GraphDisplayConfig(
                      index: graphIndex,
                      name: nameCtrl.text.trim(),
                      yAxisUnit: yUnitCtrl.text,
                      yAxis2Unit: y2UnitCtrl.text,
                    );
                  });
                  Navigator.pop(ctx);
                  if (_activeView != null) _updateView();
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addGraph() {
    // Find next available graph index (max 5)
    final usedIndices = <int>{};
    for (final c in _keyConfigs.values) {
      usedIndices.add(c.graphIndex);
    }
    int next = 0;
    for (int i = 0; i < 5; i++) {
      if (!usedIndices.contains(i)) {
        next = i;
        break;
      }
      next = i + 1;
    }
    if (next >= 5) {
      _toast(context, 'Maximum 5 graphs');
      return;
    }
    setState(() {
      _targetGraphIndex = next;
      _updateGraphConfigs();
    });
  }

  void _swapGraphs(int fromIndex, int toIndex) {
    setState(() {
      // Keep target graph index in sync with the swap
      if (_targetGraphIndex == fromIndex) {
        _targetGraphIndex = toIndex;
      } else if (_targetGraphIndex == toIndex) {
        _targetGraphIndex = fromIndex;
      }

      // Swap graphIndex for all keys assigned to either graph
      for (final key in _keyConfigs.keys.toList()) {
        final config = _keyConfigs[key]!;
        if (config.graphIndex == fromIndex) {
          _keyConfigs[key] = config.copyWith(graphIndex: toIndex);
        } else if (config.graphIndex == toIndex) {
          _keyConfigs[key] = config.copyWith(graphIndex: fromIndex);
        }
      }

      // Swap display configs
      final a = _graphConfigs[fromIndex];
      final b = _graphConfigs[toIndex];
      if (a != null && b != null) {
        _graphConfigs[fromIndex] = b.copyWith(index: fromIndex);
        _graphConfigs[toIndex] = a.copyWith(index: toIndex);
      } else if (a != null) {
        _graphConfigs[toIndex] = a.copyWith(index: toIndex);
        _graphConfigs.remove(fromIndex);
      } else if (b != null) {
        _graphConfigs[fromIndex] = b.copyWith(index: fromIndex);
        _graphConfigs.remove(toIndex);
      }
    });
  }

  // ---- DateTime range picker with seconds -----------------------------------

  static String _fmtDT(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.year)}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  String _rangeLabel(DateTimeRange r) =>
      '${_fmtDT(r.start)} → ${_fmtDT(r.end)}';

  // Get the current real-time duration
  Duration get _realtimeDuration {
    if (_realtimeWindow.inSeconds <= 0) return const Duration(minutes: 1);
    return _realtimeWindow;
  }
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
          trailing: Checkbox(
            value: selected.contains(keyName),
            onChanged: (_) => onToggleKey(keyName),
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



