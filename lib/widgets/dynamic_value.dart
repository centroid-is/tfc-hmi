import 'dart:io' show stderr;

import 'package:flutter/material.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

class DynamicValueWidget extends StatelessWidget {
  final DynamicValue _value;
  final Function(DynamicValue)? onSubmitted;

  DynamicValueWidget({
    super.key,
    required DynamicValue value,
    this.onSubmitted,
  }) : _value = DynamicValue.from(value);

  @override
  Widget build(BuildContext context) {
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    if (_value.isNull) {
      return const Text('null');
    }

    if (_value.isObject) {
      return _buildObjectWidget(context);
    }

    if (_value.isArray) {
      return _buildArrayWidget(context);
    }

    if (_value.isString) {
      return _buildStringWidget(context);
    }

    if (_value.isBoolean) {
      return _buildBooleanWidget(context);
    }

    if (_value.isInteger) {
      return _buildIntegerWidget(context);
    }

    if (_value.isDouble) {
      return _buildDoubleWidget(context);
    }

    return Text('Unknown type: ${_value.toString()}');
  }

  Widget _buildObjectWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_value.displayName != null)
          Text(
            _value.displayName!.value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (_value.description != null)
          Text(
            _value.description!.value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        ..._value.asObject.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _prettifyLabel(entry.key),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                DynamicValueWidget(
                  value: entry.value,
                  onSubmitted: onSubmitted != null
                      ? (newValue) {
                          final copy = DynamicValue.from(_value);
                          copy[entry.key] = newValue;
                          onSubmitted!(copy);
                        }
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildArrayWidget(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_value.displayName != null)
          Text(
            _value.displayName!.value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        if (_value.description != null)
          Text(
            _value.description!.value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        ..._value.asArray.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item ${entry.key}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                DynamicValueWidget(
                  value: entry.value,
                  onSubmitted: onSubmitted != null
                      ? (newValue) {
                          final copy = DynamicValue.from(_value);
                          copy[entry.key] = newValue;
                          onSubmitted!(copy);
                        }
                      : null,
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStringWidget(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: _value.asString),
      onSubmitted: onSubmitted != null
          ? (newValue) {
              onSubmitted!(DynamicValue.from(_value)..value = newValue);
            }
          : null,
      readOnly: onSubmitted == null,
      decoration: InputDecoration(
        labelText: _value.displayName?.value,
        helperText: _value.description?.value,
      ),
    );
  }

  Widget _buildBooleanWidget(BuildContext context) {
    return Row(
      children: [
        if (_value.displayName != null)
          Text(
            _value.displayName!.value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        Switch(
          value: _value.asBool,
          onChanged: onSubmitted != null
              ? (newValue) {
                  onSubmitted!(DynamicValue.from(_value)..value = newValue);
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildIntegerWidget(BuildContext context) {
    if (_value.enumFields != null) {
      try {
        return DropdownButton<int>(
          key: ValueKey(_value.asInt),
          value: _value.asInt,
          items: _value.enumFields!.entries
              .map((entry) => DropdownMenuItem<int>(
                  value: entry.key, child: Text(entry.value.displayName.value)))
              .toList(),
          onChanged: onSubmitted != null
              ? (newValue) {
                  onSubmitted!(DynamicValue.from(_value)..value = newValue);
                }
              : null,
        );
      } catch (e) {
        stderr.writeln("Error building enum dropdown: $e");
      }
    }

    return TextField(
      controller: TextEditingController(text: _value.asInt.toString()),
      keyboardType: TextInputType.number,
      onSubmitted: onSubmitted != null
          ? (newValue) {
              final intValue = int.tryParse(newValue);
              if (intValue != null) {
                onSubmitted!(DynamicValue.from(_value)..value = intValue);
              }
            }
          : null,
      readOnly: onSubmitted == null,
      decoration: InputDecoration(
        labelText: _value.displayName?.value,
        helperText: _value.description?.value,
      ),
    );
  }

  Widget _buildDoubleWidget(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: _value.asDouble.toString()),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      readOnly: onSubmitted == null,
      onSubmitted: onSubmitted != null
          ? (newValue) {
              final doubleValue = double.tryParse(newValue);
              if (doubleValue != null) {
                onSubmitted!(DynamicValue.from(_value)..value = doubleValue);
              }
            }
          : null,
      decoration: InputDecoration(
        labelText: _value.displayName?.value ?? '',
        helperText: _value.description?.value,
      ),
    );
  }

  String _prettifyLabel(String label) {
    // Convert snake_case to spaces and capitalize
    String withSpaces = label.replaceAllMapped(
      RegExp(r'(_)|([A-Z])'),
      (match) {
        if (match.group(1) != null) return ' ';
        if (match.group(2) != null) return ' ${match.group(2)}';
        return '';
      },
    );
    // Remove leading space if any, and capitalize first letter
    withSpaces = withSpaces.trimLeft();
    if (withSpaces.isEmpty) return '';
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }
}
