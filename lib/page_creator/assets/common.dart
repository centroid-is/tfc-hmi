import 'dart:math' as math;

import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/modbus_client_wrapper.dart' show ModbusDataType;
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import 'package:jbtm/src/m2400.dart' show M2400RecordType;
import '../../providers/state_man.dart';
import '../../providers/preferences.dart';
import '../../widgets/boolean_expression.dart';
import '../../widgets/bit_mask_grid.dart';
import '../../widgets/key_mapping_sections.dart';

part 'common.g.dart';

const String constAssetName = "asset_name";

@JsonEnum()
enum TextPos {
  above,
  below,
  left,
  right,
  inside,
}

@JsonSerializable()
class Coordinates {
  double x; // 0.0 to 1.0
  double y; // 0.0 to 1.0
  double? angle;

  Coordinates({
    required this.x,
    required this.y,
    this.angle,
  });

  factory Coordinates.fromJson(Map<String, dynamic> json) =>
      _$CoordinatesFromJson(json);
  Map<String, dynamic> toJson() => _$CoordinatesToJson(this);
}

@JsonSerializable()
class RelativeSize {
  final double width; // 0.0 to 1.0
  final double height; // 0.0 to 1.0

  const RelativeSize({
    required this.width,
    required this.height,
  });

  factory RelativeSize.fromJson(Map<String, dynamic> json) =>
      _$RelativeSizeFromJson(json);
  Map<String, dynamic> toJson() => _$RelativeSizeToJson(this);

  Size toSize(Size containerSize) {
    return Size(
      containerSize.width * width,
      containerSize.height * height,
    );
  }

  static RelativeSize fromSize(Size size, Size containerSize) {
    return RelativeSize(
      width: size.width / containerSize.width,
      height: size.height / containerSize.height,
    );
  }
}

abstract class Asset {
  String get assetName;
  String get displayName;
  String get category;
  String? get text;
  set text(String? text);
  TextPos? get textPos;
  set textPos(TextPos? textPos);
  Coordinates get coordinates;
  set coordinates(Coordinates coordinates);
  RelativeSize get size;
  set size(RelativeSize size);
  Widget build(BuildContext context);
  Widget configure(BuildContext context);
  Map<String, dynamic> toJson();
}

@JsonSerializable(createFactory: false, createToJson: false, explicitToJson: true)
abstract class BaseAsset implements Asset {
  @override
  String get assetName => variant;
  @JsonKey(name: constAssetName)
  String variant =
      'unknown'; // fromJson will set this during deserialization, otherwise it will be set to the runtime type

  BaseAsset() {
    if (variant == 'unknown') {
      variant = runtimeType.toString();
    }
  }

  @override
  String get displayName => _humanize(runtimeType.toString());

  @override
  String get category => 'General';

