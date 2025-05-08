import 'dart:async';

import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import '../providers/state_man.dart';
import 'client.dart';

part 'alarm.g.dart';

@JsonSerializable()
class ExpressionConfig {
  final Expression expression;

  ExpressionConfig({required this.expression});

  factory ExpressionConfig.fromJson(Map<String, dynamic> json) =>
      _$ExpressionConfigFromJson(json);
  Map<String, dynamic> toJson() => _$ExpressionConfigToJson(this);
}

@JsonEnum()
enum AlarmLevel {
  info,
  warning,
  error,
}

@JsonSerializable()
class AlarmRule {
  final AlarmLevel level;
  final ExpressionConfig expression;
  final bool acknowledgeRequired;

  AlarmRule({
    required this.level,
    required this.expression,
    required this.acknowledgeRequired,
  });

  factory AlarmRule.fromJson(Map<String, dynamic> json) =>
      _$AlarmRuleFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmRuleToJson(this);
}

@JsonSerializable()
class AlarmConfig {
  final String uid;
  // todo I would like this to fetch title and description from opcua alarm
  final String? key;
  final String title;
  final String description;
  final List<AlarmRule> rules;

  AlarmConfig({
    required this.uid,
    this.key,
    required this.title,
    required this.description,
    required this.rules,
  });

  factory AlarmConfig.fromJson(Map<String, dynamic> json) =>
      _$AlarmConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AlarmConfigToJson(this);
}

class Alarm {
  final AlarmConfig config;

  Alarm({required this.config});

  Stream<AlarmConfig?> onActive() {
    final streamController = StreamController<AlarmConfig?>.broadcast();

    streamController.onListen = () async {};

    streamController.onCancel = () async {};

    return streamController.stream;
  }
}

class CreateAlarm extends ConsumerStatefulWidget {
  const CreateAlarm({super.key});

  @override
  ConsumerState<CreateAlarm> createState() => _CreateAlarmState();
}

class _CreateAlarmState extends ConsumerState<CreateAlarm> {
  final _formKey = GlobalKey<FormState>();
  String _title = '', _description = '';
  List<AlarmRule> _rules = [];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (v) => _title = v,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Description'),
              onChanged: (v) => _description = v,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            ..._rules.asMap().entries.map((entry) {
              final i = entry.key;
              final rule = entry.value;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      DropdownButton<AlarmLevel>(
                        value: rule.level,
                        items: AlarmLevel.values
                            .map((level) => DropdownMenuItem(
                                  value: level,
                                  child: Text(level.name),
                                ))
                            .toList(),
                        onChanged: (level) {
                          if (level != null)
                            setState(() {
                              _rules[i] = AlarmRule(
                                level: level,
                                expression: rule.expression,
                                acknowledgeRequired: rule.acknowledgeRequired,
                              );
                            });
                        },
                      ),
                      // ExpressionBuilder(
                      //   value: rule.expression,
                      //   onChanged: (expr) => setState(() {
                      //     _rules[i] = AlarmRule(
                      //       level: rule.level,
                      //       expression: expr,
                      //       acknowledgeRequired: rule.acknowledgeRequired,
                      //     );
                      //   }),
                      // ),
                      SwitchListTile(
                        title: const Text('Acknowledge Required'),
                        value: rule.acknowledgeRequired,
                        onChanged: (val) => setState(() {
                          _rules[i] = AlarmRule(
                            level: rule.level,
                            expression: rule.expression,
                            acknowledgeRequired: val,
                          );
                        }),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _rules.removeAt(i)),
                        child: const Text('Remove Rule'),
                      ),
                    ],
                  ),
                ),
              );
            }),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Rule'),
              onPressed: () => setState(() => _rules.add(
                    AlarmRule(
                      level: AlarmLevel.info,
                      expression:
                          ExpressionConfig(expression: Expression(formula: '')),
                      acknowledgeRequired: false,
                    ),
                  )),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState?.validate() ?? false) {
                  final config = AlarmConfig(
                    uid: UniqueKey().toString(),
                    title: _title,
                    description: _description,
                    rules: _rules,
                  );
                  // Handle config (e.g., print, save, etc.)
                  print(config.toJson());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alarm created!')),
                  );
                }
              },
              child: const Text('Create Alarm'),
            ),
          ],
        ),
      ),
    );
  }
}

