import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:rxdart/rxdart.dart';

import 'common.dart';
import 'package:tfc/converter/icon.dart';
import 'package:tfc/converter/color_converter.dart';
import 'package:tfc_dart/core/boolean_expression.dart';
import '../../widgets/boolean_expression.dart';
import '../../providers/state_man.dart';

part 'icon.g.dart';

@JsonSerializable(explicitToJson: true)
class ConditionalIconState {
  @JsonKey(name: 'expression')
  ExpressionConfig expression;

  @IconDataConverter()
  IconData? iconData;

  @OptionalColorConverter()
  Color? color;

  ConditionalIconState({
    required this.expression,
    this.iconData,
    this.color,
  });

  factory ConditionalIconState.fromJson(Map<String, dynamic> json) =>
      _$ConditionalIconStateFromJson(json);
  Map<String, dynamic> toJson() => _$ConditionalIconStateToJson(this);
}

@JsonSerializable(explicitToJson: true)
class IconConfig extends BaseAsset {
  @override
  String get displayName => 'Icon';
  @override
  String get category => 'Basic Indicators';

  @IconDataConverter()
  IconData iconData;
  @OptionalColorConverter()
  Color? color;

  @JsonKey(name: 'conditional_states')
  List<ConditionalIconState>? conditionalStates = [];

  IconConfig({
    required this.iconData,
  });

  static const previewStr = 'Icon preview';

  IconConfig.preview() : iconData = Icons.home {
    textPos = TextPos.right;
  }

  @override
  Widget build(BuildContext context) {
    return IconAsset(this);
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
          minWidth: 320,
          minHeight: 200,
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

  factory IconConfig.fromJson(Map<String, dynamic> json) =>
      _$IconConfigFromJson(json);
  Map<String, dynamic> toJson() => _$IconConfigToJson(this);
}

class IconAsset extends ConsumerWidget {
  final IconConfig config;

  const IconAsset(this.config, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fall back to a sane finite size when an axis is unbounded.
        final hasW =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite;
        final hasH =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;

        final double w = hasW ? constraints.maxWidth : 48.0;
        final double h = hasH ? constraints.maxHeight : 48.0;
        final double size = w.isFinite && h.isFinite ? (w < h ? w : h) : 48.0;

        return Center(
          child: _buildIconWithConditions(context, ref, size),
        );
      },
    );
  }

  Widget _buildIconWithConditions(
      BuildContext context, WidgetRef ref, double size) {
    if (config.conditionalStates?.isEmpty ?? true) {
      return Icon(
        config.iconData,
        color: config.color ?? Theme.of(context).iconTheme.color,
        size: size,
      );
    }

    return ref.watch(stateManProvider).when(
          data: (stateMan) {
            final evaluators = config.conditionalStates!
                .map((state) =>
                    Evaluator(stateMan: stateMan, expression: state.expression))
                .toList();
            return StreamBuilder<List<bool>>(
              stream: CombineLatestStream.list(evaluators.map((e) => e.eval())),
              builder: (context, snapshot) {
                IconData displayIcon = config.iconData;
                Color? displayColor = config.color;

                if (snapshot.hasData) {
                  for (int i = 0; i < snapshot.data!.length; i++) {
                    if (snapshot.data![i]) {
                      final state = config.conditionalStates![i];
                      if (state.iconData != null) {
                        displayIcon = state.iconData!;
                      }
                      if (state.color != null) {
                        displayColor = state.color;
                      }
                      break; // Use the first matching condition
                    }
                  }
                }

                return Icon(
                  displayIcon,
                  color: displayColor ?? Theme.of(context).iconTheme.color,
                  size: size,
                );
              },
            );
          },
          loading: () => Icon(
            config.iconData,
            color: config.color ?? Theme.of(context).iconTheme.color,
            size: size,
          ),
          error: (_, __) => Icon(
            config.iconData,
            color: config.color ?? Theme.of(context).iconTheme.color,
            size: size,
          ),
        );
  }
}

class _ConfigContent extends StatefulWidget {
  final IconConfig config;

  const _ConfigContent({required this.config});

  @override
  State<_ConfigContent> createState() => _ConfigContentState();
}

