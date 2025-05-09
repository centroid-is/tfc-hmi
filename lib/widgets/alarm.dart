import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/alarm.dart';
import '../providers/alarm.dart';

class ListAlarms extends ConsumerStatefulWidget {
  final void Function(AlarmConfig)? onEdit;
  final void Function(AlarmConfig)? onShow;
  final void Function(AlarmConfig)? onDelete;
  final void Function()? onCreate;

  const ListAlarms({
    super.key,
    this.onEdit,
    this.onShow,
    this.onDelete,
    this.onCreate,
  });

  @override
  ConsumerState<ListAlarms> createState() => _ListAlarmsState();
}

class _ListAlarmsState extends ConsumerState<ListAlarms> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ref.read(alarmManProvider.future),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final alarms = snapshot.data!.alarms.where((alarm) {
            if (_searchQuery.isEmpty) return true;

            // Search in title
            if (alarm.config.title
                .toLowerCase()
                .contains(_searchQuery.toLowerCase())) {
              return true;
            }

            // Search in expressions
            for (final rule in alarm.config.rules) {
              if (rule.expression.value.formula
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase())) {
                return true;
              }
            }

            return false;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        widget.onCreate?.call();
                      },
                    ),
                    Expanded(
                      child: SearchBar(
                        hintText: 'Search alarms...',
                        leading: const Icon(Icons.search),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: alarms.length,
                  itemBuilder: (context, index) {
                    final alarm = alarms[index];
                    return ListTile(
                      title: Text(alarm.config.title),
                      subtitle: Text(alarm.config.description),
                      trailing: SizedBox(
                        width: 96,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                widget.onEdit?.call(alarm.config);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                // Show confirmation dialog
                                final shouldDelete = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Delete Alarm'),
                                    content: Text(
                                        'Are you sure you want to delete alarm "${alarm.config.title}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(true),
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                // If user confirmed deletion
                                if (shouldDelete == true && context.mounted) {
                                  final alarmMan =
                                      await ref.read(alarmManProvider.future);
                                  alarmMan.removeAlarm(alarm.config);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('Alarm deleted!'),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .tertiary,
                                      ),
                                    );
                                  }
                                  widget.onDelete?.call(alarm.config);
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      onTap: () => widget.onShow?.call(alarm.config),
                    );
                  },
                ),
              ),
            ],
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

class AlarmForm extends ConsumerStatefulWidget {
  final AlarmConfig? initialConfig;
  final void Function(AlarmConfig)? onSubmit;
  final String? submitText;
  final bool editable;

  const AlarmForm({
    super.key,
    this.initialConfig,
    this.onSubmit,
    this.submitText,
    this.editable = false,
  });

  @override
  ConsumerState<AlarmForm> createState() => _AlarmFormState();
}

class _AlarmFormState extends ConsumerState<AlarmForm> {
  final _formKey = GlobalKey<FormState>();
  late String _title;
  late String _description;
  late List<AlarmRule> _rules;