  static String _humanize(String typeName) {
    String name = typeName;
    if (name.endsWith('Config')) {
      name = name.substring(0, name.length - 6);
    }
    final buffer = StringBuffer();
    for (int i = 0; i < name.length; i++) {
      final ch = name[i];
      if (i > 0 && ch.toUpperCase() == ch && ch.toLowerCase() != ch) {
        final prev = name[i - 1];
        final nextIsLower = i + 1 < name.length &&
            name[i + 1].toLowerCase() == name[i + 1] &&
            name[i + 1].toUpperCase() != name[i + 1];
        if (prev.toLowerCase() == prev && prev.toUpperCase() != prev) {
          buffer.write(' ');
        } else if (nextIsLower && prev.toUpperCase() == prev) {
          buffer.write(' ');
        }
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }

  @JsonKey(name: 'coordinates')
  Coordinates _coordinates = Coordinates(x: 0.0, y: 0.0);

  @override
  Coordinates get coordinates => _coordinates;

  @override
  set coordinates(Coordinates coordinates) {
    _coordinates = coordinates;
  }

  @JsonKey(name: 'size')
  RelativeSize _size = const RelativeSize(width: 0.03, height: 0.03);

  @override
  RelativeSize get size => _size;

  @override
  set size(RelativeSize size) {
    _size = size;
  }

  @JsonKey(name: 'text')
  String? _text;

  @override
  String? get text => _text;

  @override
  set text(String? text) {
    _text = text;
  }

  @JsonKey(name: 'text_pos')
  TextPos? _textPos;

  @override
  TextPos? get textPos => _textPos;

  @override
  set textPos(TextPos? textPos) {
    _textPos = textPos;
  }

  /// The ID of the linked technical document, or null if none linked.
  ///
  /// Many assets can reference the same document (many-to-one).
  /// Stored in asset JSON and used by the LLM to find relevant
  /// manufacturer documentation when diagnosing equipment.
  @JsonKey(name: 'techDocId')
  int? techDocId;

  /// The asset key of the linked PLC code index entry, or null if none linked.
  ///
  /// Many assets can reference the same PLC asset (many-to-one).
  /// Stored in asset JSON and used by the LLM to find relevant
  /// PLC code blocks and variables when diagnosing equipment.
  @JsonKey(name: 'plcAssetKey')
  String? plcAssetKey;

  /// Returns all PLC/OPC-UA tag keys referenced by this asset.
  ///
  /// The default implementation introspects the `toJson()` map and extracts
  /// string values whose JSON field name matches common key-field patterns:
  ///   - `key` (exact)
  ///   - `key1`, `key2`, etc. (numbered)
  ///   - `*Key` (camelCase suffix, e.g. `batchesKey`, `frequencyKey`)
  ///   - `*_key` (snake_case suffix, e.g. `analog_key`, `error_key`)
  ///
  /// Excludes `plcAssetKey` (a reference ID, not a tag key) and `asset_name`.
  /// Returns deduplicated, non-empty strings.
  ///
  /// Complex asset types with keys in nested structures (lists, sub-objects)
  /// should override this getter.
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<String> get allKeys => _extractKeysFromJson(toJson());

  /// JSON key-name pattern for tag-key fields.
  ///
  /// Matches:  key | key1 | key2 | fooKey | foo_key
  static final RegExp _keyFieldPattern =
      RegExp(r'^key$|^key\d+$|Key$|_key$');

  /// JSON field names that match [_keyFieldPattern] but are NOT tag keys.
  static const Set<String> _excludedFields = {
    'plcAssetKey',
    'asset_name',
  };

  static List<String> _extractKeysFromJson(Map<String, dynamic> json) {
    final keys = <String>{};
    for (final entry in json.entries) {
      if (_excludedFields.contains(entry.key)) continue;
      if (!_keyFieldPattern.hasMatch(entry.key)) continue;
      final value = entry.value;
      if (value is String && value.isNotEmpty) {
        keys.add(value);
      }
    }
    return keys.toList();
  }
}

class KeyField extends ConsumerStatefulWidget {
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String label;
  /// If the key maps to a fixed-size OPC UA array, pass its size here
  /// so the "add key" dialog can offer a dropdown for the index.
  final int? arraySize;

  const KeyField({
    super.key,
    this.initialValue,
    this.onChanged,
    this.label = 'Key',
    this.arraySize,
  });

  @override
  ConsumerState<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends ConsumerState<KeyField> {
  late TextEditingController _controller;
  List<String> _allKeys = [];
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      setState(() {});
    }
  }

  void _openSearchDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => KeySearchDialog(
        allKeys: _allKeys,
        initialQuery: _controller.text,
      ),
    );
    if (result != null) {
      _controller.text = result;
      widget.onChanged?.call(result);
      setState(() {});
    }
  }

  void _openKeyMappingDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => KeyMappingEntryDialog(
        initialKey: _controller.text,
        initialKeyMappingEntry: KeyMappingEntry(),
        arraySize: widget.arraySize,
      ),
    );

    if (result != null) {
      final key = result['key'] as String;
      final entry = result['entry'] as KeyMappingEntry;

      final keyMappings = (await ref.read(stateManProvider.future)).keyMappings;
      keyMappings.nodes[key] = entry;
      final prefs = await ref.read(preferencesProvider.future);
      await prefs.setString('key_mappings', jsonEncode(keyMappings.toJson()));

      _controller.text = key;
      widget.onChanged?.call(key);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _allKeys = snapshot.data!.keys.toList();
        }
        return TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _openSearchDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _openKeyMappingDialog,
                ),
              ],
            ),
          ),
          onChanged: widget.onChanged,
          onSubmitted: widget.onChanged,
        );
      },
    );
  }
}

