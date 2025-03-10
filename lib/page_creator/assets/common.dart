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
}

@JsonSerializable()
class Coordinates {
  final double x; // 0.0 to 1.0
  final double y; // 0.0 to 1.0
  final double? angle;

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
