import 'package:json_annotation/json_annotation.dart';
import 'dart:ui' show Color, Size;
import 'package:flutter/material.dart';
part 'common.g.dart';

const String constAssetName = "asset_name";

@JsonSerializable()
class ColorConverter implements JsonConverter<Color, Map<String, dynamic>> {
  const ColorConverter();

  @override
  Color fromJson(Map<String, dynamic> json) {
    return Color.fromRGBO(
      (json['red']! * 255).toInt(),
      (json['green']! * 255).toInt(),
      (json['blue']! * 255).toInt(),
      json['alpha'] ?? 1.0,
    );
  }

  @override
  Map<String, double> toJson(Color color) => {
        'red': color.r,
        'green': color.g,
        'blue': color.b,
        'alpha': color.a,
      };
}

@JsonEnum()
enum TextPos {
  above,
  below,
  left,
  right,
  inside,
}

@JsonSerializable()
class Coordinates {
  double x; // 0.0 to 1.0
  double y; // 0.0 to 1.0
  double? angle;

  Coordinates({
    required this.x,
    required this.y,
    this.angle,
  });

  factory Coordinates.fromJson(Map<String, dynamic> json) =>
      _$CoordinatesFromJson(json);
  Map<String, dynamic> toJson() => _$CoordinatesToJson(this);
}

@JsonSerializable()
class RelativeSize {
  final double width; // 0.0 to 1.0
  final double height; // 0.0 to 1.0

  const RelativeSize({
    required this.width,
    required this.height,
  });

  factory RelativeSize.fromJson(Map<String, dynamic> json) =>
      _$RelativeSizeFromJson(json);
  Map<String, dynamic> toJson() => _$RelativeSizeToJson(this);

  Size toSize(Size containerSize) {
    return Size(
      containerSize.width * width,
      containerSize.height * height,
    );
  }

  static RelativeSize fromSize(Size size, Size containerSize) {
    return RelativeSize(
      width: size.width / containerSize.width,
      height: size.height / containerSize.height,
    );
  }
}

abstract class Asset {
  String get assetName;
  Coordinates get coordinates;
  set coordinates(Coordinates coordinates);
  String get pageName;
  set pageName(String pageName);
  RelativeSize get size;
  set size(RelativeSize size);
  Widget build(BuildContext context);
  Widget configure(BuildContext context);
  Map<String, dynamic> toJson();
}

@JsonSerializable(createFactory: false, explicitToJson: true)
abstract class BaseAsset implements Asset {
  @override
  String get assetName => variant;
  @JsonKey(name: constAssetName)
  String variant =
      'unknown'; // fromJson will set this during deserialization, otherwise it will be set to the runtime type

  BaseAsset() {
    if (variant == 'unknown') {
      variant = runtimeType.toString();
    }
  }

  @JsonKey(name: 'page_name')
  String _pageName = 'main';

  @override
  @JsonKey(name: 'page_name')
  String get pageName => _pageName;

  @override
  set pageName(String pageName) {
    _pageName = pageName;
  }

  @JsonKey(name: 'coordinates')
  Coordinates _coordinates = Coordinates(x: 0.0, y: 0.0);

  @override
  Coordinates get coordinates => _coordinates;

  @override
  set coordinates(Coordinates coordinates) {
    _coordinates = coordinates;
  }

  @JsonKey(name: 'size')
  RelativeSize _size = const RelativeSize(width: 0.03, height: 0.03);

  @override
  RelativeSize get size => _size;

  @override
  set size(RelativeSize size) {
    _size = size;
  }
}

Widget buildWithText(Widget widget, String text, TextPos textPos) {
  final textWidget = Text(text);
  const spacing = SizedBox(width: 8, height: 8); // 8 pixel spacing

  if (textPos == TextPos.inside) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget,
        IgnorePointer(child: textWidget),
      ],
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: textPos == TextPos.above
        ? [textWidget, spacing, widget]
        : textPos == TextPos.below
            ? [widget, spacing, textWidget]
            : textPos == TextPos.right
                ? [
                    Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [widget, spacing, textWidget])
                  ]
                : [
                    Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [textWidget, spacing, widget])
                  ],
  );
}

class KeyField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String>? onChanged;

  const KeyField({super.key, this.initialValue, this.onChanged});

  @override
  State<KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<KeyField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _KeyFieldDialog(
        initialValue: _controller.text,
      ),
    );
    if (result != null) {
      _controller.text = result;
      widget.onChanged?.call(result);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Key',
        suffixIcon: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: _openDialog,
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _KeyFieldDialog extends StatefulWidget {
  final String? initialValue;

  const _KeyFieldDialog({this.initialValue});

  @override
  State<_KeyFieldDialog> createState() => _KeyFieldDialogState();
}

class _KeyFieldDialogState extends State<_KeyFieldDialog> {
  late TextEditingController _namespaceController;
  late TextEditingController _identifierController;

  @override
  void initState() {
    super.initState();
    int ns = 0;
    String id = '';
    // Try to parse initial value if present
    final regex = RegExp(r'ns=(\d+);s=(.+)');
    if (widget.initialValue != null) {
      final match = regex.firstMatch(widget.initialValue!);
      if (match != null) {
        ns = int.tryParse(match.group(1) ?? '0') ?? 0;
        id = match.group(2) ?? '';
      }
    }
    _namespaceController = TextEditingController(text: ns.toString());
    _identifierController = TextEditingController(text: id);
  }

  @override
  void dispose() {
    _namespaceController.dispose();
    _identifierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Format OPC UA NodeId'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _namespaceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Namespace'),
          ),
          TextField(
            controller: _identifierController,
            decoration: const InputDecoration(labelText: 'Identifier'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final ns = int.tryParse(_namespaceController.text) ?? 0;
            final id = _identifierController.text;
            final isInt = int.tryParse(id) != null;
            final nodeId = isInt ? 'ns=$ns;i=$id' : 'ns=$ns;s=$id';
            Navigator.of(context).pop(nodeId);
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class SizeField extends StatefulWidget {
  final RelativeSize initialValue;
  final ValueChanged<RelativeSize>? onChanged;
  final bool useSingleSize;

  const SizeField({
    super.key,
    required this.initialValue,
    this.onChanged,
    this.useSingleSize = false, // Default to false for backward compatibility
  });

  @override
  State<SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<SizeField> {
  late TextEditingController _widthController;
  late TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(
        text: (widget.initialValue.width * 100).toStringAsFixed(2));
    _heightController = TextEditingController(
        text: (widget.initialValue.height * 100).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (widget.useSingleSize) {
      final size = double.tryParse(_widthController.text) ?? 3.0;
      final relSize = RelativeSize(width: size / 100, height: size / 100);
      widget.onChanged?.call(relSize);
    } else {
      final width = double.tryParse(_widthController.text) ?? 3.0;
      final height = double.tryParse(_heightController.text) ?? 3.0;
      final relSize = RelativeSize(width: width / 100, height: height / 100);
      widget.onChanged?.call(relSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useSingleSize) {
      return Row(
        children: [
          const Text('Size: '),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextFormField(
              controller: _widthController,
              decoration: const InputDecoration(
                suffixText: '%',
                isDense: true,
                helperText: '0.01-50%',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _onChanged(),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _widthController,
            decoration: const InputDecoration(labelText: 'Width %'),
            keyboardType: TextInputType.number,
            onChanged: (_) => _onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _heightController,
            decoration: const InputDecoration(labelText: 'Height %'),
            keyboardType: TextInputType.number,
            onChanged: (_) => _onChanged(),
          ),
        ),
      ],
    );
  }
}
