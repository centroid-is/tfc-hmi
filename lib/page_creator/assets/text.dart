import 'package:json_annotation/json_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'common.dart';
import '../../converter/color_converter.dart';

part 'text.g.dart';

@JsonSerializable()
class TextAssetConfig extends BaseAsset {
  /// The text content to display
  String textContent;

  /// Text color
  @OptionalColorConverter()
  Color? textColor;

  TextAssetConfig({
    required this.textContent,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextAssetWidget(this);
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
          minWidth: 400,
          minHeight: 300,
        ),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: Theme.of(context).dialogBackgroundColor,
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

  static const previewStr = 'Text Asset preview';

  TextAssetConfig.preview()
      : textContent = 'Sample Text',
        textColor = Colors.black {
    textPos = TextPos.inside;
    size = const RelativeSize(
        width: 0.15, height: 0.08); // Similar to option variable sizing
  }

  factory TextAssetConfig.fromJson(Map<String, dynamic> json) =>
      _$TextAssetConfigFromJson(json);
  Map<String, dynamic> toJson() => _$TextAssetConfigToJson(this);
}

class TextAssetWidget extends ConsumerStatefulWidget {
  final TextAssetConfig config;

  const TextAssetWidget(this.config, {super.key});

  @override
  ConsumerState<TextAssetWidget> createState() => _TextAssetWidgetState();
}

class _TextAssetWidgetState extends ConsumerState<TextAssetWidget> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: BoxDecoration(
            color: Colors.transparent, // Transparent background
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: SizedBox(
              width:
                  constraints.maxWidth * 0.9, // Give it 90% of available width
              height: constraints.maxHeight *
                  0.9, // Give it 90% of available height
              child: FittedBox(
                fit: BoxFit.contain,
                alignment: Alignment.center,
                child: Text(
                  widget.config.textContent,
                  style: TextStyle(
                    color: widget.config.textColor ??
                        Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                  maxLines: null, // Allow multiple lines
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConfigContent extends StatefulWidget {
  final TextAssetConfig config;

  const _ConfigContent({required this.config});

  @override
  State<_ConfigContent> createState() => _ConfigContentState();
}

class _ConfigContentState extends State<_ConfigContent> {
  late TextEditingController _textController;
  late double _fontSize;
  late Color? _textColor;
  late TextAlign _textAlign;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.config.textContent);
    _textColor = widget.config.textColor;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Configure Text Asset',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),

        // Text content
        TextFormField(
          controller: _textController,
          decoration: const InputDecoration(
            labelText: 'Text Content',
            hintText: 'Enter your text here...',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
          onChanged: (value) {
            widget.config.textContent = value;
          },
        ),

        const SizedBox(height: 20),

        // Text color
        Row(
          children: [
            const Text('Text Color: '),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showColorPicker(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _textColor,
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Size configuration
        Text(
          'Size',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizeField(
          initialValue: widget.config.size,
          onChanged: (value) {
            widget.config.size = value;
          },
        ),

        const SizedBox(height: 20),

        // Coordinates configuration
        Text(
          'Position',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        CoordinatesField(
          initialValue: widget.config.coordinates,
          onChanged: (value) {
            widget.config.coordinates = value;
          },
        ),

        const SizedBox(height: 20),

        // Text position configuration
        Text(
          'Text Position',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownButton<TextPos>(
          value: widget.config.textPos,
          isExpanded: true,
          onChanged: (value) {
            widget.config.textPos = value;
          },
          items: TextPos.values
              .map((e) => DropdownMenuItem<TextPos>(
                    value: e,
                    child: Text(e.name[0].toUpperCase() + e.name.substring(1)),
                  ))
              .toList(),
        ),

        const SizedBox(height: 20),

        // Preview
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preview',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Container(
                width: 200,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    widget.config.textContent,
                    style: TextStyle(
                      fontSize: _fontSize,
                      color: _textColor,
                    ),
                    textAlign: _textAlign,
                    maxLines: null,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showColorPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Text Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _textColor ?? Colors.black,
            onColorChanged: (color) {
              setState(() {
                _textColor = color;
                widget.config.textColor = color;
              });
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
