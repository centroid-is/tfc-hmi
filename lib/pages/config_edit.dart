import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dbus/dbus.dart';
import '../dbus/config.dart';

/// Dialog-based config editor that handles JSON schema with anyOf/oneOf, references, etc.
class ConfigEditDialog extends StatefulWidget {
  final DBusClient dbusClient;
  final String serviceName;
  final String objectPath;

  const ConfigEditDialog({
    Key? key,
    required this.dbusClient,
    required this.serviceName,
    required this.objectPath,
  }) : super(key: key);

  @override
  State<ConfigEditDialog> createState() => _ConfigEditDialogState();
}

class _ConfigEditDialogState extends State<ConfigEditDialog> {
  ConfigClient? _configClient;
  bool _isLoading = true;
  String _errorMessage = '';

  /// The root schema for this config
  Map<String, dynamic>? _schema;

  /// The current data (JSON) we are editing
  dynamic _configData;

  /// Form key for validation
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
        print('Error: $e');
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    if (_configClient == null) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    try {
      await _configClient!.setValueFromJson(_configData);
      if (mounted) {
        Navigator.of(context).pop(); // close the dialog
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

  void _cancel() {
    Navigator.of(context).pop(); // close dialog without saving
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AlertDialog(
        title: const Text('Loading Config...'),
        content: const SizedBox(
          width: 200,
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (_errorMessage.isNotEmpty) {
      return AlertDialog(
        title: const Text('Error'),
        content: Text(_errorMessage),
        actions: [
          TextButton(
            onPressed: _cancel,
            child: const Text('Close'),
          )
        ],
      );
    }

    if (_schema == null) {
      return AlertDialog(
        title: const Text('No Schema'),
        content: const Text('Schema not found or invalid.'),
        actions: [
          TextButton(
            onPressed: _cancel,
            child: const Text('Close'),
          )
        ],
      );
    }

    // Normal case: show the dynamic form with Save & Cancel
    return AlertDialog(
      title: const Text('Configuration Editor'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          // Optionally give some width/height constraints
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500,
              maxHeight: 600,
            ),
            child: _buildSchemaForm(_schema!, _configData, (updated) {
              setState(() {
                _configData = updated;
              });
            }),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveConfig,
          child: const Text('Save'),
        ),
      ],
    );
  }

  // ===========================================================================
  //                         SCHEMA FORM BUILDING (same logic)
  // ===========================================================================

  Widget _buildSchemaForm(
    Map<String, dynamic> schema,
    dynamic data,
    ValueChanged<dynamic> onChanged,
  ) {
    final type = _resolveType(schema);
    if (type == 'object') {
      if (data is! Map<String, dynamic>) {
        data = <String, dynamic>{};
      }
      return _buildObjectForm(schema, data as Map<String, dynamic>, onChanged);
    } else if (type == 'array') {
      if (data is! List) {
        data = <dynamic>[];
      }
      return _buildArrayField('root', schema, data as List, false, onChanged);
    } else {
      return Text('Root schema must be an object or array (found "$type").');
    }
  }

  Widget _buildObjectForm(
    Map<String, dynamic> schema,
    Map<String, dynamic> data,
    ValueChanged<dynamic> onChanged,
  ) {
    final props = schema['properties'] as Map<String, dynamic>? ?? {};
    final requiredFields =
        (schema['required'] as List<dynamic>? ?? []).cast<String>();

    final children = <Widget>[];
    props.forEach((propName, propSchemaRaw) {
      final propSchema = _resolveRef(propSchemaRaw as Map<String, dynamic>);
      final value = data[propName];
      final isRequired = requiredFields.contains(propName);

      children.add(
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
      children: children,
    );
  }

  Widget _buildPropertyField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value, {
    required bool isRequired,
    required ValueChanged<dynamic> onChanged,
  }) {
    if (schema.containsKey('oneOf')) {
      final oneOfList = schema['oneOf'] as List<dynamic>;
      return _buildOneOfField(
          fieldName, oneOfList, value, schema, isRequired, onChanged);
    }
    if (schema.containsKey('anyOf')) {
      final anyOfList = schema['anyOf'] as List<dynamic>;
      return _buildAnyOfField(
          fieldName, anyOfList, value, schema, isRequired, onChanged);
    }
    return _buildTypedField(fieldName, schema, value, isRequired, onChanged);
  }

  // --------------------------- oneOf Handling ---------------------------
  Widget _buildOneOfField(
    String fieldName,
    List<dynamic> oneOfList,
    dynamic value,
    Map<String, dynamic> parentSchema,
    bool isRequired,
    ValueChanged<dynamic> onChanged,
  ) {
    // Resolve sub-schemas
    final subSchemas = <Map<String, dynamic>>[];
    for (var sub in oneOfList) {
      if (sub is Map<String, dynamic>) {
        subSchemas.add(_resolveRef(sub));
      }
    }

    final index = _determineOneOfIndex(subSchemas, value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$fieldName (oneOf)',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        _buildOneOfSelector(
          fieldName: fieldName,
          subSchemas: subSchemas,
          activeIndex: index,
          onPick: (newIndex) {
            final newSub = subSchemas[newIndex];
            final newVal = _createDefaultValueForSchema(newSub);
            onChanged(newVal);
          },
        ),
        if (index >= 0 && index < subSchemas.length)
          Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: _buildTypedField(
                fieldName, subSchemas[index], value, isRequired, onChanged),
          )
      ],
    );
  }

