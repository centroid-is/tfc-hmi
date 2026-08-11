import 'dart:async';
import 'package:tfc/widgets/panes/standard_dialog.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../widgets/base_scaffold.dart';
import '../widgets/proposal_visual.dart';
import '../providers/proposal_state.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart' show ModbusDataType;
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:jbtm/src/m2400.dart' show M2400RecordType;
import '../widgets/fuzzy_search_bar.dart';
import '../widgets/bit_mask_grid.dart';
import '../widgets/key_mapping_sections.dart';
import '../providers/preferences.dart';
import '../providers/state_man.dart';
import '../providers/database.dart';

/// Extension to find a [ModbusConfig] by server alias without nullable cast.
extension ModbusConfigListExt on List<ModbusConfig> {
  ModbusConfig? findByAlias(String? alias) {
    if (alias == null) return null;
    for (final c in this) {
      if (c.serverAlias == alias) return c;
    }
    return null;
  }
}

enum _KeyStatus { ok, error, serverDisconnected, serverDisabled }

/// The full page widget with BaseScaffold (used in navigation).
class KeyRepositoryPage extends ConsumerWidget {
  /// Optional proposal JSON passed via Beamer route data.
  final String? proposalData;

  KeyRepositoryPage({super.key, this.proposalData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseScaffold(
      title: 'Key Repository',
      body: KeyRepositoryContent(proposalData: proposalData),
    );
  }
}

/// The content widget (testable without BaseScaffold).
class KeyRepositoryContent extends ConsumerWidget {
  /// Optional proposal JSON passed down from KeyRepositoryPage.
  final String? proposalData;

  const KeyRepositoryContent({super.key, this.proposalData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider);

    // The key list scrolls on its own (see [_KeyMappingsSection]) instead of
    // the whole page living in a SingleChildScrollView. A scroll view with a
    // shrink-wrapped list inside builds *every* key card up front, which is
    // what made a repository with thousands of keys crawl.
    final content = Column(
      children: [
        // Database status indicator
        dbAsync.when(
          data: (db) {
            if (db != null) return const SizedBox.shrink();
            return _DatabaseStatusBanner(connected: false);
          },
          loading: () => _DatabaseStatusBanner(connected: false, loading: true),
          error: (_, __) => _DatabaseStatusBanner(connected: false),
        ),
        Expanded(child: _KeyMappingsSection(proposalData: proposalData)),
        const SizedBox(height: 16),
        _KeyMappingsImportExportCard(),
      ],
    );

    // Header, save button and import/export are fixed height; below this the
    // key list has no room left and the column would overflow. Fall back to
    // scrolling the page as a whole (the key list itself stays lazy).
    const minContentHeight = 320.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight >= minContentHeight) return content;
        return SingleChildScrollView(
          child: SizedBox(height: minContentHeight, child: content),
        );
      },
    );
  }
}

// ===================== Database Status Banner =====================

class _DatabaseStatusBanner extends StatelessWidget {
  final bool connected;
  final bool loading;