class KeySearchDialog extends ConsumerStatefulWidget {
  final List<String>?
      allKeys; // can be omitted, then the keys are fetched from the state manager
  final String initialQuery;

  const KeySearchDialog({
    super.key,
    this.allKeys,
    required this.initialQuery,
  });

  @override
  ConsumerState<KeySearchDialog> createState() => _KeySearchDialogState();
}

class _KeySearchDialogState extends ConsumerState<KeySearchDialog> {
  late TextEditingController _searchController;
  List<String> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _performSearch(widget.initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) async {
    List<String> allKeys = widget.allKeys ??
        await ref
            .read(stateManProvider.future)
            .then((stateMan) => stateMan.keys);
    setState(() {
      _searchResults = allKeys
          .where((key) => key.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Keys'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _performSearch,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final key = _searchResults[index];
                  return ListTile(
                    dense: true,
                    title: Text(key),
                    onTap: () => Navigator.of(context).pop(key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _KeyFieldDialog extends StatefulWidget {
  const _KeyFieldDialog();

  String? get initialValue => null;

  @override
  State<_KeyFieldDialog> createState() => _KeyFieldDialogState();
}

class _KeyFieldDialogState extends State<_KeyFieldDialog> {
  late TextEditingController _namespaceController;
  late TextEditingController _identifierController;

  @override
  void initState() {
    super.initState();
    int ns = 0;
    String id = '';
    // Try to parse initial value if present
    final regex = RegExp(r'ns=(\d+);s=(.+)');
    if (widget.initialValue != null) {
      final match = regex.firstMatch(widget.initialValue!);
      if (match != null) {
        ns = int.tryParse(match.group(1) ?? '0') ?? 0;
        id = match.group(2) ?? '';
      }
    }
    _namespaceController = TextEditingController(text: ns.toString());
    _identifierController = TextEditingController(text: id);
  }

  @override
  void dispose() {
    _namespaceController.dispose();
    _identifierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Format OPC UA NodeId'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _namespaceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Namespace'),
          ),
          TextField(
            controller: _identifierController,
            decoration: const InputDecoration(labelText: 'Identifier'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final ns = int.tryParse(_namespaceController.text) ?? 0;
            final id = _identifierController.text;
            final isInt = int.tryParse(id) != null;
            final nodeId = isInt ? 'ns=$ns;i=$id' : 'ns=$ns;s=$id';
            Navigator.of(context).pop(nodeId);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class SizeField extends StatefulWidget {
  final RelativeSize initialValue;
  final ValueChanged<RelativeSize>? onChanged;
  final bool useSingleSize;

  const SizeField({
    super.key,
    required this.initialValue,
    this.onChanged,
    this.useSingleSize = false, // Default to false for backward compatibility
  });

  @override
  State<SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<SizeField> {
  late TextEditingController _widthController;
  late TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(
        text: (widget.initialValue.width * 100).toStringAsFixed(2));
    _heightController = TextEditingController(
        text: (widget.initialValue.height * 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (widget.useSingleSize) {
      final size = double.tryParse(_widthController.text) ?? 3.0;
      final relSize = RelativeSize(width: size / 100, height: size / 100);
      widget.onChanged?.call(relSize);
    } else {
      final width = double.tryParse(_widthController.text) ?? 3.0;
      final height = double.tryParse(_heightController.text) ?? 3.0;
      final relSize = RelativeSize(width: width / 100, height: height / 100);
      widget.onChanged?.call(relSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useSingleSize) {
      return Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _widthController,
              decoration: const InputDecoration(
                labelText: 'Size %',
                suffixText: '%',
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _onChanged(),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _widthController,
            decoration: const InputDecoration(labelText: 'Width %'),
            keyboardType: TextInputType.number,
            onChanged: (_) => _onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _heightController,
            decoration: const InputDecoration(labelText: 'Height %'),
            keyboardType: TextInputType.number,
            onChanged: (_) => _onChanged(),
          ),
        ),
      ],
    );
  }
}

class CoordinatesField extends StatefulWidget {
  final Coordinates initialValue;
  final ValueChanged<Coordinates>? onChanged;
  final bool enableAngle;

  const CoordinatesField({
    super.key,
    required this.initialValue,
    this.onChanged,
    this.enableAngle = false, // Default to false for backward compatibility
  });

  @override
  State<CoordinatesField> createState() => _CoordinatesFieldState();
}

class _CoordinatesFieldState extends State<CoordinatesField> {
  late TextEditingController _xController;
  late TextEditingController _yController;
  late TextEditingController _angleController;

  @override
  void initState() {
    super.initState();
    _xController = TextEditingController(
        text: (widget.initialValue.x * 100).toStringAsFixed(2));
    _yController = TextEditingController(
        text: (widget.initialValue.y * 100).toStringAsFixed(2));
    _angleController = TextEditingController(
        text: widget.initialValue.angle?.toStringAsFixed(2) ?? '');
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _angleController.dispose();
    super.dispose();
  }

  void _onChanged() {
    final x = double.tryParse(_xController.text) ?? 0.0;
    final y = double.tryParse(_yController.text) ?? 0.0;
    final angle =
        widget.enableAngle ? double.tryParse(_angleController.text) : null;

    final coordinates = Coordinates(
      x: x / 100, // Convert from percentage to 0.0-1.0 range
      y: y / 100,
      angle: angle,
    );
    widget.onChanged?.call(coordinates);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _xController,
                decoration: const InputDecoration(
                  labelText: 'X 0-100%',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _yController,
                decoration: const InputDecoration(
                  labelText: 'Y 0-100%',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _onChanged(),
              ),
            ),
          ],
        ),
        if (widget.enableAngle) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _angleController,
            decoration: InputDecoration(
              labelText: 'Angle (°)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Angle and Mirroring'),
                      content: const Text(
                        'When an angle is specified, the asset will be mirrored. '
                        'Positive angles rotate clockwise, negative angles rotate counterclockwise.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _onChanged(),
          ),
        ],
      ],
    );
  }
}

class KeyMappingEntryDialog extends ConsumerStatefulWidget {
  final String? initialKey;
  final KeyMappingEntry? initialKeyMappingEntry;
  /// Known array size for the target node. When set, the array-index field
  /// shows a dropdown (0-based) instead of a free-text box.
  final int? arraySize;

  const KeyMappingEntryDialog({
    super.key,
    this.initialKey,
    this.initialKeyMappingEntry,
    this.arraySize,
  });

  @override
  ConsumerState<KeyMappingEntryDialog> createState() =>
      _KeyMappingEntryDialogState();
}

/// Protocol type for the dialog's server selection.
enum _DialogProtocol { opcua, modbus, m2400 }

class _KeyMappingEntryDialogState extends ConsumerState<KeyMappingEntryDialog> {
  late TextEditingController _keyController;
  // The current entry being edited — updated by section widget callbacks.
  late KeyMappingEntry _entry;
  // Common state
  String? _selectedServerAlias;
  _DialogProtocol _protocol = _DialogProtocol.opcua;
  bool _isCollecting = false;
  ExpressionConfig? _sampleExpression;
  bool _useSampleExpression = false;
  // Config loaded from preferences
  StateManConfig? _config;
  bool _configLoading = true;

  @override
  void initState() {
    super.initState();

    if (widget.initialKeyMappingEntry != null) {
      final entry = widget.initialKeyMappingEntry!;
      _entry = entry;

      _keyController = TextEditingController(text: widget.initialKey ?? '');

      // Detect protocol from existing entry
      if (entry.modbusNode != null) {
        _protocol = _DialogProtocol.modbus;
        _selectedServerAlias = entry.modbusNode!.serverAlias;
      } else if (entry.m2400Node != null) {
        _protocol = _DialogProtocol.m2400;
        _selectedServerAlias = entry.m2400Node!.serverAlias;
      } else {
        _protocol = _DialogProtocol.opcua;
        _selectedServerAlias = entry.opcuaNode?.serverAlias;
      }

      final collect = entry.collect;
      if (collect != null) {
        _isCollecting = true;
        if (collect.sampleExpression != null) {
          _useSampleExpression = true;
          _sampleExpression = collect.sampleExpression;
        }
      }
    } else {
      _keyController = TextEditingController(text: widget.initialKey ?? '');
      _entry = KeyMappingEntry(
        opcuaNode: OpcUANodeConfig(namespace: 0, identifier: ''),
      );
    }

    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await ref.read(preferencesProvider.future);
      final config = await StateManConfig.fromPrefs(prefs);
      if (mounted) {
        setState(() {
          _config = config;
          _configLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _configLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  /// Builds the unified server list from all three protocol configs.
  List<({String alias, _DialogProtocol protocol, String label})> _buildServerList(
      StateManConfig config) {
    final servers = <({String alias, _DialogProtocol protocol, String label})>[];
    for (final c in config.opcua) {
      final alias = c.serverAlias ?? '__default';
      servers.add((
        alias: alias,
        protocol: _DialogProtocol.opcua,
        label: '$alias (OPC UA)',
      ));
    }
    for (final c in config.modbus) {
      final alias = c.serverAlias ?? c.host;
      servers.add((
        alias: alias,
        protocol: _DialogProtocol.modbus,
        label: '$alias (Modbus)',
      ));
    }
    for (final c in config.jbtm) {
      final alias = c.serverAlias ?? '__default';
      servers.add((
        alias: alias,
        protocol: _DialogProtocol.m2400,
        label: '$alias (M2400)',
      ));
    }
    servers.sort((a, b) => a.label.compareTo(b.label));
    return servers;
  }

  /// Finds the matching server label for the current selection.
  String? _findSelectedLabel(
      List<({String alias, _DialogProtocol protocol, String label})> servers) {
    for (final s in servers) {
      if (s.alias == _selectedServerAlias && s.protocol == _protocol) {
        return s.label;
      }
    }
    return null;
  }

  /// Whether the current entry uses a bit/boolean data type.
  /// When true, the bit mask grid restricts to single-bit selection.
  bool get _isBitType {
    if (_protocol == _DialogProtocol.modbus && _entry.modbusNode != null) {
      final node = _entry.modbusNode!;
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
    if (_protocol == _DialogProtocol.modbus && _entry.modbusNode != null) {
      final dt = _entry.modbusNode!.dataType;
      switch (dt) {
        case ModbusDataType.int32:
        case ModbusDataType.uint32:
        case ModbusDataType.float32:
          return 32;
        default:
          return 16;
      }
    }
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    if (_configLoading || _config == null) {
      return const AlertDialog(
        content: Center(child: CircularProgressIndicator()),
      );
    }

    final config = _config!;
    final servers = _buildServerList(config);
    final selectedLabel = _findSelectedLabel(servers);

    return AlertDialog(
      title: const Text('Configure Key Mapping'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _keyController,
                decoration: const InputDecoration(
                  labelText: 'Key',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedLabel,
                decoration: const InputDecoration(
                  labelText: 'Server',
                ),
                items: servers.map((s) {
                  return DropdownMenuItem(
                    value: s.label,
                    child: Text(s.label),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final selected = servers.firstWhere((s) => s.label == value);
                  setState(() {
                    _selectedServerAlias = selected.alias;
                    _protocol = selected.protocol;
                    // Switch entry to new protocol
                    switch (selected.protocol) {
                      case _DialogProtocol.opcua:
                        _entry = KeyMappingEntry(
                          opcuaNode: OpcUANodeConfig(
                            namespace: 0,
                            identifier: '',
                          )..serverAlias = selected.alias,
                          collect: _entry.collect,
                          bitMask: _entry.bitMask,
                          bitShift: _entry.bitShift,
                        );
                      case _DialogProtocol.modbus:
                        _entry = KeyMappingEntry(
                          modbusNode: ModbusNodeConfig(
                            serverAlias: selected.alias,
                            registerType: ModbusRegisterType.holdingRegister,
                            address: 0,
                          ),
                          collect: _entry.collect,
                          bitMask: _entry.bitMask,
                          bitShift: _entry.bitShift,
                        );
                      case _DialogProtocol.m2400:
                        _entry = KeyMappingEntry(
                          m2400Node: M2400NodeConfig(
                            recordType: M2400RecordType.recBatch,
                            serverAlias: selected.alias,
                          ),
                          collect: _entry.collect,
                        );
                    }
                  });
                },
              ),
              const SizedBox(height: 16),
              // Protocol-specific section widgets
              if (_protocol == _DialogProtocol.opcua)
                OpcUaConfigSection(
                  key: ValueKey('opcua-$_selectedServerAlias'),
                  config: _entry.opcuaNode ??
                      OpcUANodeConfig(namespace: 0, identifier: ''),
                  serverAliases: config.opcua
                      .map((c) => c.serverAlias ?? '__default')
                      .toList(),
                  onChanged: (nodeConfig) {
                    setState(() {
                      _entry = _entry.copyWith(opcuaNode: nodeConfig);
                    });
                  },
                )
              else if (_protocol == _DialogProtocol.modbus)
                ModbusConfigSection(
                  key: ValueKey('modbus-$_selectedServerAlias'),
                  config: _entry.modbusNode ??
                      ModbusNodeConfig(
                        registerType: ModbusRegisterType.holdingRegister,
                        address: 0,
                      ),
                  modbusServerAliases: config.modbus
                      .map((c) => c.serverAlias ?? c.host)
                      .toList(),
                  modbusConfigs: config.modbus,
                  onChanged: (nodeConfig) {
                    setState(() {
                      _entry = _entry.copyWith(modbusNode: nodeConfig);
                    });
                  },
                )
              else
                M2400ConfigSection(
                  key: ValueKey('m2400-$_selectedServerAlias'),
                  config: _entry.m2400Node ??
                      M2400NodeConfig(recordType: M2400RecordType.recBatch),
                  jbtmServerAliases: config.jbtm
                      .map((c) => c.serverAlias ?? '__default')
                      .toList(),
                  onChanged: (nodeConfig) {
                    setState(() {
                      _entry = _entry.copyWith(m2400Node: nodeConfig);
                    });
                  },
                ),
              // Bit selection -- required for bit types, optional mask for others
              if (_protocol != _DialogProtocol.m2400 && _isBitType) ...[
                const SizedBox(height: 8),
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
                        currentMask: _entry.bitMask,
                        singleBit: true,
                        onChanged: (result) {
                          setState(() {
                            if (result.mask == null) {
                              _entry = _entry.copyWith(clearBitMask: true);
                            } else {
                              _entry = _entry.copyWith(
                                bitMask: result.mask,
                                bitShift: result.shift,
                              );
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ] else if (_protocol != _DialogProtocol.m2400) ...[
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('Bit Mask (optional)'),
                  initiallyExpanded: _entry.bitMask != null,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: BitMaskGrid(
                        bitCount: _bitCountForDataType,
                        currentMask: _entry.bitMask,
                        onChanged: (result) {
                          setState(() {
                            if (result.mask == null) {
                              _entry = _entry.copyWith(clearBitMask: true);
                            } else {
                              _entry = _entry.copyWith(
                                bitMask: result.mask,
                                bitShift: result.shift,
                              );
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              // Collection config
              CollectionConfigSection(
                enabled: _isCollecting,
                collect: _entry.collect,
                keyName: _keyController.text.isNotEmpty
                    ? _keyController.text
                    : 'key',
                onToggle: (enabled) {
                  setState(() {
                    _isCollecting = enabled;
                    if (enabled) {
                      _entry = _entry.copyWith(
                        collect: CollectEntry(
                          key: _keyController.text,
                          retention: RetentionPolicy(
                            dropAfter: const Duration(days: 365),
                          ),
                        ),
                      );
                    } else {
                      _entry = KeyMappingEntry(
                        opcuaNode: _entry.opcuaNode,
                        m2400Node: _entry.m2400Node,
                        modbusNode: _entry.modbusNode,
                        bitMask: _entry.bitMask,
                        bitShift: _entry.bitShift,
                      );
                    }
                  });
                },
                onChanged: (collect) {
                  setState(() {
                    _entry = _entry.copyWith(collect: collect);
                  });
                },
              ),
              // Sample expression (dialog-specific, not in shared widget)
              if (_isCollecting) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Use Sample Expression'),
                    const SizedBox(width: 8),
                    Switch(
                      value: _useSampleExpression,
                      onChanged: (value) {
                        setState(() {
                          _useSampleExpression = value;
                          if (!value) {
                            _sampleExpression = null;
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (_useSampleExpression) ...[
                  const SizedBox(height: 16),
                  ExpressionBuilder(
                    value:
                        _sampleExpression?.value ?? Expression(formula: ''),
                    onChanged: (expression) {
                      setState(() {
                        _sampleExpression =
                            ExpressionConfig(value: expression);
                      });
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final key = _keyController.text;
            if (key.isEmpty) return;

            // Build the final collect entry with sample expression
            CollectEntry? collectEntry;
            if (_isCollecting && _entry.collect != null) {
              collectEntry = CollectEntry(
                key: key,
                name: _entry.collect!.name,
                sampleInterval: _entry.collect!.sampleInterval,
                sampleExpression:
                    _useSampleExpression ? _sampleExpression : null,
                retention: _entry.collect!.retention,
              );
            }

            final result = KeyMappingEntry(
              opcuaNode: _protocol == _DialogProtocol.opcua
                  ? _entry.opcuaNode
                  : null,
              modbusNode: _protocol == _DialogProtocol.modbus
                  ? _entry.modbusNode
                  : null,
              m2400Node: _protocol == _DialogProtocol.m2400
                  ? _entry.m2400Node
                  : null,
              collect: collectEntry,
              bitMask: _protocol != _DialogProtocol.m2400
                  ? _entry.bitMask
                  : null,
              bitShift: _protocol != _DialogProtocol.m2400
                  ? _entry.bitShift
                  : null,
            );

            // Validate required fields
            if (_protocol == _DialogProtocol.opcua &&
                (result.opcuaNode?.identifier.isEmpty ?? true)) {
              return;
            }
            // Bit type requires a bit selection
            if (_isBitType && result.bitMask == null) {
              return;
            }

            Navigator.of(context).pop({
              'key': key,
              'entry': result,
            });
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Rotates [child] by [angle] (radians),
/// *and* expands its layout box to the rotated AABB,
/// *and* transforms hit-testing so you get taps anywhere over it.
class LayoutRotatedBox extends SingleChildRenderObjectWidget {
  final double angle;
  const LayoutRotatedBox({
    required this.angle,
    super.child,
    super.key,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLayoutRotatedBox(angle);
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderLayoutRotatedBox renderObject) {
    renderObject.angle = angle;
  }
}

class _RenderLayoutRotatedBox extends RenderProxyBox {
  double _angle;
  _RenderLayoutRotatedBox(this._angle);

  set angle(double value) {
    if (value == _angle) return;
    _angle = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  @override
  void performLayout() {
    if (child == null) {
      size = constraints.smallest;
      return;
    }

    child!.layout(constraints, parentUsesSize: true);

    if (_angle == 0.0) {
      size = constraints.constrain(child!.size);
      return;
    }

    final w = child!.size.width;
    final h = child!.size.height;
    final c = math.cos(_angle).abs();
    final s = math.sin(_angle).abs();
    size = constraints.constrain(Size(w * c + h * s, w * s + h * c));
  }

  Offset _childOffset() {
    return Offset((size.width - child!.size.width) / 2,
        (size.height - child!.size.height) / 2);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    if (_angle == 0.0) {
      context.paintChild(child!, offset);
      return;
    }

    final childOffset = _childOffset();
    final transform = Matrix4.identity()
      ..translate(offset.dx + child!.size.width / 2 + childOffset.dx,
          offset.dy + child!.size.height / 2 + childOffset.dy)
      ..rotateZ(_angle)
      ..translate(-child!.size.width / 2, -child!.size.height / 2);

    context.pushTransform(
      needsCompositing,
      Offset.zero,
      transform,
      (innerContext, innerOffset) {
        innerContext.paintChild(child!, innerOffset);
      },
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (child == null) return false;

    if (_angle == 0.0) {
      if (position.dx >= 0 &&
          position.dx <= child!.size.width &&
          position.dy >= 0 &&
          position.dy <= child!.size.height) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
      return false;
    }

    final childOffset = _childOffset();
    final local = position - childOffset;
    final dx = local.dx - child!.size.width / 2;
    final dy = local.dy - child!.size.height / 2;
    final cosA = math.cos(-_angle), sinA = math.sin(-_angle);
    final x0 = cosA * dx - sinA * dy + child!.size.width / 2;
    final y0 = sinA * dx + cosA * dy + child!.size.height / 2;

    if (x0 >= 0 &&
        x0 <= child!.size.width &&
        y0 >= 0 &&
        y0 <= child!.size.height) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
