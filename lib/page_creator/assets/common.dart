import 'dart:ui' show Color, Size;
import 'dart:math' as math;

import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/collector.dart';
import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import '../../providers/state_man.dart';
import '../../providers/preferences.dart';
import '../../widgets/boolean_expression.dart';

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

@JsonSerializable(createFactory: false, explicitToJson: true)
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
}

class KeyField extends ConsumerStatefulWidget {
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String label;

  const KeyField({
    super.key,
    this.initialValue,
    this.onChanged,
    this.label = 'Key',
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
      final finalKey = await _checkArrayAndPrompt(result);
      _controller.text = finalKey;
      widget.onChanged?.call(finalKey);
      setState(() {});
    }
  }

  void _openKeyMappingDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => KeyMappingEntryDialog(
        initialKey: _controller.text,
        initialKeyMappingEntry: KeyMappingEntry(),
      ),
    );

    if (result != null) {
      final key = result['key'] as String;
      final entry = result['entry'] as KeyMappingEntry;

      final keyMappings = (await ref.read(stateManProvider.future)).keyMappings;
      keyMappings.nodes[key] = entry;
      final prefs = await ref.read(preferencesProvider.future);
      await prefs.setString('key_mappings', jsonEncode(keyMappings.toJson()));

      final finalKey = await _checkArrayAndPrompt(key);
      _controller.text = finalKey;
      widget.onChanged?.call(finalKey);
      setState(() {});
    }
  }

  /// If [key] maps to an array OPC UA node (no array index set),
  /// prompts the user to pick an index and creates a derived key.
  /// Returns the original key if not an array or user cancels.
  Future<String> _checkArrayAndPrompt(String key) async {
    if (key.isEmpty) return key;
    try {
      final stateMan = await ref.read(stateManProvider.future);
      final value = await stateMan.read(key);
      if (!value.isArray) return key;
      if (!mounted) return key;

      final selectedIndex = await showDialog<int>(
        context: context,
        builder: (context) => _ArrayIndexDialog(
          arrayValue: value,
          keyName: key,
        ),
      );
      if (selectedIndex == null) return key;

      // Create a new indexed key
      final newKey = '$key[$selectedIndex]';
      final existingEntry = stateMan.keyMappings.nodes[key];
      if (existingEntry?.opcuaNode != null) {
        final srcNode = existingEntry!.opcuaNode!;
        final indexedNode = OpcUANodeConfig(
          namespace: srcNode.namespace,
          identifier: srcNode.identifier,
        )
          ..arrayIndex = selectedIndex
          ..serverAlias = srcNode.serverAlias;
        final indexedEntry = KeyMappingEntry(opcuaNode: indexedNode);
        stateMan.keyMappings.nodes[newKey] = indexedEntry;
        final prefs = await ref.read(preferencesProvider.future);
        await prefs.setString(
            'key_mappings', jsonEncode(stateMan.keyMappings.toJson()));
      }
      return newKey;
    } catch (_) {
      // Read failed (not connected, key not found, etc.) — just use as-is
      return key;
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
  KeyMappings? _keyMappings;

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
    final stateMan = await ref.read(stateManProvider.future);
    List<String> allKeys = widget.allKeys ?? stateMan.keys;
    _keyMappings ??= stateMan.keyMappings;
    setState(() {
      _searchResults = allKeys
          .where((key) => key.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  String? _buildSubtitle(String key) {
    final entry = _keyMappings?.nodes[key];
    if (entry?.opcuaNode == null) return null;
    final node = entry!.opcuaNode!;
    final id = int.tryParse(node.identifier) != null
        ? 'ns=${node.namespace};i=${node.identifier}'
        : 'ns=${node.namespace};s=${node.identifier}';
    if (node.arrayIndex != null) {
      return '$id [idx: ${node.arrayIndex}]';
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  final subtitle = _buildSubtitle(key);
                  return ListTile(
                    dense: true,
                    title: Text(key),
                    subtitle: subtitle != null
                        ? Text(subtitle,
                            style: TextStyle(
                                fontSize: 11, color: cs.secondary))
                        : null,
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
  final String? initialValue;

  const _KeyFieldDialog({this.initialValue});

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

class _ArrayIndexDialog extends StatefulWidget {
  final DynamicValue arrayValue;
  final String keyName;

  const _ArrayIndexDialog({
    required this.arrayValue,
    required this.keyName,
  });

  @override
  State<_ArrayIndexDialog> createState() => _ArrayIndexDialogState();
}

class _ArrayIndexDialogState extends State<_ArrayIndexDialog> {
  late TextEditingController _indexController;
  int? _selectedIndex;

  List<DynamicValue> get _elements => widget.arrayValue.asArray;

  @override
  void initState() {
    super.initState();
    _indexController = TextEditingController();
  }

  @override
  void dispose() {
    _indexController.dispose();
    super.dispose();
  }

  String _formatValue(DynamicValue dv) {
    if (dv.isNull) return 'null';
    if (dv.isArray) return '[Array(${dv.asArray.length})]';
    if (dv.isObject) return '{Object(${dv.asObject.keys.length})}';
    final s = dv.value?.toString() ?? 'null';
    return s.length > 60 ? '${s.substring(0, 57)}...' : s;
  }

  bool get _isValid {
    final idx = int.tryParse(_indexController.text);
    return idx != null && idx >= 0 && idx < _elements.length;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Array: ${widget.keyName}'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_elements.length} elements (index 0 to ${_elements.length - 1})',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.secondary,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _indexController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Index',
                hintText: '0..${_elements.length - 1}',
                errorText: _indexController.text.isNotEmpty && !_isValid
                    ? 'Must be 0..${_elements.length - 1}'
                    : null,
              ),
              onChanged: (_) => setState(() {
                _selectedIndex = int.tryParse(_indexController.text);
              }),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _elements.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedIndex == index;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                        _indexController.text = index.toString();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      color: isSelected
                          ? cs.primaryContainer
                          : Colors.transparent,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              '[$index]',
                              style: TextStyle(
                                color: cs.secondary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _formatValue(_elements[index]),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isValid
              ? () => Navigator.of(context).pop(_selectedIndex)
              : null,
          child: const Text('Create Indexed Key'),
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

  const KeyMappingEntryDialog({
    super.key,
    this.initialKey,
    this.initialKeyMappingEntry,
  });

  @override
  ConsumerState<KeyMappingEntryDialog> createState() =>
      _KeyMappingEntryDialogState();
}

class _KeyMappingEntryDialogState extends ConsumerState<KeyMappingEntryDialog> {
  late TextEditingController _keyController;
  late TextEditingController _namespaceController;
  late TextEditingController _identifierController;
  late TextEditingController _arrayIndexController;
  late TextEditingController _collectNameController;
  late TextEditingController _collectIntervalController;
  late TextEditingController _retentionDaysController;
  late TextEditingController _scheduleIntervalController;
  String? _selectedServerAlias;
  bool _isCollecting = false;
  ExpressionConfig? _sampleExpression;
  bool _useSampleExpression = false;

  @override
  void initState() {
    super.initState();

    // Initialize from existing KeyMappingEntry if available
    if (widget.initialKeyMappingEntry != null) {
      final entry = widget.initialKeyMappingEntry!;

      _keyController = TextEditingController(text: widget.initialKey ?? '');
      _namespaceController = TextEditingController(
          text: entry.opcuaNode?.namespace.toString() ?? '0');
      _identifierController =
          TextEditingController(text: entry.opcuaNode?.identifier ?? '');
      _arrayIndexController = TextEditingController(
          text: entry.opcuaNode?.arrayIndex?.toString() ?? '');
      _selectedServerAlias = entry.opcuaNode?.serverAlias;

      // Initialize collect settings if they exist
      if (entry.collect != null) {
        _isCollecting = true; // Add this line to enable the toggle
        _collectNameController =
            TextEditingController(text: entry.collect!.name ?? '');
        _collectIntervalController = TextEditingController(
            text:
                entry.collect!.sampleInterval?.inMicroseconds.toString() ?? '');
        _retentionDaysController = TextEditingController(
            text: entry.collect!.retention.dropAfter.inDays.toString());
        _scheduleIntervalController = TextEditingController(
            text: entry.collect!.retention.scheduleInterval?.inMinutes
                    .toString() ??
                '');

        if (entry.collect!.sampleExpression != null) {
          _useSampleExpression = true;
          _sampleExpression = entry.collect!.sampleExpression;
        }
      } else {
        // Default values for new entries
        _isCollecting = false; // Add this line to ensure it's off
        _collectNameController = TextEditingController();
        _collectIntervalController = TextEditingController();
        _retentionDaysController = TextEditingController(text: '365');
        _scheduleIntervalController = TextEditingController();
      }
    } else {
      // Default values for completely new entries
      _keyController = TextEditingController(text: widget.initialKey ?? '');
      _namespaceController = TextEditingController(text: '0');
      _identifierController = TextEditingController();
      _arrayIndexController = TextEditingController();
      _collectNameController = TextEditingController();
      _collectIntervalController = TextEditingController();
      _retentionDaysController = TextEditingController(text: '365');
      _scheduleIntervalController = TextEditingController();
      _selectedServerAlias = null;
      _isCollecting = false; // Add this line to ensure it's off
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _namespaceController.dispose();
    _identifierController.dispose();
    _arrayIndexController.dispose();
    _collectNameController.dispose();
    _collectIntervalController.dispose();
    _retentionDaysController.dispose();
    _scheduleIntervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StateMan>(
      future: ref.watch(stateManProvider.future),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        final stateMan = snapshot.data!;
        final serverAliases = stateMan.config.opcua
            .map((config) => config.serverAlias ?? "__default")
            .toList();
        serverAliases.sort();

        return AlertDialog(
          title: const Text('Configure Key Mapping'),
          content: SingleChildScrollView(
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
                const Text('OPC UA Node Configuration',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButtonFormField<String>(
                  value: _selectedServerAlias,
                  decoration: const InputDecoration(
                    labelText: 'Server',
                  ),
                  items: serverAliases.map((alias) {
                    return DropdownMenuItem(
                      value: alias,
                      child: Text(alias),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      if (value == "__default") {
                        _selectedServerAlias = null;
                      } else {
                        _selectedServerAlias = value;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _namespaceController,
                  decoration: const InputDecoration(
                    labelText: 'Namespace',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _identifierController,
                  decoration: const InputDecoration(
                    labelText: 'Identifier',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _arrayIndexController,
                  decoration: const InputDecoration(
                    labelText: 'Array Index (optional)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Enable Data Collection'),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isCollecting,
                      onChanged: (value) {
                        setState(() {
                          _isCollecting = value;
                        });
                      },
                    ),
                  ],
                ),
                if (_isCollecting) ...[
                  TextField(
                    controller: _collectNameController,
                    decoration: const InputDecoration(
                      labelText: 'Collection Name (optional)',
                      hintText: 'Leave empty to use key name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _collectIntervalController,
                    decoration: const InputDecoration(
                      labelText: 'Sample Interval (microseconds)',
                      hintText: 'Leave empty for no sampling',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  const Text('Retention Policy',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _retentionDaysController,
                    decoration: const InputDecoration(
                      labelText: 'Retention Period (days)',
                      hintText: 'How long to keep data',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _scheduleIntervalController,
                    decoration: const InputDecoration(
                      labelText: 'Schedule Interval (minutes)',
                      hintText: 'How often to run retention policy (optional)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final key = _keyController.text;
                if (key.isEmpty) return;

                final ns = int.tryParse(_namespaceController.text) ?? 0;
                final id = _identifierController.text;
                if (id.isEmpty) return;

                final nodeConfig = OpcUANodeConfig(
                  namespace: ns,
                  identifier: id,
                )
                  ..arrayIndex = _arrayIndexController.text.isNotEmpty
                      ? int.tryParse(_arrayIndexController.text)
                      : null
                  ..serverAlias = _selectedServerAlias;

                CollectEntry? collectEntry;
                if (_isCollecting) {
                  final retentionDays =
                      int.tryParse(_retentionDaysController.text) ?? 365;
                  final sampleIntervalUs =
                      int.tryParse(_collectIntervalController.text);
                  final scheduleIntervalMinutes =
                      int.tryParse(_scheduleIntervalController.text);

                  collectEntry = CollectEntry(
                    key: key,
                    name: _collectNameController.text.isEmpty
                        ? null
                        : _collectNameController.text,
                    sampleInterval: sampleIntervalUs != null
                        ? Duration(microseconds: sampleIntervalUs)
                        : null,
                    sampleExpression:
                        _useSampleExpression ? _sampleExpression : null,
                    retention: RetentionPolicy(
                      dropAfter: Duration(days: retentionDays),
                      scheduleInterval: scheduleIntervalMinutes != null
                          ? Duration(minutes: scheduleIntervalMinutes)
                          : null,
                    ),
                  );
                }

                final entry = KeyMappingEntry(
                  opcuaNode: nodeConfig,
                  collect: collectEntry,
                );

                Navigator.of(context).pop({
                  'key': key,
                  'entry': entry,
                });
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
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
    Widget? child,
    Key? key,
  }) : super(key: key, child: child);

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

    // 1) Layout the child at its normal constraints
    child!.layout(constraints, parentUsesSize: true);
    final w = child!.size.width;
    final h = child!.size.height;

    // 2) Compute the axis-aligned bbox of the rotated rect
    final c = math.cos(_angle).abs();
    final s = math.sin(_angle).abs();
    final boxW = w * c + h * s;
    final boxH = w * s + h * c;

    size = constraints.constrain(Size(boxW, boxH));
  }

  Offset _childOffset() {
    // Center the child in our AABB
    return Offset((size.width - child!.size.width) / 2,
        (size.height - child!.size.height) / 2);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;

    // 3) Push the rotation transform + center
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

    // 4) Convert `position` into the child's unrotated coords
    final childOffset = _childOffset();
    final local = position - childOffset;
    final dx = local.dx - child!.size.width / 2;
    final dy = local.dy - child!.size.height / 2;
    final cosA = math.cos(-_angle), sinA = math.sin(-_angle);
    final x0 = cosA * dx - sinA * dy + child!.size.width / 2;
    final y0 = sinA * dx + cosA * dy + child!.size.height / 2;

    // 5) If inside the child's rect, hit
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
