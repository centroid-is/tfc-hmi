import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:beamer/beamer.dart';
import 'common.dart';
import '../../providers/state_man.dart';
part 'option_variable.g.dart';

@JsonSerializable()
class OptionItem {
  String value;
  String label;
  String? description;

  OptionItem({
    required this.value,
    required this.label,
    this.description,
  });

  factory OptionItem.fromJson(Map<String, dynamic> json) =>
      _$OptionItemFromJson(json);
  Map<String, dynamic> toJson() => _$OptionItemToJson(this);
}

@JsonSerializable()
class OptionVariableConfig extends BaseAsset {
  /// The variable name that will be set in StateMan
  /// Example: "current_baader_machine"
  String variableName;

  /// List of available options
  final List<OptionItem> options;

  /// The currently selected option value
  String? selectedValue;

  /// Optional default value
  String? defaultValue;

  /// Whether to show a search/filter field
  bool showSearch;

  /// Custom label for the dropdown
  String? customLabel;

  OptionVariableConfig({
    required this.variableName,
    required this.options,
    this.selectedValue,
    this.defaultValue,
    this.showSearch = true,
    this.customLabel,
  }) {
    // Set default value if provided and no selection made
    if (selectedValue == null && defaultValue != null) {
      selectedValue = defaultValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OptionVariableWidget(this);
  }

  @override
  Widget configure(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final maxWidth = media.width * 0.9;
    final maxHeight = media.height * 0.8;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          minWidth: 400,
          minHeight: 300,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: DialogTheme.of(context).backgroundColor ??
              Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: _ConfigContent(config: this),
            ),
          ),
        ),
      ),
    );
  }

  static const previewStr = 'OptionVariable preview';

  OptionVariableConfig.preview()
      : variableName = 'current_baader_machine',
        options = [
          OptionItem(
              value: 'Baader9',
              label: 'Baader 9',
              description: 'Baader machine 9'),
          OptionItem(
              value: 'Baader10',
              label: 'Baader 10',
              description: 'Baader machine 10'),
        ],
        showSearch = true,
        customLabel = 'Select Baader Machine' {
    textPos = TextPos.below;
    selectedValue = 'Baader9';
  }

  factory OptionVariableConfig.fromJson(Map<String, dynamic> json) =>
      _$OptionVariableConfigFromJson(json);
  Map<String, dynamic> toJson() => _$OptionVariableConfigToJson(this);
}

class OptionVariableWidget extends ConsumerStatefulWidget {
  final OptionVariableConfig config;

  const OptionVariableWidget(this.config, {super.key});

  @override
  ConsumerState<OptionVariableWidget> createState() =>
      _OptionVariableWidgetState();
}

class _OptionVariableWidgetState extends ConsumerState<OptionVariableWidget> {
  String? _selectedValue;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Logger _logger = Logger();
  bool _isExpanded = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  String? _queryParam;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.config.selectedValue;
    _searchController.text = _searchQuery;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    String? getQueryParam(BuildContext context, String name) {
      final uri =
          Beamer.of(context).currentBeamLocation.state.routeInformation.uri;
      return uri.queryParameters[name];
    }

    _queryParam = getQueryParam(context, widget.config.variableName);
    _selectedValue = _queryParam ?? widget.config.selectedValue;

