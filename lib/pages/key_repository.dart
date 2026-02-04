import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../widgets/base_scaffold.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import '../providers/preferences.dart';
import '../providers/state_man.dart';
import '../providers/database.dart';

enum _KeyStatus { ok, error, serverDisconnected }

/// The full page widget with BaseScaffold (used in navigation).
class KeyRepositoryPage extends ConsumerWidget {
  const KeyRepositoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseScaffold(
      title: 'Key Repository',
      body: KeyRepositoryContent(),
    );
  }
}

/// The content widget (testable without BaseScaffold).
class KeyRepositoryContent extends ConsumerWidget {
  const KeyRepositoryContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider);

    return SingleChildScrollView(
      child: Column(
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
          _KeyMappingsSection(),
          const SizedBox(height: 16),
          _KeyMappingsImportExportCard(),
        ],
      ),
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
  const _KeyMappingsSection();
  @override
  ConsumerState<_KeyMappingsSection> createState() =>
      _KeyMappingsSectionState();
}

class _KeyMappingsSectionState extends ConsumerState<_KeyMappingsSection> {
  KeyMappings? _keyMappings;
  KeyMappings? _savedKeyMappings;
  StateManConfig? _stateManConfig;
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String? _newlyAddedKey;
  Map<String, _KeyStatus> _keyStatuses = {};

  @override
  void initState() {
    super.initState();
    _loadKeyMappings();
  }