  const _DatabaseStatusBanner({
    required this.connected,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (connected) return const SizedBox.shrink();

    return Card(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red),
        ),
        child: Row(
          children: [
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const FaIcon(FontAwesomeIcons.circleExclamation,
                  color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                loading
                    ? 'Connecting to database...'
                    : 'Database not connected. Data collection will not work until the database is available.',
                style: TextStyle(
                  color: Colors.red[700],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== Key Mappings Section =====================

class _KeyMappingsSection extends ConsumerStatefulWidget {
  final String? proposalData;
  const _KeyMappingsSection({this.proposalData});
  @override
  ConsumerState<_KeyMappingsSection> createState() =>
      _KeyMappingsSectionState();
}

/// One row of the key list with its search fields pre-lowercased.
///
/// Lowercasing every key/identifier/alias on each keystroke was a large part
/// of the search lag; the index is built once per mutation instead.
class _KeyRow {
  final String key;
  final KeyMappingEntry entry;
  final List<String> searchFields;

  const _KeyRow(this.key, this.entry, this.searchFields);
}

class _KeyMappingsSectionState extends ConsumerState<_KeyMappingsSection> {
  KeyMappings? _keyMappings;

  /// Encoded snapshot of the last persisted mappings, used for the unsaved
  /// check. Kept as a string so the comparison is one cached encode instead
  /// of re-serialising both sides on every build.
  String? _savedJson;
  StateManConfig? _stateManConfig;
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  final Map<String, _KeyStatus> _keyStatuses = {};

  /// Expansion state lives here rather than in the cards: the list is lazy,
  /// so a card scrolled out of view is destroyed and would otherwise forget
  /// that the operator had it open.
  final Set<String> _expandedKeys = {};

  final ScrollController _listController = ScrollController();

  // ---- Derived caches, all invalidated by [_invalidateDerived] ----
  String? _currentJsonCache;
  List<_KeyRow>? _rowsCache;
  String? _filterCacheQuery;
  List<_KeyRow>? _filterCache;
  List<String> _serverAliases = const [];
  List<String> _jbtmServerAliases = const [];
  List<String> _modbusServerAliases = const [];

  /// Coalesces the per-key status updates produced by [_probeKeys] into at
  /// most one rebuild per 250 ms.
  Timer? _statusFlushTimer;
  bool _statusDirty = false;

  /// Proposal state
  Map<String, dynamic>? _proposedMapping;
  bool _isProposal = false;
  int? _proposalId;

  @override
  void initState() {
    super.initState();
    _loadKeyMappings();
    _parseKeyMappingProposal(widget.proposalData);
  }

  @override
  void dispose() {
    _statusFlushTimer?.cancel();
    _listController.dispose();
    super.dispose();
  }

  /// Drops every cache derived from [_keyMappings]. Call from anything that
  /// mutates the mappings.
  void _invalidateDerived() {
    _currentJsonCache = null;
    _rowsCache = null;
    _filterCache = null;
    _filterCacheQuery = null;
  }

  /// Parses key mapping proposal JSON.
  ///
  /// Sets [_proposedMapping] and [_isProposal] on success.
  /// Gracefully handles invalid JSON.
  void _parseKeyMappingProposal(String? json) {
    if (json == null) return;

    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['_proposal_type'] as String?;
      if (type != 'key_mapping') return;

      _proposedMapping = decoded;
      _isProposal = true;

      // Match against universal proposal state for ID tracking.
      try {
        final state = ref.read(proposalStateProvider);
        for (final p in state.proposals) {
          if (p.proposalJson == json) {
            _proposalId = p.id;
            break;
          }
        }
      } catch (_) {}
    } catch (_) {
      // Graceful: malformed JSON ignored.
    }
  }

  Future<void> _loadKeyMappings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await ref.read(preferencesProvider.future);
      _keyMappings = await KeyMappings.fromPrefs(prefs);
      _invalidateDerived();
      _savedJson = _currentJson();
      _stateManConfig = await StateManConfig.fromPrefs(prefs);
      _rebuildAliasLists();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _probeKeys();
      }
    }
  }

  String _currentJson() =>
      _currentJsonCache ??= jsonEncode(_keyMappings!.toJson());

  bool get _hasUnsavedChanges {
    if (_keyMappings == null || _savedJson == null) return false;
    return _currentJson() != _savedJson;
  }

  Future<void> _saveKeyMappings() async {
    if (_keyMappings == null) return;
    // Unfocus active text field to commit pending changes (e.g. key rename)
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final prefs = await ref.read(preferencesProvider.future);
      // Unfocusing above may have committed a rename, so re-encode.
      _invalidateDerived();
      final json = _currentJson();
      await prefs.setString('key_mappings', json);
      _savedJson = json;
      ref.invalidate(stateManProvider);
      if (!mounted) return;
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Key mappings saved successfully!'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  final Map<String, GlobalKey> _cardKeys = {};

  /// Scrolls the newly added/duplicated [name] into view once it is laid out.
  ///
  /// The list is lazy, so a card appended past the bottom of the viewport has
  /// no element yet and [Scrollable.ensureVisible] has nothing to target. When
  /// the key is the last one — which is where [_addKey] puts it — jump to the
  /// end of the list and retry on the following frame. A key inserted mid-list
  /// (a duplicate) sits next to its original, which is on screen, so its card
  /// is already built; jumping to the end for that case would scroll the
  /// operator somewhere they didn't ask to go.
  void _revealKey(String name) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final keyContext = _cardKeys[name]?.currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(keyContext,
            duration: const Duration(milliseconds: 300));
        return;
      }
      final isLast = _keyMappings?.nodes.keys.lastOrNull == name;
      if (!isLast || !_listController.hasClients) return;
      _listController.jumpTo(_listController.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _cardKeys[name]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx);
      });
    });
  }

  void _addKey() {
    final baseName = 'new_key';
    var name = baseName;
    var i = 1;
    while (_keyMappings!.nodes.containsKey(name)) {
      name = '${baseName}_$i';
      i++;
    }
    _cardKeys[name] = GlobalKey();
    _expandedKeys.add(name);
    setState(() {
      _keyMappings!.nodes[name] = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(namespace: 0, identifier: ''),
      );
      _invalidateDerived();
    });
    _revealKey(name);
  }

  void _duplicateKey(String key) {
    final original = _keyMappings!.nodes[key];
    if (original == null) return;
    final copy = KeyMappingEntry.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
    var newName = '${key}_copy';
    var i = 1;
    while (_keyMappings!.nodes.containsKey(newName)) {
      newName = '${key}_copy_$i';
      i++;
    }
    if (copy.collect != null) {
      copy.collect!.key = newName;
    }
    _cardKeys[newName] = GlobalKey();
    _expandedKeys.add(newName);
    // Insert copy right after the original, preserving order
    final newNodes = <String, KeyMappingEntry>{};
    for (final kv in _keyMappings!.nodes.entries) {
      newNodes[kv.key] = kv.value;
      if (kv.key == key) {
        newNodes[newName] = copy;
      }
    }
    setState(() {
      _keyMappings!.nodes = newNodes;
      _invalidateDerived();
    });
    _revealKey(newName);
  }

  void _removeKey(String key) {
    _cardKeys.remove(key);
    _keyStatuses.remove(key);
    _expandedKeys.remove(key);
    setState(() {
      _keyMappings!.nodes.remove(key);
      _invalidateDerived();
    });
  }

  /// Requests a rebuild for freshly probed statuses, at most once per 250 ms.
  ///
  /// Probing thousands of keys used to rebuild the whole page per key (and
  /// copy the status map each time, making it quadratic).
  void _scheduleStatusFlush() {
    _statusDirty = true;
    if (_statusFlushTimer != null) return;
    _statusFlushTimer = Timer(const Duration(milliseconds: 250), () {
      _statusFlushTimer = null;
      if (!mounted || !_statusDirty) return;
      _statusDirty = false;
      setState(() {});
    });
  }

  Future<void> _probeKeys() async {
    if (_keyMappings == null || _keyMappings!.nodes.isEmpty) return;

    final stateManAsync = ref.read(stateManProvider);
    final stateMan = stateManAsync.valueOrNull;
    if (stateMan == null) return;

    final keys = _keyMappings!.nodes.keys.toList();
    for (final key in keys) {
      if (!mounted) return;
      // The operator can rename or delete keys while a long probe runs.
      // Statuses are written in place now, so skip keys that are gone —
      // otherwise the map keeps entries no card will ever read, and a key
      // later given that same name inherits a stale status.
      if (!_keyMappings!.nodes.containsKey(key)) {
        _keyStatuses.remove(key);
        continue;
      }
      // Keys on a disabled server have nothing to probe — reading them
      // would just burn the 5 s timeout each, one key at a time.
      if (stateMan.isKeyDisabled(key)) {
        _keyStatuses[key] = _KeyStatus.serverDisabled;
        _scheduleStatusFlush();
        continue;
      }
      try {
        await stateMan.read(key).timeout(const Duration(seconds: 5));
        _keyStatuses[key] = _KeyStatus.ok;
      } on TimeoutException {
        _keyStatuses[key] = _KeyStatus.serverDisconnected;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('not found') || msg.contains('connect')) {
          _keyStatuses[key] = _KeyStatus.serverDisconnected;
        } else {
          _keyStatuses[key] = _KeyStatus.error;
        }
      }
      _scheduleStatusFlush();
    }
  }

  void _renameKey(String oldKey, String newKey) {
    if (oldKey == newKey) return;
    if (_keyMappings!.nodes.containsKey(newKey)) return;
    final entry = _keyMappings!.nodes[oldKey];
    if (entry == null) return;
    if (entry.collect != null) {
      entry.collect!.key = newKey;
    }
    final cardKey = _cardKeys.remove(oldKey);
    if (cardKey != null) _cardKeys[newKey] = cardKey;
    final status = _keyStatuses.remove(oldKey);
    if (status != null) _keyStatuses[newKey] = status;
    if (_expandedKeys.remove(oldKey)) _expandedKeys.add(newKey);
    // Rebuild map preserving insertion order
    final newNodes = <String, KeyMappingEntry>{};
    for (final kv in _keyMappings!.nodes.entries) {
      newNodes[kv.key == oldKey ? newKey : kv.key] = kv.value;
    }
    setState(() {
      _keyMappings!.nodes = newNodes;
      _invalidateDerived();
    });
  }

  void _updateEntry(String key, KeyMappingEntry entry) {
    setState(() {
      _keyMappings!.nodes[key] = entry;
      _invalidateDerived();
    });
  }

  /// Reorders the key at [oldIndex] to [newIndex] in the underlying
  /// [_keyMappings.nodes] map.
  ///
  /// [oldIndex] and [newIndex] are indices into the current iteration
  /// order of the map (which equals the rendered list when no search
  /// filter is active — reorder is disabled while a search query is
  /// in effect, so this assumption holds).
  ///
  /// Follows the ReorderableListView convention: if [newIndex] is
  /// greater than [oldIndex], it must be decremented by one to land
  /// at the intended slot (because the item is conceptually removed
  /// first, then inserted).
  void _reorderKey(int oldIndex, int newIndex) {
    if (_keyMappings == null) return;
    if (oldIndex == newIndex) return;
    final entries = _keyMappings!.nodes.entries.toList();
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target > entries.length - 1) target = entries.length - 1;
    if (target == oldIndex) return;
    final moved = entries.removeAt(oldIndex);
    entries.insert(target, moved);
    final newNodes = <String, KeyMappingEntry>{};
    for (final kv in entries) {
      newNodes[kv.key] = kv.value;
    }
    setState(() {
      _keyMappings!.nodes = newNodes;
      _invalidateDerived();
    });
  }

  /// The key list with search fields pre-lowercased. Rebuilt only when the
  /// mappings change, not on every keystroke.
  List<_KeyRow> get _rows {
    if (_keyMappings == null) return const [];
    return _rowsCache ??= [
      for (final e in _keyMappings!.nodes.entries)
        _KeyRow(e.key, e.value, [
          e.key.toLowerCase(),
          (e.value.opcuaNode?.identifier ?? '').toLowerCase(),
          (e.value.opcuaNode?.serverAlias ??
                  e.value.m2400Node?.serverAlias ??
                  e.value.modbusNode?.serverAlias ??
                  '')
              .toLowerCase(),
        ]),
    ];
  }

  List<_KeyRow> get _filteredEntries {
    final rows = _rows;
    if (_searchQuery.isEmpty) return rows;
    if (_filterCache != null && _filterCacheQuery == _searchQuery) {
      return _filterCache!;
    }
    final q = _searchQuery.toLowerCase();
    final matched = <_KeyRow>[];
    for (final row in rows) {
      for (final field in row.searchFields) {
        if (fuzzyMatch(field, q)) {
          matched.add(row);
          break;
        }
      }
    }
    _filterCacheQuery = _searchQuery;
    return _filterCache = matched;
  }

  /// The three server-alias lists used to be getters that rebuilt on every
  /// build and were handed to every card. They only change when the config
  /// is (re)loaded.
  void _rebuildAliasLists() {
    final cfg = _stateManConfig;
    _serverAliases = _nonEmptyAliases(cfg?.opcua.map((c) => c.serverAlias));
    _jbtmServerAliases = _nonEmptyAliases(cfg?.jbtm.map((c) => c.serverAlias));
    _modbusServerAliases =
        _nonEmptyAliases(cfg?.modbus.map((c) => c.serverAlias));
  }

  static List<String> _nonEmptyAliases(Iterable<String?>? aliases) => [
        for (final a in aliases ?? const <String?>[])
          if (a != null && a.isNotEmpty) a,
      ];

  @override
  Widget build(BuildContext context) {
    // Reactively watch for new key mapping proposals arriving via MCP.
    ref.listen<ProposalState>(proposalStateProvider, (prev, next) {
      if (_isProposal) return; // Already showing a proposal.
      final keyProposals =
          next.proposals.where((p) => p.proposalType == 'key_mapping');
      if (keyProposals.isEmpty) return;
      final proposal = keyProposals.first;
      _parseKeyMappingProposal(proposal.proposalJson);
      if (_isProposal) setState(() {});
    });

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(FontAwesomeIcons.triangleExclamation,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Error loading key mappings: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _loadKeyMappings, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredEntries;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Proposal banner
        if (_isProposal && _proposedMapping != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.amber.shade50,
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'AI Proposal: Map \'${_proposedMapping!['key']}\' '
                    'to OPC UA node',
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final key = _proposedMapping!['key'] as String?;
                    if (key != null && _keyMappings != null) {
                      final opcuaNode = _proposedMapping!['opcua_node'];
                      final mapping = KeyMappingEntry();
                      if (opcuaNode is Map<String, dynamic>) {
                        mapping.opcuaNode = OpcUANodeConfig.fromJson(opcuaNode);
                      }
                      _keyMappings!.nodes[key] = mapping;
                      _expandedKeys.add(key);
                      // _saveKeyMappings() invalidates too, but only after
                      // its first await — the setState below would otherwise
                      // rebuild the list from a cache that predates this key.
                      _invalidateDerived();
                      _saveKeyMappings();
                    }
                    if (_proposalId != null) {
                      try {
                        ref
                            .read(proposalStateProvider.notifier)
                            .acceptProposal(_proposalId!);
                      } catch (_) {}
                    }
                    setState(() {
                      _isProposal = false;
                      _proposedMapping = null;
                    });
                    if (key != null) _revealKey(key);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Accept'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    if (_proposalId != null) {
                      try {
                        ref
                            .read(proposalStateProvider.notifier)
                            .rejectProposal(_proposalId!);
                      } catch (_) {}
                    }
                    setState(() {
                      _isProposal = false;
                      _proposedMapping = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ),
        // Proposed key mapping inline display
        if (_isProposal && _proposedMapping != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: proposalDecoration(),
            child: ListTile(
              leading: const ProposalBadge(),
              title: Text('${_proposedMapping!['key']}'),
              subtitle: Text('AI Proposed key mapping'),
            ),
          ),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 500;
                      if (isNarrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const FaIcon(FontAwesomeIcons.key, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text('Key Mappings',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                ),
                                if (_hasUnsavedChanges) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: const Text('Unsaved',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText: 'Search keys...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) =>
                                  setState(() => _searchQuery = value),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _addKey,
                              icon:
                                  const FaIcon(FontAwesomeIcons.plus, size: 16),
                              label: const Text('Add Key'),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Row(
                            children: [
                              const FaIcon(FontAwesomeIcons.key, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text('Key Mappings',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              if (_hasUnsavedChanges) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: const Text('Unsaved Changes',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                              const Spacer(),
                              SizedBox(
                                width: 200,
                                child: TextField(
                                  decoration: const InputDecoration(
                                    prefixIcon: Icon(Icons.search),
                                    hintText: 'Search keys...',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _addKey,
                                icon: const FaIcon(FontAwesomeIcons.plus,
                                    size: 16),
                                label: const Text('Add Key'),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Key list. Both branches scroll themselves and build lazily —
                  // only the cards on screen exist, so a repository with thousands
                  // of keys costs the same to render as one with ten.
                  Expanded(
                    child: filtered.isEmpty
                        ? const _EmptyKeysWidget()
                        : _searchQuery.isEmpty
                            ? ReorderableListView.builder(
                                scrollController: _listController,
                                buildDefaultDragHandles: false,
                                itemCount: filtered.length,
                                onReorder: _reorderKey,
                                itemBuilder: (context, index) => _buildCard(
                                    filtered[index],
                                    reorderIndex: index),
                              )
                            : ListView.builder(
                                controller: _listController,
                                itemCount: filtered.length,
                                itemBuilder: (context, index) =>
                                    _buildCard(filtered[index]),
                              ),
                  ),
                  const SizedBox(height: 16),
                  // Save button
                  Row(
                    children: [
                      if (_keyMappings!.nodes.isNotEmpty || _hasUnsavedChanges)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _hasUnsavedChanges ? _saveKeyMappings : null,
                            icon: FaIcon(FontAwesomeIcons.floppyDisk,
                                size: 16,
                                color: _hasUnsavedChanges ? null : Colors.grey),
                            label: Text(_hasUnsavedChanges
                                ? 'Save Key Mappings'
                                : 'All Changes Saved'),
                            style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor:
                                    _hasUnsavedChanges ? null : Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Builds one key card. [reorderIndex] is non-null only in the
  /// reorderable (unfiltered) list.
  Widget _buildCard(_KeyRow row, {int? reorderIndex}) {
    // Every card gets a stable GlobalKey keyed by entry name, not just
    // newly-added ones. _renameKey and _reorderKey both keep the GlobalKey
    // associated with the entry's current name, so it survives reorders and
    // renames alike.
    final cardKey = _cardKeys.putIfAbsent(row.key, () => GlobalKey());
    return _KeyMappingCard(
      key: cardKey,
      keyName: row.key,
      entry: row.entry,
      serverAliases: _serverAliases,
      jbtmServerAliases: _jbtmServerAliases,
      modbusServerAliases: _modbusServerAliases,
      modbusConfigs: _stateManConfig?.modbus ?? const [],
      onUpdate: (updated) => _updateEntry(row.key, updated),
      onRename: (newName) => _renameKey(row.key, newName),
      onCopy: () => _duplicateKey(row.key),
      onRemove: () => _showDeleteDialog(row.key),
      initiallyExpanded: _expandedKeys.contains(row.key),
      onExpansionChanged: (expanded) {
        // No setState: the tile animates itself, and this only needs to be
        // remembered for when the lazy list rebuilds the card.
        if (expanded) {
          _expandedKeys.add(row.key);
        } else {
          _expandedKeys.remove(row.key);
        }
      },
      status: _keyStatuses[row.key],
      reorderIndex: reorderIndex,
    );
  }

  void _showDeleteDialog(String key) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove key',
      message: 'Are you sure you want to remove "$key"?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed) _removeKey(key);
  }
}

// ===================== Empty State =====================

class _EmptyKeysWidget extends StatelessWidget {
  const _EmptyKeysWidget();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FaIcon(FontAwesomeIcons.key, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No keys configured',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('Add your first key mapping to get started',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ===================== Key Mapping Card =====================

class _KeyMappingCard extends StatefulWidget {
  final String keyName;
  final KeyMappingEntry entry;
  final List<String> serverAliases;
  final List<String> jbtmServerAliases;
  final List<String> modbusServerAliases;
  final List<ModbusConfig> modbusConfigs;
  final Function(KeyMappingEntry) onUpdate;
  final Function(String) onRename;
  final VoidCallback onCopy;
  final VoidCallback onRemove;
  final bool initiallyExpanded;

  /// Reported so the parent can remember expansion across the lazy list
  /// destroying and rebuilding this card as it scrolls.
  final ValueChanged<bool>? onExpansionChanged;
  final _KeyStatus? status;

  /// When non-null, this card is rendered inside a [ReorderableListView]
  /// and a drag handle is shown that lets the operator grab the card to
  /// reorder it. The value is the card's index in the reorderable list,
  /// which [ReorderableDragStartListener] uses to initiate the drag.
  final int? reorderIndex;

  const _KeyMappingCard({
    super.key,
    required this.keyName,
    required this.entry,
    required this.serverAliases,
    required this.jbtmServerAliases,
    required this.modbusServerAliases,
    required this.modbusConfigs,
    required this.onUpdate,
    required this.onRename,
    required this.onCopy,
    required this.onRemove,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.status,
    this.reorderIndex,
  });

  @override
  State<_KeyMappingCard> createState() => _KeyMappingCardState();
}

class _KeyMappingCardState extends State<_KeyMappingCard> {
  late TextEditingController _keyNameController;
  late FocusNode _keyNameFocusNode;
  bool _collectEnabled = false;

  @override
  void initState() {
    super.initState();
    _keyNameController = TextEditingController(text: widget.keyName);
    _keyNameFocusNode = FocusNode();
    _keyNameFocusNode.addListener(_onKeyNameFocusChange);
    _collectEnabled = widget.entry.collect != null;
  }

  @override
  void didUpdateWidget(covariant _KeyMappingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyName != widget.keyName &&
        _keyNameController.text != widget.keyName) {
      _keyNameController.text = widget.keyName;
    }
    if ((widget.entry.collect != null) != _collectEnabled) {
      _collectEnabled = widget.entry.collect != null;
    }
  }

  void _onKeyNameFocusChange() {
    if (!_keyNameFocusNode.hasFocus) {
      _submitKeyName(_keyNameController.text);
    }
  }

  void _submitKeyName(String value) {
    if (value.isNotEmpty && value != widget.keyName) {
      widget.onRename(value);
    }
  }

  @override
  void dispose() {
    _keyNameFocusNode.removeListener(_onKeyNameFocusChange);
    _keyNameFocusNode.dispose();
    _keyNameController.dispose();
    super.dispose();
  }

  bool get _isM2400 => widget.entry.m2400Node != null;
  bool get _isModbus => widget.entry.modbusNode != null;

  String _buildSubtitle() {
    if (_isModbus) {
      final node = widget.entry.modbusNode!;
      final variableName = widget.entry.variableName;
      // Prefer the UMAS symbol path over the Modbus address when the
      // mapping is bound by name — operators recognise their FB-instance
      // member names, not 'holdingRegister[N]'.
      if (variableName != null && variableName.isNotEmpty) {
        var subtitle = variableName;
        if (node.serverAlias != null && node.serverAlias!.isNotEmpty) {
          subtitle += ' @ ${node.serverAlias}';
        }
        return subtitle;
      }
      var subtitle = '${node.registerType.name}[${node.address}]';
      subtitle += ' ${node.dataType.name}';
      if (node.serverAlias != null && node.serverAlias!.isNotEmpty) {
        subtitle += ' @ ${node.serverAlias}';
      }
      return subtitle;
    }
    if (_isM2400) {
      final node = widget.entry.m2400Node!;
      var subtitle = 'REC=${node.recordType.name}(${node.recordType.id})';
      if (node.field != null) {
        subtitle += '; FLD=${node.field!.displayName}(${node.field!.id})';
      }
      if (node.serverAlias != null && node.serverAlias!.isNotEmpty) {
        subtitle += ' @ ${node.serverAlias}';
      }
      return subtitle;
    }
    final node = widget.entry.opcuaNode;
    if (node == null) return 'No config';
    var subtitle = 'ns=${node.namespace}; id=${node.identifier}';
    if (node.serverAlias != null && node.serverAlias!.isNotEmpty) {
      subtitle += ' @ ${node.serverAlias}';
    }
    if (node.arrayIndex != null) {
      subtitle += ' [${node.arrayIndex}]';
    }
    return subtitle;
  }

  void _updateOpcUaConfig(OpcUANodeConfig config) {
    widget.onUpdate(widget.entry.copyWith(opcuaNode: config));
  }

  void _updateM2400Config(M2400NodeConfig config) {
    widget.onUpdate(widget.entry.copyWith(m2400Node: config));
  }

  void _switchToM2400() {
    widget.onUpdate(KeyMappingEntry(
      m2400Node: M2400NodeConfig(recordType: M2400RecordType.recBatch),
      collect: widget.entry.collect,
    ));
  }

  void _switchToOpcUa() {
    widget.onUpdate(KeyMappingEntry(
      opcuaNode: OpcUANodeConfig(namespace: 0, identifier: ''),
      collect: widget.entry.collect,
      bitMask: widget.entry.bitMask,
      bitShift: widget.entry.bitShift,
    ));
  }

  void _switchToModbus() {
    widget.onUpdate(KeyMappingEntry(
      modbusNode: ModbusNodeConfig(
        registerType: ModbusRegisterType.holdingRegister,
        address: 0,
      ),
      collect: widget.entry.collect,
      bitMask: widget.entry.bitMask,
      bitShift: widget.entry.bitShift,
    ));
  }

  // TD-010 (v1.1.x): _updateModbusConfig + _updatePickedVariableName
  // moved into [KeyMappingModbusSection] so the page editor and this
  // row share one implementation.

  void _updateBitMask(int? mask, int? shift) {
    if (mask == null) {
      widget.onUpdate(widget.entry.copyWith(clearBitMask: true));
    } else {
      widget.onUpdate(widget.entry.copyWith(bitMask: mask, bitShift: shift));
    }
  }

  /// Returns true if the current key uses a bit/boolean data type
  /// (coils, discrete inputs, or explicit bit type).
  /// When true, the bit mask grid restricts to single-bit selection.
  bool get _isBitType {
    if (_isModbus) {
      final node = widget.entry.modbusNode!;
      if (node.dataType == ModbusDataType.bit) return true;
      if (node.registerType == ModbusRegisterType.coil ||
          node.registerType == ModbusRegisterType.discreteInput) {
        return true;
      }
    }
    return false;
  }

  /// Returns the number of bits for the current data type.
  int get _bitCountForDataType {
    if (_isModbus) {
      final dt = widget.entry.modbusNode!.dataType;
      switch (dt) {
        case ModbusDataType.int32:
        case ModbusDataType.uint32:
        case ModbusDataType.float32:
          return 32;
        default:
          return 16;
      }
    }
    // OPC UA: default to 16 bits
    return 16;
  }

  void _toggleCollect(bool enabled) {
    setState(() => _collectEnabled = enabled);
    widget.onUpdate(widget.entry.copyWith(
      collect: enabled
          ? CollectEntry(
              key: widget.keyName,
              retention: const RetentionPolicy(
                  dropAfter: Duration(days: 365), scheduleInterval: null),
            )
          : null,
    ));
  }

  void _updateCollectEntry(CollectEntry collect) {
    widget.onUpdate(widget.entry.copyWith(collect: collect));
  }

  Widget _buildTrailing() {
    final chip = _buildStatusChip();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chip != null) ...[
          chip,
          const SizedBox(width: 8),
        ],
        IconButton(
          icon: const FaIcon(FontAwesomeIcons.copy, size: 16),
          onPressed: widget.onCopy,
        ),
        IconButton(
          icon: const FaIcon(FontAwesomeIcons.trash, size: 16),
          onPressed: widget.onRemove,
        ),
        const SizedBox(width: 8),
        const FaIcon(FontAwesomeIcons.chevronDown, size: 16),
      ],
    );
  }

  Widget? _buildStatusChip() {
    if (widget.status == null) return null;
    final (color, label) = switch (widget.status!) {
      _KeyStatus.ok => (Colors.green, 'OK'),
      _KeyStatus.error => (Colors.red, 'Error'),
      _KeyStatus.serverDisconnected => (Colors.red, 'Disconnected'),
      // Grey, not red: the server is off because someone switched it off.
      _KeyStatus.serverDisabled => (Colors.grey, 'Disabled'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        onExpansionChanged: widget.onExpansionChanged,
        leading: widget.reorderIndex != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReorderableDragStartListener(
                    index: widget.reorderIndex!,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 20,
                          color: Colors.grey,
                          semanticLabel: 'Drag to reorder',
                        ),
                      ),
                    ),
                  ),
                  FaIcon(
                    FontAwesomeIcons.key,
                    size: 20,
                    color: _collectEnabled ? Colors.green : null,
                  ),
                ],
              )
            : FaIcon(
                FontAwesomeIcons.key,
                size: 20,
                color: _collectEnabled ? Colors.green : null,
              ),
        title: Text(
          widget.keyName,
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        subtitle: Text(
          _buildSubtitle(),
          style: TextStyle(color: Colors.grey[600]),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        trailing: _buildTrailing(),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Key name
                TextField(
                  controller: _keyNameController,
                  focusNode: _keyNameFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Key Name',
                    prefixIcon: FaIcon(FontAwesomeIcons.tag, size: 16),
                  ),
                  onChanged: (value) => _submitKeyName(value),
                  onSubmitted: (value) => _submitKeyName(value),
                ),
                const SizedBox(height: 12),
                // Device type selector
                if (widget.jbtmServerAliases.isNotEmpty ||
                    widget.modbusServerAliases.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      children: [
                        const FaIcon(FontAwesomeIcons.plug, size: 14),
                        const SizedBox(width: 8),
                        Text('Device Type',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('OPC UA'),
                          selected: !_isM2400 && !_isModbus,
                          onSelected: (selected) {
                            if (selected && (_isM2400 || _isModbus))
                              _switchToOpcUa();
                          },
                        ),
                        if (widget.jbtmServerAliases.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('M2400'),
                            selected: _isM2400,
                            onSelected: (selected) {
                              if (selected && !_isM2400) _switchToM2400();
                            },
                          ),
                        ],
                        if (widget.modbusServerAliases.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Modbus'),
                            selected: _isModbus,
                            onSelected: (selected) {
                              if (selected && !_isModbus) _switchToModbus();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                // Protocol-specific config section
                if (_isModbus)
                  // TD-010 (v1.1.x): both the page editor and this key
                  // repository row used to inline the same picker-wiring
                  // boilerplate. Both now route through
                  // [KeyMappingModbusSection] so the wiring lives in one
                  // place and can't drift.
                  KeyMappingModbusSection(
                    entry: widget.entry,
                    modbusServerAliases: widget.modbusServerAliases,
                    modbusConfigs: widget.modbusConfigs,
                    onEntryChanged: widget.onUpdate,
                    defaultNodeConfigBuilder: () => widget.entry.modbusNode!,
                  )
                else if (_isM2400)
                  M2400ConfigSection(
                    config: widget.entry.m2400Node ??
                        M2400NodeConfig(recordType: M2400RecordType.recBatch),
                    jbtmServerAliases: widget.jbtmServerAliases,
                    onChanged: _updateM2400Config,
                  )
                else
                  OpcUaConfigSection(
                    config: widget.entry.opcuaNode ??
                        OpcUANodeConfig(namespace: 0, identifier: ''),
                    serverAliases: widget.serverAliases,
                    onChanged: _updateOpcUaConfig,
                  ),
                // Bit selection — required for bit types, optional mask
                // for others.
                //
                // F-5 (v1.1.x): when the operator has bound a UMAS symbol
                // path via Browse, the runtime read path ignores
                // bitMask/bitShift just like the address fields. Hide the
                // section entirely so there's no "edits the mask, nothing
                // happens" trap — the UMAS chip's clear-X re-exposes the
                // section.
                if (!_isM2400 &&
                    _isBitType &&
                    (widget.entry.variableName == null ||
                        widget.entry.variableName!.isEmpty)) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bit Select (required)',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        BitMaskGrid(
                          bitCount: _bitCountForDataType,
                          currentMask: widget.entry.bitMask,
                          singleBit: true,
                          onChanged: (result) {
                            _updateBitMask(result.mask, result.shift);
                          },
                        ),
                      ],
                    ),
                  ),
                ] else if (!_isM2400 &&
                    (widget.entry.variableName == null ||
                        widget.entry.variableName!.isEmpty)) ...[
                  const Divider(),
                  ExpansionTile(
                    title: const Text('Bit Mask (optional)'),
                    initiallyExpanded: widget.entry.bitMask != null,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: BitMaskGrid(
                          bitCount: _bitCountForDataType,
                          currentMask: widget.entry.bitMask,
                          onChanged: (result) {
                            _updateBitMask(result.mask, result.shift);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // Collection Config Section
                CollectionConfigSection(
                  enabled: _collectEnabled,
                  collect: widget.entry.collect,
                  keyName: widget.keyName,
                  onToggle: _toggleCollect,
                  onChanged: _updateCollectEntry,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== Import/Export Card =====================

class _KeyMappingsImportExportCard extends ConsumerWidget {
  const _KeyMappingsImportExportCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync_alt, size: 20),
                      const SizedBox(width: 8),
                      Text('Import / Export',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _onImport(context, ref),
                    icon: const FaIcon(FontAwesomeIcons.fileImport, size: 16),
                    label: const Text('Import'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _onExport(context, ref),
                    icon: const FaIcon(FontAwesomeIcons.fileExport, size: 16),
                    label: const Text('Export'),
                  ),
                ],
              );
            }
            return Row(
              children: [
                const Icon(Icons.sync_alt, size: 20),
                const SizedBox(width: 8),
                Text('Import / Export',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _onImport(context, ref),
                  icon: const FaIcon(FontAwesomeIcons.fileImport, size: 16),
                  label: const Text('Import'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _onExport(context, ref),
                  icon: const FaIcon(FontAwesomeIcons.fileExport, size: 16),
                  label: const Text('Export'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _onExport(BuildContext context, WidgetRef ref) async {
    try {
      final prefs = await ref.read(preferencesProvider.future);
      final keyMappings = await KeyMappings.fromPrefs(prefs);
      final jsonString =
          const JsonEncoder.withIndent('  ').convert(keyMappings.toJson());

      String? savePath;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Key Mappings',
          fileName: 'key_mappings.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
        savePath = path.join(dir.path, 'key_mappings_$ts.json');
      }
      if (savePath == null) return;

      final file = File(savePath);
      await file.writeAsString(jsonString);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Key mappings exported to ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _onImport(BuildContext context, WidgetRef ref) async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Import Key Mappings',
      );
      if (pick == null || pick.files.single.path == null) return;

      final file = File(pick.files.single.path!);
      final jsonMap =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final imported = KeyMappings.fromJson(jsonMap);

      if (!context.mounted) return;

      // Confirm overwrite
      final confirm = await showConfirmDialog(
        context: context,
        title: 'Import key mappings',
        message: 'This will overwrite all existing key mappings with '
            '${imported.nodes.length} imported keys. Continue?',
        confirmLabel: 'Import',
        destructive: true,
      );
      if (!confirm) return;

      final prefs = await ref.read(preferencesProvider.future);
      await prefs.setString('key_mappings', jsonEncode(imported.toJson()));
      ref.invalidate(stateManProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Imported ${imported.nodes.length} key mappings successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }
}