class AlarmMan {
  final List<Alarm> alarms;

  AlarmMan({required this.alarms});

  void addAlarm(Alarm alarm) {
    alarms.add(alarm);
  }

  void removeAlarm(Alarm alarm) {
    alarms.remove(alarm);
  }

  void updateAlarm(Alarm alarm) {
    alarms.remove(alarm);
    alarms.add(alarm);
  }
}

class _Evaluator {
  final StateMan stateMan;
  final ExpressionConfig expression;
  _Evaluator({required this.stateMan, required this.expression});

  // Future<List<Stream<DynamicValue>>> _parseExpression() async {
  //   final formula = expression.formula;
  // }

  bool _evaluate(String expr) {
    return true;
  }

  Stream<bool> evaluate() {
    final streamController = StreamController<bool>.broadcast();

    streamController.onListen = () async {
      // for (final expr in expressions) {}
      // streamController.add(result);
    };

    streamController.onCancel = () async {
      streamController.close();
    };

    return streamController.stream;
  }
}

class _Token {
  final String value;
  final bool isOperator;

  _Token({required this.value, required this.isOperator});
}

class Expression {
  final String formula;

  // Define operators as static constants
  static const operators = {
    'AND': 'Logical AND (both sides must be true)',
    'OR': 'Logical OR (either side can be true)',
    '<': 'Less than',
    '<=': 'Less than or equal',
    '>': 'Greater than',
    '>=': 'Greater than or equal',
    '==': 'Equal to',
    '!=': 'Not equal to',
  };
  static final operatorRegex = RegExp(r'(AND|OR|<|>|==|!=|<=|>=)');

  Expression({required this.formula});

  /// Creates an Expression from JSON
  factory Expression.fromJson(Map<String, dynamic> json) {
    return Expression(formula: json['formula'] as String);
  }

  /// Converts the Expression to JSON
  Map<String, dynamic> toJson() => {'formula': formula};

  /// Validates if the expression looks like a valid boolean expression
  bool isValid() {
    // todo boolean DynamicValue

    return _looksBoolean(formula);
  }

  /// Basic validation that the expression contains at least one operator
  bool _looksBoolean(String expr) {
    return operatorRegex.hasMatch(expr);
  }

  /// Parses the expression and returns a list of variable names used in the expression
  List<String> extractVariables() {
    // Remove operators and split by spaces to get potential variables
    final withoutOperators = formula
        .replaceAll(operatorRegex, ' ')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();

    // Filter out numeric literals and quoted strings
    return withoutOperators.where((s) {
      if (double.tryParse(s) != null) return false;
      if (s.startsWith('"') && s.endsWith('"')) return false;
      if (s.startsWith("'") && s.endsWith("'")) return false;
      return true;
    }).toList();
  }

  // List of (variable, operator, variable, operator, variable, ...)
  List<_Token> _parseExpression() {
    if (formula.isEmpty) return [];

    // Get all matches (both operators and the text between them)
    final matches = operatorRegex.allMatches(formula);
    final tokens = <_Token>[];
    var lastEnd = 0;

    for (final match in matches) {
      // Add the text before the operator (if any)
      final beforeOp = formula.substring(lastEnd, match.start).trim();
      if (beforeOp.isNotEmpty) {
        tokens.add(_Token(value: beforeOp, isOperator: false));
      }

      // Add the operator
      tokens.add(_Token(value: match.group(0)!, isOperator: true));
      lastEnd = match.end;
    }

    // Add any remaining text after the last operator
    final remaining = formula.substring(lastEnd).trim();
    if (remaining.isNotEmpty) {
      tokens.add(_Token(value: remaining, isOperator: false));
    }

    // Validate that we have a valid pattern of variables and operators
    if (tokens.isEmpty) return [];

    return tokens;
  }