  Widget _buildOneOfSelector({
    required String fieldName,
    required List<Map<String, dynamic>> subSchemas,
    required int activeIndex,
    required ValueChanged<int> onPick,
  }) {
    return DropdownButton<int>(
      value: activeIndex >= 0 ? activeIndex : null,
      hint: Text('Pick sub-schema for $fieldName'),
      items: List.generate(subSchemas.length, (i) {
        final desc = subSchemas[i]['description']?.toString() ?? 'OneOf #$i';
        return DropdownMenuItem<int>(
          value: i,
          child: Text(desc),
        );
      }),
      onChanged: (val) {
        if (val != null) onPick(val);
      },
    );
  }

  int _determineOneOfIndex(List<Map<String, dynamic>> subs, dynamic value) {
    if (value is Map) {
      // naive approach
      for (int i = 0; i < subs.length; i++) {
        if (subs[i]['properties'] is Map) {
          final keys = (subs[i]['properties'] as Map).keys;
          if (keys.any(value.containsKey)) return i;
        }
      }
    } else if (value == null) {
      // see if there's a "null" type
      for (int i = 0; i < subs.length; i++) {
        if (_resolveType(subs[i]) == 'null') return i;
      }
    }
    return 0;
  }

  // --------------------------- anyOf Handling ---------------------------
  Widget _buildAnyOfField(
    String fieldName,
    List<dynamic> anyOfList,
    dynamic value,
    Map<String, dynamic> parentSchema,
    bool isRequired,
    ValueChanged<dynamic> onChanged,
  ) {
    final subSchemas = <Map<String, dynamic>>[];
    for (var sub in anyOfList) {
      if (sub is Map<String, dynamic>) {
        subSchemas.add(_resolveRef(sub));
      }
    }

    // find which sub-schemas match, naive approach
    final matches = _determineAnyOfMatches(subSchemas, value);

    // pick an active index from matches or 0
    final idx = matches.isEmpty ? 0 : matches.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$fieldName (anyOf)',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        if (subSchemas.length > 1)
          DropdownButton<int>(
            value: idx,
            items: List.generate(subSchemas.length, (i) {
              final desc =
                  subSchemas[i]['description']?.toString() ?? 'AnyOf #$i';
              return DropdownMenuItem<int>(
                value: i,
                child: Text(desc),
              );
            }),
            onChanged: (val) {
              if (val != null) {
                final newSchema = subSchemas[val];
                final newVal = _createDefaultValueForSchema(newSchema);
                onChanged(newVal);
              }
            },
          ),
        Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: _buildTypedField(
              fieldName, subSchemas[idx], value, isRequired, onChanged),
        ),
      ],
    );
  }

  List<int> _determineAnyOfMatches(
      List<Map<String, dynamic>> subs, dynamic value) {
    final matches = <int>[];
    for (int i = 0; i < subs.length; i++) {
      final t = _resolveType(subs[i]);
      if (t == 'object' && value is Map) {
        matches.add(i);
      } else if (t == 'array' && value is List) {
        matches.add(i);
      } else if (t == 'string' && value is String) {
        matches.add(i);
      } else if ((t == 'integer' || t == 'number') && value is num) {
        matches.add(i);
      } else if (t == 'boolean' && value is bool) {
        matches.add(i);
      } else if (t == 'null' && value == null) {
        matches.add(i);
      }
    }
    return matches;
  }

  // ------------------ Build typed field from a single type ------------------
  Widget _buildTypedField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value,
    bool isRequired,
    ValueChanged<dynamic> onChanged,
  ) {
    final type = _resolveType(schema);
    final readOnly = schema['readOnly'] == true;

    switch (type) {
      case 'object':
        if (value is! Map<String, dynamic>) value = <String, dynamic>{};
        return ExpansionTile(
          title: Text(fieldName),
          subtitle: Text(schema['description']?.toString() ?? ''),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildObjectForm(schema, value, onChanged),
            ),
          ],
        );
      case 'array':
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
        return _buildNumberField(
            fieldName, schema, value, type, isRequired, readOnly, onChanged);
      case 'null':
        return ListTile(title: Text(fieldName), subtitle: const Text('(null)'));
      default:
        return Text('$fieldName: Unsupported type "$type"');
    }
  }

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

    final itemsSchemaRaw = schema['items'];
    Map<String, dynamic>? itemsSchema;
    if (itemsSchemaRaw is Map<String, dynamic>) {
      itemsSchema = _resolveRef(itemsSchemaRaw);
    }

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

    void ensureUnique() {
      if (uniqueItems) {
        final setVals = <dynamic>{};
        final duplicates = <int>[];
        for (int i = 0; i < value.length; i++) {
          if (!setVals.add(value[i])) duplicates.add(i);
        }
        for (final idx in duplicates.reversed) {
          value.removeAt(idx);
        }
      }
    }

    ensureUnique();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fieldName, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (int i = 0; i < value.length; i++)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
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
                    ),
                ],
              ),
            ),
          if (!readOnly && (maxItems == null || value.length < maxItems))
            TextButton.icon(
              onPressed: () {
                final newItem = _createDefaultValueForSchema(itemsSchema);
                setState(() {
                  value.add(newItem);
                  ensureUnique();
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

    // enum as dropdown
    if (enumList != null && enumList.isNotEmpty) {
      if (!enumList.contains(value)) {
        value = enumList.first;
        onChanged(value);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          value: value as String?,
          decoration:
              InputDecoration(labelText: fieldName, hintText: description),
          items: enumList
              .map((e) => DropdownMenuItem(child: Text(e), value: e))
              .toList(),
          onChanged: readOnly ? null : (val) => onChanged(val),
          validator: (val) {
            if (isRequired && (val == null || val.isEmpty)) {
              return '$fieldName is required';
            }
            return null;
          },
        ),
      );
    }

    // normal text field
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        enabled: !readOnly,
        maxLength: maxLength,
        decoration:
            InputDecoration(labelText: fieldName, hintText: description),
        validator: (text) {
          if (isRequired && (text == null || text.isEmpty)) {
            return '$fieldName is required';
          }
          final length = text?.length ?? 0;
          if (length < minLength) {
            return 'Minimum length is $minLength';
          }
          if (maxLength != null && length > maxLength) {
            return 'Maximum length is $maxLength';
          }
          if (pattern != null && text != null) {
            final regExp = RegExp(pattern);
            if (!regExp.hasMatch(text)) {
              return 'Does not match pattern "$pattern"';
            }
          }
          return null;
        },
        onChanged: (val) => onChanged(val),
      ),
    );
  }

  Widget _buildBooleanField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value,
    bool readOnly,
    ValueChanged<dynamic> onChanged,
  ) {
    final boolVal = value == true;
    final description = schema['description']?.toString() ?? '';

    return Row(
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
    );
  }

  Widget _buildNumberField(
    String fieldName,
    Map<String, dynamic> schema,
    dynamic value,
    String fieldType,
    bool isRequired,
    bool readOnly,
    ValueChanged<dynamic> onChanged,
  ) {
    final controller = TextEditingController(text: value?.toString() ?? '');
    final description = schema['description']?.toString() ?? '';

    final minimum = schema['minimum'];
    final maximum = schema['maximum'];
    final exclusiveMin = schema['exclusiveMinimum'] == true;
    final exclusiveMax = schema['exclusiveMaximum'] == true;
    final multipleOf = schema['multipleOf'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        enabled: !readOnly,
        keyboardType: TextInputType.number,
        decoration:
            InputDecoration(labelText: fieldName, hintText: description),
        validator: (text) {
          if (isRequired && (text == null || text.isEmpty)) {
            return '$fieldName is required';
          }
          if (text == null || text.isEmpty) {
            return null;
          }

          num? parsed;
          if (fieldType == 'integer') {
            parsed = int.tryParse(text);
            if (parsed == null) return 'Invalid integer';
          } else {
            parsed = double.tryParse(text);
            if (parsed == null) return 'Invalid number';
          }

          if (minimum is num) {
            if (exclusiveMin && parsed <= minimum) {
              return 'Value must be > $minimum';
            } else if (!exclusiveMin && parsed < minimum) {
              return 'Value must be >= $minimum';
            }
          }
          if (maximum is num) {
            if (exclusiveMax && parsed >= maximum) {
              return 'Value must be < $maximum';
            } else if (!exclusiveMax && parsed > maximum) {
              return 'Value must be <= $maximum';
            }
          }
          if (multipleOf is num) {
            final remainder = parsed % multipleOf;
            if (remainder.abs() > 1e-10) {
              return 'Value must be multiple of $multipleOf';
            }
          }
          return null;
        },
        onChanged: (text) {
          if (text.isEmpty) {
            onChanged(null);
            return;
          }
          if (fieldType == 'integer') {
            final p = int.tryParse(text);
            onChanged(p ?? value);
          } else {
            final p = double.tryParse(text);
            onChanged(p ?? value);
          }
        },
      ),
    );
  }

  // ===========================================================================
  //                           $ref RESOLUTION
  // ===========================================================================
  Map<String, dynamic> _resolveRef(Map<String, dynamic> schema) {
    if (schema.containsKey(r'$ref')) {
      final refStr = schema[r'$ref'] as String;
      if (refStr.startsWith('#/definitions/')) {
        final key = refStr.substring('#/definitions/'.length);
        final def = _schema?['definitions']?[key];
        if (def is Map<String, dynamic>) {
          // Merge definition with local schema
          return {...def, ...schema}..remove(r'$ref');
        }
      }
    }
    return schema;
  }

  String _resolveType(Map<String, dynamic> schema) {
    final rawType = schema['type'];
    if (rawType is String) {
      return rawType;
    }
    if (rawType is List && rawType.isNotEmpty) {
      return rawType.first;
    }
    if (schema['properties'] != null) return 'object';
    if (schema['items'] != null) return 'array';
    return 'object';
  }

  dynamic _createDefaultValueForSchema(Map<String, dynamic>? schema) {
    if (schema == null) return null;
    final type = _resolveType(schema);
    if (schema.containsKey('default')) return schema['default'];

    switch (type) {
      case 'object':
        return <String, dynamic>{};
      case 'array':
        return <dynamic>[];
      case 'string':
        return '';
      case 'boolean':
        return false;
      case 'integer':
      case 'number':
        return 0;
      case 'null':
        return null;
      default:
        return null;
    }
  }
}
