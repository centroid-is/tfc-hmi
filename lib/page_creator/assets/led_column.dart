import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/services.dart';

import 'led.dart';
import 'common.dart';

part 'led_column.g.dart';

@JsonSerializable()
class LEDColumnConfig extends BaseAsset {
  List<LEDConfig> leds;
  double? spacing;

  LEDColumnConfig({required this.leds});

  factory LEDColumnConfig.fromJson(Map<String, dynamic> json) =>
      _$LEDColumnConfigFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$LEDColumnConfigToJson(this);

  @override
  Widget build(BuildContext context) {
    return LEDColumn(config: this);
  }

  static const previewStr = 'LED Column preview';

  LEDColumnConfig.preview() : leds = [LEDConfig.preview(), LEDConfig.preview()];

  @override
  Widget configure(BuildContext context) {
    return _LEDColumnConfigEditor(config: this);
  }
}

class _LEDColumnConfigEditor extends StatefulWidget {
  final LEDColumnConfig config;
  const _LEDColumnConfigEditor({required this.config});

  @override
  State<_LEDColumnConfigEditor> createState() => _LEDColumnConfigEditorState();
}

class _LEDColumnConfigEditorState extends State<_LEDColumnConfigEditor> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizeField(
            initialValue: widget.config.size,
            onChanged: (size) => setState(() => widget.config.size = size),
          ),
          TextFormField(
            initialValue: widget.config.spacing?.toString(),
            onChanged: (spacing) {
              final value = double.tryParse(spacing);
              if (value != null) {
                final constrained = value.clamp(0.0, 100.0); // Min 0%, Max 100%
                setState(() => widget.config.spacing = constrained);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Spacing %',
              suffixText: '%',
              isDense: true,
              helperText: 'Range: 0-100%',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(
                  r'^\d*\.?\d*')), // Only allow numbers and decimal point
            ],
            validator: (value) {
              if (value == null || value.isEmpty) return null;
              final number = double.tryParse(value);
              if (number == null) return 'Please enter a valid number';
              if (number < 0) return 'Minimum is 0%';
              if (number > 100) return 'Maximum is 100%';
              return null;
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...List.generate(widget.config.leds.length, (ledIdx) {
                    final ledConfig = widget.config.leds[ledIdx];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ledConfig.configure(context),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() {
                                widget.config.leds.removeAt(ledIdx);
                              });
                            },
                          ),
                        ),
                        const Divider(),
                      ],
                    );
                  }),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add LED'),
                    onPressed: () {
                      setState(() {
                        widget.config.leds.add(LEDConfig.preview());
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LEDColumn extends StatelessWidget {
  final LEDColumnConfig config;

  const LEDColumn({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            for (int i = 0; i < config.leds.length; i++) ...[
              Expanded(
                child: LayoutBuilder(
                  builder: (context, rowConstraints) {
                    final ledConfig = config.leds[i];
                    final double fontSize = rowConstraints.maxHeight * 0.5;

                    // LED widget with consistent size
                    final ledWidget = AspectRatio(
                      aspectRatio: 1,
                      child: FractionallySizedBox(
                        widthFactor: 1.0,
                        heightFactor: 1.0,
                        child: Led(ledConfig),
                      ),
                    );

                    // Text widget with consistent style
                    final textWidget = ledConfig.text != null
                        ? Expanded(
                            child: Text(
                              ledConfig.text!,
                              style: TextStyle(fontSize: fontSize),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              textAlign: ledConfig.textPos == TextPos.left
                                  ? TextAlign.right
                                  : ledConfig.textPos == TextPos.right
                                      ? TextAlign.left
                                      : TextAlign.center,
                            ),
                          )
                        : null;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (textWidget != null &&
                            ledConfig.textPos == TextPos.left) ...[
                          textWidget,
                          const SizedBox(width: 8),
                        ],
                        ledWidget,
                        if (textWidget != null &&
                            (ledConfig.textPos == TextPos.right ||
                                ledConfig.textPos == null)) ...[
                          const SizedBox(width: 8),
                          textWidget,
                        ],
                      ],
                    );
                  },
                ),
              ),
              // Add spacing between rows, but not after the last row
              if (i < config.leds.length - 1 && config.spacing != null)
                SizedBox(
                  height: constraints.maxHeight * (config.spacing! / 100),
                ),
            ],
          ],
        );
      },
    );
  }
}