  Future<void> _loadKeyMappings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final prefs = await ref.read(preferencesProvider.future);
      _keyMappings = await KeyMappings.fromPrefs(prefs);
      _savedKeyMappings =
          KeyMappings.fromJson(jsonDecode(jsonEncode(_keyMappings!.toJson())));
      _stateManConfig = await StateManConfig.fromPrefs(prefs);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _probeKeys();
      }
    }
  }

  bool get _hasUnsavedChanges {
    if (_keyMappings == null || _savedKeyMappings == null) return false;
    return jsonEncode(_keyMappings!.toJson()) !=
        jsonEncode(_savedKeyMappings!.toJson());
  }

  Future<void> _saveKeyMappings() async {
    if (_keyMappings == null) return;
    try {
      final prefs = await ref.read(preferencesProvider.future);
      await prefs.setString('key_mappings', jsonEncode(_keyMappings!.toJson()));
      _savedKeyMappings =
          KeyMappings.fromJson(jsonDecode(jsonEncode(_keyMappings!.toJson())));
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

  void _addKey() {
    final baseName = 'new_key';
    var name = baseName;
    var i = 1;
    while (_keyMappings!.nodes.containsKey(name)) {
      name = '${baseName}_$i';
      i++;
    }
    _cardKeys[name] = GlobalKey();
    setState(() {
      _keyMappings!.nodes[name] = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(namespace: 0, identifier: ''),
      );
      _newlyAddedKey = name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final keyContext = _cardKeys[name]?.currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(keyContext,
            duration: const Duration(milliseconds: 300));
      }
      _newlyAddedKey = null;
    });
  }

  void _removeKey(String key) {
    _cardKeys.remove(key);
    _keyStatuses.remove(key);
    setState(() {
      _keyMappings!.nodes.remove(key);
    });
  }

  Future<void> _probeKeys() async {
    if (_keyMappings == null || _keyMappings!.nodes.isEmpty) return;

    final stateManAsync = ref.read(stateManProvider);
    final stateMan = stateManAsync.valueOrNull;
    if (stateMan == null) return;

    final newStatuses = <String, _KeyStatus>{};
    for (final key in _keyMappings!.nodes.keys) {
      try {
        await stateMan.read(key).timeout(const Duration(seconds: 5));
        newStatuses[key] = _KeyStatus.ok;
      } on TimeoutException {
        newStatuses[key] = _KeyStatus.serverDisconnected;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('not found') || msg.contains('connect')) {
          newStatuses[key] = _KeyStatus.serverDisconnected;
        } else {
          newStatuses[key] = _KeyStatus.error;
        }
      }
      // Update UI incrementally
      if (mounted) setState(() => _keyStatuses = Map.of(newStatuses));
    }
  }

  void _renameKey(String oldKey, String newKey) {
    if (oldKey == newKey) return;
    if (_keyMappings!.nodes.containsKey(newKey)) return;
    final entry = _keyMappings!.nodes.remove(oldKey);
    if (entry != null) {
      if (entry.collect != null) {
        entry.collect!.key = newKey;
      }
      setState(() {
        _keyMappings!.nodes[newKey] = entry;
      });
    }
  }

  void _updateEntry(String key, KeyMappingEntry entry) {
    setState(() {
      _keyMappings!.nodes[key] = entry;
    });
  }

  List<MapEntry<String, KeyMappingEntry>> get _filteredEntries {
    if (_keyMappings == null) return [];
    final entries = _keyMappings!.nodes.entries.toList();
    if (_searchQuery.isEmpty) return entries;
    final query = _searchQuery.toLowerCase();
    return entries.where((e) {
      if (e.key.toLowerCase().contains(query)) return true;
      final node = e.value.opcuaNode;
      if (node != null) {
        if (node.identifier.toLowerCase().contains(query)) return true;
        if (node.serverAlias?.toLowerCase().contains(query) ?? false) return true;
      }
      return false;
    }).toList();
  }

  List<String> get _serverAliases {
    if (_stateManConfig == null) return [];
    return _stateManConfig!.opcua
        .where((c) => c.serverAlias != null && c.serverAlias!.isNotEmpty)
        .map((c) => c.serverAlias!)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
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

    return Card(
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
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                          if (_hasUnsavedChanges) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12)),
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
                        icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
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
                              style: Theme.of(context).textTheme.titleMedium),
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
                          icon: const FaIcon(FontAwesomeIcons.plus, size: 16),
                          label: const Text('Add Key'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Key list
            filtered.isEmpty
                ? const SizedBox(
                    height: 200,
                    child: _EmptyKeysWidget(),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final isNew = entry.key == _newlyAddedKey;
                      if (isNew) {
                        _cardKeys.putIfAbsent(entry.key, () => GlobalKey());
                      }
                      return _KeyMappingCard(
                        key: _cardKeys[entry.key],
                        keyName: entry.key,
                        entry: entry.value,
                        serverAliases: _serverAliases,
                        onUpdate: (updated) => _updateEntry(entry.key, updated),
                        onRename: (newName) => _renameKey(entry.key, newName),
                        onRemove: () => _showDeleteDialog(entry.key),
                        initiallyExpanded: isNew,
                        status: _keyStatuses[entry.key],
                      );
                    },
                  ),
            const SizedBox(height: 16),
            // Save button
            Row(
              children: [
                if (_keyMappings!.nodes.isNotEmpty || _hasUnsavedChanges)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _hasUnsavedChanges ? _saveKeyMappings : null,
                      icon: FaIcon(FontAwesomeIcons.floppyDisk,
                          size: 16,
                          color: _hasUnsavedChanges ? null : Colors.grey),
                      label: Text(_hasUnsavedChanges
                          ? 'Save Key Mappings'
                          : 'All Changes Saved'),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor:
                              _hasUnsavedChanges ? null : Colors.grey),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(String key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Key'),
        content: Text('Are you sure you want to remove "$key"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _removeKey(key);
              },
              child: const Text('Remove')),
        ],
      ),
    );
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
  final Function(KeyMappingEntry) onUpdate;
  final Function(String) onRename;
  final VoidCallback onRemove;
  final bool initiallyExpanded;
  final _KeyStatus? status;

  const _KeyMappingCard({
    super.key,
    required this.keyName,
    required this.entry,
    required this.serverAliases,
    required this.onUpdate,
    required this.onRename,
    required this.onRemove,
    this.initiallyExpanded = false,
    this.status,
  });

  @override
  State<_KeyMappingCard> createState() => _KeyMappingCardState();
}

class _KeyMappingCardState extends State<_KeyMappingCard> {
  late TextEditingController _keyNameController;
  bool _collectEnabled = false;

  @override
  void initState() {
    super.initState();
    _keyNameController = TextEditingController(text: widget.keyName);
    _collectEnabled = widget.entry.collect != null;
  }

  @override
  void dispose() {
    _keyNameController.dispose();
    super.dispose();
  }

