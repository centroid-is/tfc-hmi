import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_core/core/boolean_expression.dart';
import '../page_creator/assets/common.dart';

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
          'Boolean Expression',
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
                'Enter a boolean expression that determines when it should trigger.',
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
