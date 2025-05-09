import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/alarm.dart';

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
                      ExpressionBuilder(
                        value: rule.expression.value,
                        onChanged: (expr) => setState(() {
                          _rules[i] = AlarmRule(
                            level: rule.level,
                            expression: ExpressionConfig(value: expr),
                            acknowledgeRequired: rule.acknowledgeRequired,
                          );
                        }),
                      ),
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
                          ExpressionConfig(value: Expression(formula: '')),
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
