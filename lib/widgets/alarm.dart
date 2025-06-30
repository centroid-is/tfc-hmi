import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/alarm.dart';
import '../core/boolean_expression.dart';
import '../providers/alarm.dart';
import 'base_scaffold.dart';
import '../page_creator/assets/common.dart';

class ListAlarms extends ConsumerStatefulWidget {
  final void Function(AlarmConfig)? onEdit;
  final void Function(AlarmConfig)? onShow;
  final void Function(AlarmConfig)? onDelete;
  final void Function(AlarmConfig?)? onCreate;

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
      future: ref.watch(alarmManProvider.future),
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
                        widget.onCreate?.call(null);
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
                        width: 144,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                widget.onCreate?.call(alarm.config);
                              },
                            ),
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

  // Add a method to check if all expressions are valid
  bool _areAllExpressionsValid() {
    return _rules.every((rule) => rule.expression.value.isValid());
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
                onPressed: (_rules.isEmpty || !_areAllExpressionsValid())
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
              const Text('  (temperature > 100 OR pressure < 10) AND flow > 5'),
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
          children: [
            ...Expression.operators.keys.map((op) {
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
            }),
            OutlinedButton(
              onPressed: widget.editable
                  ? () {
                      final text = controller.text;
                      final selection = controller.selection;
                      final newText = text.isEmpty
                          ? '('
                          : text.replaceRange(
                              selection.start,
                              selection.end,
                              '(',
                            );
                      controller.text = newText;
                      controller.selection = TextSelection.collapsed(
                          offset: text.isEmpty ? 1 : selection.start + 1);
                      widget.onChanged(Expression(formula: controller.text));
                    }
                  : null,
              child: const Text('('),
            ),
            OutlinedButton(
              onPressed: widget.editable
                  ? () {
                      final text = controller.text;
                      final selection = controller.selection;
                      final newText = text.isEmpty
                          ? ')'
                          : text.replaceRange(
                              selection.start,
                              selection.end,
                              ')',
                            );
                      controller.text = newText;
                      controller.selection = TextSelection.collapsed(
                          offset: text.isEmpty ? 1 : selection.start + 1);
                      widget.onChanged(Expression(formula: controller.text));
                    }
                  : null,
              child: const Text(')'),
            ),
            OutlinedButton(
              onPressed: widget.editable
                  ? () async {
                      final key = await showDialog<String>(
                        context: context,
                        builder: (context) => KeySearchDialog(
                          initialQuery: '',
                        ),
                      );
                      if (key != null && context.mounted) {
                        final text = controller.text;
                        final selection = controller.selection;
                        final newText = text.isEmpty
                            ? key
                            : text.replaceRange(
                                selection.start,
                                selection.end,
                                key,
                              );
                        controller.text = newText;
                        controller.selection = TextSelection.collapsed(
                            offset: text.isEmpty
                                ? key.length
                                : selection.start + key.length);
                        widget.onChanged(Expression(formula: controller.text));
                      }
                    }
                  : null,
              child: const Text('Key'),
            ),
          ],
        ),
      ],
    );
  }
}

class CreateAlarm extends ConsumerWidget {
  final void Function() onSubmit;
  final AlarmConfig? template;

  const CreateAlarm({super.key, required this.onSubmit, this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlarmForm(
      initialConfig: template == null ? null : AlarmConfig.from(template!),
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
        ref.invalidate(alarmManProvider);
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
        ref.invalidate(alarmManProvider);
        onSubmit();
      },
    );
  }
}

class ListActiveAlarms extends ConsumerStatefulWidget {
  final void Function(AlarmActive)? onShow;
  final void Function()? onViewChanged;

  const ListActiveAlarms({
    super.key,
    this.onShow,
    this.onViewChanged,
  });

  @override
  ConsumerState<ListActiveAlarms> createState() => _ListActiveAlarmsState();
}

