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
import '../widgets/opcua_browse.dart';
import '../widgets/umas_browse.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart' show ModbusDataType;
import 'package:tfc_dart/core/umas_types.dart' show mapUmasDataTypeToModbus;
import '../widgets/opcua_array_index_field.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import '../widgets/fuzzy_search_bar.dart';
import '../widgets/bit_mask_grid.dart';
import 'package:jbtm/src/m2400.dart' show M2400RecordType;
import 'package:jbtm/src/m2400_fields.dart'
    show M2400Field, WeigherStatus, expectedFields;
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
    // Unfocus active text field to commit pending changes (e.g. key rename)
    FocusManager.instance.primaryFocus?.unfocus();
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
      _newlyAddedKey = newName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final keyContext = _cardKeys[newName]?.currentContext;
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
    final keys = _keyMappings!.nodes.keys.toList();
    for (final key in keys) {
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
    final entry = _keyMappings!.nodes[oldKey];
    if (entry == null) return;
    if (entry.collect != null) {
      entry.collect!.key = newKey;
    }
    final cardKey = _cardKeys.remove(oldKey);
    if (cardKey != null) _cardKeys[newKey] = cardKey;
    final status = _keyStatuses.remove(oldKey);
    if (status != null) _keyStatuses[newKey] = status;
    // Rebuild map preserving insertion order
    final newNodes = <String, KeyMappingEntry>{};
    for (final kv in _keyMappings!.nodes.entries) {
      newNodes[kv.key == oldKey ? newKey : kv.key] = kv.value;
    }
    setState(() {
      _keyMappings!.nodes = newNodes;
    });
  }

  void _updateEntry(String key, KeyMappingEntry entry) {
    setState(() {
      _keyMappings!.nodes[key] = entry;
    });
  }

  List<MapEntry<String, KeyMappingEntry>> get _filteredEntries {
    if (_keyMappings == null) return [];
    final entries = _keyMappings!.nodes.entries.toList();
    return fuzzyFilter(entries, _searchQuery, [
      (e) => e.key,
      (e) => e.value.opcuaNode?.identifier ?? '',
      (e) => e.value.opcuaNode?.serverAlias ?? e.value.m2400Node?.serverAlias ?? e.value.modbusNode?.serverAlias ?? '',
    ]);
  }

  List<String> get _serverAliases {
    if (_stateManConfig == null) return [];
    return _stateManConfig!.opcua
        .where((c) => c.serverAlias != null && c.serverAlias!.isNotEmpty)
        .map((c) => c.serverAlias!)
        .toList();
  }

  List<String> get _jbtmServerAliases {
    if (_stateManConfig == null) return [];
    return _stateManConfig!.jbtm
        .where((c) => c.serverAlias != null && c.serverAlias!.isNotEmpty)
        .map((c) => c.serverAlias!)
        .toList();
  }

  List<String> get _modbusServerAliases {
    if (_stateManConfig == null) return [];
    return _stateManConfig!.modbus
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
                        key: _cardKeys[entry.key] ?? ValueKey(entry.key),
                        keyName: entry.key,
                        entry: entry.value,
                        serverAliases: _serverAliases,
                        jbtmServerAliases: _jbtmServerAliases,
                        modbusServerAliases: _modbusServerAliases,
                        modbusConfigs: _stateManConfig?.modbus ?? [],
                        onUpdate: (updated) => _updateEntry(entry.key, updated),
                        onRename: (newName) => _renameKey(entry.key, newName),
                        onCopy: () => _duplicateKey(entry.key),
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
  final List<String> jbtmServerAliases;
  final List<String> modbusServerAliases;
  final List<ModbusConfig> modbusConfigs;
  final Function(KeyMappingEntry) onUpdate;
  final Function(String) onRename;
  final VoidCallback onCopy;
  final VoidCallback onRemove;
  final bool initiallyExpanded;
  final _KeyStatus? status;

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
    this.status,
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
    widget.onUpdate(widget.entry.copyWith(
      opcuaNode: OpcUANodeConfig(namespace: 0, identifier: ''),
    ));
  }

  void _switchToModbus() {
    widget.onUpdate(widget.entry.copyWith(
      modbusNode: ModbusNodeConfig(
        registerType: ModbusRegisterType.holdingRegister,
        address: 0,
      ),
    ));
  }

  void _updateModbusConfig(ModbusNodeConfig config) {
    widget.onUpdate(widget.entry.copyWith(modbusNode: config));
  }

  void _updateBitMask(int? mask, int? shift) {
    if (mask == null) {
      widget.onUpdate(widget.entry.copyWith(clearBitMask: true));
    } else {
      widget.onUpdate(widget.entry.copyWith(bitMask: mask, bitShift: shift));
    }
  }

  /// Returns true if the current key uses a bit/boolean data type
  /// (coils, discrete inputs, or explicit bit type) where masking
  /// does not make sense.
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
                if (widget.jbtmServerAliases.isNotEmpty || widget.modbusServerAliases.isNotEmpty)
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
                            if (selected && (_isM2400 || _isModbus)) _switchToOpcUa();
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
                  _ModbusConfigSection(
                    config: widget.entry.modbusNode!,
                    modbusServerAliases: widget.modbusServerAliases,
                    modbusConfigs: widget.modbusConfigs,
                    onChanged: _updateModbusConfig,
                  )
                else if (_isM2400)
                  _M2400ConfigSection(
                    config: widget.entry.m2400Node ??
                        M2400NodeConfig(recordType: M2400RecordType.recBatch),
                    jbtmServerAliases: widget.jbtmServerAliases,
                    onChanged: _updateM2400Config,
                  )
                else
                  _OpcUaConfigSection(
                    config: widget.entry.opcuaNode ??
                        OpcUANodeConfig(namespace: 0, identifier: ''),
                    serverAliases: widget.serverAliases,
                    onChanged: _updateOpcUaConfig,
                  ),
                // Bit Mask section -- for Modbus and OPC UA numeric keys
                if (!_isBitType && !_isM2400) ...[
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

class _OpcUaConfigSection extends ConsumerStatefulWidget {
  final OpcUANodeConfig config;
  final List<String> serverAliases;
  final Function(OpcUANodeConfig) onChanged;

  const _OpcUaConfigSection({
    required this.config,
    required this.serverAliases,
    required this.onChanged,
  });

  @override
  ConsumerState<_OpcUaConfigSection> createState() => _OpcUaConfigSectionState();
}

class _OpcUaConfigSectionState extends ConsumerState<_OpcUaConfigSection> {
  late TextEditingController _namespaceController;
  late TextEditingController _identifierController;
  String? _selectedAlias;
  int? _selectedArrayIndex;

  @override
  void initState() {
    super.initState();
    _namespaceController =
        TextEditingController(text: widget.config.namespace.toString());
    _identifierController =
        TextEditingController(text: widget.config.identifier);
    _selectedAlias = widget.config.serverAlias;
    _selectedArrayIndex = widget.config.arrayIndex;
  }

  @override
  void dispose() {
    _namespaceController.dispose();
    _identifierController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    final config = OpcUANodeConfig(
      namespace: int.tryParse(_namespaceController.text) ?? 0,
      identifier: _identifierController.text,
    )
      ..arrayIndex = _selectedArrayIndex
      ..serverAlias = (_selectedAlias != null && _selectedAlias!.isNotEmpty)
          ? _selectedAlias
          : null;
    widget.onChanged(config);
  }

  /// Called when namespace or identifier changes — clears the stale array index.
  void _onNodeIdentityChanged() {
    _selectedArrayIndex = null;
    _notifyChanged();
  }

  Future<void> _openBrowseDialog(BuildContext context) async {
    final stateManAsync = ref.read(stateManProvider);
    final stateMan = stateManAsync.valueOrNull;
    if (stateMan == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server connections not ready yet')),
      );
      return;
    }

    final result = await browseOpcUaNode(
      context: context,
      stateMan: stateMan,
      serverAlias: _selectedAlias,
    );

    if (result != null) {
      final nodeId = result.nodeId;
      setState(() {
        _namespaceController.text = nodeId.namespace.toString();
        _identifierController.text =
            nodeId.isString() ? nodeId.string : nodeId.numeric.toString();
      });
      _notifyChanged();
    }
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
                Expanded(
                  child: Text('OPC UA Node Configuration',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                TextButton.icon(
                  onPressed: () => _openBrowseDialog(context),
                  icon: const FaIcon(FontAwesomeIcons.sitemap, size: 14),
                  label: const Text('Browse'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
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
                        onChanged: (_) => _onNodeIdentityChanged(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _identifierController,
                        decoration: const InputDecoration(
                          labelText: 'Identifier',
                        ),
                        onChanged: (_) => _onNodeIdentityChanged(),
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
                        onChanged: (_) => _onNodeIdentityChanged(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _identifierController,
                        decoration: const InputDecoration(
                          labelText: 'Identifier',
                        ),
                        onChanged: (_) => _onNodeIdentityChanged(),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            OpcUaArrayIndexField(
              namespace: int.tryParse(_namespaceController.text) ?? 0,
              identifier: _identifierController.text,
              serverAlias: _selectedAlias,
              value: _selectedArrayIndex,
              onChanged: (v) {
                setState(() => _selectedArrayIndex = v);
                _notifyChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ===================== M2400 Config Section =====================

class _M2400ConfigSection extends StatefulWidget {
  final M2400NodeConfig config;
  final List<String> jbtmServerAliases;
  final Function(M2400NodeConfig) onChanged;

  const _M2400ConfigSection({
    required this.config,
    required this.jbtmServerAliases,
    required this.onChanged,
  });

  @override
  State<_M2400ConfigSection> createState() => _M2400ConfigSectionState();
}

class _M2400ConfigSectionState extends State<_M2400ConfigSection> {
  String? _selectedAlias;
  M2400RecordType? _selectedRecordType;
  M2400Field? _selectedField;
  int? _selectedStatusFilter;

  @override
  void initState() {
    super.initState();
    _selectedAlias = widget.config.serverAlias;
    _selectedRecordType = widget.config.recordType;
    _selectedField = widget.config.field;
    _selectedStatusFilter = widget.config.statusFilter;
  }

  void _notifyChanged() {
    final config = M2400NodeConfig(
      recordType: _selectedRecordType ?? M2400RecordType.recBatch,
      field: _selectedField,
      serverAlias: (_selectedAlias != null && _selectedAlias!.isNotEmpty)
          ? _selectedAlias
          : null,
      statusFilter: _selectedStatusFilter,
    );
    widget.onChanged(config);
  }

  List<M2400Field> _getExpectedFields(M2400RecordType? recType) {
    if (recType == null) return [];
    final expected = expectedFields[recType];
    if (expected != null) return expected.toList();
    return [];
  }

  List<M2400Field> _getOtherFields(M2400RecordType? recType) {
    if (recType == null) return M2400Field.values.toList();
    final expected = expectedFields[recType];
    if (expected == null) return M2400Field.values.toList();
    return M2400Field.values.where((f) => !expected.contains(f)).toList();
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
                const FaIcon(FontAwesomeIcons.scaleBalanced, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('M2400 Key Configuration',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Server alias dropdown (JBTM servers only)
            DropdownButtonFormField<String>(
              value: _selectedAlias,
              decoration: const InputDecoration(
                labelText: 'M2400 Server',
                prefixIcon: FaIcon(FontAwesomeIcons.scaleBalanced, size: 16),
              ),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('(none)')),
                ...widget.jbtmServerAliases.map((alias) =>
                    DropdownMenuItem(value: alias, child: Text(alias))),
              ],
              onChanged: (value) {
                setState(() => _selectedAlias = value);
                _notifyChanged();
              },
            ),
            const SizedBox(height: 12),
            // REC type dropdown (REQUIRED)
            DropdownButtonFormField<M2400RecordType>(
              value: _selectedRecordType,
              decoration: const InputDecoration(
                labelText: 'Record Type (REC)',
                prefixIcon: FaIcon(FontAwesomeIcons.layerGroup, size: 16),
              ),
              items: M2400RecordType.values
                  .where((t) => t != M2400RecordType.unknown)
                  .map((recType) => DropdownMenuItem(
                        value: recType,
                        child: Text('${recType.name} (${recType.id})'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRecordType = value;
                  // Reset field if it's not in the expected set for the new REC type
                  if (_selectedField != null && value != null) {
                    final expected = expectedFields[value];
                    if (expected != null && !expected.contains(_selectedField)) {
                      _selectedField = null;
                    }
                  }
                  // Clear status filter when switching away from BATCH
                  if (value != M2400RecordType.recBatch) {
                    _selectedStatusFilter = null;
                  }
                });
                _notifyChanged();
              },
            ),
            const SizedBox(height: 12),
            // FLD dropdown (OPTIONAL -- null means subscribe to full record)
            DropdownButtonFormField<M2400Field?>(
              value: _selectedField,
              decoration: const InputDecoration(
                labelText: 'Field (FLD) -- optional',
                prefixIcon: FaIcon(FontAwesomeIcons.hashtag, size: 16),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<M2400Field?>(
                    value: null,
                    child: Text('(Full record -- all fields)')),
                // Expected fields for this REC type (shown first)
                ..._getExpectedFields(_selectedRecordType).map((field) =>
                    DropdownMenuItem(
                      value: field,
                      child: Text('${field.displayName} (${field.id})'),
                    )),
                // Other fields
                ..._getOtherFields(_selectedRecordType).map((field) =>
                    DropdownMenuItem(
                      value: field,
                      child: Text('${field.displayName} (${field.id})'),
                    )),
              ],
              onChanged: (value) {
                setState(() => _selectedField = value);
                _notifyChanged();
              },
            ),
            // Status filter dropdown (BATCH only)
            if (_selectedRecordType == M2400RecordType.recBatch) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _selectedStatusFilter,
                decoration: const InputDecoration(
                  labelText: 'Status Filter (optional)',
                  prefixIcon: FaIcon(FontAwesomeIcons.filter, size: 16),
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('(No filter -- all records)')),
                  ...WeigherStatus.values
                      .where((s) => s != WeigherStatus.unknown)
                      .map((s) => DropdownMenuItem<int?>(
                            value: s.code,
                            child: Text('${s.displayName} (${s.code})'),
                          )),
                ],
                onChanged: (value) {
                  setState(() => _selectedStatusFilter = value);
                  _notifyChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===================== Modbus Config Section =====================

class _ModbusConfigSection extends ConsumerStatefulWidget {
  final ModbusNodeConfig config;
  final List<String> modbusServerAliases;
  final List<ModbusConfig> modbusConfigs;
  final Function(ModbusNodeConfig) onChanged;

  const _ModbusConfigSection({
    required this.config,
    required this.modbusServerAliases,
    required this.modbusConfigs,
    required this.onChanged,
  });

  @override
  ConsumerState<_ModbusConfigSection> createState() => _ModbusConfigSectionState();
}

class _ModbusConfigSectionState extends ConsumerState<_ModbusConfigSection> {
  String? _selectedAlias;
  late ModbusRegisterType _selectedRegisterType;
  late TextEditingController _addressController;
  late ModbusDataType _selectedDataType;
  late String _selectedPollGroup;

  bool get _isBooleanRegisterType =>
      _selectedRegisterType == ModbusRegisterType.coil ||
      _selectedRegisterType == ModbusRegisterType.discreteInput;

  bool get _isUmasEnabled {
    if (_selectedAlias == null) return false;
    final config = widget.modbusConfigs.findByAlias(_selectedAlias);
    return config?.umasEnabled ?? false;
  }

  Future<void> _openUmasBrowseDialog(BuildContext context) async {
    final stateManAsync = ref.read(stateManProvider);
    final stateMan = stateManAsync.valueOrNull;
    if (stateMan == null) return;

    final result = await browseUmasNode(
      context: context,
      stateMan: stateMan,
      serverAlias: _selectedAlias,
    );

    if (result != null) {
      final blockNo = int.tryParse(result.metadata['blockNo'] ?? '') ?? 0;
      final offset = int.tryParse(result.metadata['offset'] ?? '') ?? 0;
      final address = blockNo + offset;
      final dataTypeName = result.metadata['dataTypeName'] ?? '';
      final byteSize = int.tryParse(result.metadata['byteSize'] ?? '') ?? 2;

      setState(() {
        _addressController.text = address.toString();
        _selectedRegisterType = ModbusRegisterType.holdingRegister;
        _selectedDataType = mapUmasDataTypeToModbus(dataTypeName, byteSize);
      });
      _notifyChanged();
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedAlias = widget.config.serverAlias;
    _selectedRegisterType = widget.config.registerType;
    _addressController =
        TextEditingController(text: widget.config.address.toString());
    _selectedDataType = widget.config.dataType;
    _selectedPollGroup = widget.config.pollGroup;
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  List<ModbusPollGroupConfig> _getAvailablePollGroups() {
    if (_selectedAlias == null) {
      return [ModbusPollGroupConfig(name: 'default', intervalMs: 1000)];
    }
    final serverConfig = widget.modbusConfigs.findByAlias(_selectedAlias);
    if (serverConfig != null && serverConfig.pollGroups.isNotEmpty) {
      return serverConfig.pollGroups;
    }
    return [ModbusPollGroupConfig(name: 'default', intervalMs: 1000)];
  }

  void _notifyChanged() {
    final config = ModbusNodeConfig(
      serverAlias: _selectedAlias,
      registerType: _selectedRegisterType,
      address: (int.tryParse(_addressController.text) ?? 0).clamp(0, 65535),
      dataType: _selectedDataType,
      pollGroup: _selectedPollGroup,
    );
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
                const FaIcon(FontAwesomeIcons.networkWired, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Modbus Key Configuration',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (_isUmasEnabled)
                  TextButton.icon(
                    onPressed: () => _openUmasBrowseDialog(context),
                    icon: const FaIcon(FontAwesomeIcons.sitemap, size: 14),
                    label: const Text('Browse'),
                  ),
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
                ...widget.modbusServerAliases.map((alias) =>
                    DropdownMenuItem(value: alias, child: Text(alias))),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedAlias = value;
                  _selectedPollGroup = 'default';
                });
                _notifyChanged();
              },
            ),
            const SizedBox(height: 12),
            // Register type dropdown
            DropdownButtonFormField<ModbusRegisterType>(
              value: _selectedRegisterType,
              decoration: const InputDecoration(
                labelText: 'Register Type',
                prefixIcon: FaIcon(FontAwesomeIcons.layerGroup, size: 16),
              ),
              items: ModbusRegisterType.values
                  .map((rt) => DropdownMenuItem(
                        value: rt,
                        child: Text(rt.name),
                      ))
                  .toList(),
              onChanged: (ModbusRegisterType? value) {
                if (value == null) return;
                setState(() {
                  _selectedRegisterType = value;
                  // Auto-lock data type for boolean register types
                  if (value == ModbusRegisterType.coil ||
                      value == ModbusRegisterType.discreteInput) {
                    _selectedDataType = ModbusDataType.bit;
                  } else if (_selectedDataType == ModbusDataType.bit) {
                    // Switching away from boolean type -- reset to default
                    _selectedDataType = ModbusDataType.uint16;
                  }
                });
                _notifyChanged();
              },
            ),
            const SizedBox(height: 12),
            // Address field
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: FaIcon(FontAwesomeIcons.locationDot, size: 16),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _notifyChanged(),
            ),
            const SizedBox(height: 12),
            // Data type dropdown (disabled for coil/discrete input)
            DropdownButtonFormField<ModbusDataType>(
              value: _selectedDataType,
              decoration: InputDecoration(
                labelText:
                    _isBooleanRegisterType ? 'Data Type (auto)' : 'Data Type',
                prefixIcon:
                    const FaIcon(FontAwesomeIcons.hashtag, size: 16),
              ),
              items: _isBooleanRegisterType
                  ? [
                      const DropdownMenuItem(
                          value: ModbusDataType.bit, child: Text('bit'))
                    ]
                  : ModbusDataType.values
                      .map((dt) =>
                          DropdownMenuItem(value: dt, child: Text(dt.name)))
                      .toList(),
              onChanged: _isBooleanRegisterType
                  ? null // null disables the dropdown
                  : (value) {
                      if (value == null) return;
                      setState(() => _selectedDataType = value);
                      _notifyChanged();
                    },
            ),
            const SizedBox(height: 12),
            // Poll group dropdown
            DropdownButtonFormField<String>(
              value: _selectedPollGroup,
              decoration: const InputDecoration(
                labelText: 'Poll Group',
                prefixIcon:
                    FaIcon(FontAwesomeIcons.clockRotateLeft, size: 16),
              ),
              items: _getAvailablePollGroups()
                  .map((pg) => DropdownMenuItem(
                        value: pg.name,
                        child: Text('${pg.name} (${pg.intervalMs}ms)'),
                      ))
                  .toList(),
              onChanged: _selectedAlias == null
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _selectedPollGroup = value);
                      _notifyChanged();
                    },
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
