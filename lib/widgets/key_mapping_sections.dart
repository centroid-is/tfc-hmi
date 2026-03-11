import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart' show ModbusDataType;
import 'package:tfc_dart/core/umas_types.dart' show mapUmasDataTypeToModbus;
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:jbtm/src/m2400.dart' show M2400RecordType;
import 'package:jbtm/src/m2400_fields.dart'
    show M2400Field, WeigherStatus, expectedFields;
import '../providers/state_man.dart';
import '../pages/key_repository.dart' show ModbusConfigListExt;
import 'opcua_array_index_field.dart';
import 'opcua_browse.dart';
import 'umas_browse.dart';

// ===================== OPC UA Config Section =====================

class OpcUaConfigSection extends ConsumerStatefulWidget {
  final OpcUANodeConfig config;
  final List<String> serverAliases;
  final Function(OpcUANodeConfig) onChanged;

  const OpcUaConfigSection({
    super.key,
    required this.config,
    required this.serverAliases,
    required this.onChanged,
  });

  @override
  ConsumerState<OpcUaConfigSection> createState() => _OpcUaConfigSectionState();
}

class _OpcUaConfigSectionState extends ConsumerState<OpcUaConfigSection> {
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

class M2400ConfigSection extends StatefulWidget {
  final M2400NodeConfig config;
  final List<String> jbtmServerAliases;
  final Function(M2400NodeConfig) onChanged;

  const M2400ConfigSection({
    super.key,
    required this.config,
    required this.jbtmServerAliases,
    required this.onChanged,
  });

  @override
  State<M2400ConfigSection> createState() => _M2400ConfigSectionState();
}

class _M2400ConfigSectionState extends State<M2400ConfigSection> {
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

class ModbusConfigSection extends ConsumerStatefulWidget {
  final ModbusNodeConfig config;
  final List<String> modbusServerAliases;
  final List<ModbusConfig> modbusConfigs;
  final Function(ModbusNodeConfig) onChanged;

  const ModbusConfigSection({
    super.key,
    required this.config,
    required this.modbusServerAliases,
    required this.modbusConfigs,
    required this.onChanged,
  });

  @override
  ConsumerState<ModbusConfigSection> createState() => _ModbusConfigSectionState();
}

class _ModbusConfigSectionState extends ConsumerState<ModbusConfigSection> {
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

class CollectionConfigSection extends StatefulWidget {
  final bool enabled;
  final CollectEntry? collect;
  final String keyName;
  final Function(bool) onToggle;
  final Function(CollectEntry) onChanged;

  const CollectionConfigSection({
    super.key,
    required this.enabled,
    required this.collect,
    required this.keyName,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  State<CollectionConfigSection> createState() =>
      _CollectionConfigSectionState();
}

class _CollectionConfigSectionState extends State<CollectionConfigSection> {
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