class _ListActiveAlarmsState extends ConsumerState<ListActiveAlarms> {
  String _searchQuery = '';
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<(AlarmMan, List<(AlarmActive, DateTime?)>)>(
      stream: Stream.fromFuture(ref.watch(alarmManProvider.future)).asyncExpand(
        (alarmMan) => _showHistory
            ? alarmMan.history().map((history) => (
                  alarmMan,
                  history
                      .where((h) => h != null)
                      .map((h) => (h!, h!.deactivated))
                      .toList()
                    ..sort((a, b) => b.$2!.compareTo(a.$2!))
                ))
            : alarmMan.activeAlarms().map((active) =>
                (alarmMan, active.map((a) => (a, null as DateTime?)).toList())),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var (alarmMan, alarms) = snapshot.data!;
        if (!_showHistory) {
          alarms = alarmMan
              .filterAlarms(alarms.map((a) => a.$1).toList(), _searchQuery)
              .map((a) => (a, null as DateTime?))
              .toList();
        }

        if (alarms.isEmpty) {
          return Column(
            children: [
              _buildSearchAndToggleBar(),
              const Expanded(
                child: Center(
                  child: Text('No alarms'),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildSearchAndToggleBar(),
            Expanded(
              child: ListView.builder(
                itemCount: alarms.length,
                itemBuilder: (context, index) {
                  final (alarm, deactivationTime) = alarms[index];
                  final (backgroundColor, textColor) =
                      alarm.notification.getColors(context);

                  return Card(
                    color: backgroundColor,
                    child: ListTile(
                      title: Text(
                        alarm.alarm.config.title,
                        style: TextStyle(color: textColor),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Activated: ${formatTimestamp(alarm.notification.timestamp)}',
                            style: TextStyle(
                              color: textColor.withAlpha(178),
                            ),
                          ),
                          if (deactivationTime != null)
                            Text(
                              'Deactivated: ${formatTimestamp(deactivationTime)}',
                              style: TextStyle(
                                color: textColor.withAlpha(178),
                              ),
                            ),
                        ],
                      ),
                      onTap: () => widget.onShow?.call(alarm),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchAndToggleBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Row(
            children: [
              // Search field
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText:
                        'Search ${_showHistory ? "historical" : "active"} alarms...',
                    prefixIcon: const Icon(Icons.search),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              // Toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: SegmentedButton<bool>(
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: WidgetStateProperty.all(BorderSide.none),
                  ),
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.warning, size: 18),
                      label: Text('Active'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.history, size: 18),
                      label: Text('History'),
                    ),
                  ],
                  selected: {_showHistory},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _showHistory = newSelection.first;
                      _searchQuery = '';
                    });
                    widget.onViewChanged?.call();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ViewActiveAlarm extends ConsumerWidget {
  final AlarmActive alarm;
  final void Function()? onClose;

  const ViewActiveAlarm({
    super.key,
    required this.alarm,
    this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (backgroundColor, textColor) = alarm.notification.getColors(context);
    final isActive = alarm.notification.active;
    final requiresAck = alarm.notification.rule.acknowledgeRequired;
    final canAck = !isActive && alarm.pendingAck && alarm.deactivated == null;

    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  alarm.alarm.config.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                    color: textColor,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activated: ${formatTimestamp(alarm.notification.timestamp)}',
                  style: TextStyle(
                    color: textColor.withAlpha(178),
                    fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                  ),
                ),
                if (alarm.deactivated != null)
                  Text(
                    'Deactivated: ${formatTimestamp(alarm.deactivated!)}',
                    style: TextStyle(
                      color: textColor.withAlpha(178),
                      fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              alarm.alarm.config.description,
              style: TextStyle(color: textColor),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: textColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Level: ${alarm.notification.rule.level.name.toUpperCase()}',
                    style: TextStyle(color: textColor),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: textColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Status: ${isActive ? 'ACTIVE' : 'INACTIVE'}',
                    style: TextStyle(color: textColor),
                  ),
                ),
              ],
            ),
            if (alarm.notification.expression != null) ...[
              const SizedBox(height: 16),
              Text(
                'Expression: ${alarm.notification.expression}',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ],
            if (requiresAck) ...[
              const SizedBox(height: 16),
              Text(
                'This alarm requires acknowledgment',
                style: TextStyle(
                  color: textColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (canAck) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  final alarmMan = await ref.read(alarmManProvider.future);
                  alarmMan.ackAlarm(alarm);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Alarm acknowledged')),
                    );
                  }
                  onClose?.call();
                },
                icon: const Icon(Icons.check),
                label: const Text('Acknowledge'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: textColor,
                  foregroundColor: backgroundColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
