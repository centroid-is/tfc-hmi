import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dbus/dbus.dart';
import '../dbus/config.dart';

class ConfigEditPage extends StatefulWidget {
  final DBusClient dbusClient;
  final String serviceName;
  final String objectPath;

  const ConfigEditPage({
    Key? key,
    required this.dbusClient,
    required this.serviceName,
    required this.objectPath,
  }) : super(key: key);

  @override
  State<ConfigEditPage> createState() => _ConfigEditPageState();
}

class _ConfigEditPageState extends State<ConfigEditPage> {
  ConfigClient? _configClient;
  bool _isLoading = true;
  String _errorMessage = '';

  Map<String, dynamic>? _schema;
  Map<String, dynamic> _configData = {};

  // We might keep a global form key for validation, if desired
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _initConfigClient();
  }

  @override
  void dispose() {
    _configClient?.close();
    super.dispose();
  }

  Future<void> _initConfigClient() async {
    try {
      final client = await ConfigClient.create(
        widget.dbusClient,
        DBusObjectPath(widget.objectPath),
        widget.serviceName,
      );
      _configClient = client;
      final schemaStr = await client.getSchema();
      final config = await client.getValueAsJson();

      setState(() {
        _schema = json.decode(schemaStr) as Map<String, dynamic>?;
        _configData = config;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize config: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    if (_configClient == null) return;
    // Optionally validate form if using Form widgets
    if (!_formKey.currentState!.validate()) {
      // If validation fails, do not proceed
      return;
    }
    try {
      await _configClient!.setValueFromJson(_configData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Config saved successfully!')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save config: $err')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading Config...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(_errorMessage)),
      );
    }

    if (_schema == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('No Schema')),
        body: const Center(child: Text('Schema not found or invalid.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuration Editor')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildSchemaForm(_schema!, _configData, (updated) {
            setState(() {
              // Root-level update
              _configData = updated;
            });
          }),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveConfig,
        child: const Icon(Icons.save),
      ),
    );
  }

  // =========== SCHEMA FORM BUILDING ===========

  /// Entry point for building the entire form from the root schema object
  Widget _buildSchemaForm(
    Map<String, dynamic> schema,
    Map<String, dynamic> data,
    ValueChanged<Map<String, dynamic>> onChanged,
  ) {
    if (schema['type'] == 'object') {
      return _buildObjectForm(schema, data, onChanged);
    } else {
      return const Text('Root schema must be an object for this example.');
    }
  }

  /// Build a form for an object schema (which has "properties").
  Widget _buildObjectForm(
    Map<String, dynamic> schema,
    Map<String, dynamic> data,
    ValueChanged<Map<String, dynamic>> onChanged,
  ) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final requiredFields =
        (schema['required'] as List<dynamic>? ?? []).cast<String>();

    // For each property, build an appropriate widget
    final fields = <Widget>[];
    properties.forEach((propName, propSchemaRaw) {
      final propSchema = propSchemaRaw as Map<String, dynamic>;
      final value = data[propName];
      final isRequired = requiredFields.contains(propName);

      fields.add(
        _buildPropertyField(
          propName,
          propSchema,
          value,
          isRequired: isRequired,
          onChanged: (newVal) {
            data[propName] = newVal;
            onChanged(data);
          },
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields,
    );
  }

  /// Decides how to build a specific property field, based on schema type, etc.
  Widget _buildPropertyField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value, {
    required bool isRequired,
    required ValueChanged<dynamic> onChanged,
  }) {
    final readOnly = schema['readOnly'] == true;
    final fieldType = schema['type'];

    // Handle multiple types if it's an array of possible types
    if (fieldType is List) {
      // For simplicity, pick the first or handle logic here
      // This is a simplified approach (real logic might require "anyOf"/"oneOf").
      return Text('$fieldName: multiple types not fully supported yet');
    }

    switch (fieldType) {
      case 'object':
        // Nested object
        if (value is! Map<String, dynamic>) value = <String, dynamic>{};
        return ExpansionTile(
          title: Text(fieldName),
          subtitle: Text(schema['description']?.toString() ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _buildObjectForm(
                  schema, value, (newMap) => onChanged(newMap)),
            ),
          ],
        );

      case 'array':
        // Array of items
        if (value is! List) value = <dynamic>[];
        return _buildArrayField(fieldName, schema, value, readOnly, onChanged);

      case 'string':
        return _buildStringField(
            fieldName, schema, value, isRequired, readOnly, onChanged);

      case 'boolean':
        return _buildBooleanField(
            fieldName, schema, value, readOnly, onChanged);

      case 'number':
      case 'integer':
        return _buildNumberField(fieldName, schema, value, fieldType,
            isRequired, readOnly, onChanged);

      case 'null':
        // Rare; if your schema explicitly sets "type": "null" – basically read-only
        return ListTile(
          title: Text(fieldName),
          subtitle: const Text('Value is null'),
        );

      default:
        return Text('$fieldName: Unsupported type "$fieldType"');
    }
  }

  // =========== ARRAY FIELD ===========

  Widget _buildArrayField(
    String fieldName,
    Map<String, dynamic> schema,
    List<dynamic> value,
    bool readOnly,
    ValueChanged<dynamic> onChanged,
  ) {
    final minItems = schema['minItems'] as int? ?? 0;
    final maxItems = schema['maxItems'] as int?;
    final uniqueItems = schema['uniqueItems'] == true;
    final itemsSchema = schema['items'] as Map<String, dynamic>?;

    Widget buildItem(int index, dynamic itemValue) {
      if (itemsSchema == null) {
        return Text('$fieldName[$index]: no "items" schema');
      }
      return _buildPropertyField(
        '$fieldName[$index]',
        itemsSchema,
        itemValue,
        isRequired: false,
        onChanged: (newVal) {
          value[index] = newVal;
          onChanged(value);
        },
      );
    }

    // Validate uniqueness if `uniqueItems == true`
    void _ensureUniqueItems() {
      if (uniqueItems) {
        final unique = <dynamic>{};
        final duplicates = <int>[];
        for (int i = 0; i < value.length; i++) {
          if (!unique.add(value[i])) {
            duplicates.add(i);
          }
        }
        // Remove duplicates from the end so indexes remain stable
        for (final dupIndex in duplicates.reversed) {
          value.removeAt(dupIndex);
        }
      }
    }

    _ensureUniqueItems();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fieldName, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (int i = 0; i < value.length; i++)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: buildItem(i, value[i])),
                  if (!readOnly)
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        if (value.length > minItems) {
                          setState(() {
                            value.removeAt(i);
                          });
                          onChanged(value);
                        }
                      },
                    )
                ],
              ),
            ),
          if (!readOnly && (maxItems == null || value.length < maxItems))
            ElevatedButton.icon(
              onPressed: () {
                // We attempt to create a default item
                dynamic newItem;
                if (itemsSchema?['default'] != null) {
                  newItem = itemsSchema!['default'];
                } else {
                  // type-based default
                  final t = itemsSchema?['type'];
                  if (t == 'string')
                    newItem = '';
                  else if (t == 'number' || t == 'integer')
                    newItem = 0;
                  else if (t == 'boolean')
                    newItem = false;
                  else if (t == 'object')
                    newItem = <String, dynamic>{};
                  else if (t == 'array')
                    newItem = <dynamic>[];
                  else
                    newItem = null;
                }
                setState(() {
                  value.add(newItem);
                  _ensureUniqueItems();
                });
                onChanged(value);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
        ],
      ),
    );
  }

  // =========== STRING FIELD ===========

  Widget _buildStringField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value,
    bool isRequired,
    bool readOnly,
    ValueChanged<dynamic> onChanged,
  ) {
    final controller = TextEditingController(text: value?.toString() ?? '');
    final maxLength = schema['maxLength'] as int?;
    final minLength = schema['minLength'] as int? ?? 0;
    final pattern = schema['pattern'] as String?;
    final enumList = (schema['enum'] as List<dynamic>?)?.cast<String>();

    final description = schema['description']?.toString() ?? '';

    // If the field is an enum, we might use a dropdown
    if (enumList != null && enumList.isNotEmpty) {
      // Ensure that the current value is in the enum; if not, pick the first
      if (!enumList.contains(value)) {
        value = enumList.first;
        onChanged(value);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: DropdownButtonFormField<String>(
          value: value as String?,
          decoration: InputDecoration(
            labelText: fieldName,
            hintText: description,
          ),
          items: enumList.map((e) {
            return DropdownMenuItem<String>(value: e, child: Text(e));
          }).toList(),
          onChanged: readOnly
              ? null
              : (newVal) {
                  onChanged(newVal);
                },
          validator: (val) {
            if (isRequired && (val == null || val.isEmpty)) {
              return '$fieldName is required';
            }
            return null;
          },
        ),
      );
    }

    // Otherwise, treat it as a free text input
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        enabled: !readOnly,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: fieldName,
          hintText: description,
        ),
        validator: (text) {
          final length = text?.length ?? 0;
          if (isRequired && (text == null || text.isEmpty)) {
            return '$fieldName is required';
          }
          if (length < minLength) {
            return 'Minimum length is $minLength';
          }
          if (maxLength != null && length > maxLength) {
            return 'Maximum length is $maxLength';
          }
          if (pattern != null) {
            final regExp = RegExp(pattern);
            if (!regExp.hasMatch(text!)) {
              return 'Does not match pattern "$pattern"';
            }
          }
          return null;
        },
        onChanged: (newVal) => onChanged(newVal),
      ),
    );
  }

  // =========== BOOLEAN FIELD ===========

  Widget _buildBooleanField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value,
    bool readOnly,
    ValueChanged<dynamic> onChanged,
  ) {
    final boolVal = value == true;
    final description = schema['description']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$fieldName${description.isNotEmpty ? ' ($description)' : ''}',
            ),
          ),
          Switch(
            value: boolVal,
            onChanged: readOnly ? null : (val) => onChanged(val),
          ),
        ],
      ),
    );
  }

  // =========== NUMBER / INTEGER FIELD ===========

  Widget _buildNumberField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value,
    String fieldType, // 'number' or 'integer'
    bool isRequired,
    bool readOnly,
    ValueChanged<dynamic> onChanged,
  ) {
    final controller = TextEditingController(text: value?.toString() ?? '');
    final minimum = schema['minimum'] as num?;
    final maximum = schema['maximum'] as num?;
    final exclusiveMin = schema['exclusiveMinimum'] == true;
    final exclusiveMax = schema['exclusiveMaximum'] == true;
    final multipleOf = schema['multipleOf'] as num?;
    final description = schema['description']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        enabled: !readOnly,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: fieldName,
          hintText: description,
        ),
        validator: (text) {
          if (isRequired && (text == null || text.isEmpty)) {
            return '$fieldName is required';
          }
          if (text == null || text.isEmpty) {
            return null; // not required or blank is okay if not required
          }

          final parsed = (fieldType == 'integer')
              ? int.tryParse(text)
              : double.tryParse(text);
          if (parsed == null) {
            return 'Invalid $fieldType';
          }

          if (minimum != null) {
            if (exclusiveMin) {
              if (parsed <= minimum) {
                return 'Value must be > $minimum';
              }
            } else {
              if (parsed < minimum) {
                return 'Value must be >= $minimum';
              }
            }
          }

          if (maximum != null) {
            if (exclusiveMax) {
              if (parsed >= maximum) {
                return 'Value must be < $maximum';
              }
            } else {
              if (parsed > maximum) {
                return 'Value must be <= $maximum';
              }
            }
          }

          if (multipleOf != null) {
            // For floating usage, we might check with a tolerance
            final remainder = parsed % multipleOf;
            // Because of floating precision, allow a small epsilon:
            if (remainder.abs() > 1e-10) {
              return 'Value must be a multiple of $multipleOf';
            }
          }
          return null;
        },
        onChanged: (newVal) {
          final parsed = (fieldType == 'integer')
              ? int.tryParse(newVal)
              : double.tryParse(newVal);
          if (parsed != null) {
            onChanged(parsed);
          } else if (newVal.isEmpty) {
            onChanged(null);
          }
        },
      ),
    );
  }
}