  /// Evaluates the expression with given variable values
  bool evaluate(Map<String, DynamicValue> variables) {
    final tokens = _parseExpression();
    if (tokens.isEmpty) return false;

    DynamicValue? lastValue;
    _Token? lastOperator;

    for (final token in tokens) {
      if (token.isOperator && lastOperator == null) {
        lastOperator = token;
        continue;
      } else if (!token.isOperator && lastValue == null) {
        lastValue = variables[token.value];
        continue;
      } else if (lastOperator != null &&
          lastValue != null &&
          !token.isOperator) {
        final rhs = variables[token.value];
        if (rhs == null) {
          throw ArgumentError('Variable ${token.value} not found');
        }
        var thisResult = DynamicValue(value: null);
        switch (lastOperator.value) {
          case 'AND':
            thisResult.value = lastValue.asBool && rhs.asBool;
            break;
          case 'OR':
            thisResult.value = lastValue.asBool || rhs.asBool;
            break;
          case '<': // double is not strictly correct but it's ok for now
            thisResult.value = lastValue.asDouble < rhs.asDouble;
            break;
          case '<=':
            thisResult.value = lastValue.asDouble <= rhs.asDouble;
            break;
          case '>':
            thisResult.value = lastValue.asDouble > rhs.asDouble;
            break;
          case '>=':
            thisResult.value = lastValue.asDouble >= rhs.asDouble;
            break;
          case '==': // string is not strictly correct but it's ok for now
            thisResult.value = lastValue.asString == rhs.asString;
            break;
          case '!=':
            thisResult.value = lastValue.asString != rhs.asString;
            break;
          default:
            throw ArgumentError('Invalid operator ${lastOperator.value}');
        }
        lastValue = thisResult;
      } else {
        throw ArgumentError('Invalid expression');
      }
    }
    return lastValue?.asBool ?? false;
  }

  /// Creates a UI widget for building/editing the expression
  static Widget buildEditor({
    required Expression value,
    required void Function(Expression) onChanged,
  }) {
    return ExpressionBuilder(
      value: value,
      onChanged: onChanged,
    );
  }
}

/// UI widget for building expressions
class ExpressionBuilder extends ConsumerWidget {
  final Expression value;
  final void Function(Expression) onChanged;

  const ExpressionBuilder({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: value.formula);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Alarm Condition Expression',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter a boolean expression that determines when the alarm should trigger.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                'Examples:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text('  temperature > 100'),
              const Text('  pressure < 10 AND flow > 5'),
              const Text('  status == "FAULT"'),
              const SizedBox(height: 8),
              const Text(
                'Allowed operators:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ...Expression.operators.entries.map((op) => Row(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(op.key,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Text(op.value),
                    ],
                  )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Expression',
            hintText: 'e.g. temperature > 100 AND pressure < 10',
            border: OutlineInputBorder(),
          ),
          onChanged: (f) => onChanged(Expression(formula: f)),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final expr = controller.text;
            if (expr.isEmpty) {
              return const Text(
                'Please enter an expression.',
                style: TextStyle(color: Colors.orange),
              );
            }
            if (!Expression(formula: expr).isValid()) {
              return const Text(
                '⚠️ This does not look like a boolean expression. Make sure to use comparison or logical operators.',
                style: TextStyle(color: Colors.red),
              );
            }
            return const Text(
              '✓ Looks like a valid boolean expression.',
              style: TextStyle(color: Colors.green),
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: Expression.operators.keys.map((op) {
            return OutlinedButton(
              onPressed: () {
                final text = controller.text;
                final selection = controller.selection;
                final newText = text.replaceRange(
                  selection.start,
                  selection.end,
                  ' $op ',
                );
                controller.text = newText;
                controller.selection = TextSelection.collapsed(
                    offset: selection.start + op.length + 2);
                onChanged(Expression(formula: controller.text));
              },
              child: Text(op),
            );
          }).toList(),
        ),
      ],
    );
  }
}