    _initializeVariable();
  }

  void _initializeVariable() async {
    if (_selectedValue != null) {
      try {
        final stateMan = await ref.read(stateManProvider.future);

        if (_queryParam != null) {
          _logger.d(
              'Setting variable ${widget.config.variableName} = $_selectedValue from query param $_queryParam');
          stateMan.setSubstitution(widget.config.variableName, _selectedValue!);
        }

        // Only set if not already set
        if (stateMan.getSubstitution(widget.config.variableName) == null) {
          stateMan.setSubstitution(widget.config.variableName, _selectedValue!);
          _logger.d(
              'Initialized variable ${widget.config.variableName} = $_selectedValue');
        } else {
          _logger.d(
              'Variable ${widget.config.variableName} already set, skipping initialization');
        }
      } catch (e) {
        _logger.e('Failed to initialize variable: $e');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggleDropdown() {
    if (_isExpanded) {
      _removeOverlay();
      setState(() {
        _isExpanded = false;
      });
    } else {
      _showDropdown();
      setState(() {
        _isExpanded = true;
      });
    }
  }

  void _showDropdown() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 250, // Fixed width for dropdown
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 40),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search field
                  if (widget.config.showSearch)
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          prefixIcon: const Icon(Icons.search, size: 16),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),

                  // Options list
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredOptions.length,
                      itemBuilder: (context, index) {
                        final option = _filteredOptions[index];
                        final isSelected = option.value == _selectedValue;

                        return InkWell(
                          onTap: () {
                            _updateVariable(option.value);
                            _removeOverlay();
                            setState(() {
                              _isExpanded = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue.shade50 : null,
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade200,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  color: isSelected ? Colors.blue : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        option.label,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      if (option.description != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          option.description!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ],
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
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateVariable(String value) async {
    try {
      final stateMan = await ref.read(stateManProvider.future);
      stateMan.setSubstitution(widget.config.variableName, value);

      setState(() {
        _selectedValue = value;
        widget.config.selectedValue = value;
        _searchQuery = '';
        _searchController.clear();
      });

      _logger.d('Set variable ${widget.config.variableName} = $value');
    } catch (e) {
      _logger.e('Failed to set variable: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set variable: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  List<OptionItem> get _filteredOptions {
    if (_searchQuery.isEmpty) return widget.config.options;

    return widget.config.options.where((option) {
      return option.label.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          option.value.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (option.description
                  ?.toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ??
              false);
    }).toList();
  }

  String _getSelectedLabel() {
    final selectedOption = widget.config.options.firstWhere(
      (option) => option.value == _selectedValue,
      orElse: () => OptionItem(value: '', label: ''),
    );

    // Truncate label if it's too long to prevent overflow
    final label = selectedOption.label;
    if (label.length > 20) {
      return '${label.substring(0, 17)}...';
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CompositedTransformTarget(
          link: _layerLink,
          child: Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: InkWell(
              onTap: _toggleDropdown,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 0, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedValue == null) ...[
                            SizedBox(
                              width: constraints.maxWidth *
                                  0.7, // Give it 70% of available width
                              height: constraints.maxHeight * 0.7,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.config.customLabel ??
                                      widget.config.variableName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            )
                          ],
                          if (_selectedValue != null) ...[
                            SizedBox(
                              width: constraints.maxWidth *
                                  0.7, // Give it 70% of available width
                              height: constraints.maxHeight * 0.7,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _getSelectedLabel(),
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Arrow indicator - also make it scale
                    FittedBox(
                      fit: BoxFit.contain,
                      child: Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: _isExpanded
                            ? Colors.blue.shade600
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConfigContent extends ConsumerWidget {
  final OptionVariableConfig config;

  const _ConfigContent({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Configure Option Variable',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),

        // Variable name
        TextFormField(
          initialValue: config.variableName,
          decoration: const InputDecoration(
            labelText: 'Variable Name',
            hintText: 'e.g., current_baader_machine',
            helperText:
                'This variable will be available in StateMan for key substitution',
          ),
          onChanged: (value) {
            config.variableName = value;
          },
        ),

        const SizedBox(height: 20),

        // Custom label
        TextFormField(
          initialValue: config.customLabel,
          decoration: const InputDecoration(
            labelText: 'Custom Label (Optional)',
            hintText: 'e.g., Select Baader Machine',
          ),
          onChanged: (value) {
            config.customLabel = value;
          },
        ),

        const SizedBox(height: 20),

        // Options list with editor
        Row(
          children: [
            Text(
              'Options',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _showOptionsEditor(context),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Edit Options'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Current options display
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Options (${config.options.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              ...config.options.asMap().entries.map((entry) {
                final index = entry.key;
                final option = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (option.description != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                option.description!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              'Value: ${option.value}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16),
                        onPressed: () => _editOption(context, index, option),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete,
                            size: 16, color: Colors.red),
                        onPressed: () => _deleteOption(context, index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Show search toggle
        SwitchListTile(
          title: const Text('Show Search Field'),
          subtitle: const Text('Allow users to search/filter options'),
          value: config.showSearch,
          onChanged: (value) {
            config.showSearch = value;
          },
        ),

        const SizedBox(height: 20),

        // Size configuration
        Text(
          'Size',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizeField(
          initialValue: config.size,
          onChanged: (value) {
            config.size = value;
          },
        ),

        const SizedBox(height: 20),

        // Coordinates configuration
        Text(
          'Position',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        CoordinatesField(
          initialValue: config.coordinates,
          onChanged: (value) {
            config.coordinates = value;
          },
        ),

        const SizedBox(height: 20),

        // Text position configuration
        Text(
          'Text Position',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButton<TextPos>(
          value: config.textPos,
          isExpanded: true,
          onChanged: (value) {
            config.textPos = value;
          },
          items: TextPos.values
              .map((e) => DropdownMenuItem<TextPos>(
                    value: e,
                    child: Text(e.name[0].toUpperCase() + e.name.substring(1)),
                  ))
              .toList(),
        ),

        const SizedBox(height: 20),

        // Text content configuration
        TextFormField(
          initialValue: config.text,
          decoration: const InputDecoration(
            labelText: 'Text (Optional)',
            hintText: 'Text to display with this asset',
          ),
          onChanged: (value) {
            config.text = value;
          },
        ),
      ],
    );
  }

  void _showOptionsEditor(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _OptionsEditorDialog(config: config),
    );
  }

  void _editOption(BuildContext context, int index, OptionItem option) {
    showDialog(
      context: context,
      builder: (context) => _OptionEditDialog(
        config: config,
        index: index,
        option: option,
      ),
    );
  }

  void _deleteOption(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Option'),
        content: Text(
            'Are you sure you want to delete "${config.options[index].label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              config.options.removeAt(index);
              Navigator.of(context).pop();
              // Force rebuild
              (context as Element).markNeedsBuild();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _OptionsEditorDialog extends StatefulWidget {
  final OptionVariableConfig config;

  const _OptionsEditorDialog({required this.config});

  @override
  State<_OptionsEditorDialog> createState() => _OptionsEditorDialogState();
}

class _OptionsEditorDialogState extends State<_OptionsEditorDialog> {
  late List<OptionItem> _options;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Create a copy of the options to edit
    _options = widget.config.options
        .map((o) => OptionItem(
              value: o.value,
              label: o.label,
              description: o.description,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Options'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Option'),
                ),
                const Spacer(),
                Text('${_options.length} options'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _options.length,
                itemBuilder: (context, index) {
                  final option = _options[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Option ${index + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18),
                                onPressed: () => _removeOption(index),
                                color: Colors.red,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: option.label,
                                  decoration: const InputDecoration(
                                    labelText: 'Label',
                                    isDense: true,
                                  ),
                                  onChanged: (value) {
                                    option.label = value;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  initialValue: option.value,
                                  decoration: const InputDecoration(
                                    labelText: 'Value',
                                    isDense: true,
                                  ),
                                  onChanged: (value) {
                                    option.value = value;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: option.description,
                            decoration: const InputDecoration(
                              labelText: 'Description (Optional)',
                              isDense: true,
                            ),
                            onChanged: (value) {
                              option.description = value;
                            },
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
          onPressed: _saveOptions,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _addOption() {
    setState(() {
      _options.add(OptionItem(
        value: 'Option${_options.length + 1}',
        label: 'Option ${_options.length + 1}',
        description: null,
      ));
    });
  }

  void _removeOption(int index) {
    setState(() {
      _options.removeAt(index);
    });
  }

  void _saveOptions() {
    // Update the config with the new options
    widget.config.options.clear();
    widget.config.options.addAll(_options);
    Navigator.of(context).pop();
    // Force rebuild of the parent
    (context as Element).markNeedsBuild();
  }
}

class _OptionEditDialog extends StatefulWidget {
  final OptionVariableConfig config;
  final int index;
  final OptionItem option;

  const _OptionEditDialog({
    required this.config,
    required this.index,
    required this.option,
  });

  @override
  State<_OptionEditDialog> createState() => _OptionEditDialogState();
}

class _OptionEditDialogState extends State<_OptionEditDialog> {
  late TextEditingController _labelController;
  late TextEditingController _valueController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.option.label);
    _valueController = TextEditingController(text: widget.option.value);
    _descriptionController =
        TextEditingController(text: widget.option.description);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _valueController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Option ${widget.index + 1}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Label',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _valueController,
            decoration: const InputDecoration(
              labelText: 'Value',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description (Optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveOption,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _saveOption() {
    widget.option.label = _labelController.text;
    widget.option.value = _valueController.text;
    widget.option.description = _descriptionController.text.isEmpty
        ? null
        : _descriptionController.text;

    Navigator.of(context).pop();
    // Force rebuild of the parent
    (context as Element).markNeedsBuild();
  }
}
