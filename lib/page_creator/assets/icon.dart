import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'common.dart';
import '../../converter/icon.dart';
import '../../converter/color_converter.dart';

part 'icon.g.dart';

@JsonSerializable(explicitToJson: true)
class IconConfig extends BaseAsset {
  @IconDataConverter()
  IconData iconData;
  @OptionalColorConverter()
  Color? color;

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
        // Use the available space provided by the page layout system
        final availableSize = Size(constraints.maxWidth, constraints.maxHeight);

        return SizedBox.fromSize(
          size: availableSize,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.center,
            child: Icon(
              config.iconData,
              color: config.color ?? Theme.of(context).iconTheme.color,
              // Use a reasonable base size that will be scaled by FittedBox
              size: 48.0,
            ),
          ),
        );
      },
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

  @override
  Widget build(BuildContext context) {
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
}