  String _buildSubtitle() {
    final node = widget.entry.opcuaNode;
    if (node == null) return 'No OPC UA config';
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
    final updatedEntry = KeyMappingEntry(
      opcuaNode: config,
      collect: widget.entry.collect,
    );
    widget.onUpdate(updatedEntry);
  }

  void _toggleCollect(bool enabled) {
    setState(() => _collectEnabled = enabled);
    final updatedEntry = KeyMappingEntry(
      opcuaNode: widget.entry.opcuaNode,
      collect: enabled
          ? CollectEntry(
              key: widget.keyName,
              retention: const RetentionPolicy(
                  dropAfter: Duration(days: 365), scheduleInterval: null),
            )
          : null,
    );
    widget.onUpdate(updatedEntry);
  }

  void _updateCollectEntry(CollectEntry collect) {
    final updatedEntry = KeyMappingEntry(
      opcuaNode: widget.entry.opcuaNode,
      collect: collect,
    );
    widget.onUpdate(updatedEntry);
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
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        leading: FaIcon(
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
                  decoration: const InputDecoration(
                    labelText: 'Key Name',
                    prefixIcon: FaIcon(FontAwesomeIcons.tag, size: 16),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty && value != widget.keyName) {
                      widget.onRename(value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                // OPC UA Config Section
                _OpcUaConfigSection(
                  config: widget.entry.opcuaNode ??
                      OpcUANodeConfig(namespace: 0, identifier: ''),
                  serverAliases: widget.serverAliases,
                  onChanged: _updateOpcUaConfig,
                ),
                const SizedBox(height: 16),
                // Collection Config Section
                _CollectionConfigSection(
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

// ===================== OPC UA Config Section (extensible for Modbus) =====================

class _OpcUaConfigSection extends StatefulWidget {
  final OpcUANodeConfig config;
  final List<String> serverAliases;
  final Function(OpcUANodeConfig) onChanged;

  const _OpcUaConfigSection({
    required this.config,
    required this.serverAliases,
    required this.onChanged,
  });

  @override
  State<_OpcUaConfigSection> createState() => _OpcUaConfigSectionState();
}

class _OpcUaConfigSectionState extends State<_OpcUaConfigSection> {
  late TextEditingController _namespaceController;
  late TextEditingController _identifierController;
  late TextEditingController _arrayIndexController;
  String? _selectedAlias;

  @override
  void initState() {
    super.initState();
    _namespaceController =
        TextEditingController(text: widget.config.namespace.toString());
    _identifierController =
        TextEditingController(text: widget.config.identifier);
    _arrayIndexController =
        TextEditingController(text: widget.config.arrayIndex?.toString() ?? '');
    _selectedAlias = widget.config.serverAlias;
  }

  @override
  void dispose() {
    _namespaceController.dispose();
    _identifierController.dispose();
    _arrayIndexController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    final config = OpcUANodeConfig(
      namespace: int.tryParse(_namespaceController.text) ?? 0,
      identifier: _identifierController.text,
    )
      ..arrayIndex = _arrayIndexController.text.isNotEmpty
          ? int.tryParse(_arrayIndexController.text)
          : null
      ..serverAlias = (_selectedAlias != null && _selectedAlias!.isNotEmpty)
          ? _selectedAlias
          : null;
    widget.onChanged(config);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.server, size: 16),
                const SizedBox(width: 8),
                Text('OPC UA Node Configuration',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            // Server alias dropdown
            DropdownButtonFormField<String>(
              value: _selectedAlias,
              decoration: const InputDecoration(
                labelText: 'Server Alias',
                prefixIcon: FaIcon(FontAwesomeIcons.server, size: 16),
              ),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('(none)')),
                ...widget.serverAliases.map((alias) =>
                    DropdownMenuItem(value: alias, child: Text(alias))),
              ],
              onChanged: (value) {
                setState(() => _selectedAlias = value);
                _notifyChanged();
              },
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 400;
                if (isNarrow) {
                  return Column(
                    children: [
                      TextField(
                        controller: _namespaceController,
                        decoration: const InputDecoration(
                          labelText: 'Namespace',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _notifyChanged(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _identifierController,
                        decoration: const InputDecoration(
                          labelText: 'Identifier',
                        ),
                        onChanged: (_) => _notifyChanged(),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _namespaceController,
                        decoration: const InputDecoration(
                          labelText: 'Namespace',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => _notifyChanged(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _identifierController,
                        decoration: const InputDecoration(
                          labelText: 'Identifier',
                        ),
                        onChanged: (_) => _notifyChanged(),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Array Index field (NEW - not in current UI)
            TextField(
              controller: _arrayIndexController,
              decoration: const InputDecoration(
                labelText: 'Array Index (optional)',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _notifyChanged(),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== Collection Config Section =====================

class _CollectionConfigSection extends StatefulWidget {
  final bool enabled;
  final CollectEntry? collect;
  final String keyName;
  final Function(bool) onToggle;
  final Function(CollectEntry) onChanged;

  const _CollectionConfigSection({
    required this.enabled,
    required this.collect,
    required this.keyName,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  State<_CollectionConfigSection> createState() =>
      _CollectionConfigSectionState();
}

class _CollectionConfigSectionState extends State<_CollectionConfigSection> {
  late TextEditingController _collectionNameController;
  late TextEditingController _sampleIntervalController;
  late TextEditingController _retentionDaysController;
  late TextEditingController _scheduleIntervalController;

  @override
  void initState() {
    super.initState();
    final collect = widget.collect;
    _collectionNameController =
        TextEditingController(text: collect?.name ?? '');
    _sampleIntervalController = TextEditingController(
        text: collect?.sampleInterval?.inMicroseconds.toString() ?? '');
    _retentionDaysController = TextEditingController(
        text: collect?.retention.dropAfter.inDays.toString() ?? '365');
    _scheduleIntervalController = TextEditingController(
        text: collect?.retention.scheduleInterval?.inMinutes.toString() ?? '');
  }

  @override
  void dispose() {
    _collectionNameController.dispose();
    _sampleIntervalController.dispose();
    _retentionDaysController.dispose();
    _scheduleIntervalController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    final sampleUs = int.tryParse(_sampleIntervalController.text);
    final retDays = int.tryParse(_retentionDaysController.text) ?? 365;
    final schedMins = int.tryParse(_scheduleIntervalController.text);

    final collect = CollectEntry(
      key: widget.keyName,
      name: _collectionNameController.text.isNotEmpty
          ? _collectionNameController.text
          : null,
      sampleInterval:
          sampleUs != null ? Duration(microseconds: sampleUs) : null,
      retention: RetentionPolicy(
        dropAfter: Duration(days: retDays),
        scheduleInterval:
            schedMins != null ? Duration(minutes: schedMins) : null,
      ),
    );
    widget.onChanged(collect);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.database, size: 16),
                const SizedBox(width: 8),
                Text('Data Collection',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Switch(
                  value: widget.enabled,
                  onChanged: widget.onToggle,
                ),
              ],
            ),
            if (widget.enabled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _collectionNameController,
                decoration: const InputDecoration(
                  labelText: 'Collection Name (optional)',
                ),
                onChanged: (_) => _notifyChanged(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sampleIntervalController,
                decoration: const InputDecoration(
                  labelText: 'Sample Interval (microseconds)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => _notifyChanged(),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 400;
                  if (isNarrow) {
                    return Column(
                      children: [
                        TextField(
                          controller: _retentionDaysController,
                          decoration: const InputDecoration(
                            labelText: 'Retention (days)',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _notifyChanged(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _scheduleIntervalController,
                          decoration: const InputDecoration(
                            labelText: 'Schedule Interval (minutes, optional)',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _notifyChanged(),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _retentionDaysController,
                          decoration: const InputDecoration(
                            labelText: 'Retention (days)',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _notifyChanged(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _scheduleIntervalController,
                          decoration: const InputDecoration(
                            labelText: 'Schedule Interval (minutes, optional)',
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _notifyChanged(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
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
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import Key Mappings'),
          content: Text(
              'This will overwrite all existing key mappings with ${imported.nodes.length} imported keys. Continue?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import')),
          ],
        ),
      );
      if (confirm != true) return;

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