  @override
  void initState() {
    super.initState();
    _title = widget.initialConfig?.title ?? '';
    _description = widget.initialConfig?.description ?? '';
    _rules = widget.initialConfig?.rules.toList() ?? [];
  }

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
              initialValue: _title,
              onChanged: (v) => _title = v,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              enabled: widget.editable,
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Description'),
              initialValue: _description,
              onChanged: (v) => _description = v,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              enabled: widget.editable,
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
                      const SizedBox(height: 16),
                      DropdownButtonFormField<AlarmLevel>(
                        value: rule.level,
                        decoration: InputDecoration(
                          labelText: 'Alarm Level',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        items: AlarmLevel.values
                            .map((level) => DropdownMenuItem(
                                  value: level,
                                  child: Text(level.name),
                                ))
                            .toList(),
                        onChanged: widget.editable
                            ? (level) {
                                if (level != null) {
                                  setState(() {
                                    _rules[i] = AlarmRule(
                                      level: level,
                                      expression: rule.expression,
                                      acknowledgeRequired:
                                          rule.acknowledgeRequired,
                                    );
                                  });
                                }
                              }
                            : null,
                      ),
                      ExpressionBuilder(
                        value: rule.expression.value,
                        editable: widget.editable,
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
                        onChanged: widget.editable
                            ? (val) => setState(() {
                                  _rules[i] = AlarmRule(
                                    level: rule.level,
                                    expression: rule.expression,
                                    acknowledgeRequired: val,
                                  );
                                })
                            : null,
                      ),
                      if (widget.editable)
                        TextButton(
                          onPressed: () => setState(() => _rules.removeAt(i)),
                          child: const Text('Remove Rule'),
                        ),
                    ],
                  ),
                ),
              );
            }),
            if (widget.editable)
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Rule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _rules.isEmpty
                      ? Theme.of(context).colorScheme.errorContainer
                      : null,
                  foregroundColor: _rules.isEmpty
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : null,
                ),
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
            if (widget.onSubmit != null)
              ElevatedButton(
                onPressed: _rules.isEmpty
                    ? null
                    : () {
                        if (_formKey.currentState?.validate() ?? false) {
                          final config = AlarmConfig(
                            uid: widget.initialConfig?.uid ??
                                UniqueKey().toString(),
                            title: _title,
                            description: _description,
                            rules: _rules,
                          );
                          widget.onSubmit?.call(config);
                        }
                      },
                child: Text(widget.submitText ?? 'Submit'),
              ),
          ],
        ),
      ),
    );
  }
}

/// UI widget for building expressions
class ExpressionBuilder extends ConsumerStatefulWidget {
  final Expression value;
  final void Function(Expression) onChanged;
  final bool editable;

  const ExpressionBuilder({
    super.key,
    required this.value,
    required this.onChanged,
    this.editable = true,
  });

  @override
  ConsumerState<ExpressionBuilder> createState() => _ExpressionBuilderState();
}

class _ExpressionBuilderState extends ConsumerState<ExpressionBuilder> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.value.formula);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            color: Theme.of(context).colorScheme.surface,
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
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(op.key,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimary,
                            )),
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
          enabled: widget.editable,
          onChanged: (value) => widget.onChanged(Expression(formula: value)),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final expr = controller.text;
            if (expr.isEmpty) {
              return Text(
                'Please enter an expression.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              );
            }
            if (!Expression(formula: expr).isValid()) {
              return Text(
                '⚠️ This does not look like a boolean expression. Make sure to use comparison or logical operators.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              );
            }
            return Text(
              '✓ Looks like a valid boolean expression.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: Expression.operators.keys.map((op) {
            return OutlinedButton(
              onPressed: widget.editable
                  ? () {
                      final text = controller.text;
                      final selection = controller.selection;
                      final newText = text.isEmpty
                          ? op
                          : text.replaceRange(
                              selection.start,
                              selection.end,
                              ' $op ',
                            );
                      controller.text = newText;
                      controller.selection = TextSelection.collapsed(
                          offset: text.isEmpty
                              ? op.length
                              : selection.start + op.length + 2);
                      widget.onChanged(Expression(formula: controller.text));
                    }
                  : null,
              child: Text(op),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class CreateAlarm extends ConsumerWidget {
  final void Function() onSubmit;

  const CreateAlarm({super.key, required this.onSubmit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlarmForm(
      editable: true,
      submitText: 'Create Alarm',
      onSubmit: (config) async {
        final newConfig = AlarmConfig(
          uid: UniqueKey().toString(),
          title: config.title,
          description: config.description,
          rules: config.rules,
        );

        final alarmMan = await ref.read(alarmManProvider.future);
        alarmMan.addAlarm(newConfig);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alarm created!')),
          );
        }
        onSubmit();
      },
    );
  }
}

class EditAlarm extends ConsumerWidget {
  final AlarmConfig config;
  final void Function() onSubmit;

  const EditAlarm({
    super.key,
    required this.config,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlarmForm(
      editable: true,
      initialConfig: config,
      onSubmit: (updatedConfig) async {
        final alarmMan = await ref.read(alarmManProvider.future);
        alarmMan.updateAlarm(updatedConfig);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alarm updated!')),
          );
        }
        onSubmit();
      },
    );
  }
}