class _ConfigContentState extends State<_ConfigContent> {
  void _showIconPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Icon'),
        content: SizedBox(
          width: 600,
          height: 600,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              childAspectRatio: 1,
            ),
            itemCount: iconList.length,
            itemBuilder: (context, index) {
              final icon = iconList[index];
              return InkWell(
                onTap: () {
                  setState(() {
                    widget.config.iconData = icon;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.config.iconData == icon
                          ? Theme.of(context).primaryColor
                          : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(icon),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _addConditionalState() {
    setState(() {
      widget.config.conditionalStates!.add(
        ConditionalIconState(
          expression: ExpressionConfig(value: Expression(formula: '')),
        ),
      );
    });
  }

  void _removeConditionalState(int index) {
    setState(() {
      widget.config.conditionalStates!.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.conditionalStates == null) {
      widget.config.conditionalStates = [];
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon Selection
        Row(
          children: [
            const Text('Icon: '),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: IconButton(
                icon: Icon(widget.config.iconData),
                onPressed: _showIconPicker,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _showIconPicker,
                child: const Text('Change Icon'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Color picker
        ColorPicker(
          pickerColor:
              widget.config.color ?? Theme.of(context).colorScheme.primary,
          onColorChanged: (color) =>
              setState(() => widget.config.color = color),
        ),
        const SizedBox(height: 16),

        // Conditional States Section
        const Text(
          'Conditional States',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add conditions that will change the icon or color when the expression evaluates to true.',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),

        // Add Conditional State Button
        ElevatedButton.icon(
          onPressed: _addConditionalState,
          icon: const Icon(Icons.add),
          label: const Text('Add Conditional State'),
        ),
        const SizedBox(height: 16),

        // Conditional States List
        ...widget.config.conditionalStates!.asMap().entries.map((entry) {
          final index = entry.key;
          final state = entry.value;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Condition ${index + 1}'),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeConditionalState(index),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Expression Builder
                  ExpressionBuilder(
                    value: state.expression.value,
                    onChanged: (expression) {
                      setState(() {
                        state.expression = ExpressionConfig(value: expression);
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // Icon Selection for this condition
                  Row(
                    children: [
                      const Text('Override Icon: '),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: IconButton(
                          icon: Icon(state.iconData ?? Icons.help_outline),
                          onPressed: () => _showConditionalIconPicker(index),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _showConditionalIconPicker(index),
                          child: Text(state.iconData != null
                              ? 'Change Icon'
                              : 'Set Icon'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Color Selection for this condition
                  Row(
                    children: [
                      const Text('Override Color: '),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: state.color ?? Colors.grey,
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: InkWell(
                          onTap: () => _showConditionalColorPicker(index),
                          child: state.color == null
                              ? const Icon(Icons.color_lens,
                                  color: Colors.white)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _showConditionalColorPicker(index),
                          child: Text(state.color != null
                              ? 'Change Color'
                              : 'Set Color'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),

        const SizedBox(height: 16),

        // Text field
        TextFormField(
          initialValue: widget.config.text,
          decoration: const InputDecoration(
            labelText: 'Text',
          ),
          onChanged: (value) {
            setState(() {
              widget.config.text = value;
            });
          },
        ),
        const SizedBox(height: 16),

        // Text Position
        DropdownButton<TextPos>(
          value: widget.config.textPos,
          isExpanded: true,
          onChanged: (value) {
            setState(() {
              widget.config.textPos = value!;
            });
          },
          items: TextPos.values
              .map((e) =>
                  DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
              .toList(),
        ),
        const SizedBox(height: 16),

        // Size field
        SizeField(
          initialValue: widget.config.size,
          useSingleSize: true,
          onChanged: (value) {
            setState(() {
              widget.config.size = value;
            });
          },
        ),
        const SizedBox(height: 16),

        // Coordinates field
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (c) => setState(() => widget.config.coordinates = c),
        ),
      ],
    );
  }

  void _showConditionalIconPicker(int stateIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Icon for Condition'),
        content: SizedBox(
          width: 600,
          height: 600,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              childAspectRatio: 1,
            ),
            itemCount: iconList.length,
            itemBuilder: (context, index) {
              final icon = iconList[index];
              return InkWell(
                onTap: () {
                  setState(() {
                    widget.config.conditionalStates![stateIndex].iconData =
                        icon;
                  });
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.config.conditionalStates![stateIndex]
                                  .iconData ==
                              icon
                          ? Theme.of(context).primaryColor
                          : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(icon),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                widget.config.conditionalStates![stateIndex].iconData = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Clear Icon'),
          ),
        ],
      ),
    );
  }

  void _showConditionalColorPicker(int stateIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Color for Condition'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: widget.config.conditionalStates![stateIndex].color ??
                Theme.of(context).colorScheme.primary,
            onColorChanged: (color) {
              setState(() {
                widget.config.conditionalStates![stateIndex].color = color;
              });
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                widget.config.conditionalStates![stateIndex].color = null;
              });
              Navigator.pop(context);
            },
            child: const Text('Clear Color'),
          ),
        ],
      ),
    );
  }
}
